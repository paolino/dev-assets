document.addEventListener("DOMContentLoaded", function () {
  var synth = window.speechSynthesis;
  if (!synth) return;

  var playing = null;

  function getTextContent(section) {
    var cloned = section.cloneNode(true);
    cloned.querySelectorAll(
      "pre, code, .mermaid, table, .md-nav, .md-footer"
    ).forEach(function (el) {
      el.remove();
    });
    return cloned.textContent.replace(/\s+/g, " ").trim();
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
    if (playing) {
      playing.textContent = "\u25B6";
      playing.style.opacity = "0.5";
      playing = null;
    }
  }

  document.querySelectorAll("h2, h3").forEach(function (heading) {
    var section = [];
    var sibling = heading.nextElementSibling;
    while (sibling && !sibling.matches("h2, h3")) {
      section.push(sibling);
      sibling = sibling.nextElementSibling;
    }
    if (section.length === 0) return;

    var wrapper = document.createElement("div");
    section.forEach(function (el) {
      wrapper.appendChild(el.cloneNode(true));
    });
    var text = getTextContent(wrapper);
    if (text.length < 20) return;

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
      var utterance = new SpeechSynthesisUtterance(text);
      utterance.rate = 1.0;
      utterance.onend = function () {
        btn.textContent = "\u25B6";
        btn.style.opacity = "0.5";
        playing = null;
      };
      btn.textContent = "\u25A0";
      btn.style.opacity = "1";
      playing = btn;
      synth.speak(utterance);
    });
  });
});
