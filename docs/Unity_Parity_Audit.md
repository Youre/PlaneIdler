# Plane Idler – Unity Parity Audit (2025-12-01)

Scope: compared Godot baseline (`scripts/`, `scenes/`) with Unity port in `UnityVersion/PlaneIdler` as of 2025-12-01. Focus on functional parity, not visual polish.

## Headline gaps
- Runway/ATC flow in Unity skips the queueing/holding logic, so arrivals land even when the runway is marked busy and no diversion reasons are tracked (`Assets/PlaneIdler/Scripts/Sim/SimController.cs` vs `scripts/sim/sim_controller.gd`).
- Upgrade effects that change the world (add stands/hangars/runways, pave/widen runway, taxiways, runway lights) are stubs in Unity and never modify the scene or sim state (`Assets/PlaneIdler/Scripts/Systems/UpgradeManager.cs`).
- Progression and traffic generation are flattened: Unity ignores tiers, unlocks, and night-ops gating, so spawn mix and pacing never evolve (`Assets/PlaneIdler/Scripts/Sim/ArrivalGenerator.cs`, `SimState.cs`).

## Detailed findings by area

### Simulation flow and traffic control
- Godot enforces a single active runway operation, queues arrivals/departures, and diverts when busy without ATC; Unity does not check `_runwayBusy` before `HandleArrival`, so simultaneous landings occur and no runway-queue exists (`SimController.cs`).
- Holding patterns with ATC are visualized and dequeued in Godot; Unity spawns a looping actor when the runway is busy but never ties it to a landing slot or a timeout/diversion path (`SimController.cs`).
- Diversion reasons and counts (used for AI context) are tracked in Godot (`sim_controller.gd` + `sim_state.gd`); Unity only increments `missed/diverted` integers and drops the reason data entirely (`SimState.cs`).
- Flyovers/flybys that keep the airfield lively (and provide diversion feedback) are missing in Unity; only arrival/departure actors exist (`sim_controller.gd` has `_spawn_flyover/_spawn_flyby`).
- Actor lifecycle: Godot reuses parked actors, culls distant/stuck ones, and limits lifetime; Unity instantiates a new actor for every arrival and every departure, leaving parked arrivals in the scene indefinitely and never culling (`SimController.cs`, `Actors/AircraftActor.cs`).

### Progression, arrivals, and economy
- Spawn selection: Godot weights aircraft by progression tier and unlocked upgrades, with an initial delay and rate scaling by `traffic_rate_multiplier`; Unity uses fixed `spawnWeight` per aircraft and a simple jittered interval, so larger aircraft appear without meeting runway/upgrade thresholds and pacing never accelerates (`ArrivalGenerator.cs` vs `arrival_generator.gd`).
- Night ops: Godot blocks night arrivals unless `night_ops` is unlocked; Unity spawns 24/7 and only toggles lights visually (`ArrivalGenerator.cs`, `RunwayLightsController.cs`).
- Income: Godot charges landing + dwell; FBO fee is added only when service occurs. Unity always adds `fboService` in `AddIncome` and may add it a second time when FBO triggers, inflating revenue (`SimController.cs` vs `sim_controller.gd`).
- FBO capacity: Godot tracks hangar slots added via upgrades and enforces slot limits; Unity has `fboSlotsTotal/Used` fields but never registers slots from upgrades and never decrements on departure, so capacity is ineffective (`SimState.cs`, `UpgradeManager.cs`, `SimController.cs`).

### Upgrades and world changes
- Effect handling gaps: `add_stand`, `add_hangar`, `extend_runway`, `upgrade_surface`, `widen_runway`, `add_runway`, `add_taxi_exit` are stubs or log-only in Unity, so purchasing upgrades does not change geometry, capacity, traffic rate, or visuals (`UpgradeManager.cs`). Godot applies all effects, rebuilds taxiways, widens/extends runways, enables lights, and updates sim multipliers (`upgrade_manager.gd`, `airport_manager.gd`).
- Construction timing ignores sim time-scale in Unity (always uses real `deltaTime`); Godot scales build timers by `sim.time_scale` so pausing/fast-forwarding affects build completion.
- Tier progression and unlock sequencing: Godot tracks `progression_tier` and per-tier upgrade counts to drive spawn weighting; Unity does not store tier or prerequisites beyond simple purchase count, so higher-tier traffic is never gated and the sim cannot escalate properly (`SimState.cs`, `UpgradeManager.cs`).

### Airport layout and infrastructure
- Procedural airport builder in Godot creates rows of stands, hangars, taxiways, runway lights, and parallel/cross runways with correct headings; Unity `AirportManager` is effectively empty and does not spawn or manage any of this, leaving only manually placed primitives from `PrototypeSceneBuilder` (`AirportManager.cs` vs `airport_manager.gd`).
- Runway suitability: Godot supports multiple runways and picks an eligible one per aircraft; Unity holds a single runway reference and lacks `register_runway`/multi-runway selection, so second-runway upgrades cannot function (`SimController.cs` vs `sim_controller.gd`).
- Runway lights and taxiways are upgrade-gated in Godot (e.g., `ils_lighting`, `taxi_loop`); Unity lights are always on at night and taxiways are never built (`RunwayLightsController.cs`, `UpgradeManager.cs`).

### UI/UX and controls
- Godot HUD includes time-scale buttons, upgrade list, build queue, console log, airport status (runway length, stand counts), and two live charts fed by sim signals (`main.gd` + `ui/*`). Unity HUD shows only a few counters; there is no time-scale control, no upgrade list/build queue UI, no airport status, and no console log (`UI/HudController.cs`, `UI/HudRuntimeBuilder.cs`).
- Charts: Godot draws stacked bars for received/missed and income history with proper day buckets; Unity `SimpleLineChart` just appends the latest bucket value each second, lacks missed traffic display, and does not align to in-game days (`ChartUpdater.cs`).

### Lighting and camera
- Godot animates sun/moon color, position, and a visible sky orb tied to the sim clock; Unity uses a simpler gradient and does not visualize the sun/moon positions (`DayNightController.cs` vs `main.gd` lighting section).
- Camera orbit in Unity matches the general idea but does not scale radius based on runway length changes from upgrades (because those upgrades are not applied), so framing will be wrong once geometry should grow (`CameraAutoOrbit.cs`).

### Data/state integrity
- Godot `SimState` carries `nav_capabilities`, `traffic_rate_multiplier`, daily received/missed arrays, diversion reasons, and upgrade catalogs; Unity `SimState` drops capabilities, diversion reasons, and tier counts, so systems that depend on them cannot be added later without schema changes (`SimState.cs`).
- Events: Godot emits rich signals (bank_changed, etc.); Unity `Events` hub only covers four counters, so UI cannot react to construction, upgrade availability, or time-scale changes (`Systems/Events.cs`).

### Notable bugs/regressions
- Runway busy flag in Unity never blocks incoming arrivals; actors can overlap on the runway (`SimController.cs`).
- Parked arrival actors are never reused or destroyed; departures spawn new actors and parked ones persist indefinitely (`SimController.cs`, `AircraftActor.cs`).
- Income double-count: FBO fee applied to every arrival and again when FBO chance hits (`SimController.cs`).
- Build timers ignore `timeScale` and continue while paused/slow-mo (`UpgradeManager.cs`).
- Spawn gating: night arrivals still spawn when night ops should be locked (`ArrivalGenerator.cs`).

## Partial parity (working or close)
- Data loading from the same JSON assets is wired (`Systems/CatalogLoader.cs`).
- Basic stand occupancy and eligibility checks exist (`Airport/StandManager.cs`, `Sim/Eligibility.cs`).
- Time-of-day clock advances at day/night rates and drives light toggling (`SimState.cs`, `DayNightController.cs`).
- Camera auto-orbit and ground/grass setup roughly mirror Godot defaults (`CameraAutoOrbit.cs`, `PrototypeSceneBuilder.cs`).

## Recommended next steps
1) Restore functional parity in sim flow: implement runway queueing/ATC holding and diversion reasons; enforce busy-runway checks before landing/departure start.  
2) Finish upgrade effect handlers and airport builder hooks (stands, hangars/FBO slots, runway geometry, taxiways, lights, second runway) so purchases change both scene and sim data.  
3) Reintroduce progression gating: tier-aware arrival selection, night-ops spawn blocking, traffic/income multipliers, and nav capability storage.  
4) Bring HUD to parity: time controls, upgrade list/build queue, airport status, console log, and true daily charts driven by sim signals.  
5) Add actor lifecycle management (reuse or despawn parked craft, distance culling) to prevent runway crowding and performance leaks.  
