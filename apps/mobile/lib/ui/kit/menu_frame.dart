import 'package:flutter/material.dart';

import 'arena_backdrop.dart';
import 'motion.dart';
import 'pixel_theme.dart';
import 'sprite_icon.dart';

/// A menu page over the drifting maze: a pixel back button, a title and
/// optional trailing widgets on top, then [child].
class MenuFrame extends StatelessWidget {
  const MenuFrame({
    super.key,
    required this.title,
    required this.child,
    this.trailing = const [],
  });

  final String title;
  final Widget child;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ArenaBackdrop(
      chase: false,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    Pressable(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Semantics(
                        button: true,
                        label: 'Back',
                        child: Container(
                          key: const Key('menu-back'),
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Px.panel,
                            border: Border.all(color: Px.edge, width: 3),
                          ),
                          child: Transform.flip(
                            flipX: true,
                            child: const SpriteIcon('chev', size: 24),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Entrance(
                      offset: const Offset(-24, 0),
                      child: Text(title, style: Px.title(16, color: Px.fuse)),
                    ),
                    const Spacer(),
                    ...trailing,
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A full-screen "working on it" veil: a fizzing bomb and a line of text.
class BusyVeil extends StatelessWidget {
  const BusyVeil({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Px.ink.withValues(alpha: 0.8),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Ambient(
            amount: 2,
            period: Duration(milliseconds: 500),
            child: Ambient(
              kind: AmbientKind.wobble,
              period: Duration(milliseconds: 300),
              child: SpriteIcon('bomb', size: 56),
            ),
          ),
          const SizedBox(height: 16),
          Text(text, style: Px.title(12)),
        ],
      ),
    ),
  );
}
