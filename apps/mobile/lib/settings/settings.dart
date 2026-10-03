import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Player settings (§9.2 controls, §9.6 accessibility), saved on the device.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  /// Settings that live only in memory, for tests and previews.
  AppSettings.memory() : _prefs = null;

  final SharedPreferences? _prefs;

  static Future<AppSettings> load() async {
    final s = AppSettings._(await SharedPreferences.getInstance());
    s._read();
    if (s.installId.isEmpty) {
      final r = Random.secure();
      s.installId = List.generate(
        16,
        (_) => r.nextInt(16).toRadixString(16),
      ).join();
      await s._prefs?.setString('installId', s.installId);
    }
    return s;
  }

  // ---- Audio
  double musicVolume = 0.6;
  double sfxVolume = 0.8;

  // ---- Controls
  bool haptics = true;

  /// 0.3 (barely there) to 1 (the default see-through look).
  double controlsOpacity = 1;

  /// 0.8 to 1.3: larger buttons (§9.6).
  double controlsScale = 1;
  bool leftHanded = false;

  // ---- Accessibility
  bool reduceShake = false;
  bool highContrastFlames = false;

  /// Solo only: 0.75 slows the whole game down (§9.6).
  double soloSpeed = 1;

  // ---- Profile
  /// Equipped hat from the locker (see `Cosmetics`).
  String skin = 'classic';

  /// Anonymous gameplay stats sent to the server (§13). On by default,
  /// switchable in Settings.
  bool shareAnalytics = true;

  /// Name for rooms and leaderboards; empty until the player types one.
  String playerName = '';

  /// Random per-install id for analytics; not tied to the player.
  String installId = '';

  static const _keys = (
    music: 'musicVolume',
    sfx: 'sfxVolume',
    haptics: 'haptics',
    opacity: 'controlsOpacity',
    scale: 'controlsScale',
    leftHanded: 'leftHanded',
    shake: 'reduceShake',
    flames: 'highContrastFlames',
    speed: 'soloSpeed',
    skin: 'skin',
    analytics: 'shareAnalytics',
  );

  void _read() {
    final p = _prefs;
    if (p == null) return;
    musicVolume = p.getDouble(_keys.music) ?? musicVolume;
    sfxVolume = p.getDouble(_keys.sfx) ?? sfxVolume;
    haptics = p.getBool(_keys.haptics) ?? haptics;
    controlsOpacity = p.getDouble(_keys.opacity) ?? controlsOpacity;
    controlsScale = p.getDouble(_keys.scale) ?? controlsScale;
    leftHanded = p.getBool(_keys.leftHanded) ?? leftHanded;
    reduceShake = p.getBool(_keys.shake) ?? reduceShake;
    highContrastFlames = p.getBool(_keys.flames) ?? highContrastFlames;
    soloSpeed = p.getDouble(_keys.speed) ?? soloSpeed;
    skin = p.getString(_keys.skin) ?? skin;
    shareAnalytics = p.getBool(_keys.analytics) ?? shareAnalytics;
    installId = p.getString('installId') ?? '';
    playerName = p.getString('playerName') ?? '';
  }

  /// Applies [change] and saves everything.
  void update(void Function(AppSettings s) change) {
    change(this);
    controlsOpacity = controlsOpacity.clamp(0.3, 1);
    controlsScale = controlsScale.clamp(0.8, 1.3);
    soloSpeed = soloSpeed.clamp(0.5, 1);
    notifyListeners();
    final p = _prefs;
    if (p == null) return;
    p.setDouble(_keys.music, musicVolume);
    p.setDouble(_keys.sfx, sfxVolume);
    p.setBool(_keys.haptics, haptics);
    p.setDouble(_keys.opacity, controlsOpacity);
    p.setDouble(_keys.scale, controlsScale);
    p.setBool(_keys.leftHanded, leftHanded);
    p.setBool(_keys.shake, reduceShake);
    p.setBool(_keys.flames, highContrastFlames);
    p.setDouble(_keys.speed, soloSpeed);
    p.setString(_keys.skin, skin);
    p.setBool(_keys.analytics, shareAnalytics);
    p.setString('playerName', playerName);
  }

  /// Screen shake multiplier.
  double get shake => reduceShake ? 0 : 1;
}

/// Puts [AppSettings] in the widget tree.
class Settings extends InheritedNotifier<AppSettings> {
  const Settings({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AppSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Settings>()?.notifier ??
      _fallback;

  /// Read without listening, for game code that polls.
  static AppSettings read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<Settings>()?.notifier ?? _fallback;

  static final _fallback = AppSettings.memory();
}
