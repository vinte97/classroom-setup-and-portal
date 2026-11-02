(function (root) {
  var CLIENT_PREFIX = "workai://share/prompt?text=";
  var WEB_PREFIX = "https://workai.su/link/prompt?text=";
  var CLIENT_MAX = 8000;

  function workaiHref(text) {
    var encoded = encodeURIComponent(text);
    if ((CLIENT_PREFIX + encoded).length > CLIENT_MAX) return null;
    return WEB_PREFIX + encoded;
  }

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  function selectNode(node) {
    var range = document.createRange();
    range.selectNodeContents(node);
    var selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }

  function copyText(text, status, source) {
    function done(ok) {
      if (ok) {
        status.textContent = "Скопировано";
        return;
      }
      if (source) selectNode(source);
      status.textContent = "Автокопирование недоступно. Текст выделен: нажмите Ctrl+C или Cmd+C.";
    }
    function fallback() {
      var area = document.createElement("textarea");
      area.value = text;
      area.setAttribute("readonly", "");
      area.style.position = "fixed";
      area.style.top = "0";
      area.style.left = "0";
      area.style.opacity = "0";
      document.body.appendChild(area);
      area.focus();
      area.select();
      var ok = false;
      try { ok = document.execCommand("copy"); } catch (err) { ok = false; }
      document.body.removeChild(area);
      done(ok);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () { done(true); }, fallback);
      return;
    }
    fallback();
  }

  function renderPrompt(host, prompt) {
    var card = el("article", "prompt");
    card.appendChild(el("h2", null, prompt.title));
    card.appendChild(el("p", null, prompt.goal));
    card.appendChild(el("p", "meta", "Версия " + prompt.version + " · день " + prompt.day));
    card.appendChild(el("p", null, "Нужные файлы"));
    var list = el("ul");
    (prompt.inputs || []).forEach(function (item) {
      list.appendChild(el("li", null, item));
    });
    card.appendChild(list);
    var block = el("pre", null, prompt.text);
    card.appendChild(block);
    var actions = el("div", "actions");
    var copy = el("button", null, "Скопировать");
    copy.type = "button";
    var status = el("p", "status", "");
    status.setAttribute("aria-live", "polite");
    copy.addEventListener("click", function () { copyText(prompt.text, status, block); });
    actions.appendChild(copy);
    var href = workaiHref(prompt.text);
    if (href) {
      var link = el("a", "btn secondary", "Открыть в WorkAI");
      link.href = href;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      actions.appendChild(link);
    } else {
      actions.appendChild(el("p", "note", "Текст длиннее лимита ссылки WorkAI. Остаётся кнопка «Скопировать»."));
    }
    card.appendChild(actions);
    card.appendChild(status);
    host.appendChild(card);
  }

  function init() {
    var host = document.getElementById("prompt-list");
    if (host) {
      var day = host.getAttribute("data-day");
      var prompts = root.COURSE_PROMPTS || [];
      prompts.forEach(function (prompt) {
        if (day && day !== "all" && String(prompt.day) !== String(day)) return;
        renderPrompt(host, prompt);
      });
      if (!host.children.length) {
        host.appendChild(el("p", "note", "Промпты не загрузились. Откройте index.html из папки docs целиком, вместе с соседними файлами."));
      }
    }
    var pack = root.COURSE_PACK;
    var hash = document.getElementById("pack-hash");
    if (pack && hash) hash.textContent = "SHA-256: " + pack.zip_sha256;
    var link = document.getElementById("pack-link");
    if (pack && link && pack.zip_name) link.setAttribute("href", "files/" + pack.zip_name);
  }

  if (typeof document !== "undefined") {
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
    else init();
  }

  if (typeof module !== "undefined" && module.exports) {
    module.exports = {
      workaiHref: workaiHref,
      CLIENT_MAX: CLIENT_MAX,
      CLIENT_PREFIX: CLIENT_PREFIX,
      WEB_PREFIX: WEB_PREFIX
    };
  }
})(typeof window !== "undefined" ? window : global);
