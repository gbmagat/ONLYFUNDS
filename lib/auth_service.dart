import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

ValueNotifier<AuthService> authService = ValueNotifier(AuthService());

class AuthService {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseAuth firebaseAuth = FirebaseAuth.instance;

  User? get currentUser => firebaseAuth.currentUser;

  Stream<User?> get authStateChanges => firebaseAuth.authStateChanges();

  Future<UserCredential> signIn ({
    required String email,
    required String password,
  }) async {
    return await firebaseAuth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> createAccount ({
    required String email,
    required String password,
  }) async {
    return await firebaseAuth.createUserWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await firebaseAuth.signOut();
  }

  Future<void> resetPassword ({
    required String email,
  }) async {
    return await firebaseAuth.sendPasswordResetEmail(email: email);
  }

  Future<void> updateUsername ({
    required String username,
  }) async {
    await currentUser!.updateDisplayName(username);
  }

  Future<void> deleteAccount({ required String password }) async {
  try {
    final currentUser = firebaseAuth.currentUser;
    if (currentUser == null) throw Exception("No user logged in");

    final credential = EmailAuthProvider.credential(
      email: currentUser.email!,
      password: password,
    );

    await currentUser.reauthenticateWithCredential(credential);

    await deleteUserData(); // delete all Firestore data
    await currentUser.delete(); // delete auth account
    await firebaseAuth.signOut();
  } on FirebaseAuthException catch (e) {
    debugPrint("Auth error: ${e.message}");
    rethrow;
  } catch (e) {
    debugPrint("Unexpected error: $e");
    rethrow;
  }
}

  Future<void> deleteUserData() async {
    final user = firebaseAuth.currentUser;
    if (user == null) throw Exception("No user logged in");

    final userRef = firestore.collection("users").doc(user.uid);
    final monthsRef = userRef.collection("monthly_records");

    // The app writes only to the subcollections of each month, never to the
    // month document itself. Firestore leaves such missing parents out of
    // collection queries, so listing monthly_records finds nothing. Build the
    // month IDs from the account's lifetime and add any that do exist.
    final monthIds = <String>{};
    final existingMonths = await monthsRef.get();
    for (final doc in existingMonths.docs) {
      monthIds.add(doc.id);
    }

    final now = DateTime.now();
    final created =
        user.metadata.creationTime ?? DateTime(now.year - 5, now.month);
    // Pad by one month on each side to cover time zone and clock differences.
    var cursor = DateTime(created.year, created.month - 1);
    final end = DateTime(now.year, now.month + 1);
    while (!cursor.isAfter(end)) {
      monthIds.add(_monthId(cursor));
      cursor = DateTime(cursor.year, cursor.month + 1);
    }

    for (final monthId in monthIds) {
      final monthRef = monthsRef.doc(monthId);
      await _deleteCollection(monthRef.collection("transactions"));
      await _deleteCollection(monthRef.collection("goals"));
      await _deleteCollection(monthRef.collection("summary"));
      await monthRef.delete();
    }

    // Finally delete the user document
    await userRef.delete();
  }

  String _monthId(DateTime date) =>
      "${date.year}-${date.month.toString().padLeft(2, '0')}";

  /// Deletes every document in [collection], in batches.
  Future<void> _deleteCollection(
      CollectionReference<Map<String, dynamic>> collection) async {
    const batchLimit = 400; // Firestore allows at most 500 writes per batch.
    final snapshot = await collection.get();
    for (var i = 0; i < snapshot.docs.length; i += batchLimit) {
      final batch = firestore.batch();
      for (final doc in snapshot.docs.skip(i).take(batchLimit)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }


  Future<void> resetPasswordFromCurrentPassword ({
    required String currentPassword,
    required String newPassword,
    required String email,
  }) async {
   AuthCredential credential = EmailAuthProvider.credential(email: email, password: currentPassword);
   await currentUser!.reauthenticateWithCredential(credential);
   await currentUser!.updatePassword(newPassword);
  }
}