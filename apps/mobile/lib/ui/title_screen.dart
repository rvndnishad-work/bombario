import 'package:flutter/material.dart';

import '../audio/game_audio.dart';
import 'home_screen.dart';
import 'kit/arena_backdrop.dart';
import 'kit/motion.dart';
import 'kit/pixel_theme.dart';
import 'kit/sprite_icon.dart';

/// The arcade title: the logo drops in letter by letter, a bomb fizzes
/// beside it, and "TAP TO START" blinks. A tap flashes white and opens Home.
class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen>
    with SingleTickerProviderStateMixin {
  static const _word = 'BOMBARIO';

  /// Gap between letters dropping in.
  static const _letterStep = Duration(milliseconds: 90);

  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  bool _leaving = false;

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_leaving) return;
    _leaving = true;
    GameAudio.instance.play(Sfx.explode);
    await _flash.forward();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => const HomeScreen(),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lettersDone = _letterStep * _word.length;
    return Scaffold(
      body: GestureDetector(
        key: const Key('title-start'),
        behavior: HitTestBehavior.opaque,
        onTap: _start,
        child: ArenaBackdrop(
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final (i, ch) in _word.split('').indexed)
                          Entrance(
                            delay: _letterStep * i,
                            offset: const Offset(0, -90),
                            duration: const Duration(milliseconds: 500),
                            child: _Letter(ch, phase: i / _word.length),
                          ),
                        const SizedBox(width: 14),
                        Entrance(
                          delay: lettersDone,
                          offset: const Offset(60, 0),
                          child: const Ambient(
                            kind: AmbientKind.wobble,
                            period: Duration(milliseconds: 500),
                            child: SpriteIcon('bomb', size: 64),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Entrance(
                      delay: lettersDone + const Duration(milliseconds: 150),
                      child: Text(
                        'BLAST  ·  CHAIN  ·  ESCAPE',
                        style: Px.label(14, color: Px.muted),
                      ),
                    ),
                    const SizedBox(height: 46),
                    Entrance(
                      delay: lettersDone + const Duration(milliseconds: 350),
                      child: Ambient(
                        kind: AmbientKind.blink,
                        period: const Duration(milliseconds: 1000),
                        child: Text(
                          'TAP TO START',
                          style: Px.title(16, color: Px.paper),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // The bang on the way out.
              IgnorePointer(
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _flash,
                    curve: Curves.easeOutCubic,
                  ),
                  child: const ColoredBox(
                    color: Px.paper,
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One logo letter: fuse-yellow with a hard drop shadow, bobbing a little
/// out of step with its neighbours.
class _Letter extends StatelessWidget {
  const _Letter(this.ch, {required this.phase});

  final String ch;
  final double phase;

  @override
  Widget build(BuildContext context) => Ambient(
    phase: phase,
    period: const Duration(milliseconds: 1400),
    amount: 0.8,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Stack(
        children: [
          Transform.translate(
            offset: const Offset(5, 5),
            child: Text(ch, style: Px.title(54, color: Px.brick)),
          ),
          Text(ch, style: Px.title(54, color: Px.fuse)),
        ],
      ),
    ),
  );
}
