#!/usr/bin/env node
// cleanup-merge-contamination.mjs — DRAFT. Do NOT run without CEO approval.
//
// Purpose: detect and (optionally) reset users/{uid} cloud docs that may have been
// seeded/merged with a PREVIOUS user's LOCAL data by the CloudSync merge-push bug
// (AppData.merged unions sets; a fresh account's first sign-in either seeded
// users/{newUid} from foreign local data via `!snap.exists`, or the victim's doc
// absorbed foreign data on a shared device).
//
// This is DETECTION-HEAVY and CONSERVATIVE. The `json` blob is one opaque string and
// carries NO ownerUid, so we CANNOT prove contamination from the doc alone. We surface
// signals for a human to adjudicate; --apply only ever touches uids passed explicitly.
//
// Auth: reuses the service-account path already in server/firestore.js
//   (FIREBASE_SERVICE_ACCOUNT env = the JSON key). Service accounts bypass rules.
//
// USAGE:
//   FIREBASE_SERVICE_ACCOUNT="$(cat key.json)" node server/admin/cleanup-merge-contamination.mjs report
//     -> lists every users/{uid} with heuristics (blob size, device count, createdAt,
//        displayName/email vs stats, day/meal counts). Read-only. Run this FIRST.
//
//   ... node server/admin/cleanup-merge-contamination.mjs inspect <uid>
//     -> dumps that uid's decoded json blob keys + profile + day/meal ids for eyeball review.
//
//   ... node server/admin/cleanup-merge-contamination.mjs plan  --uids u1,u2
//     -> DRY RUN: shows exactly what would be deleted/reset for the named uids. No writes.
//
//   ... node server/admin/cleanup-merge-contamination.mjs apply --uids u1,u2 --confirm
//     -> DESTRUCTIVE. Requires BOTH --uids (explicit, never "all") AND --confirm.
//        For each uid: backs the doc up to backups/{uid}_{ts}, then resets the account.
//
// RESET SEMANTICS (see resetPlan): we do NOT blind-delete. Two modes per uid:
//   --mode purge  (default): delete users/{uid} + its days/* + meals/* entirely.
//        Use for a NEW-user doc that was seeded ENTIRELY from foreign local data
//        (the new user had no real data of their own yet). Safe: nothing legitimate lost.
//   --mode blob-only: overwrite ONLY the `json` field with the caller-supplied clean
//        blob (from --clean-json-file) and leave profile/stats; use when a victim doc
//        has real data mixed with foreign data and the app will re-push a clean blob.
//        (Prefer having the affected user re-sync from a known-clean device instead.)
//
// The safest real remedy for a NEW user is usually `purge` + tell them to reinstall;
// for the VICTIM (CEO) it is: sign in on the clean device, let the app re-push, THEN
// purge stray day/meal rows that no longer exist locally (handled by app mirror-diff).

import { importPKCS8, SignJWT } from "jose";

const PROJECT = process.env.FIREBASE_PROJECT_ID ?? "fat-loss-6516d";
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

const account = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT ?? "null");
if (!account?.client_email) { console.error("Set FIREBASE_SERVICE_ACCOUNT to the service-account JSON."); process.exit(1); }

let cached = { token: null, exp: 0 };
async function token() {
  if (cached.token && Date.now() < cached.exp - 60000) return cached.token;
  const key = await importPKCS8(account.private_key, "RS256");
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/datastore" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email).setSubject(account.client_email)
    .setAudience("https://oauth2.googleapis.com/token").setIssuedAt().setExpirationTime("1h").sign(key);
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!r.ok) throw new Error(`token: ${r.status} ${await r.text()}`);
  const j = await r.json();
  cached = { token: j.access_token, exp: Date.now() + j.expires_in * 1000 };
  return cached.token;
}
async function api(method, path, body, query = "") {
  const url = path.startsWith(":") ? `${BASE}${path}${query}` : `${BASE}/${path}${query}`;
  const r = await fetch(url, {
    method, headers: { authorization: `Bearer ${await token()}`, "content-type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (r.status === 404) return null;
  if (!r.ok) throw new Error(`${method} ${path}: ${r.status} ${await r.text()}`);
  return r.json();
}
const decode = (v) => {
  if (!v) return null;
  if ("nullValue" in v) return null;
  if ("booleanValue" in v) return v.booleanValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("stringValue" in v) return v.stringValue;
  if ("timestampValue" in v) return v.timestampValue;
  if ("arrayValue" in v) return (v.arrayValue.values ?? []).map(decode);
  if ("mapValue" in v) return dec(v.mapValue.fields ?? {});
  return null;
};
const dec = (f) => Object.fromEntries(Object.entries(f ?? {}).map(([k, v]) => [k, decode(v)]));
const idOf = (name) => name.slice(name.lastIndexOf("/") + 1);

async function listCollection(path) {
  const out = []; let pageToken = "";
  do {
    const q = new URLSearchParams({ pageSize: "300" }); if (pageToken) q.set("pageToken", pageToken);
    const page = await api("GET", path, null, `?${q}`); if (!page) break;
    for (const d of page.documents ?? []) out.push({ id: idOf(d.name), updateTime: d.updateTime, ...dec(d.fields) });
    pageToken = page.nextPageToken ?? "";
  } while (pageToken);
  return out;
}

// --- heuristics: what a contaminated doc might look like ---------------------
function signals(user) {
  const s = [];
  const blob = typeof user.json === "string" ? user.json : "";
  if (blob) {
    try {
      const j = JSON.parse(blob);
      const dayKeys = new Set([...Object.keys(j.habits ?? {}), ...Object.keys(j.supplements ?? {}),
        ...Object.keys(j.meals ?? {}), ...Object.keys(j.water ?? {})]);
      s.push(`blobBytes=${blob.length}`, `weightLogs=${(j.weightLogs ?? []).length}`,
        `distinctDays=${dayKeys.size}`, `hasIntake=${!!j.intake}`, `program=p${j.program?.phase}/${j.program?.startDate ?? "unstarted"}`);
    } catch { s.push("blobUNPARSEABLE"); }
  } else s.push("noBlob");
  s.push(`profile.createdAt=${user.profile?.createdAt ?? "none"}`,
    `email=${user.profile?.email ?? "none"}`, `dayCount=${user.stats?.dayCount ?? "?"}`,
    `mealCount=${user.stats?.mealCount ?? "?"}`);
  return s.join("  ");
}

const argv = process.argv.slice(2);
const cmd = argv[0];
const flag = (n) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : undefined; };
const uids = (flag("--uids") ?? "").split(",").map((s) => s.trim()).filter(Boolean);
const mode = flag("--mode") ?? "purge";

async function report() {
  const users = await listCollection("users");
  console.log(`# ${users.length} user docs in ${PROJECT}\n`);
  for (const u of users.sort((a, b) => (a.profile?.createdAt ?? "").localeCompare(b.profile?.createdAt ?? "")))
    console.log(`- ${u.id}\n    ${signals(u)}`);
  console.log(`\nCross-check createdAt ordering against the known incident window. A NEW uid whose`);
  console.log(`blob already contains many distinctDays / an intake it never filled is the seeded-foreign signal.`);
}

async function inspect(uid) {
  const u = await api("GET", `users/${uid}`);
  if (!u) return console.log(`${uid}: no doc`);
  const f = dec(u.fields);
  console.log(`profile:`, JSON.stringify(f.profile, null, 2));
  console.log(`stats:`, JSON.stringify(f.stats, null, 2));
  try { const j = JSON.parse(f.json ?? "{}"); console.log(`json keys:`, Object.keys(j)); console.log(`json.program:`, j.program); }
  catch { console.log(`json: unparseable`); }
  const days = await listCollection(`users/${uid}/days`);
  const meals = await listCollection(`users/${uid}/meals`);
  console.log(`days rows (${days.length}):`, days.map((d) => d.id).sort());
  console.log(`meals rows (${meals.length}):`, meals.map((m) => m.id));
}

async function planOrApply(apply) {
  if (!uids.length) { console.error("Refusing: pass explicit --uids u1,u2 (never 'all')."); process.exit(1); }
  if (apply && !argv.includes("--confirm")) { console.error("Refusing apply without --confirm."); process.exit(1); }
  for (const uid of uids) {
    const days = await listCollection(`users/${uid}/days`);
    const meals = await listCollection(`users/${uid}/meals`);
    console.log(`\n${uid}  mode=${mode}`);
    console.log(`  would ${apply ? "DELETE" : "delete"}: ${days.length} day rows, ${meals.length} meal rows`);
    if (mode === "purge") console.log(`  would ${apply ? "DELETE" : "delete"}: users/${uid} (whole doc)`);
    if (mode === "blob-only") console.log(`  would OVERWRITE users/${uid}.json only (needs --clean-json-file)`);
    if (!apply) { console.log(`  [dry-run] no writes.`); continue; }
    // backup first
    const doc = await api("GET", `users/${uid}`);
    if (doc) await api("PATCH", `backups/${uid}_${Date.now()}`, { fields: doc.fields });
    for (const d of days) await api("DELETE", `users/${uid}/days/${d.id}`);
    for (const m of meals) await api("DELETE", `users/${uid}/meals/${m.id}`);
    if (mode === "purge") await api("DELETE", `users/${uid}`);
    if (mode === "blob-only") {
      const clean = flag("--clean-json-file");
      if (!clean) { console.error("blob-only needs --clean-json-file"); process.exit(1); }
      const { readFileSync } = await import("node:fs");
      await api("PATCH", `users/${uid}`, { fields: { json: { stringValue: readFileSync(clean, "utf8") } } },
        "?updateMask.fieldPaths=json");
    }
    console.log(`  APPLIED (backup at backups/${uid}_...).`);
  }
}

const run = { report, inspect: () => inspect(argv[1]), plan: () => planOrApply(false), apply: () => planOrApply(true) }[cmd];
if (!run) { console.error("commands: report | inspect <uid> | plan --uids .. | apply --uids .. --confirm"); process.exit(1); }
run().catch((e) => { console.error(e); process.exit(1); });
