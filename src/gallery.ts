import { API, GitHubError, b64utf8, ghJSON, parseFrontMatter } from "./github";
import { esc, md } from "./markdown";

const ORG = "sol-apps";
const TOPIC = "solhann-app";
const CACHE_KEY = "solhann_gallery_v1";
const CACHE_TTL = 10 * 60 * 1000; // 10 min — be kind to the 60/hr unauth limit

export interface App {
  slug: string;
  title: string;
  description: string;
  emoji: string;
  url: string;
  repo: string;
  readme: string;
}

interface Cached {
  t: number;
  data: App[];
}

interface RepoSearchResult {
  items?: Array<{
    name: string;
    full_name: string;
    description: string | null;
    html_url: string;
  }>;
}

interface ReadmeResponse {
  content: string;
}

async function discover(): Promise<App[]> {
  const q = encodeURIComponent(`org:${ORG} topic:${TOPIC} fork:true`);
  const search = await ghJSON<RepoSearchResult>(
    `${API}/search/repositories?q=${q}&per_page=100&sort=updated`
  );
  const repos = search.items ?? [];
  return Promise.all(
    repos.map(async (r): Promise<App> => {
      let meta: Record<string, string> = {};
      let body = "";
      try {
        const readme = await ghJSON<ReadmeResponse>(`${API}/repos/${r.full_name}/readme`);
        const parsed = parseFrontMatter(b64utf8(readme.content));
        meta = parsed.meta;
        body = parsed.body;
      } catch { /* no readme / rate-limited mid-flight: degrade */ }
      const slug = (meta.slug ?? r.name).toLowerCase();
      return {
        slug,
        title: meta.title ?? r.name,
        description: meta.description ?? r.description ?? "",
        emoji: meta.emoji ?? "🕹️",
        url: `https://${slug}.solhann.net`,
        repo: r.html_url,
        readme: body,
      };
    })
  );
}

function readCache(): App[] | null {
  try {
    const c = JSON.parse(sessionStorage.getItem(CACHE_KEY) ?? "null") as Cached | null;
    if (c && Date.now() - c.t < CACHE_TTL) return c.data;
  } catch { /* ignore */ }
  return null;
}

function readStaleCache(): App[] | null {
  try {
    const c = JSON.parse(sessionStorage.getItem(CACHE_KEY) ?? "null") as Cached | null;
    if (c?.data) return c.data;
  } catch { /* ignore */ }
  return null;
}

function writeCache(data: App[]): void {
  try {
    sessionStorage.setItem(CACHE_KEY, JSON.stringify({ t: Date.now(), data } satisfies Cached));
  } catch { /* ignore */ }
}

function renderLoading(gallery: HTMLElement): void {
  gallery.setAttribute("aria-busy", "true");
  gallery.innerHTML = Array.from({ length: 6 }, () => '<div class="skel"></div>').join("");
}

function renderError(gallery: HTMLElement, rate: boolean): void {
  gallery.setAttribute("aria-busy", "false");
  gallery.innerHTML = `<div class="notice">
    <div class="big">${rate ? "&#9888; RATE LIMITED" : "&#9888; CONNECTION LOST"}</div>
    <div class="sub">${
      rate
        ? "GitHub's anonymous API limit (60/hr) is spent. Give it a few minutes and reload."
        : "Couldn't reach the GitHub API. Check your connection and reload."
    }</div>
  </div>`;
}

function renderEmpty(gallery: HTMLElement, prompt: HTMLElement | null): void {
  gallery.setAttribute("aria-busy", "false");
  if (prompt) prompt.style.display = "none";
  gallery.innerHTML = `<div class="notice">
    <div class="coin">&#129689;</div>
    <div class="big">NO APPS INSERTED YET</div>
    <div class="sub">Tag a repo in <a href="https://github.com/${ORG}" target="_blank" rel="noopener">sol-apps</a>
    with the <code>solhann-app</code> topic and it appears here automatically.</div>
  </div>`;
}

function render(gallery: HTMLElement, prompt: HTMLElement | null, apps: App[]): void {
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
          <button class="src" data-act="code" title="view source on GitHub">&lt;/&gt;</button>
          <div class="emoji">${esc(a.emoji)}</div>
          <h2 class="card-title">${esc(a.title)}</h2>
          <p class="card-desc">${esc(a.description)}</p>
          <div class="card-actions">
            <button class="btn primary" data-act="launch">&#9656; LAUNCH</button>
            <button class="btn" data-act="readme">READ ME</button>
          </div>
        </div>
        <div class="face back">
          <div class="back-bar"><span>${esc(a.title)}</span><button class="x" data-act="back">&times; CLOSE</button></div>
          <div class="readme">${a.readme ? md(a.readme) : "<p>No README yet.</p>"}</div>
        </div>
      </div>
    </article>`
    )
    .join("");
}

function wireInteractions(gallery: HTMLElement): void {
  gallery.addEventListener("click", (e) => {
    const target = e.target as HTMLElement;
    const card = target.closest<HTMLElement>(".card");
    if (!card) return;
    const act = target.closest<HTMLElement>("[data-act]")?.dataset.act;
    if (target.closest(".readme a")) return; // let README links work
    if (act === "code") {
      window.open(card.dataset.repo, "_blank", "noopener");
      return;
    }
    if (act === "readme") {
      card.classList.add("flipped");
      return;
    }
    if (act === "back") {
      card.classList.remove("flipped");
      return;
    }
    if (card.classList.contains("flipped")) return; // ignore body clicks while reading
    window.open(card.dataset.url, "_blank", "noopener");
  });
}

export async function loadGallery(gallery: HTMLElement, prompt: HTMLElement | null): Promise<void> {
  wireInteractions(gallery);
  renderLoading(gallery);

  const cached = readCache();
  if (cached) {
    render(gallery, prompt, cached);
    return;
  }

  try {
    const apps = await discover();
    writeCache(apps);
    render(gallery, prompt, apps);
  } catch (e) {
    const stale = readStaleCache();
    if (stale) {
      render(gallery, prompt, stale);
      return;
    }
    const rate = e instanceof GitHubError && e.message === "ratelimit";
    renderError(gallery, rate);
  }
}
