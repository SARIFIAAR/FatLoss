// Minimal Firestore REST client for the analyzer (no firebase-admin: keeps the image at ~70 MB).
// Authenticates with a service account (FIREBASE_SERVICE_ACCOUNT = the JSON key, as one Fly secret).
// Service accounts bypass security rules, so this is only ever used server-side.
import { importPKCS8, SignJWT } from "jose";

const PROJECT = process.env.FIREBASE_PROJECT_ID ?? "fat-loss-6516d";
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

let account = null;
try {
  if (process.env.FIREBASE_SERVICE_ACCOUNT) account = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
} catch (e) {
  console.error("FIREBASE_SERVICE_ACCOUNT is not valid JSON:", e.message);
}
export const enabled = Boolean(account?.client_email && account?.private_key);

let cached = { token: null, exp: 0 };
async function accessToken() {
  if (cached.token && Date.now() < cached.exp - 60_000) return cached.token;
  const key = await importPKCS8(account.private_key, "RS256");
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/datastore" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setSubject(account.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!res.ok) throw new Error(`token exchange failed: ${res.status} ${await res.text()}`);
  const json = await res.json();
  cached = { token: json.access_token, exp: Date.now() + json.expires_in * 1000 };
  return cached.token;
}

async function call(method, path, body, query = "") {
  const token = await accessToken();
  const url = path.startsWith(":") ? `${BASE}${path}${query}` : `${BASE}/${path}${query}`;
  const res = await fetch(url, {
    method,
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) throw new Error(`firestore ${method} ${path}: ${res.status} ${await res.text()}`);
  return res.json();
}

// ---- value encoding -------------------------------------------------------------------------

export function encode(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === "string") return { stringValue: v };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encode) } };
  if (typeof v === "object") return { mapValue: { fields: encodeFields(v) } };
  return { stringValue: String(v) };
}
function encodeFields(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj)) if (v !== undefined) out[k] = encode(v);
  return out;
}

export function decode(v) {
  if (!v) return null;
  if ("nullValue" in v) return null;
  if ("booleanValue" in v) return v.booleanValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("stringValue" in v) return v.stringValue;
  if ("timestampValue" in v) return v.timestampValue;
  if ("arrayValue" in v) return (v.arrayValue.values ?? []).map(decode);
  if ("mapValue" in v) return decodeFields(v.mapValue.fields ?? {});
  return null;
}
function decodeFields(fields) {
  const out = {};
  for (const [k, v] of Object.entries(fields)) out[k] = decode(v);
  return out;
}
function docId(name) { return name.slice(name.lastIndexOf("/") + 1); }

// ---- operations -----------------------------------------------------------------------------

/** Adds a document with an auto id (fire-and-forget safe: caller catches). */
export async function add(collection, data) {
  return call("POST", collection, { fields: encodeFields(data) });
}

/** Lists every document in a collection (follows pagination). `fields` limits what comes back. */
export async function list(collection, { fields, orderBy, pageSize = 300 } = {}) {
  const out = [];
  let pageToken = "";
  do {
    const q = new URLSearchParams({ pageSize: String(pageSize) });
    if (pageToken) q.set("pageToken", pageToken);
    if (orderBy) q.set("orderBy", orderBy);
    for (const f of fields ?? []) q.append("mask.fieldPaths", f);
    const page = await call("GET", collection, null, `?${q}`);
    for (const d of page.documents ?? []) {
      out.push({ id: docId(d.name), updateTime: d.updateTime, ...decodeFields(d.fields ?? {}) });
    }
    pageToken = page.nextPageToken ?? "";
  } while (pageToken);
  return out;
}

/** Structured query on a collection group / collection: `where` = [[field, op, value], ...]. */
export async function query(parent, collectionId, { where = [], orderBy, limit } = {}) {
  const filters = where.map(([field, op, value]) => ({
    fieldFilter: { field: { fieldPath: field }, op, value: encode(value) },
  }));
  const structuredQuery = { from: [{ collectionId }] };
  if (filters.length === 1) structuredQuery.where = filters[0];
  else if (filters.length > 1) structuredQuery.where = { compositeFilter: { op: "AND", filters } };
  if (orderBy) structuredQuery.orderBy = [{ field: { fieldPath: orderBy.field }, direction: orderBy.direction ?? "ASCENDING" }];
  if (limit) structuredQuery.limit = limit;
  const rows = await call("POST", parent ? `${parent}:runQuery` : ":runQuery", { structuredQuery });
  return rows.filter((r) => r.document).map((r) => ({ id: docId(r.document.name), ...decodeFields(r.document.fields ?? {}) }));
}
