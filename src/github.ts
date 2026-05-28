export const API = "https://api.github.com";

export interface FrontMatter {
  meta: Record<string, string>;
  body: string;
}

export class GitHubError extends Error {
  constructor(message: string, public code: number) {
    super(message);
  }
}

export function b64utf8(b64: string): string {
  const bin = atob(b64.replace(/\s/g, ""));
  const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
  return new TextDecoder("utf-8").decode(bytes);
}

export function parseFrontMatter(raw: string): FrontMatter {
  const m = raw.match(/^﻿?---\s*\n([\s\S]*?)\n---\s*\n?/);
  const meta: Record<string, string> = {};
  let body = raw;
  if (m) {
    body = raw.slice(m[0].length);
    for (const line of m[1]!.split("\n")) {
      const kv = line.match(/^([A-Za-z0-9_]+)\s*:\s*(.*)$/);
      if (kv) meta[kv[1]!.toLowerCase()] = kv[2]!.trim().replace(/^["']|["']$/g, "");
    }
  }
  return { meta, body: body.trim() };
}

export async function ghJSON<T>(url: string, opts?: RequestInit): Promise<T> {
  const res = await fetch(url, opts);
  if (res.status === 403 || res.status === 429) {
    const rateLimited = res.headers.get("x-ratelimit-remaining") === "0";
    throw new GitHubError(rateLimited ? "ratelimit" : "forbidden", res.status);
  }
  if (!res.ok) throw new GitHubError(`http ${res.status}`, res.status);
  return res.json() as Promise<T>;
}
