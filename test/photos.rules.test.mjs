// Emulator rules test suite for HUMANS (FatLoss) progress-photo rules.
// Covers BOTH firestore.rules (users/{uid}/photos) and storage.rules (users/{uid}/photos/**).
// For EVERY allow there is a positive case AND the negative cases that prove the deny.
//
// This environment has no firebase CLI and no Java runtime, so this suite was NOT run here.
// Run it where a JRE + CLI exist:
//   cd /Users/MetaTec/FatLossCoach
//   npm i -D @firebase/rules-unit-testing firebase   # once
//   firebase emulators:exec --only firestore,storage --project fat-loss-6516d \
//     "node --test test/photos.rules.test.mjs"
//
// Every assertion is awaited — unsequenced async makes suites lie green.

import { test, before, after, beforeEach } from 'node:test';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs,
} from 'firebase/firestore';
import {
  ref, uploadBytes, getBytes, deleteObject,
} from 'firebase/storage';

const PROJECT = 'fat-loss-6516d';
const ALICE = 'alice-uid';
const BOB = 'bob-uid';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { rules: readFileSync('firestore.rules', 'utf8') },
    storage: { rules: readFileSync('storage.rules', 'utf8') },
  });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

const fs = (uid) => env.authenticatedContext(uid).firestore();
const st = (uid) => env.authenticatedContext(uid).storage();
const guestFs = () => env.unauthenticatedContext().firestore();
const guestSt = () => env.unauthenticatedContext().storage();

const metaDoc = (db, uid, id) => doc(db, `users/${uid}/photos/${id}`);
const goodMeta = (uid) => ({ ownerUid: uid, date: '2026-09-23', createdAt: new Date(), storagePath: `users/${uid}/photos/p1.jpg` });
const objRef = (s, uid, id) => ref(s, `users/${uid}/photos/${id}.jpg`);
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);

// ---------- FIRESTORE metadata: users/{uid}/photos/{photo} ----------

test('FS read: owner reads own photo meta', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await setDoc(metaDoc(c.firestore(), ALICE, 'p1'), goodMeta(ALICE));
  });
  await assertSucceeds(getDoc(metaDoc(fs(ALICE), ALICE, 'p1')));
});

test('FS read DENY: other user cannot read', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await setDoc(metaDoc(c.firestore(), ALICE, 'p1'), goodMeta(ALICE));
  });
  await assertFails(getDoc(metaDoc(fs(BOB), ALICE, 'p1')));
});

test('FS read DENY: guest cannot read', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await setDoc(metaDoc(c.firestore(), ALICE, 'p1'), goodMeta(ALICE));
  });
  await assertFails(getDoc(metaDoc(guestFs(), ALICE, 'p1')));
});

test('FS list DENY: cross-tenant collection listen refused', async () => {
  // The app listens on its OWN users/{uid}/photos; a cross-tenant list must be refused, not filtered.
  await assertFails(getDocs(collection(fs(BOB), `users/${ALICE}/photos`)));
});

test('FS create: owner with ownerUid==uid succeeds', async () => {
  await assertSucceeds(setDoc(metaDoc(fs(ALICE), ALICE, 'p1'), goodMeta(ALICE)));
});

test('FS create DENY: ownerUid spoofed to another uid', async () => {
  await assertFails(setDoc(metaDoc(fs(ALICE), ALICE, 'p1'), { ...goodMeta(ALICE), ownerUid: BOB }));
});

test('FS create DENY: writing under another user path', async () => {
  await assertFails(setDoc(metaDoc(fs(BOB), ALICE, 'p1'), goodMeta(ALICE)));
});

test('FS create DENY: guest', async () => {
  await assertFails(setDoc(metaDoc(guestFs(), ALICE, 'p1'), goodMeta(ALICE)));
});

test('FS update: owner may update own doc (ownerUid stays == uid)', async () => {
  await assertSucceeds(setDoc(metaDoc(fs(ALICE), ALICE, 'p1'), goodMeta(ALICE)));
  await assertSucceeds(updateDoc(metaDoc(fs(ALICE), ALICE, 'p1'), { note: 'week 3' }));
});

test('FS update DENY: mutating ownerUid to another uid (immutability)', async () => {
  await assertSucceeds(setDoc(metaDoc(fs(ALICE), ALICE, 'p1'), goodMeta(ALICE)));
  await assertFails(updateDoc(metaDoc(fs(ALICE), ALICE, 'p1'), { ownerUid: BOB }));
});

test('FS delete: owner may delete own doc (regression: combined write rule denied this)', async () => {
  await assertSucceeds(setDoc(metaDoc(fs(ALICE), ALICE, 'p1'), goodMeta(ALICE)));
  await assertSucceeds(deleteDoc(metaDoc(fs(ALICE), ALICE, 'p1')));
});

test('FS delete DENY: other user cannot delete', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await setDoc(metaDoc(c.firestore(), ALICE, 'p1'), goodMeta(ALICE));
  });
  await assertFails(deleteDoc(metaDoc(fs(BOB), ALICE, 'p1')));
});

// ---------- STORAGE bytes: users/{uid}/photos/{photo} ----------

test('ST write+read: owner uploads and reads own object', async () => {
  await assertSucceeds(uploadBytes(objRef(st(ALICE), ALICE, 'p1'), JPEG));
  await assertSucceeds(getBytes(objRef(st(ALICE), ALICE, 'p1')));
});

test('ST read DENY: other user cannot read', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await uploadBytes(objRef(c.storage(), ALICE, 'p1'), JPEG);
  });
  await assertFails(getBytes(objRef(st(BOB), ALICE, 'p1')));
});

test('ST read DENY: guest cannot read', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await uploadBytes(objRef(c.storage(), ALICE, 'p1'), JPEG);
  });
  await assertFails(getBytes(objRef(guestSt(), ALICE, 'p1')));
});

test('ST write DENY: other user cannot write into your path', async () => {
  await assertFails(uploadBytes(objRef(st(BOB), ALICE, 'p1'), JPEG));
});

test('ST write DENY: guest cannot write', async () => {
  await assertFails(uploadBytes(objRef(guestSt(), ALICE, 'p1'), JPEG));
});

test('ST delete: owner may delete own object', async () => {
  await assertSucceeds(uploadBytes(objRef(st(ALICE), ALICE, 'p1'), JPEG));
  await assertSucceeds(deleteObject(objRef(st(ALICE), ALICE, 'p1')));
});

test('ST catch-all DENY: no other path is readable/writable', async () => {
  await assertFails(uploadBytes(ref(st(ALICE), `misc/${ALICE}.jpg`), JPEG));
  await assertFails(getBytes(ref(st(ALICE), 'public/banner.jpg')));
  await assertFails(uploadBytes(ref(st(ALICE), `users/${ALICE}/avatar.jpg`), JPEG)); // outside /photos/
});
