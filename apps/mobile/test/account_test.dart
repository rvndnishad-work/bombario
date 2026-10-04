import 'package:bombario/account/account.dart';
import 'package:bombario/account/profile.dart';
import 'package:bombario/progress/achievements.dart';
import 'package:bombario/settings/settings.dart';
import 'package:bombario/ui/kit/pixel_theme.dart';
import 'package:bombario/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBackend implements AccountBackend {
  FakeBackend({this.cloud = const CloudProfile()});

  CloudProfile cloud;
  AccountUser? user;
  int syncs = 0;

  @override
  AccountUser? get current => user;

  @override
  Future<AccountUser?> signIn(SignInMethod method) async => user = AccountUser(
    uid: 'u1',
    method: method,
    name: 'Arvind Kumar Nishad',
  );

  @override
  Future<void> signOut() async => user = null;

  @override
  Future<void> delete() async {
    cloud = const CloudProfile();
    user = null;
  }

  @override
  Future<CloudProfile> sync(
    String uid,
    CloudProfile Function(CloudProfile cloud) merge,
  ) async {
    syncs++;
    return cloud = merge(cloud);
  }
}

void main() {
  test('merge keeps the best of phone and account', () {
    final merged = CloudProfile.merge(
      const CloudProfile(
        name: 'Ace',
        skin: 'classic',
        unlocked: {'kicker'},
        stats: {'bombsPlaced': 40, 'daily.2026-10-04': 90000, 'revives': 0},
      ),
      const CloudProfile(
        name: 'Old',
        skin: 'crown',
        unlocked: {'versus-win', 'from-a-newer-app'},
        stats: {'bombsPlaced': 120, 'daily.2026-10-04': 70000, 'revives': 3},
      ),
    );
    expect(merged.name, 'Ace');
    expect(merged.skin, 'crown', reason: 'classic is "no choice made"');
    expect(merged.unlocked, {'kicker', 'versus-win', 'from-a-newer-app'});
    expect(merged.stats['bombsPlaced'], 120);
    expect(merged.stats['daily.2026-10-04'], 70000, reason: 'faster time');
    expect(merged.stats['revives'], 3);
  });

  test('profile survives a JSON round trip and ignores junk', () {
    const p = CloudProfile(
      name: 'Ace',
      skin: 'cap',
      unlocked: {'kicker'},
      stats: {'bombsPlaced': 4},
    );
    final back = CloudProfile.fromJson(p.toJson());
    expect(back.name, 'Ace');
    expect(back.unlocked, {'kicker'});
    expect(back.stats, {'bombsPlaced': 4});
    expect(
      CloudProfile.fromJson({'stats': 'nope', 'unlocked': 3}).stats,
      isEmpty,
    );
  });

  test(
    'signing in uploads guest progress and brings the cloud copy back',
    () async {
      final settings = AppSettings.memory();
      final achievements = Achievements.memory()
        ..recordStageCleared('1-1'); // unlocks first-spark
      final backend = FakeBackend(
        cloud: const CloudProfile(
          skin: 'crown',
          unlocked: {'versus-win'},
          stats: {'versusWins': 2},
        ),
      );
      final account = Account(
        backend: backend,
        settings: settings,
        achievements: achievements,
      );
      expect(account.signedIn, isFalse);

      await account.signIn(SignInMethod.google);

      expect(account.signedIn, isTrue);
      expect(
        backend.cloud.unlocked,
        containsAll(['first-spark', 'versus-win']),
      );
      expect(achievements.unlocked, containsAll(['first-spark', 'versus-win']));
      expect(achievements.stat(Achievements.versusWins), 2);
      expect(settings.skin, 'crown');
      expect(
        settings.playerName,
        'Arvind',
        reason: 'first name, guest had none',
      );

      await account.signOut();
      expect(account.signedIn, isFalse);
      expect(achievements.unlocked, contains('versus-win'), reason: 'kept');
      account.dispose();
    },
  );

  testWidgets('settings say sign-in is not set up without Firebase', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    await tester.pumpWidget(
      MaterialApp(theme: Px.theme(), home: const SettingsScreen()),
    );
    expect(find.textContaining('not set up'), findsOneWidget);
    expect(find.byKey(const Key('sign-in-google')), findsNothing);
  });

  testWidgets('guests see the Google button; signed-in players see sign out', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    final account = Account(
      backend: FakeBackend(),
      settings: AppSettings.memory(),
      achievements: Achievements.memory(),
    );
    await tester.pumpWidget(
      AccountScope(
        account: account,
        child: MaterialApp(theme: Px.theme(), home: const SettingsScreen()),
      ),
    );
    await tester.tap(find.byKey(const Key('sign-in-google')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Signed in with Google'), findsOneWidget);
    expect(find.byKey(const Key('sign-out')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sign-in-google')), findsOneWidget);
  });
}
