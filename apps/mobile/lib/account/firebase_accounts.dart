import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

import '../firebase_options.dart';
import 'account.dart';
import 'profile.dart';

/// [AccountBackend] on Firebase Auth (Google, Facebook) and Firestore.
class FirebaseAccounts implements AccountBackend {
  FirebaseAccounts._();

  /// Starts Firebase, or returns null when the project isn't configured yet
  /// (lib/firebase_options.dart is still the placeholder) so the game runs
  /// guest-only.
  static Future<FirebaseAccounts?> start() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return FirebaseAccounts._();
    } catch (e) {
      debugPrint('Sign-in off: $e');
      return null;
    }
  }

  final _auth = FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  @override
  AccountUser? get current => _toUser(_auth.currentUser);

  @override
  Future<AccountUser?> signIn(SignInMethod method) async {
    try {
      final cred = switch (method) {
        SignInMethod.google => await _auth.signInWithProvider(
          GoogleAuthProvider(),
        ),
        SignInMethod.facebook => await _facebook(
          (c) => _auth.signInWithCredential(c),
        ),
      };
      return _toUser(cred?.user);
    } on FirebaseAuthException catch (e) {
      if (_cancelled(e)) return null;
      throw AccountError(_explain(e));
    }
  }

  @override
  Future<void> signOut() async {
    if (current?.method == SignInMethod.facebook) {
      await FacebookAuth.instance.logOut();
    }
    await _auth.signOut();
  }

  @override
  Future<void> delete() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _doc(user.uid).delete();
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login') throw AccountError(_explain(e));
      // Firebase wants a fresh sign-in before deleting an account.
      if (_toUser(user)?.method == SignInMethod.facebook) {
        await _facebook((c) => user.reauthenticateWithCredential(c));
      } else {
        await user.reauthenticateWithProvider(GoogleAuthProvider());
      }
      await user.delete();
    }
    await signOut();
  }

  @override
  Future<CloudProfile> sync(
    String uid,
    CloudProfile Function(CloudProfile cloud) merge,
  ) {
    final doc = _doc(uid);
    return FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(doc);
      final merged = merge(CloudProfile.fromJson(snap.data()));
      tx.set(doc, {
        ...merged.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return merged;
    });
  }

  /// Runs the Facebook login and hands Firebase the result. Null when the
  /// player backed out.
  Future<UserCredential?> _facebook(
    Future<UserCredential> Function(AuthCredential) use,
  ) async {
    // iOS uses Facebook's Limited Login, which returns a signed token tied
    // to this nonce instead of a classic access token.
    final rawNonce = _nonce();
    final result = await FacebookAuth.instance.login(
      permissions: const ['public_profile', 'email'],
      nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
    );
    switch (result.status) {
      case LoginStatus.success:
        final token = result.accessToken!;
        final AuthCredential cred = token is LimitedToken
            ? OAuthProvider(
                'facebook.com',
              ).credential(idToken: token.tokenString, rawNonce: rawNonce)
            : FacebookAuthProvider.credential(token.tokenString);
        return use(cred);
      case LoginStatus.cancelled:
        return null;
      default:
        throw AccountError(result.message ?? 'Facebook sign-in failed.');
    }
  }

  static String _nonce() {
    final r = Random.secure();
    return base64Url.encode(List.generate(32, (_) => r.nextInt(256)));
  }

  static AccountUser? _toUser(User? u) {
    if (u == null) return null;
    final facebook = u.providerData.any((p) => p.providerId == 'facebook.com');
    return AccountUser(
      uid: u.uid,
      method: facebook ? SignInMethod.facebook : SignInMethod.google,
      name: u.displayName ?? '',
      email: u.email ?? '',
    );
  }

  static bool _cancelled(FirebaseAuthException e) =>
      e.code == 'web-context-canceled' ||
      e.code == 'canceled' ||
      e.code == 'popup-closed-by-user';

  static String _explain(FirebaseAuthException e) => switch (e.code) {
    'account-exists-with-different-credential' =>
      'That email already has an account with the other sign-in button. '
          'Use that one instead.',
    'network-request-failed' => 'No connection. Try again when online.',
    _ => e.message ?? 'Sign-in failed (${e.code}).',
  };
}
