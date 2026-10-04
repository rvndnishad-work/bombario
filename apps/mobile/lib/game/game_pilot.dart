import 'package:bombario_core/bombario_core.dart' as core;

/// Something other than the player at the controls of a [BlastGame]: the
/// dev playthrough recorder replays autopilot runs through this.
abstract interface class GamePilot {
  /// Stage [stageIndex] has just been set up, before its first tick.
  void onStage(int stageIndex, core.World sim, core.Player player);

  /// The input for the next tick the world actually advances.
  core.PlayerInput next();
}
