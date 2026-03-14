document.addEventListener("DOMContentLoaded", function () {
  var synth = window.speechSynthesis;
  if (!synth) return;

  var playing = null;
  var queue = [];
  var currentIndex = 0;
  var speechData = null;

  // Try loading speech JSON for this page
  var pagePath = window.location.pathname
    .replace(/\/$/, "")
    .replace(/\/index$/, "");
  var speechUrl = pagePath + ".speech.json";
  if (pagePath === "" || pagePath === "/") {
    speechUrl = "/index.speech.json";
  }

  fetch(speechUrl)
    .then(function (r) {
      if (r.ok) return r.json();
      return null;
    })
    .then(function (data) {
      speechData = data;
    })
    .catch(function () {
      speechData = null;
    });

  function extractText(el) {
    var cloned = el.cloneNode(true);
    cloned.querySelectorAll(
      "pre, code, .mermaid, table, .md-nav, .md-footer"
    ).forEach(function (node) {
      node.remove();
    });
    return cloned.textContent.replace(/\s+/g, " ").trim();
  }

  function collectSegments(elements) {
    var segments = [];
    elements.forEach(function (el) {
      if (el.tagName === "UL" || el.tagName === "OL") {
        el.querySelectorAll(":scope > li").forEach(function (li) {
          var text = extractText(li);
          if (text.length > 0) {
            segments.push({ text: text + ".", pause: 300 });
          }
        });
      } else {
        var text = extractText(el);
        if (text.length > 0) {
          segments.push({ text: text, pause: 200 });
        }
      }
    });
    return segments;
  }

  function getSectionId(heading) {
    return heading.id || heading.textContent.trim().toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/(^-|-$)/g, "");
  }

  function createButton() {
    var btn = document.createElement("button");
    btn.textContent = "\u25B6";
    btn.title = "Read aloud";
    btn.style.cssText =
      "background:none;border:1px solid var(--md-default-fg-color--lighter);" +
      "border-radius:4px;cursor:pointer;font-size:14px;padding:2px 8px;" +
      "margin-left:8px;opacity:0.5;vertical-align:middle;color:inherit;";
    btn.addEventListener("mouseenter", function () {
      btn.style.opacity = "1";
    });
    btn.addEventListener("mouseleave", function () {
      if (playing !== btn) btn.style.opacity = "0.5";
    });
    return btn;
  }

  function stopSpeaking() {
    synth.cancel();
    queue = [];
    currentIndex = 0;
    if (playing) {
      playing.textContent = "\u25B6";
      playing.style.opacity = "0.5";
      playing = null;
    }
  }

  function speakSegment(btn) {
    if (currentIndex >= queue.length) {
      btn.textContent = "\u25B6";
      btn.style.opacity = "0.5";
      playing = null;
      return;
    }
    var seg = queue[currentIndex];
    if (seg.skip) {
      currentIndex++;
      speakSegment(btn);
      return;
    }
    var utterance = new SpeechSynthesisUtterance(seg.text);
    utterance.rate = seg.rate || 1.0;
    utterance.onend = function () {
      currentIndex++;
      var pause = seg.pause || 200;
      if (pause > 0) {
        setTimeout(function () { speakSegment(btn); }, pause);
      } else {
        speakSegment(btn);
      }
    };
    synth.speak(utterance);
  }

  document.querySelectorAll("h2, h3").forEach(function (heading) {
    var section = [];
    var sibling = heading.nextElementSibling;
    while (sibling && !sibling.matches("h2, h3")) {
      section.push(sibling);
      sibling = sibling.nextElementSibling;
    }
    if (section.length === 0) return;

    var fallbackSegments = collectSegments(section);
    if (fallbackSegments.length === 0) return;

    var sectionId = getSectionId(heading);
    var btn = createButton();
    heading.appendChild(btn);

    btn.addEventListener("click", function (e) {
      e.preventDefault();
      e.stopPropagation();

      if (playing === btn) {
        stopSpeaking();
        return;
      }

      stopSpeaking();

      // Prefer speech JSON if available for this section
      if (speechData && speechData[sectionId]) {
        queue = speechData[sectionId];
      } else {
        queue = fallbackSegments;
      }

      currentIndex = 0;
      btn.textContent = "\u25A0";
      btn.style.opacity = "1";
      playing = btn;
      speakSegment(btn);
    });
  });
});
