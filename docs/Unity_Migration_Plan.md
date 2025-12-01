# Plane Idler — Godot → Unity Migration Plan

## How to use and keep this plan updated
- Keep this file as the single source of truth for migration status; update it daily or whenever a task changes state.
- Use the checklist boxes `[ ]` → `[x]` to mark progress; add your initials/date in parentheses, e.g., `[x] Configured URP (DK, 2025-12-02)`.
- Log decisions/unknowns in the **Open Questions & Decisions** table to avoid losing context.
- When adding new tasks, place them inside the appropriate phase and include owner + target date.

## Project pointers
- Godot project root: `./`
- Unity project root: `UnityVersion/PlaneIdler` (Unity 6000.2.14f1)
- Primary Godot entry scene: `scenes/Main.tscn`

## Current Godot inventory (snapshot 2025-12-01)
### Scenes
- `scenes/Main.tscn`
- `scenes/actors/AircraftActor.tscn`
- `scenes/airport/Airport.tscn`
- `scenes/airport/Stand.tscn`

### Scripts
- Root: `catalog_loader.gd`, `llm_agent.gd`, `main.gd`, `ollama_client.gd`, `upgrade_manager.gd`
- Actors: `scripts/actors/aircraft_actor.gd`
- Airport: `scripts/airport/airport_manager.gd`, `fuel_station.gd`, `runway.gd`, `stand.gd`, `tower.gd`
- Simulation: `scripts/sim/arrival_generator.gd`, `eligibility.gd`, `sim_controller.gd`, `sim_state.gd`, `stand_manager.gd`
- UI: `scripts/ui/income_chart.gd`, `traffic_chart.gd`

### Data & assets
- Data: `data/aircraft.json`, `data/upgrades.json`
- Textures: `assets/grass.jpg` (+ `.import`)
- Other: `.godot` project settings, `.uid` helper files alongside scripts

## Phase 1 — Preparation & Alignment
- [x] Lock Unity editor to 6000.2.14f1 in Unity Hub for all contributors.
- [x] Create `unity-migration` branch; keep Godot project read-only for reference.
- [x] Decide render pipeline (URP vs HDRP) → **URP** accepted (2025-12-01).
- [ ] Enable baseline Unity packages: TextMeshPro, Addressables, chosen Render Pipeline. (Input/Cinemachine optional; Godot had no player camera input.)
- [ ] Define coding conventions (namespaces, folder layout under `Assets/`, prefab naming).
- [ ] Export a Godot gameplay capture for behavior reference (movement, UI flows).

## Phase 2 — Content Transfer & Parity Foundations
- [ ] Import art into Unity with proper import presets (sRGB/linear, compression, mipmaps off for UI). Audio/VFX not present in Godot.
- [x] Grass texture imported to Unity Art folder (2025-12-01).
- [ ] Recreate materials/shaders to match Godot look; verify grass ground texture parity.
- [ ] Rebuild core scenes in Unity as prefabs: AircraftActor, Stand, Runway, Airport, Main scene layout (currently primitives via PrefabMaker).
- [x] Extend procedural scene bootstrapper (PrototypeSceneBuilder) to place baseline airport layout and systems (2025-12-01).
- [x] Added editor PrefabMaker to generate placeholder prefabs and builder now consumes them when present (2025-12-01).
- [ ] Physics/layers: Godot used no custom collisions; keep Unity defaults unless new gameplay requires.
- [ ] Input System optional (Godot had no player controls); add only if new controls are introduced.
- [x] Camera orbit implemented to mirror Godot top-down view.
- [x] Copy Godot data JSON into Unity project for reference (`Assets/PlaneIdler/Data`) (2025-12-01).
- [x] Mirrored JSON into `Assets/PlaneIdler/Resources/Data` for auto-loading (2025-12-01).

## Phase 3 — Gameplay Systems Port (C#)
- [x] Port `sim_controller.gd` + `sim_state.gd` to C# (game loop, tick/update cadence, ToD).
- [x] Port arrival generation (`arrival_generator.gd`) and eligibility logic.
- [x] Port airport domain: `airport_manager`, `runway`, `stand`, `tower`, `fuel_station` behaviors.
- [x] Port actor behavior: `aircraft_actor` movement/state (paths).
- [x] Port progression/economy: `upgrade_manager`, `catalog_loader`, data loading from JSON.
- [x] Replace Godot signals with C# events (bank/arrivals/missed/diverted).
- [x] LLM/Ollama integration stub added (HTTP client + agent).
- [x] UpgradeManager applies income/arrival multipliers and night_ops; infra adds logged.

## Phase 4 — UI/UX & Meta
- [x] HUD: bank label, sim clock, console log, income/traffic charts (daily buckets).
- [x] Upgrades list and build queue UI (runtime-built); purchase triggers build queue.
- [x] Airport status label (runway length, stand counts).
- [ ] LLM UI not present in Godot HUD (skip unless required later).

## Phase 5 — Lighting & Polish
- [x] Time-of-day (sun/moon) driven by SimState clock.
- [x] Add runway edge lights toggled by time of day.
- [ ] Match Godot lighting look (directional light and any runway/stand lights).
- [ ] Performance pass: batching, light counts, physics iterations, mobile/PC targets as needed.

## Phase 6 — Validation & Release
- [ ] Side-by-side playtest vs Godot reference video; log discrepancies.
- [ ] Automated sanity tests (play mode) for spawn rates, income calculations, upgrade effects.
- [ ] Build targets (PC/WebGL/Mobile as applicable); smoke test.
- [ ] Update docs/README with Unity build/run instructions; archive Godot project as historical reference.

## Task breakdown to start immediately
- Materials: recreate grass/ground material parity; decide on URP shader settings.
- Lighting: tune sun/moon and add runway/stand lights to match Godot visuals.
- Validation: capture parity clips vs Godot and log discrepancies.
- Builds/README: add Unity build/run instructions and smoke-test target platforms.

## Open Questions & Decisions Log
| Date | Item | Owner | Decision/Notes |
| ---- | ---- | ----- | -------------- |
| 2025-12-01 | Render pipeline choice (URP/HDRP) | Team | URP accepted |
|      | Target platforms to prioritize first |      | |
|      | Input devices to support (kb/mouse, gamepad, touch) |      | |
|      | Data persistence format in Unity (JSON vs PlayerPrefs vs custom) |      | |
