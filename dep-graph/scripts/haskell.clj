#!/usr/bin/env bb

(require '[babashka.process :as p]
         '[cheshire.core :as json]
         '[clojure.string :as str])

;; ── Args ───────────────────────────────────────────────────────────────────
;;
;; Usage: haskell.clj <flake-path> <owner-regex> [--title T] [--no-staleness]
;;
;;   --title         H1 heading for the document (default "Dependency Graph").
;;   --no-staleness  Skip the "N behind HEAD" / diverged-branch checks. These
;;                   compare each pinned commit against the *current* upstream
;;                   default-branch HEAD — moving external state — so a CI drift
;;                   gate must omit them to stay a pure function of flake.lock +
;;                   cabal.project. The live (deploy-time) render keeps them.

(defn parse-args [args]
  (loop [a args, pos [], title nil, no-stale false]
    (if (empty? a)
      {:positional pos :title title :no-staleness no-stale}
      (let [x (first a)]
        (cond
          (= x "--title") (recur (drop 2 a) pos (second a) no-stale)
          (= x "--no-staleness") (recur (rest a) pos title true)
          :else (recur (rest a) (conj pos x) title no-stale))))))

(def parsed (parse-args (vec *command-line-args*)))

(def flake-path (or (first (:positional parsed)) "."))
(def owner-regex (or (second (:positional parsed))
                     (do (println "Usage: haskell.clj <flake-path> <owner-regex> [--title T] [--no-staleness]")
                         (System/exit 1))))
(def doc-title (or (:title parsed) "Dependency Graph"))
(def no-staleness? (:no-staleness parsed))

(def owner-pattern (re-pattern owner-regex))

(defn managed? [owner]
  (and owner (re-find owner-pattern owner)))

;; ── Shell helpers ──────────────────────────────────────────────────────────

(defn sh [& args]
  (-> (apply p/process {:out :string :err :string :dir flake-path} args)
      deref :out str/trim))

(defn sh-home [& args]
  (-> (apply p/process {:out :string :err :string} args)
      deref :out str/trim))

;; ── Step 1: Flake closure ──────────────────────────────────────────────────

(def metadata
  (json/parse-string (sh "nix" "flake" "metadata" "--json") true))

(def nodes (get-in metadata [:locks :nodes]))

(defn node-locked [key]
  (get-in nodes [(keyword key) :locked]))

(defn resolve-to-node-key
  "Resolve a flake input reference to the final node key in the lock file.
   Direct: string -> that key
   Follows: [a, b] -> nodes[a].inputs[b], then recurse
   Follows: [a, b, c, ...] -> walk: nodes[a].inputs[b] to get node, then .inputs[c], etc."
  [ref]
  (if (vector? ref)
    (loop [path ref]
      (if (<= (count path) 1)
        (first path)
        (let [node-key (first path)
              input-name (second path)
              next-ref (get-in nodes [(keyword node-key) :inputs (keyword input-name)])]
          (if (nil? next-ref)
            node-key
            (if (vector? next-ref)
              ;; The input itself is a follows — resolve it, then continue with rest of path
              (let [resolved-key (resolve-to-node-key next-ref)]
                (if (> (count path) 2)
                  (recur (into [resolved-key] (drop 2 path)))
                  resolved-key))
              ;; Direct reference — use it, then continue with rest of path
              (if (> (count path) 2)
                (recur (into [next-ref] (drop 2 path)))
                next-ref))))))
    ref))

(defn resolve-ref
  "Resolve a flake input reference to the actual locked info."
  [ref]
  (node-locked (resolve-to-node-key ref)))

(def managed-nodes
  (->> nodes
       (filter (fn [[_ v]] (managed? (get-in v [:locked :owner]))))
       (map (fn [[k v]]
              (let [l (:locked v)]
                {:key (name k)
                 :owner (:owner l)
                 :repo (:repo l)
                 :rev (:rev l)
                 :rev-short (subs (:rev l) 0 12)
                 :id (str (:owner l) "/" (:repo l))})))))

(defn extract-flake-edges []
  (let [all-inputs
        (concat
         ;; Root edges
         (for [[input-name ref] (get-in nodes [:root :inputs])
               :let [target (resolve-ref ref)]
               :when (managed? (:owner target))]
           {:from "root"
            :to (str (:owner target) "/" (:repo target))
            :to-rev (subs (:rev target) 0 12)
            :via (name input-name)
            :kind (if (vector? ref) "follows" "flake")})
         ;; Internal edges
         (for [{:keys [key id]} managed-nodes
               [input-name ref] (get-in nodes [(keyword key) :inputs])
               :let [target (resolve-ref ref)]
               :when (and (managed? (:owner target))
                          (not= id (str (:owner target) "/" (:repo target))))]
           {:from id
            :from-rev (subs (get-in nodes [(keyword key) :locked :rev]) 0 12)
            :to (str (:owner target) "/" (:repo target))
            :to-rev (subs (:rev target) 0 12)
            :via (name input-name)
            :kind (if (vector? ref) "follows" "flake")}))]
    (->> all-inputs
         (map #(select-keys % [:from :from-rev :to :to-rev :via :kind]))
         (distinct)
         (sort-by (juxt :from :to)))))

(def flake-edges (extract-flake-edges))

;; ── Step 2: Root repo info ─────────────────────────────────────────────────

(def root-rev (subs (sh "git" "rev-parse" "HEAD") 0 12))
(def root-owner
  (let [url (sh "git" "remote" "get-url" "origin")]
    (-> url
        (str/replace #"\.git$" "")
        (str/replace #".*github\.com[:/]" ""))))
;; Prefer the repo name from the git remote (stable) over the path basename,
;; which is "." when the action runs with the default flake-path.
(def root-name
  (let [from-remote (last (str/split root-owner #"/"))]
    (if (seq from-remote) from-remote (last (str/split flake-path #"/")))))
;; Full HEAD sha + canonical owner/repo id for the root repo. The root is a
;; *cabal* dependency root in its own right (its local `cabal.project` carries
;; source-repository-package pins), so it must seed cabal edge collection too —
;; not only the flake-input repos.
(def root-rev-full (sh "git" "rev-parse" "HEAD"))
(def root-id root-owner)
(def root-desc
  (let [flake (slurp (str flake-path "/flake.nix"))]
    (second (re-find #"description\s*=\s*\"([^\"]+)\"" flake))))

(defn short12
  "Truncate a 40-char git sha to 12 chars; leave short refs (branch names,
   short tags) untouched."
  [s]
  (if (and s (> (count s) 12)) (subs s 0 12) s))

;; Display ref for the ROOT's own self-links. In --no-staleness (deterministic)
;; mode use the default branch, NOT the HEAD sha: the committed doc lives in
;; this same repo, so embedding HEAD would make it differ from any regen at a
;; later commit, and a drift gate could never pass. In staleness mode keep the
;; exact sha (that render is live, not gated).
(def root-ref
  (if no-staleness?
    (let [b (try (sh-home "gh" "api" (str "repos/" root-id) "--jq" ".default_branch")
                 (catch Exception _ ""))]
      (if (seq b) b "HEAD"))
    root-rev))

;; ── Step 3: Cabal source-repository-package (recursive) ────────────────────

(def visited-cabal (atom #{}))

(defn fetch-cabal-project [owner-repo rev]
  (if (= owner-repo root-id)
    ;; Root: read the working-tree cabal.project directly. The root's own SRP
    ;; pins are what cabal actually flattens (SRPs are not transitive), and they
    ;; are not visible to the Nix closure — so they must be read locally.
    (try (slurp (str flake-path "/cabal.project")) (catch Exception _ nil))
    (try
      (let [raw (sh-home "gh" "api"
                         (str "repos/" owner-repo "/contents/cabal.project?ref=" rev)
                         "--jq" ".content")
            decoded (sh-home "bash" "-c" (str "echo '" raw "' | base64 -d"))]
        decoded)
      (catch Exception _ nil))))

(defn parse-source-repo-packages [content]
  (when content
    (let [lines (str/split-lines content)
          blocks (loop [i 0 blocks [] current nil]
                   (if (>= i (count lines))
                     (if current (conj blocks current) blocks)
                     (let [line (nth lines i)]
                       (cond
                         (str/starts-with? line "source-repository-package")
                         (recur (inc i)
                                (if current (conj blocks current) blocks)
                                {:start-line (inc i)})

                         (and current (re-find #"location:\s*(.*)" line))
                         (let [loc (-> (second (re-find #"location:\s*(.*)" line))
                                       str/trim
                                       (str/replace #"\.git$" ""))]
                           (recur (inc i) blocks
                                  (assoc current :location loc :line (inc i))))

                         (and current (re-find #"tag:\s*(.*)" line))
                         (let [tag (str/trim (second (re-find #"tag:\s*(.*)" line)))]
                           (recur (inc i) blocks (assoc current :tag tag)))

                         :else
                         (recur (inc i) blocks current)))))]
      (->> blocks
           (filter #(and (:location %) (:tag %)))
           (map (fn [{:keys [location tag line]}]
                  (let [m (re-find #"github\.com/([^/]+/[^/]+)" location)]
                    (when m
                      {:owner-repo (second m) :tag tag :line line}))))
           (filter some?)
           (filter #(managed? (first (str/split (:owner-repo %) #"/"))))))))

(defn collect-cabal-edges [owner-repo rev]
  (let [cache-key (str owner-repo "/" rev)]
    (when-not (@visited-cabal cache-key)
      (swap! visited-cabal conj cache-key)
      (when-let [content (fetch-cabal-project owner-repo rev)]
        (let [deps (parse-source-repo-packages content)]
          (concat
           (for [dep deps]
             {:from owner-repo :from-rev (short12 rev)
              :to (:owner-repo dep) :to-rev (short12 (:tag dep))
              :to-rev-full (:tag dep) :line (:line dep) :kind "cabal"})
           (mapcat #(collect-cabal-edges (:owner-repo %) (:tag %)) deps)))))))

(def cabal-edges-raw
  ;; Seed from the ROOT first (its local cabal.project is what cabal flattens),
  ;; then every managed flake-input repo. `collect-cabal-edges` recurses through
  ;; each dependency's own cabal.project at its pinned rev, so the transitive
  ;; mirror structure (e.g. cardano-node-clients -> chain-follower -> ...) is
  ;; discovered automatically instead of being filled in by hand.
  (->> (cons {:id root-id :rev root-ref} managed-nodes)
       (mapcat #(collect-cabal-edges (:id %) (:rev %)))
       (filter some?)
       (distinct)
       (sort-by (juxt :from :to))))

;; ── Pin skew: same dependency pinned to different revs by different declarers ─
;; SRPs are not transitive, so the root re-pins the union of what its deps each
;; declare — and the root's pin wins. When a dep's own cabal.project names a
;; different rev for a shared package than the root does, the dep is silently
;; built against the root's rev. That divergence is the main maintenance hazard;
;; surface it instead of leaving it implicit.
(def pin-skews
  (->> cabal-edges-raw
       (group-by :to)
       (keep (fn [[to edges]]
               (let [decls (->> edges
                                (map (fn [e] {:from (:from e)
                                              :from-rev (:from-rev e)
                                              :rev (:to-rev-full e)
                                              :rev-short (:to-rev e)}))
                                distinct)]
                 (when (> (count (distinct (map :rev decls))) 1)
                   ;; The root's pin (if the root declares this dep) is effective.
                   (let [root-decl (->> decls (filter #(= (:from %) root-id)) first)]
                     {:to to
                      :effective (:rev-short root-decl)
                      :effective-from (when root-decl root-id)
                      :decls (sort-by :from decls)})))))
       (sort-by :to)))

;; ── Step 3b: Extract build-depends sub-libraries for edge labels ───────────

(defn fetch-gh-file
  "Fetch a file from a GitHub repo at a specific rev."
  [owner-repo rev path]
  (try
    (let [raw (sh-home "gh" "api"
                       (str "repos/" owner-repo "/contents/" path "?ref=" rev)
                       "--jq" ".content")]
      (sh-home "bash" "-c" (str "echo '" raw "' | base64 -d")))
    (catch Exception _ nil)))

(defn find-cabal-files
  "List .cabal files in the repo root (and one level of subdirs)."
  [owner-repo rev]
  (try
    (let [entries (json/parse-string
                   (sh-home "gh" "api"
                            (str "repos/" owner-repo "/contents/?ref=" rev))
                   true)]
      (->> entries
           (filter #(str/ends-with? (:name %) ".cabal"))
           (map :path)))
    (catch Exception _ [])))

(defn find-cabal-files-recursive
  "Find .cabal files in root and first-level subdirs."
  [owner-repo rev]
  (let [root-files (find-cabal-files owner-repo rev)]
    (if (seq root-files)
      root-files
      ;; Try subdirs that match repo name patterns
      (try
        (let [entries (json/parse-string
                       (sh-home "gh" "api"
                                (str "repos/" owner-repo "/contents/?ref=" rev))
                       true)
              dirs (->> entries (filter #(= (:type %) "dir")) (map :name))]
          (->> dirs
               (mapcat (fn [d]
                         (try
                           (let [sub (json/parse-string
                                      (sh-home "gh" "api"
                                               (str "repos/" owner-repo "/contents/" d "?ref=" rev))
                                      true)]
                             (->> sub
                                  (filter #(str/ends-with? (:name %) ".cabal"))
                                  (map :path)))
                           (catch Exception _ []))))
               vec))
        (catch Exception _ [])))))

;; Map of managed cabal package names to their repo names
;; e.g. "mts" -> "haskell-mts", "rocksdb-haskell-jprupp" -> "rocksdb-haskell"
(def pkg-name-to-repo
  {"mts" "haskell-mts"
   "rocksdb-haskell-jprupp" "rocksdb-haskell"
   "rocksdb-kv-transactions" "rocksdb-kv-transactions"
   "cardano-utxo-csmt" "cardano-utxo-csmt"
   "cardano-node-clients" "cardano-node-clients"
   "cardano-read-ledger" "cardano-read-ledger"
   "contra-tracer-contrib" "contra-tracer-contrib"
   "aiken-codegen" "aiken-codegen"
   "cardano-mpfs-cage" "cardano-mpfs-cage"
   "cardano-mpfs-offchain" "cardano-mpfs-offchain"
   "sparse-merkle-trees" "sparse-merkle-trees"})

(defn extract-managed-build-deps
  "From .cabal content, extract build-depends entries referencing managed packages.
   Returns map of repo-name -> set of sub-library references."
  [cabal-content]
  (let [;; Match patterns like: , mts:csmt or , rocksdb-haskell-jprupp >=2.1
        dep-pattern #"(?:,\s*|\bbuild-depends:\s*)([\w-]+(?::[\w-]+)?)"
        matches (re-seq dep-pattern cabal-content)]
    (->> matches
         (map second)  ; get the captured group
         (map (fn [dep]
                (let [[pkg sub] (str/split dep #":" 2)
                      repo-name (get pkg-name-to-repo pkg)]
                  (when repo-name
                    {:repo-name repo-name :ref (or sub pkg)}))))
         (filter some?)
         (group-by :repo-name)
         (map (fn [[repo-name entries]]
                [repo-name (->> entries (map :ref) distinct sort vec)]))
         (into {}))))

(defn fetch-build-deps-labels
  "For a given repo at rev, fetch .cabal files and extract managed build-depends."
  [owner-repo rev]
  (let [cabal-paths (find-cabal-files-recursive owner-repo rev)]
    (->> cabal-paths
         (map #(fetch-gh-file owner-repo rev %))
         (filter some?)
         (map extract-managed-build-deps)
         (apply merge-with into))))

;; Build label map: {[from-repo, to-repo-name] -> "sub1, sub2"}
(def cabal-edge-labels
  (let [froms (->> cabal-edges-raw (map :from) distinct)]
    (->> froms
         (mapcat (fn [from]
                   (let [rev (->> cabal-edges-raw
                                  (filter #(= (:from %) from))
                                  first :from-rev)
                         ;; Get full rev
                         full-rev (or (->> cabal-edges-raw
                                          (filter #(= (:from %) from))
                                          first :to-rev-full)
                                      rev)
                         ;; Use the from's own rev for fetching
                         from-rev (->> managed-nodes
                                       (filter #(= (:id %) from))
                                       first :rev)
                         deps (when from-rev
                                (fetch-build-deps-labels from from-rev))]
                     (when deps
                       (for [[repo-name refs] deps]
                         [[from repo-name] (str/join ", " refs)])))))
         (filter some?)
         (into {}))))

(defn edge-label
  "Get the label for a cabal edge."
  [from to]
  (let [to-name (last (str/split to #"/"))]
    (get cabal-edge-labels [from to-name] "")))

(def cabal-edges
  (->> cabal-edges-raw
       (map #(assoc % :label (edge-label (:from %) (:to %))))
       vec))

;; ── Step 4: Deduplicate repos (forks) ──────────────────────────────────────

(def owner-priority
  {"cardano-foundation" 0 "lambdasistemi" 1 "paolino" 2})

(def all-repos-raw
  (->> (concat
        (map :id managed-nodes)
        (map :to cabal-edges))
       distinct sort))

(def canonical-repos
  "Map of repo-name -> best owner/repo"
  (->> all-repos-raw
       (group-by #(last (str/split % #"/")))
       (map (fn [[name repos]]
              [name (first (sort-by #(get owner-priority (first (str/split % #"/")) 99) repos))]))
       (into {})))

(def unique-repos
  (->> (vals canonical-repos) sort vec))

;; ── Step 5: Fetch descriptions and languages ───────────────────────────────

(defn gh-repo-info [repo]
  (try
    (let [raw (sh-home "gh" "api" (str "repos/" repo)
                       "--jq" "[.description // \"(no description)\", .language // \"Unknown\"] | @tsv")]
      (let [[desc lang] (str/split raw #"\t")]
        {:description desc :language lang}))
    (catch Exception _ {:description "(private)" :language "Unknown"})))

(def repo-info
  (->> unique-repos
       (map (fn [r] [r (gh-repo-info r)]))
       (into {})))

(defn find-rev [repo]
  (or (->> managed-nodes
           (filter #(= (:id %) repo))
           first :rev-short)
      (->> cabal-edges
           (filter #(= (:to %) repo))
           first :to-rev)
      ""))

(defn find-full-rev [repo]
  (or (->> managed-nodes
           (filter #(= (:id %) repo))
           first :rev)
      (->> cabal-edges
           (filter #(= (:to %) repo))
           first :to-rev-full)
      ""))

;; ── Step 5b: Staleness check — compare pinned rev to default branch HEAD ──

(defn gh-staleness [repo pinned-rev]
  (try
    (let [;; Get default branch name and HEAD
          branch-raw (sh-home "gh" "api" (str "repos/" repo)
                              "--jq" ".default_branch")
          default-branch (str/trim branch-raw)
          head-raw (sh-home "gh" "api" (str "repos/" repo "/commits/" default-branch)
                            "--jq" ".sha")
          head-sha (str/trim head-raw)]
      (if (str/starts-with? head-sha pinned-rev)
        ;; Pinned is HEAD
        {:status "current" :behind 0 :default-branch default-branch :head-sha (subs head-sha 0 12)}
        ;; Compare
        (let [cmp-raw (sh-home "gh" "api"
                               (str "repos/" repo "/compare/" pinned-rev "..." default-branch)
                               "--jq" "[.status, .ahead_by, .behind_by] | @tsv")
              parts (str/split (str/trim cmp-raw) #"\t")
              status (first parts)
              ahead (try (Integer/parseInt (second parts)) (catch Exception _ 0))]
          (if (= status "ahead")
            ;; Default branch is ahead of pinned — pinned is behind
            {:status "behind" :behind ahead :default-branch default-branch :head-sha (subs head-sha 0 12)}
            (if (= status "identical")
              {:status "current" :behind 0 :default-branch default-branch :head-sha (subs head-sha 0 12)}
              ;; diverged or pinned is on a different branch
              (let [;; Try to find which branch contains the pinned commit
                    branches-raw (try
                                   (sh-home "gh" "api"
                                            (str "repos/" repo "/commits/" pinned-rev "/branches-where-head")
                                            "--jq" ".[].name")
                                   (catch Exception _ ""))
                    branches (->> (str/split-lines branches-raw)
                                  (map str/trim)
                                  (filter seq))]
                {:status "diverged"
                 :behind ahead
                 :default-branch default-branch
                 :head-sha (subs head-sha 0 12)
                 :branches (vec branches)}))))))
    (catch Exception e
      {:status "unknown" :error (.getMessage e)})))

;; Known org migrations: old-org -> new-org
;; When a repo shows as very stale under old-org, check if new-org has it
(def org-migrations
  {"input-output-hk" ["intersectmbo" "IntersectMBO" "cardano-foundation"]
   "IntersectMBO"    ["intersectmbo"]
   "intersectmbo"    ["IntersectMBO"]})

(defn detect-migration
  "Check if a repo has migrated to another org by probing GitHub."
  [owner repo-name]
  (when-let [candidate-orgs (get org-migrations owner)]
    (->> candidate-orgs
         (some (fn [new-org]
                 (try
                   (let [result (deref (p/process {:out :string :err :string}
                                                  "gh" "api" (str "repos/" new-org "/" repo-name)
                                                  "--jq" "[.full_name, .archived] | @tsv"))
                         exit (:exit result)]
                     (when (= exit 0)
                       (let [parts (str/split (str/trim (:out result)) #"\t")
                             full-name (first parts)
                             archived (= (second parts) "true")]
                         (when (and (seq full-name) (not archived))
                           {:migrated-to full-name}))))
                   (catch Exception _ nil)))))))

;; When --no-staleness is set, skip every default-branch HEAD comparison (moving
;; external state) so the output is a pure function of the pinned inputs — the
;; mode a CI drift gate diffs against.
(def staleness-info
  (if no-staleness?
    {}
    (->> unique-repos
         (map (fn [r]
                (let [rev (find-full-rev r)
                      info (when (seq rev) (gh-staleness r rev))
                      ;; Check for org migration when significantly behind or diverged
                      owner (first (str/split r #"/"))
                      repo-name (last (str/split r #"/"))
                      behind-count (or (:behind info) 0)
                      migration (when (and info (> behind-count 500))
                                  (detect-migration owner repo-name))
                      info (if migration (merge info migration) info)]
                  [r info])))
         (into {}))))

(defn staleness-badge [repo]
  (let [info (get staleness-info repo)]
    (if (:migrated-to info)
      (str "migrated → " (:migrated-to info))
      (case (:status info)
        "current" "up to date"
        "behind" (str (:behind info) " behind " (:default-branch info) " @ `" (:head-sha info) "`")
        "diverged" (let [br (:branches info)]
                     (str "diverged"
                          (when (seq br) (str ", on: " (str/join ", " br)))))
        "unknown" "?"
        ""))))

(defn staleness-short [repo]
  (let [info (get staleness-info repo)]
    (if (:migrated-to info)
      (str "→ " (first (str/split (:migrated-to info) #"/")))
      (case (:status info)
        "current" nil
        "behind" (str "↑" (:behind info))
        "diverged" (let [br (:branches info)]
                     (if (seq br)
                       (str "⑂ " (first br))
                       "⑂ diverged"))
        "unknown" "?"
        nil))))

;; ── Step 6: Output ─────────────────────────────────────────────────────────

(defn lang->class [lang]
  (case lang
    "Haskell" "haskell"
    "PureScript" "purescript"
    "Nix" "nix"
    ("Aiken" "aiken") "aiken"
    "haskell"))

(defn node-id [repo]
  (-> repo (str/split #"/") last (str/replace #"-" "_")))

(defn wrap-desc
  "Wrap description into lines of ~40 chars at word boundaries, joined by <br/>."
  [s]
  (if (<= (count s) 40)
    s
    (let [words (str/split s #"\s+")]
      (loop [remaining words, line "", lines []]
        (if (empty? remaining)
          (str/join "<br/>" (if (seq line) (conj lines line) lines))
          (let [w (first remaining)
                candidate (if (seq line) (str line " " w) w)]
            (if (> (count candidate) 40)
              (recur (rest remaining) w (conj lines line))
              (recur (rest remaining) candidate lines))))))))

(defn detect-lang [repo]
  (let [name (last (str/split repo #"/"))
        gh-lang (get-in repo-info [repo :language] "Unknown")]
    (cond
      (= name "dev-assets") "Nix"
      (= name "cardano-mpfs-onchain") "Aiken"
      :else gh-lang)))

(println (str "# " doc-title "\n"))
(println "Computed from the Nix flake closure + `cabal.project` `source-repository-package` entries at locked revisions. Every edge is pinned to an exact commit hash.\n")

;; Node table — the "Pin status" column carries staleness, so drop it under
;; --no-staleness to keep the table a pure function of the pinned inputs.
(println "## Repositories\n")
(if no-staleness?
  (do (println "| Repo | Owner | Description |")
      (println "|------|-------|-------------|")
      (printf "| [**%s**](https://github.com/%s/tree/%s) | %s | %s |\n"
              root-name root-owner root-ref (first (str/split root-owner #"/")) root-desc)
      (doseq [repo unique-repos]
        (let [name (last (str/split repo #"/"))
              owner (first (str/split repo #"/"))
              rev (find-rev repo)
              desc (get-in repo-info [repo :description] "")]
          (printf "| [**%s**](https://github.com/%s/tree/%s) | %s | %s |\n"
                  name repo rev owner desc))))
  (do (println "| Repo | Owner | Description | Pin status |")
      (println "|------|-------|-------------|------------|")
      (printf "| [**%s**](https://github.com/%s/tree/%s) | %s | %s | root |\n"
              root-name root-owner root-rev (first (str/split root-owner #"/")) root-desc)
      (doseq [repo unique-repos]
        (let [name (last (str/split repo #"/"))
              owner (first (str/split repo #"/"))
              rev (find-rev repo)
              desc (get-in repo-info [repo :description] "")
              badge (staleness-badge repo)]
          (printf "| [**%s**](https://github.com/%s/tree/%s) | %s | %s | %s |\n"
                  name repo rev owner desc badge)))))
(println)

;; Flake edges
(println "## Flake inputs\n")
(let [root-edges (filter #(= (:from %) "root") flake-edges)
      internal-edges (filter #(not= (:from %) "root") flake-edges)]

  (printf "### %s (root)\n\n" root-name)
  (println "| Input | Target | Type | Source |")
  (println "|-------|--------|------|--------|")
  (doseq [e root-edges]
    (printf "| `%s` | %s `%s` | %s | [flake.nix](https://github.com/%s/blob/%s/flake.nix) |\n"
            (:via e) (:to e) (:to-rev e) (:kind e) root-owner root-ref))
  (println)

  (doseq [[from edges] (group-by :from internal-edges)]
    (printf "### %s @ `%s`\n\n" from (:from-rev (first edges)))
    (println "| Input | Target | Type | Source |")
    (println "|-------|--------|------|--------|")
    (doseq [e edges]
      (printf "| `%s` | %s `%s` | %s | [flake.nix](https://github.com/%s/blob/%s/flake.nix) |\n"
              (:via e) (:to e) (:to-rev e) (:kind e) from (:from-rev e)))
    (println)))

;; Cabal edges
(println "## Cabal source-repository-package\n")
;; Group by (declarer, declarer-rev): a repo that appears at two different revs
;; (because of pin skew) gets one section per rev, each showing only its own pins.
(doseq [[[from from-rev] edges]
        (sort-by key (group-by (juxt :from :from-rev) cabal-edges))]
  (printf "### %s @ `%s`\n\n" from from-rev)
  (println "| Dependency | Locked tag | Source |")
  (println "|------------|-----------|--------|")
  (doseq [e (sort-by :to edges)]
    (printf "| %s | `%s` | [cabal.project:%d](https://github.com/%s/blob/%s/cabal.project#L%d) |\n"
            (:to e) (:to-rev e) (:line e) from (:from-rev e) (:line e)))
  (println))

;; Pin skew
(when (seq pin-skews)
  (println "## ⚠️ Pin skew\n")
  (println "The same dependency is pinned to different revisions by different declarers. Because `source-repository-package` entries are flattened at the root, **the root's pin wins** — any dependency declaring a different rev is silently built against the root's.\n")
  (doseq [{:keys [to effective decls]} pin-skews]
    (printf "### %s\n\n" to)
    (when effective
      (printf "Effective (root pin): [`%s`](https://github.com/%s/commit/%s)\n\n" effective to effective))
    (println "| Declared by | at its own rev | Pins this dep to |")
    (println "|-------------|----------------|------------------|")
    (doseq [{:keys [from from-rev rev rev-short]} (sort-by (juxt :from :from-rev) decls)]
      (printf "| %s | `%s` | [`%s`](https://github.com/%s/commit/%s) |\n"
              from from-rev rev-short to rev))
    (println)))

;; Mermaid
(println "## Diagram\n")
(println "```mermaid")
(println "graph TD")
(println "    classDef haskell fill:#5e5086,stroke:#3d3364,color:#fff")
(println "    classDef aiken fill:#e06c3c,stroke:#b34a24,color:#fff")
(println "    classDef purescript fill:#1d222d,stroke:#14181f,color:#fff")
(println "    classDef nix fill:#7ebae4,stroke:#5a8ab0,color:#000")
(println)

;; Root node
(let [rlang (if (re-find #"(?i)purescript|explorer" (or root-desc "")) "PureScript" "Unknown")]
  (printf "    %s[\"<a href='https://github.com/%s/tree/%s'>%s</a><br/>%s<br/><a href='https://github.com/%s/commit/%s'><code>%s</code></a>\"]:::%s\n"
          (node-id root-owner) root-owner root-ref root-name (wrap-desc root-desc)
          root-owner root-ref root-ref (lang->class rlang)))

;; Other nodes (deduplicated)
(doseq [repo unique-repos]
  (let [name (last (str/split repo #"/"))
        rev (find-rev repo)
        desc (wrap-desc (get-in repo-info [repo :description] ""))
        lang (detect-lang repo)
        stale (staleness-short repo)
        stale-line (if stale (str "<br/><b>" stale "</b>") "")]
    (printf "    %s[\"<a href='https://github.com/%s/tree/%s'>%s</a><br/>%s<br/><a href='https://github.com/%s/commit/%s'><code>%s</code></a>%s\"]:::%s\n"
            (node-id repo) repo rev name desc repo rev rev stale-line (lang->class lang))))

(println)

;; Edges with index tracking
(let [edge-idx (atom 0)
      flake-idx (atom [])
      follows-idx (atom [])
      cabal-idx (atom [])
      skew-idx (atom [])

      emit-edge! (fn [from-id to-id kind label]
                   (let [lbl (if (and label (seq label))
                               (format "|\"%s\"|" label)
                               "")]
                     (case kind
                       "flake" (do (printf "    %s -->%s %s\n" from-id lbl to-id)
                                   (swap! flake-idx conj @edge-idx))
                       "follows" (do (printf "    %s -.->%s %s\n" from-id lbl to-id)
                                     (swap! follows-idx conj @edge-idx))
                       "cabal" (do (printf "    %s ==>%s %s\n" from-id lbl to-id)
                                   (swap! cabal-idx conj @edge-idx))
                       "skew" (do (printf "    %s -.->%s %s\n" from-id lbl to-id)
                                  (swap! skew-idx conj @edge-idx))))
                   (swap! edge-idx inc))

      root-id (node-id root-owner)]

  ;; Flake edges
  (doseq [e flake-edges
          :let [from-id (if (= (:from e) "root") root-id (node-id (:from e)))
                to-id (node-id (:to e))]
          :when (not= from-id to-id)]
    (emit-edge! from-id to-id (:kind e) (:via e)))

  ;; Cabal edges (deduplicated by canonical name)
  (let [seen (atom #{})]
    (doseq [e cabal-edges
            :let [from-id (node-id (:from e))
                  to-id (node-id (:to e))
                  edge-key (str from-id "__" to-id)]
            :when (not (@seen edge-key))]
      (swap! seen conj edge-key)
      (emit-edge! from-id to-id "cabal" (:label e))))

  ;; Pin-skew edges: dashed amber from each non-root declarer that pins a
  ;; different rev than the effective (root) pin. Deduplicated by endpoints+rev.
  (let [skew-seen (atom #{})]
    (doseq [{:keys [to effective decls]} pin-skews
            {:keys [from rev-short]} decls
            :let [from-id (if (= from root-owner) root-id (node-id from))
                  to-id (node-id to)
                  ekey [from-id to-id rev-short]]
            :when (and (not= from root-owner)
                       (not= rev-short effective)
                       (not= from-id to-id)
                       (not (@skew-seen ekey)))]
      (swap! skew-seen conj ekey)
      (emit-edge! from-id to-id "skew" (str "skew " rev-short))))

  (println)

  (when (seq @flake-idx)
    (printf "    linkStyle %s stroke:#2196F3,stroke-width:2px\n"
            (str/join "," @flake-idx)))
  (when (seq @follows-idx)
    (printf "    linkStyle %s stroke:#90CAF9,stroke-width:1px\n"
            (str/join "," @follows-idx)))
  (when (seq @cabal-idx)
    (printf "    linkStyle %s stroke:#e53935,stroke-width:2px\n"
            (str/join "," @cabal-idx)))
  (when (seq @skew-idx)
    (printf "    linkStyle %s stroke:#ffb300,stroke-width:1px,stroke-dasharray:4 3\n"
            (str/join "," @skew-idx))))

(println "```")
(println)
(println "**Legend**")
(println)
(println "| | |")
(println "|---|---|")
(println "| **Nodes** | |")
(println "| ![#5e5086](https://placehold.co/15x15/5e5086/5e5086.png) Purple | Haskell |")
(println "| ![#e06c3c](https://placehold.co/15x15/e06c3c/e06c3c.png) Orange | Aiken |")
(println "| ![#1d222d](https://placehold.co/15x15/1d222d/1d222d.png) Dark | PureScript |")
(println "| ![#7ebae4](https://placehold.co/15x15/7ebae4/7ebae4.png) Blue | Nix |")
(println "| **Edges** | |")
(println "| ![#2196F3](https://placehold.co/15x15/2196F3/2196F3.png) Blue solid ──> | Flake input (declared in `flake.nix`) |")
(println "| ![#90CAF9](https://placehold.co/15x15/90CAF9/90CAF9.png) Light blue dashed --.-> | Flake follows (delegated to another input) |")
(println "| ![#e53935](https://placehold.co/15x15/e53935/e53935.png) Red thick ==> | Cabal `source-repository-package` |")
(println "| ![#ffb300](https://placehold.co/15x15/ffb300/ffb300.png) Amber dashed --.-> | Pin skew: declarer pins a different rev than the effective (root) pin |")
(when-not no-staleness?
  (println "| **Pin status** | |")
  (println "| ↑N | Pinned commit is N commits behind the default branch HEAD |")
  (println "| ⑂ branch | Pinned commit is on a different branch (diverged from default) |")
  (println "| → org | Repo has migrated to a different GitHub org (pin is on stale fork) |"))
