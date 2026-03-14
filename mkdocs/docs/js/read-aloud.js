document.addEventListener("DOMContentLoaded", function () {
  var synth = window.speechSynthesis;
  if (!synth) return;

  var playing = null;
  var queue = [];
  var currentIndex = 0;

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
          if (text.length > 0) segments.push(text + ".");
        });
      } else {
        var text = extractText(el);
        if (text.length > 0) segments.push(text);
      }
    });
    return segments;
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

  function speakNext(btn) {
    if (currentIndex >= queue.length) {
      btn.textContent = "\u25B6";
      btn.style.opacity = "0.5";
      playing = null;
      return;
    }
    var utterance = new SpeechSynthesisUtterance(queue[currentIndex]);
    utterance.rate = 1.0;
    utterance.onend = function () {
      currentIndex++;
      speakNext(btn);
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

    var segments = collectSegments(section);
    if (segments.length === 0) return;

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
      queue = segments;
      currentIndex = 0;
      btn.textContent = "\u25A0";
      btn.style.opacity = "1";
      playing = btn;
      speakNext(btn);
    });
  });
});
