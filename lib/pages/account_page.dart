import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool isLoading = true;
  String? dateCreated;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
  final user = _auth.currentUser;

  if (user != null) {
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!mounted) return;

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _usernameController.text = data['user_name'] ?? '';
          // The sign-in email is the source of truth; the stored copy can lag.
          _emailController.text = user.email ?? data['email'] ?? '';
          _phoneController.text = data['phone'] ?? '';
          final createdAt = data['date_created'];
          dateCreated = createdAt != null
              ? (createdAt as Timestamp).toDate().toString().substring(0, 10)
              : 'N/A';
          isLoading = false;
        });
      } else {
        // Document missing — still show user info from Firebase Auth
        setState(() {
          _usernameController.text = user.displayName ?? '';
          _emailController.text = user.email ?? '';
          _phoneController.text = '';
          dateCreated = 'N/A';
          isLoading = false;
        });
        debugPrint('No Firestore document found for this user.');
      }
    } catch (e) {
      // Handle permission or network errors gracefully
      debugPrint('Error loading user data: $e');
      if (!mounted) return;
      setState(() {
        _emailController.text = user.email ?? '';
        _usernameController.text = user.displayName ?? '';
        dateCreated = 'N/A';
        isLoading = false;
      });
    }
  } else {
    // No authenticated user — stop loading
    setState(() => isLoading = false);
    debugPrint('No authenticated user found.');
  }
}

  Future<void> _saveChanges() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final username = _usernameController.text.trim();
    final newEmail = _emailController.text.trim();
    final newPassword = _passwordController.text.trim();
    final emailChanged = newEmail.isNotEmpty && newEmail != user.email;

    try {
      // Merge rather than update, so saving also works when the profile
      // document is missing. The stored email mirrors the verified sign-in
      // email, so a requested change is not written here.
      await _firestore.collection('users').doc(user.uid).set({
        'user_name': username,
        'phone': _phoneController.text.trim(),
        if (user.email != null) 'email': user.email,
      }, SetOptions(merge: true));

      // Update display name in Firebase Auth
      await user.updateDisplayName(username);

      // Request the email change. It takes effect only after the user opens
      // the verification link sent to the new address.
      if (emailChanged) {
        await user.verifyBeforeUpdateEmail(newEmail);
      }

      // Update password if provided
      if (newPassword.isNotEmpty) {
        await user.updatePassword(newPassword);
      }

      // The page may have closed during the awaits above, and its controllers
      // are disposed with it, so touch them only while it is still mounted.
      if (!mounted) return;
      if (newPassword.isNotEmpty) _passwordController.clear();
      if (emailChanged) {
        // Keep showing the email that still signs the user in.
        _emailController.text = user.email ?? '';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(emailChanged
              ? 'Changes saved. Open the link sent to $newEmail to confirm your new email.'
              : 'Changes saved successfully!'),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message = e.code == 'requires-recent-login'
          ? 'For security, sign out and sign in again before changing your email or password.'
          : 'Failed to save changes: ${e.message ?? e.code}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save changes: $e')),
      );
    }
  }

  void _discardChanges() {
    _loadUserData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Changes discarded')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'Edit Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.grey[100],
        elevation: 1,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  const CircleAvatar(
                    radius: 45,
                    backgroundColor: Colors.grey,
                    child: Icon(Icons.person, size: 60, color: Colors.white),
                  ),
                  const SizedBox(height: 25),

                  // --- PROFILE SECTION (username) ---
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Profile',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  // --- CONTACTS & SECURITY SECTION ---
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Contacts & Security',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _phoneController,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        TextField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: 'Email Address',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        TextField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            labelText: 'New Password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          obscureText: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  // --- ACCOUNT INFO SECTION ---
                  Container(
                    padding: const EdgeInsets.all(15),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Account Information',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Date Created: $dateCreated',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // --- BUTTONS ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                            side: const BorderSide(color: Colors.black),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 25, vertical: 14),
                        ),
                        onPressed: _discardChanges,
                        child: const Text('Discard Changes'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 25, vertical: 14),
                        ),
                        onPressed: _saveChanges,
                        child: const Text('Save Changes'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}