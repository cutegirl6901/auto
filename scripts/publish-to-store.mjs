#!/usr/bin/env node
// Upload built files to the public store repository so SideStore can fetch them.
//
// The source repository is private; SideStore downloads anonymously, so the IPA
// and its source.json must live in a public repository instead.
//
// Usage:
//   node scripts/publish-to-store.mjs <tag> <path-to-ipa> [owner/repo]
//
// Example:
//   node scripts/publish-to-store.mjs v0.10.1 build/TuneMetronome.ipa
//
// Requires a token with Contents write on the store repository, taken from the
// GITHUB_STORE_TOKEN environment variable.
import { readFileSync } from "node:fs";

const [tag, ipaPath, repoArg] = process.argv.slice(2);
if (!tag || !ipaPath) {
  console.error("usage: publish-to-store.mjs <tag> <ipa> [owner/repo]");
  process.exit(1);
}

const repo = repoArg || "likehao0522cn-gif/tune-store";
const token = process.env.GITHUB_STORE_TOKEN;
if (!token) {
  console.error("GITHUB_STORE_TOKEN is not set");
  process.exit(1);
}

const headers = {
  "User-Agent": "publish-to-store",
  Authorization: "token " + token,
  Accept: "application/vnd.github+json"
};

async function api(path, method = "GET", body = null) {
  const res = await fetch("https://api.github.com" + path, {
    method,
    headers: { ...headers, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined
  });
  const text = await res.text();
  if (!res.ok) throw new Error(method + " " + path + " -> " + res.status + " " + text.slice(0, 300));
  return text ? JSON.parse(text) : null;
}

async function uploadAsset(releaseId, name, content, contentType) {
  const res = await fetch(
    `https://uploads.github.com/repos/${repo}/releases/${releaseId}/assets?name=${encodeURIComponent(name)}`,
    { method: "POST", headers: { ...headers, "Content-Type": contentType, "Content-Length": String(content.length) }, body: content }
  );
  const text = await res.text();
  if (!res.ok) throw new Error("upload " + name + " -> " + res.status + " " + text.slice(0, 300));
  return JSON.parse(text);
}

const ipa = readFileSync(ipaPath);
const source = readFileSync("docs/store/source.json");
const icon = readFileSync("docs/store/icon.png");

// Reuse the release for this tag, or create it.
let release;
try {
  release = await api(`/repos/${repo}/releases/tags/${tag}`);
} catch {
  release = await api(`/repos/${repo}/releases`, "POST", {
    tag_name: tag,
    name: "TuneMetronome " + tag.replace(/^v/, ""),
    body: "调音节拍器 " + tag.replace(/^v/, ""),
    draft: false,
    prerelease: false
  });
}

// Replace any existing copy of each asset.
for (const name of ["TuneMetronome.ipa", "source.json", "icon.png"]) {
  const existing = (release.assets || []).find(a => a.name === name);
  if (existing) {
    await fetch(`https://api.github.com/repos/${repo}/releases/assets/${existing.id}`, {
      method: "DELETE", headers
    });
  }
}

await uploadAsset(release.id, "TuneMetronome.ipa", ipa, "application/octet-stream");
await uploadAsset(release.id, "source.json", source, "application/json");
await uploadAsset(release.id, "icon.png", icon, "image/png");

// Make this the latest release so /releases/latest/download/source.json works.
await api(`/repos/${repo}/releases/${release.id}`, "PATCH", { make_latest: "true" });

console.log("published " + tag + " to " + repo);
console.log("source: https://github.com/" + repo + "/releases/latest/download/source.json");
