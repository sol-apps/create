const STORAGE_KEY = "solhann_theme";

export type Theme = "light" | "dark";

export function initTheme(toggle: HTMLButtonElement): void {
  const root = document.documentElement;

  const setTheme = (t: Theme) => {
    root.setAttribute("data-theme", t);
    toggle.textContent = t === "dark" ? "LIGHT" : "DARK";
    try { localStorage.setItem(STORAGE_KEY, t); } catch { /* ignore */ }
  };

  let saved: Theme = "light";
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored === "dark" || stored === "light") saved = stored;
  } catch { /* ignore */ }
  setTheme(saved);

  toggle.addEventListener("click", () => {
    const next: Theme = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    setTheme(next);
  });
}
