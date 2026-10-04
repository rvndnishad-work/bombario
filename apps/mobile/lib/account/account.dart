import 'dart:async';

import 'package:flutter/widgets.dart';

import '../progress/achievements.dart';
import '../settings/settings.dart';
import '../ui/player_name.dart';
import 'profile.dart';

enum SignInMethod { google, facebook }

/// The signed-in player, as shown in Settings.
class AccountUser {
  const AccountUser({
    required this.uid,
    required this.method,
    this.name = '',
    this.email = '',
  });

  final String uid;
  final SignInMethod method;
  final String name;
  final String email;
}

/// Thrown when signing in fails in a way the player should hear about.
class AccountError implements Exception {
  const AccountError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sign-in and the cloud copy of a player's profile. `FirebaseAccounts`
/// is the real one; tests use a fake.
abstract interface class AccountBackend {
  AccountUser? get current;

  /// Null when the player closed the sign-in sheet.
  Future<AccountUser?> signIn(SignInMethod method);
  Future<void> signOut();

  /// Deletes the cloud profile and the account itself.
  Future<void> delete();

  /// Reads the cloud profile, lets [merge] combine it with this phone's,
  /// saves and returns the result.
  Future<CloudProfile> sync(
    String uid,
    CloudProfile Function(CloudProfile cloud) merge,
  );
}

/// Optional sign-in (§15: guest play by default). Players start as guests
/// with progress on the phone; signing in with Google or Facebook copies that
/// progress to their account, and signing in on a new phone brings it back.
///
/// [available] is false until the Firebase project is set up, and the
/// Settings screen says so instead of showing the buttons.
class Account extends ChangeNotifier {
  Account({
    required this.backend,
    required this.settings,
    required this.achievements,
  }) : user = backend?.current {
    achievements.addListener(_progressChanged);
    settings.addListener(_settingsChanged);
  }

  /// No backend: sign-in isn't configured, everyone is a guest.
  Account.offline({required this.settings, required this.achievements})
    : backend = null,
      user = null;

  final AccountBackend? backend;
  final AppSettings settings;
  final Achievements achievements;

  AccountUser? user;
  bool busy = false;

  bool get available => backend != null;
  bool get signedIn => user != null;

  Timer? _pushTimer;
  bool _applying = false;
  late String _seenName = settings.playerName;
  late String _seenSkin = settings.skin;

  /// Brings the account's progress in at startup when already signed in.
  Future<void> start() async {
    if (user != null) await _sync();
  }

  Future<void> signIn(SignInMethod method) async {
    final b = backend;
    if (b == null || busy) return;
    await _busy(() async {
      final u = await b.signIn(method);
      if (u == null) return;
      user = u;
      if (settings.playerName.isEmpty && u.name.isNotEmpty) {
        _applyName(u.name);
      }
      await _sync();
    });
  }

  Future<void> signOut() async {
    final b = backend;
    if (b == null || busy) return;
    await _busy(() async {
      _pushTimer?.cancel();
      await b.signOut();
      user = null;
    });
  }

  /// Removes the account and its cloud copy. Progress stays on this phone.
  Future<void> deleteAccount() async {
    final b = backend;
    if (b == null || busy) return;
    await _busy(() async {
      _pushTimer?.cancel();
      await b.delete();
      user = null;
    });
  }

  Future<void> _busy(Future<void> Function() work) async {
    busy = true;
    notifyListeners();
    try {
      await work();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  CloudProfile _local() => CloudProfile(
    name: settings.playerName,
    skin: settings.skin,
    unlocked: {...achievements.unlocked},
    stats: {...achievements.stats},
  );

  Future<void> _sync() async {
    final b = backend;
    final u = user;
    if (b == null || u == null) return;
    try {
      final merged = await b.sync(
        u.uid,
        (cloud) => CloudProfile.merge(_local(), cloud),
      );
      _applying = true;
      try {
        achievements.absorb(merged.unlocked, merged.stats);
        if (settings.playerName.isEmpty && merged.name.isNotEmpty) {
          _applyName(merged.name);
        }
        if (merged.skin.isNotEmpty && merged.skin != settings.skin) {
          settings.update((s) => s.skin = merged.skin);
        }
      } finally {
        _applying = false;
      }
    } catch (e) {
      // Offline or the database refused: progress is safe on the phone and
      // goes up with the next change or the next start.
      debugPrint('Profile sync failed: $e');
    }
  }

  void _applyName(String name) {
    final trimmed = name.trim();
    final first = trimmed.split(RegExp(r'\s+')).first;
    final short = first.length > 12 ? first.substring(0, 12) : first;
    PlayerName.value.value = short;
    settings.update((s) => s.playerName = short);
  }

  /// Progress changed on this phone: send it up a few seconds later, so a
  /// stage full of bombs is one write, not hundreds.
  void _progressChanged() {
    if (_applying || user == null) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 5), _sync);
  }

  /// Only the name and hat go to the account, not volumes and controls.
  void _settingsChanged() {
    if (settings.playerName == _seenName && settings.skin == _seenSkin) return;
    _seenName = settings.playerName;
    _seenSkin = settings.skin;
    _progressChanged();
  }

  @override
  void dispose() {
    _pushTimer?.cancel();
    achievements.removeListener(_progressChanged);
    settings.removeListener(_settingsChanged);
    super.dispose();
  }
}

/// Puts [Account] in the widget tree.
class AccountScope extends InheritedNotifier<Account> {
  const AccountScope({
    super.key,
    required Account account,
    required super.child,
  }) : super(notifier: account);

  static Account? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountScope>()?.notifier;
}
