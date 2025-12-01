# Plane Idler (Unity) workspace

- **Scenes**: Unity scene files; mirrors Godot `scenes/`.
- **Prefabs**: Prefab equivalents for reusable Godot node trees (AircraftActor, Stand, Runway, Airport, UI panels).
- **Scripts**: C# ports of GDScript (namespace `PlaneIdler`).
- **Data**: Game data copied from Godot JSON (`aircraft.json`, `upgrades.json`); convert to ScriptableObjects as we port systems.
- **Art/UI**: Imported textures, fonts, audio; set import presets to match Godot look.
- **Settings**: Project or package-specific assets (Input Actions, pipeline settings) scoped to the game.
- **Tests**: Play/Edit mode tests for regression coverage.

Notes:
- Godot files stay in place for reference; do not delete or move them.
- Keep tasks and status in `docs/Unity_Migration_Plan.md`; update checkboxes as work progresses.
