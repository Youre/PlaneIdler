# Catalog Schemas (draft)

These JSON structures back the procedural and AI logic. Keep them deterministic and stable across runs.

## Aircraft Catalog
Each entry defines a type/class of aircraft, not individual instances.

Required fields:
- `id` (string): unique slug, e.g., "c172".
- `displayName` (string): user-facing name.
- `class` (enum): `ga_small | ga_medium | turboprop | regional_jet | narrowbody | widebody | cargo_small | cargo_wide`.
- `fees` (object): `{ "landing": number, "parkingPerMinute": number }`.
- `runway` (object):
  - `minLengthMeters` (int)
  - `surface` (enum): `grass | asphalt | concrete`
  - `widthClass` (enum): `narrow | standard | wide`
- `standClass` (enum): matches stand capability required.
- `dwellMinutes` (object): `{ "min": int, "max": int }`.
- `spawnWeight` (number): relative probability within its unlocked tier.
- `tierUnlock` (int): 0..4 matching progression tiers.
- `mtowKg` (int): for realism/fee scaling hooks.

Optional fields:
- `notes` (string)
- `cargo` (object): `{ "maxTons": number }` for cargo variants.

Example entry:
```json
{
  "id": "c172",
  "displayName": "Cessna 172",
  "class": "ga_small",
  "fees": { "landing": 120, "parkingPerMinute": 2 },
  "runway": { "minLengthMeters": 650, "surface": "grass", "widthClass": "narrow" },
  "standClass": "ga_small",
  "dwellMinutes": { "min": 2, "max": 6 },
  "spawnWeight": 1.4,
  "tierUnlock": 0,
  "mtowKg": 1111
}
```

## Upgrade Catalog
Each upgrade is a purchasable action that modifies airport capability.

Required fields:
- `id` (string): unique slug.
- `displayName` (string)
- `category` (enum): `stand | runway | taxiway | surface | extension | nav | utility | multiplier`.
- `cost` (int): in-game currency.
- `buildTimeSeconds` (int)
- `prerequisites` (array of strings): ids that must be owned; can be empty.
- `effects` (array of effect objects): see below.
- `tierUnlock` (int): progression gate at which it becomes available.

Effect object shapes (union):
- `{ "type": "add_stand", "standClass": "...", "count": int }`
- `{ "type": "extend_runway", "meters": int }`
- `{ "type": "upgrade_surface", "from": "grass", "to": "asphalt" }`
- `{ "type": "add_runway", "lengthMeters": int, "surface": "...", "widthClass": "...", "ops": "arrival|departure|both" }`
- `{ "type": "add_taxi_exit", "runwayId": "...", "kind": "rapid|standard" }`
- `{ "type": "unlock_nav", "capability": "ils|lighting|night_ops" }`
- `{ "type": "multiplier", "target": "income", "value": 1.15 }`
- `{ "type": "capacity_bonus", "target": "parking", "value": 2 }`

Example entry:
```json
{
  "id": "ga_stand_pack_1",
  "displayName": "Add 2 GA Stands",
  "category": "stand",
  "cost": 1800,
  "buildTimeSeconds": 60,
  "prerequisites": [],
  "effects": [
    { "type": "add_stand", "standClass": "ga_small", "count": 2 }
  ],
  "tierUnlock": 0
}
```

## File Layout Proposal
- `data/aircraft.json`: array of aircraft entries.
- `data/upgrades.json`: array of upgrade entries.
- `data/tiers.json` (optional): describes per-tier spawn rate multipliers and price scaling.

## Validation
- Add a lightweight validator (C# or Python) to ensure required fields exist, enums are valid, and ranges make sense before loading in Godot.
