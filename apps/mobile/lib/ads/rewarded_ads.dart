import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Rewarded video ads: watch one to the end, get a reward (an extra life).
///
/// Uses Google AdMob on Android and iOS. The unit ids below are Google's
/// public test ids, which always serve a test ad; swap in the real AdMob
/// unit ids (and the app ids in AndroidManifest.xml and Info.plist) before
/// publishing. Everywhere else (desktop, tests) no ad is ever ready.
abstract class RewardedAds {
  /// The app-wide instance; tests replace it with a fake.
  static RewardedAds instance =
      (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
      ? AdMobRewardedAds()
      : const NoRewardedAds();

  /// Whether this platform can show rewarded ads at all.
  bool get supported;

  /// Starts the SDK and loads the first ad. Safe to call more than once.
  Future<void> start();

  /// Shows an ad, loading one first if needed. Completes with true once the
  /// player has earned the reward, false if no ad came or it was skipped.
  Future<bool> showForReward();
}

/// Platforms without ads.
class NoRewardedAds implements RewardedAds {
  const NoRewardedAds();

  @override
  bool get supported => false;

  @override
  Future<void> start() async {}

  @override
  Future<bool> showForReward() async => false;
}

class AdMobRewardedAds implements RewardedAds {
  static String get unitId => Platform.isIOS
      ? 'ca-app-pub-3940256099942544/1712485313'
      : 'ca-app-pub-3940256099942544/5224354917';

  RewardedAd? _ready;
  Future<RewardedAd?>? _loading;
  bool _started = false;

  @override
  bool get supported => true;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await MobileAds.instance.initialize();
      unawaited(_load());
    } catch (e) {
      debugPrint('RewardedAds: start failed: $e');
    }
  }

  Future<RewardedAd?> _load() {
    final ready = _ready;
    if (ready != null) return Future.value(ready);
    return _loading ??= () {
      final done = Completer<RewardedAd?>();
      RewardedAd.load(
        adUnitId: unitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _ready = ad;
            _loading = null;
            done.complete(ad);
          },
          onAdFailedToLoad: (error) {
            debugPrint('RewardedAds: load failed: $error');
            _loading = null;
            done.complete(null);
          },
        ),
      );
      return done.future;
    }();
  }

  @override
  Future<bool> showForReward() async {
    await start();
    final ad = await _load().timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );
    if (ad == null) return false;
    _ready = null;
    final result = Completer<bool>();
    final earned = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) async {
        ad.dispose();
        unawaited(_load());
        // The reward event can land just after the dismissal, so give it a
        // moment before calling the ad unwatched.
        final got = await earned.future
            .then((_) => true)
            .timeout(
              const Duration(milliseconds: 1500),
              onTimeout: () => false,
            );
        if (!result.isCompleted) result.complete(got);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('RewardedAds: show failed: $error');
        ad.dispose();
        if (!result.isCompleted) result.complete(false);
        unawaited(_load());
      },
    );
    await ad.show(
      onUserEarnedReward: (_, _) {
        if (!earned.isCompleted) earned.complete();
      },
    );
    return result.future;
  }
}
