import 'package:flutter/widgets.dart';

/// Draws the whole UI larger on big screens, so a tablet looks like a big
/// phone rather than a phone layout lost in space: menus, cards, the HUD
/// and the touch controls all grow together. Phones are untouched.
///
/// The child lays out on a smaller logical screen (the real one divided by
/// [factor]) and is scaled back up to fill it. Scaling is a transform, so
/// text and the nearest-filtered sprites render sharp at device
/// resolution, and touches map through it.
class UiScale extends StatelessWidget {
  const UiScale({super.key, required this.child});

  final Widget child;

  /// Screens this narrow on their short side or narrower are phones.
  static const double phoneMax = 600;

  /// The short side a scaled screen lays out at, before the cap.
  static const double designShortSide = 480;

  /// The most a big screen scales up.
  static const double maxFactor = 1.5;

  /// How much a screen of [size] (logical pixels) scales the UI: 1 on a
  /// phone, up to [maxFactor] on a 10-inch tablet.
  static double factor(Size size) {
    final short = size.shortestSide;
    if (short < phoneMax) return 1;
    return (short / designShortSide).clamp(1.0, maxFactor);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final s = factor(media.size);
    if (s == 1) return child;
    final size = media.size / s;
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: size,
        child: MediaQuery(
          data: media.copyWith(
            size: size,
            devicePixelRatio: media.devicePixelRatio * s,
            padding: media.padding / s,
            viewPadding: media.viewPadding / s,
            viewInsets: media.viewInsets / s,
            systemGestureInsets: media.systemGestureInsets / s,
          ),
          child: child,
        ),
      ),
    );
  }
}
