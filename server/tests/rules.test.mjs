// Firestore rules unit tests — account isolation for fat-loss-6516d.
// Every allow has a positive case; every deny has the negative that proves it.
//
// RUN (needs a JRE for the emulator — not present on the CEO Mac by default):
//   npm i -D @firebase/rules-unit-testing firebase-tools
//   npx firebase emulators:exec --only firestore \
//       --project fat-loss-6516d "node --test server/tests/rules.test.mjs"
// firebase.json must expose the emulator, e.g.:
//   { "emulators": { "firestore": { "port": 8080 } },
//     "firestore": { "rules": "firestore.rules" } }

import { readFileSync } from "node:fs";
import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import {
  doc, getDoc, setDoc, collection, getDocs, query as fsQuery, where,
} from "firebase/firestore";

const OWNER = "userA_uid";
const OTHER = "userB_uid";

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "fat-loss-6516d",
    firestore: { rules: readFileSync("firestore.rules", "utf8") },
  });
});
after(async () => { await testEnv.cleanup(); });
beforeEach(async () => { await testEnv.clearFirestore(); });

const owner = () => testEnv.authenticatedContext(OWNER).firestore();
const other = () => testEnv.authenticatedContext(OTHER).firestore();
const anon  = () => testEnv.unauthenticatedContext().firestore();

// Seed as admin (bypasses rules) so read/list denials can be proven against real data.
async function seedOwnerDoc() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users", OWNER), { json: "{owner-A-blob}", schema: 2 });
    await setDoc(doc(db, "users", OWNER, "days", "2026-09-20"), { steps: 8000 });
    await setDoc(doc(db, "users", OWNER, "meals", "m1"), { name: "Owner meal" });
    await setDoc(doc(db, "scans", "s1"), { uid: OWNER, ok: true });
  });
}

// ---- users/{uid} : owner may, everyone else may not --------------------------

test("owner reads own doc — ALLOW", async () => {
  await seedOwnerDoc();
  await assertSucceeds(getDoc(doc(owner(), "users", OWNER)));
});

test("owner writes own doc — ALLOW", async () => {
  await assertSucceeds(setDoc(doc(owner(), "users", OWNER), { json: "{a}", schema: 2 }));
});

test("other user reads owner's doc — DENY (cross-account read)", async () => {
  await seedOwnerDoc();
  await assertFails(getDoc(doc(other(), "users", OWNER)));
});

test("other user writes owner's doc — DENY (cross-account write / contamination)", async () => {
  await assertFails(setDoc(doc(other(), "users", OWNER), { json: "{evil}" }));
});

test("unauthenticated reads any user doc — DENY", async () => {
  await seedOwnerDoc();
  await assertFails(getDoc(doc(anon(), "users", OWNER)));
});

test("unauthenticated writes any user doc — DENY", async () => {
  await assertFails(setDoc(doc(anon(), "users", OWNER), { json: "{x}" }));
});

// ---- subcollections days / meals --------------------------------------------

test("owner reads own day row — ALLOW", async () => {
  await seedOwnerDoc();
  await assertSucceeds(getDoc(doc(owner(), "users", OWNER, "days", "2026-09-20")));
});

test("other user reads owner's day row — DENY", async () => {
  await seedOwnerDoc();
  await assertFails(getDoc(doc(other(), "users", OWNER, "days", "2026-09-20")));
});

test("other user reads owner's meal row — DENY", async () => {
  await seedOwnerDoc();
  await assertFails(getDoc(doc(other(), "users", OWNER, "meals", "m1")));
});

test("owner writes own meal row — ALLOW", async () => {
  await assertSucceeds(setDoc(doc(owner(), "users", OWNER, "meals", "m2"), { name: "x" }));
});

test("other user writes into owner's meals — DENY", async () => {
  await assertFails(setDoc(doc(other(), "users", OWNER, "meals", "m9"), { name: "evil" }));
});

// ---- list must be rejected, not silently filtered ---------------------------
// A collection-group / cross-tenant list is refused outright because the query
// is not constrained to a single owned path. This is the "rules are not filters" test.

test("cross-tenant list of another user's meals — DENY (query not owner-scoped)", async () => {
  await seedOwnerDoc();
  await assertFails(getDocs(collection(other(), "users", OWNER, "meals")));
});

test("owner list of own meals — ALLOW", async () => {
  await seedOwnerDoc();
  await assertSucceeds(getDocs(collection(owner(), "users", OWNER, "meals")));
});

// ---- scans : server-only, denied to every client ----------------------------

test("owner reads scans — DENY (server-only)", async () => {
  await seedOwnerDoc();
  await assertFails(getDoc(doc(owner(), "scans", "s1")));
});

test("owner writes scans — DENY (server-only)", async () => {
  await assertFails(setDoc(doc(owner(), "scans", "s1"), { ok: true }));
});

// ---- catch-all --------------------------------------------------------------

test("any client read of an undeclared path — DENY", async () => {
  await assertFails(getDoc(doc(owner(), "config", "admins")));
});

test("any client write to an undeclared path — DENY", async () => {
  await assertFails(setDoc(doc(owner(), "randomCollection", "x"), { a: 1 }));
});
