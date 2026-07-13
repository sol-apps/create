/* create.solhann.net — the app gallery.
 *
 * Discovery is server-side: this app's own PocketBase runs
 * pb_hooks/gallery.pb.js, which proxies + caches the GitHub org search
 * (org:sol-apps topic:solhann-app), so visitors never spend GitHub's
 * anonymous rate limit. The client just fetches /api/gallery and renders.
 */
(() => {
  "use strict";

  const ORG = "sol-apps";

  /* sha256 of the cheat code*/
  const KEY_HASH = "e7749c35f442f154e3a644e88a23a608f22f0d22afdf548f3f010afc34e3f7ad";
  const KEY_STORE = "solhann_key";

  /* ── theme ─────────────────────────────────────────────── */

  const THEME_KEY = "solhann_theme";

  function initTheme(toggle) {
    const root = document.documentElement;

    const setTheme = (t) => {
      root.setAttribute("data-theme", t);
      toggle.textContent = t === "dark" ? "LIGHT" : "DARK";
      try { localStorage.setItem(THEME_KEY, t); } catch { /* ignore */ }
    };

    let saved = "light";
    try {
      const stored = localStorage.getItem(THEME_KEY);
      if (stored === "dark" || stored === "light") saved = stored;
    } catch { /* ignore */ }
    setTheme(saved);

    toggle.addEventListener("click", () => {
      setTheme(root.getAttribute("data-theme") === "dark" ? "light" : "dark");
    });
  }

  /* ── html escaping ─────────────────────────────────────── */

  const ENTITY_MAP = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  };

  const esc = (s) => s.replace(/[&<>"']/g, (c) => ENTITY_MAP[c]);

  /* ── gallery rendering ─────────────────────────────────── */

  function renderLoading(gallery) {
    gallery.setAttribute("aria-busy", "true");
    gallery.innerHTML = Array.from({ length: 6 }, () => '<div class="skel"></div>').join("");
  }

  function renderError(gallery) {
    gallery.setAttribute("aria-busy", "false");
    gallery.innerHTML = `<div class="notice">
      <div class="big">&#9888; CONNECTION LOST</div>
      <div class="sub">Couldn't load the gallery. Give it a moment and reload.</div>
    </div>`;
  }

  function renderEmpty(gallery, prompt) {
    gallery.setAttribute("aria-busy", "false");
    if (prompt) prompt.style.display = "none";
    gallery.innerHTML = `<div class="notice">
      <div class="coin">&#129689;</div>
      <div class="big">NO APPS INSERTED YET</div>
      <div class="sub">Tag a repo in <a href="https://github.com/${ORG}" target="_blank" rel="noopener">${ORG}</a>
      with the <code>solhann-app</code> topic and it appears here automatically.</div>
    </div>`;
  }

  function render(gallery, prompt, apps) {
    gallery.setAttribute("aria-busy", "false");
    if (!apps.length) {
      renderEmpty(gallery, prompt);
      return;
    }
    gallery.innerHTML = apps
      .map(
        (a, i) => `
      <article class="card" style="animation-delay:${i * 70}ms" data-url="${esc(a.url)}" data-repo="${esc(a.repo)}">
        <div class="card-inner">
          <div class="face front">
            <div class="card-head">
              <div class="emoji">${esc(a.emoji)}</div>
              <h2 class="card-title">${esc(a.title)}</h2>
            </div>
            <div class="card-actions">
              <button class="btn primary" data-act="launch">&#9656; LAUNCH</button>
              <button class="btn" data-act="code" title="view source on GitHub">&lt;/&gt;</button>
            </div>
          </div>
        </div>
      </article>`
      )
      .join("");
  }

  function wireInteractions(gallery) {
    gallery.addEventListener("click", (e) => {
      const target = e.target;
      const card = target.closest(".card");
      if (!card) return;
      const act = target.closest("[data-act]")?.dataset.act;
      if (act === "code") {
        window.open(card.dataset.repo, "_blank", "noopener");
        return;
      }
      window.open(card.dataset.url, "_blank", "noopener");
    });
  }

  async function loadGallery(gallery, prompt, key) {
    renderLoading(gallery);
    try {
      const res = await fetch("/api/gallery" + (key ? "?key=" + encodeURIComponent(key) : ""));
      if (!res.ok) throw new Error(`http ${res.status}`);
      render(gallery, prompt, await res.json());
    } catch {
      renderError(gallery);
    }
  }

  /* ── cheat code (passowrd entry_ ────────────────────────────────────────── */

  async function sha256hex(text) {
    if (!crypto.subtle) return ""; // http dev context: gate simply stays shut
    const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
    return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
  }

  function markUnlocked(input) {
    input.value = "";
    input.placeholder = "UNLOCKED \u2605";
    input.disabled = true;
    input.classList.add("unlocked");
  }

  /* unlock survives the tab's lifetime, not the browser's */
  async function savedKey() {
    try {
      const k = sessionStorage.getItem(KEY_STORE) || "";
      if (k && (await sha256hex(k)) === KEY_HASH) return k;
    } catch { /* ignore */ }
    return "";
  }

  function initPasskey(input, onUnlock) {
    input.addEventListener("input", () => {
      const v = input.value.trim();
      if (!v) return;
      void sha256hex(v).then((h) => {
        if (h !== KEY_HASH) return;
        try { sessionStorage.setItem(KEY_STORE, v); } catch { /* ignore */ }
        markUnlocked(input);
        onUnlock(v);
      });
    });
  }

  /* ── boot ──────────────────────────────────────────────── */

  const themeToggle = document.getElementById("themeToggle");
  const gallery = document.getElementById("gallery");
  const prompt = document.getElementById("prompt");
  const passkey = document.getElementById("passkey");

  if (themeToggle) initTheme(themeToggle);
  if (gallery) {
    wireInteractions(gallery);
    void (async () => {
      const key = await savedKey();
      if (key && passkey) markUnlocked(passkey);
      await loadGallery(gallery, prompt, key);
    })();
    if (passkey) initPasskey(passkey, (key) => void loadGallery(gallery, prompt, key));
  }
})();
