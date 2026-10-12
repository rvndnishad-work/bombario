import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Menu animation helpers: one-shot entrances that settle, and looping
/// "ambient" motion (bobbing, pulsing, blinking) for idle screens.
abstract final class Motion {
  /// Looping animations never settle, so `flutter test` (and its
  /// `pumpAndSettle`) runs without them; they also stop when the system asks
  /// for reduced motion.
  static bool ambient =
      !(!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST'));

  /// Whether looping motion should run here.
  static bool loops(BuildContext context) =>
      ambient && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// The menus' bouncy pop.
  static const Curve pop = Curves.easeOutBack;
}

/// Slides and fades [child] in once, [delay] after it first builds. Use
/// increasing delays to stagger a screen's tiles.
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
    this.offset = const Offset(0, 24),
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Where the child starts, in logical pixels from its place.
  final Offset offset;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  // The delay is the front of one animation rather than a timer, so a
  // screen closed early leaves nothing pending.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
  )..forward();

  late final double _start =
      widget.delay.inMicroseconds /
      (widget.delay + widget.duration).inMicroseconds;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final v = _start >= 1
          ? 1.0
          : ((_c.value - _start) / (1 - _start)).clamp(0.0, 1.0);
      final t = Motion.pop.transform(v);
      return Opacity(
        opacity: v,
        child: Transform.translate(
          offset: widget.offset * (1 - t),
          child: child,
        ),
      );
    },
  );
}

/// A tappable that squashes while pressed and springs back on release.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: widget.onTap == null ? null : (_) => _set(true),
    onTapUp: (_) => _set(false),
    onTapCancel: () => _set(false),
    onTap: widget.onTap,
    child: AnimatedScale(
      scale: _down ? 0.95 : 1,
      duration: Duration(milliseconds: _down ? 60 : 220),
      curve: _down ? Curves.easeOut : Motion.pop,
      child: widget.child,
    ),
  );
}

/// The kind of loop [Ambient] plays.
enum AmbientKind {
  /// Up and down, like an idle sprite.
  bob,

  /// Grows and shrinks a little: "tap me".
  pulse,

  /// On and off, like an arcade "PRESS START".
  blink,

  /// Rocks side to side, like a fizzing bomb.
  wobble,
}

/// Loops [child] forever while [Motion.loops] allows; otherwise shows it
/// still.
class Ambient extends StatefulWidget {
  const Ambient({
    super.key,
    required this.child,
    this.kind = AmbientKind.bob,
    this.period = const Duration(milliseconds: 900),
    this.amount = 1,
    this.phase = 0,
  });

  final Widget child;
  final AmbientKind kind;
  final Duration period;

  /// Scales the motion: pixels for bob, a factor for the rest.
  final double amount;

  /// 0 to 1: start part-way through the loop, so neighbours don't move in
  /// lockstep.
  final double phase;

  @override
  State<Ambient> createState() => _AmbientState();
}

class _AmbientState extends State<Ambient> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
    value: widget.phase,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.loops(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      if (!_c.isAnimating) return child!;
      final wave = math.sin(_c.value * 2 * math.pi);
      return switch (widget.kind) {
        AmbientKind.bob => Transform.translate(
          // Whole pixels keep the pixel art crisp.
          offset: Offset(0, (wave * 3 * widget.amount).roundToDouble()),
          child: child,
        ),
        AmbientKind.pulse => Transform.scale(
          scale: 1 + 0.04 * widget.amount * (wave + 1) / 2,
          child: child,
        ),
        AmbientKind.blink => Opacity(
          opacity: _c.value < 0.6 ? 1 : 0,
          child: child,
        ),
        AmbientKind.wobble => Transform.rotate(
          angle: wave * 0.12 * widget.amount,
          child: child,
        ),
      };
    },
  );
}
