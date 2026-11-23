// Checks firestore.rules against the Firestore emulator.
//
// Run with `npm test` from this folder. The emulator runs locally under the
// offline demo project "demo-onlyfunds"; no real Firebase project is used.
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
  setLogLevel,
  updateDoc,
} from 'firebase/firestore';

const month = 'users/alice/monthly_records/2026-06';

let testEnv;

before(async () => {
  // Many requests below are meant to be denied. Stop the SDK from logging a
  // warning for each one; a request that should succeed still fails its test.
  setLogLevel('error');
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-onlyfunds',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// Writes alice's profile and one record of each kind, bypassing the rules, so
// a test can act on documents that already exist. The rules check `create`
// for a new document but `update` or `delete` for an existing one.
async function seedAliceData() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'users/alice'), { user_name: 'Alice' });
    await setDoc(doc(db, `${month}/transactions/t1`), { amount: 500, type: 'expense' });
    await setDoc(doc(db, `${month}/summary/record`), { balance: 9500, totalExpense: 500 });
    await setDoc(doc(db, `${month}/goals/Travel Fund`), { amount: 2000 });
  });
}

describe('the signed-in owner', () => {
  test('can write and read their profile', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(db, 'users/alice'), { user_name: 'Alice' }));
    await assertSucceeds(getDoc(doc(db, 'users/alice')));
  });

  test('can write and read every kind of monthly record', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      setDoc(doc(db, `${month}/transactions/t1`), { amount: 500, type: 'expense' }),
    );
    await assertSucceeds(setDoc(doc(db, `${month}/summary/record`), { balance: 9500 }));
    await assertSucceeds(setDoc(doc(db, `${month}/goals/Travel Fund`), { amount: 2000 }));
    await assertSucceeds(getDocs(collection(db, `${month}/transactions`)));
    await assertSucceeds(getDoc(doc(db, `${month}/summary/record`)));
    await assertSucceeds(getDocs(collection(db, `${month}/goals`)));
  });

  test('can update existing records, as transactions, deposits, and profile edits do', async () => {
    await seedAliceData();
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      setDoc(doc(db, `${month}/summary/record`), { balance: 9000, totalExpense: 1000 }, { merge: true }),
    );
    await assertSucceeds(
      setDoc(doc(db, `${month}/goals/Travel Fund`), { amount: 2500 }, { merge: true }),
    );
    await assertSucceeds(updateDoc(doc(db, 'users/alice'), { user_name: 'Alice B.' }));
  });

  test('can list their months and delete their data, as account deletion does', async () => {
    await seedAliceData();
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(getDocs(collection(db, 'users/alice/monthly_records')));
    for (const records of ['transactions', 'goals', 'summary']) {
      await assertSucceeds(getDocs(collection(db, `${month}/${records}`)));
    }
    await assertSucceeds(deleteDoc(doc(db, `${month}/transactions/t1`)));
    await assertSucceeds(deleteDoc(doc(db, `${month}/goals/Travel Fund`)));
    await assertSucceeds(deleteDoc(doc(db, `${month}/summary/record`)));
    await assertSucceeds(deleteDoc(doc(db, month)));
    await assertSucceeds(deleteDoc(doc(db, 'users/alice')));
  });
});

describe('anyone else', () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, 'users/alice'), { user_name: 'Alice' });
      await setDoc(doc(db, `${month}/transactions/t1`), { amount: 500, type: 'expense' });
    });
  });

  test("another user cannot read the owner's profile or records", async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(getDoc(doc(db, 'users/alice')));
    await assertFails(getDoc(doc(db, `${month}/transactions/t1`)));
    await assertFails(getDocs(collection(db, `${month}/transactions`)));
    await assertFails(getDocs(collection(db, 'users/alice/monthly_records')));
  });

  test("another user cannot write or delete the owner's data", async () => {
    const db = testEnv.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(db, `${month}/transactions/t2`), { amount: 1 }));
    await assertFails(setDoc(doc(db, 'users/alice'), { user_name: 'Bob' }));
    await assertFails(deleteDoc(doc(db, `${month}/transactions/t1`)));
  });

  test('a signed-out visitor cannot read or write anything', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'users/alice')));
    await assertFails(setDoc(doc(db, 'users/mallory'), { user_name: 'Mallory' }));
  });
});

test('paths outside users/ are denied even to signed-in users', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();
  await assertFails(setDoc(doc(db, 'stats/global'), { count: 1 }));
  await assertFails(getDoc(doc(db, 'stats/global')));
});
