import 'package:flutter/material.dart';

import '../settings/settings.dart';
import 'kit/pixel_theme.dart';

/// Sound, controls and accessibility (§9.2, §9.6).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Settings.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Px.night,
        title: Text('Settings', style: Px.title(14)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            const _Header('Sound'),
            _SliderRow(
              label: 'Music',
              value: s.musicVolume,
              display: '${(s.musicVolume * 100).round()}%',
              onChanged: (v) => s.update((s) => s.musicVolume = v),
            ),
            _SliderRow(
              label: 'Effects',
              value: s.sfxVolume,
              display: '${(s.sfxVolume * 100).round()}%',
              onChanged: (v) => s.update((s) => s.sfxVolume = v),
            ),
            const _Header('Controls'),
            _SwitchRow(
              label: 'Vibration',
              value: s.haptics,
              onChanged: (v) => s.update((s) => s.haptics = v),
            ),
            _SliderRow(
              label: 'Control opacity',
              value: s.controlsOpacity,
              min: 0.3,
              display: '${(s.controlsOpacity * 100).round()}%',
              onChanged: (v) => s.update((s) => s.controlsOpacity = v),
            ),
            _SliderRow(
              label: 'Button size',
              value: s.controlsScale,
              min: 0.8,
              max: 1.3,
              divisions: 5,
              display: '${(s.controlsScale * 100).round()}%',
              onChanged: (v) => s.update((s) => s.controlsScale = v),
            ),
            _SwitchRow(
              key: const Key('left-handed'),
              label: 'Left-handed (bomb on the left)',
              value: s.leftHanded,
              onChanged: (v) => s.update((s) => s.leftHanded = v),
            ),
            const _Header('Accessibility'),
            _SwitchRow(
              label: 'Reduce screen shake',
              value: s.reduceShake,
              onChanged: (v) => s.update((s) => s.reduceShake = v),
            ),
            _SwitchRow(
              label: 'High-contrast flames',
              value: s.highContrastFlames,
              onChanged: (v) => s.update((s) => s.highContrastFlames = v),
            ),
            _SliderRow(
              label: 'Solo game speed',
              value: s.soloSpeed,
              min: 0.5,
              max: 1,
              divisions: 2,
              display: '${(s.soloSpeed * 100).round()}%',
              onChanged: (v) => s.update((s) => s.soloSpeed = v),
            ),
            const _Header('Privacy'),
            _SwitchRow(
              key: const Key('share-analytics'),
              label: 'Share anonymous play stats',
              value: s.shareAnalytics,
              onChanged: (v) => s.update((s) => s.shareAnalytics = v),
            ),
            const SizedBox(height: 8),
            Text(
              'Players are told apart by hat as well as colour, so every '
              'palette stays colour-blind safe.',
              style: Px.label(12, color: Px.muted, bold: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 6),
    child: Text(text.toUpperCase(), style: Px.label(12, color: Px.fuse)),
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label, style: Px.label(14, bold: false)),
    value: value,
    onChanged: onChanged,
  );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.display,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions = 10,
  });

  final String label;
  final double value;
  final String display;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final int divisions;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 200,
        child: Text(label, style: Px.label(14, bold: false)),
      ),
      Expanded(
        child: Semantics(
          label: label,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ),
      SizedBox(
        width: 56,
        child: Text(display, style: Px.label(13), textAlign: TextAlign.end),
      ),
    ],
  );
}
