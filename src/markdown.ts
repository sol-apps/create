const ENTITY_MAP: Record<string, string> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};

export const esc = (s: string): string =>
  s.replace(/[&<>"']/g, (c) => ENTITY_MAP[c]!);

/* tiny, safe-ish markdown -> html (input is HTML-escaped first; raw HTML in README is neutralised) */
export function md(src: string): string {
  const blocks: string[] = [];
  src = src.replace(/```([\s\S]*?)```/g, (_, c: string) => {
    blocks.push(c.replace(/^\n/, ""));
    return ` ${blocks.length - 1} `;
  });
  src = esc(src);
  const lines = src.split("\n");
  let html = "";
  let list: "ul" | "ol" | null = null;
  const closeList = () => {
    if (list) {
      html += `</${list}>`;
      list = null;
    }
  };
  const inline = (t: string): string =>
    t
      .replace(/!\[([^\]]*)\]\((https?:[^)\s]+)\)/g, '<img alt="$1" src="$2">')
      .replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>')
      .replace(/`([^`]+)`/g, "<code>$1</code>")
      .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
      .replace(/(^|[^*])\*([^*\n]+)\*/g, "$1<em>$2</em>")
      .replace(/_([^_\n]+)_/g, "<em>$1</em>");

  for (const raw of lines) {
    const ph = raw.match(/^ (\d+) $/);
    if (ph) {
      closeList();
      html += `<pre><code>${esc(blocks[Number(ph[1])]!)}</code></pre>`;
      continue;
    }
    const h = raw.match(/^(#{1,6})\s+(.*)$/);
    if (h) {
      closeList();
      const n = h[1]!.length;
      html += `<h${n}>${inline(h[2]!)}</h${n}>`;
      continue;
    }
    const ul = raw.match(/^\s*[-*]\s+(.*)$/);
    const ol = raw.match(/^\s*\d+\.\s+(.*)$/);
    if (ul) {
      if (list !== "ul") {
        closeList();
        html += "<ul>";
        list = "ul";
      }
      html += `<li>${inline(ul[1]!)}</li>`;
      continue;
    }
    if (ol) {
      if (list !== "ol") {
        closeList();
        html += "<ol>";
        list = "ol";
      }
      html += `<li>${inline(ol[1]!)}</li>`;
      continue;
    }
    if (!raw.trim()) {
      closeList();
      continue;
    }
    closeList();
    html += `<p>${inline(raw)}</p>`;
  }
  closeList();
  return html;
}
