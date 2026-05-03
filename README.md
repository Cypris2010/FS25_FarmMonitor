# FS25 FarmMonitor

A Farming Simulator 25 mod that exports live farm data to JSON files every 10 seconds. Intended as a backend data source for an external web dashboard.

## What it exports

| File | Content | Updated |
|---|---|---|
| `silos.json` | All silo and silo extension fill levels | every 10 s |
| `productions.json` | Production point inputs, outputs and chain status | every 10 s |
| `husbandries.json` | Animal counts, food/water levels and outputs (milk, eggs, …) | every 10 s |
| `fillTypes.json` | All fill type names, titles and HUD icon paths | once on map load |

All files are written to the mod directory:
```
<FS25 user data>/mods/FS25_FarmMonitor/
```

## JSON structure

### silos.json
```json
{
  "timestamp": "2026-05-03T22:49:23",
  "farmId": 1,
  "silos": [
    {
      "name": "Grosses Silo",
      "type": "silo",
      "capacity": 200000,
      "contents": [
        { "fillType": "WHEAT", "title": "Weizen", "level": 45000 }
      ]
    }
  ]
}
```

### productions.json
```json
{
  "timestamp": "2026-05-03T22:49:23",
  "farmId": 1,
  "productions": [
    {
      "name": "Bäckerei",
      "inputs":  [ { "fillType": "WHEAT", "title": "Weizen",  "level": 1200, "capacity": 5000 } ],
      "outputs": [ { "fillType": "BREAD", "title": "Brot",    "level":  300, "capacity": 1000 } ],
      "productions": [
        { "id": "bread", "name": "Brot backen", "status": "running", "cyclesPerMonth": 12 }
      ]
    }
  ]
}
```

### husbandries.json
```json
{
  "timestamp": "2026-05-03T22:49:23",
  "farmId": 1,
  "husbandries": [
    {
      "name": "Kuhstall",
      "animalType": "COW",
      "numAnimals": 24,
      "maxAnimals": 30,
      "food":  [ { "title": "Mischration", "value": 800, "capacity": 1000 } ],
      "water": { "value": 600, "capacity": 1000 },
      "outputs": [ { "fillType": "MILK", "title": "Milch", "level": 4200, "capacity": 10000 } ]
    }
  ]
}
```

### fillTypes.json
```json
[
  {
    "name": "WHEAT",
    "title": "Weizen",
    "hudOverlayFilename": "dataS/menu/hud/fillTypes/hud_fill_wheat.png"
  }
]
```

Icon paths use two formats depending on their origin:
- **Base game:** `dataS/menu/hud/fillTypes/...` — relative to the FS25 installation directory
- **Mods:** absolute path to the mod folder

## Installation

1. Copy the `FS25_FarmMonitor` folder into your FS25 mods directory:
   - **macOS:** `~/Library/Application Support/FarmingSimulator2025/mods/`
   - **Windows:** `Documents/My Games/FarmingSimulator2025/mods/`
2. Enable the mod in the in-game mod manager.
3. Load a savegame — the JSON files appear in the mod folder within the first few seconds.

## Notes

- Singleplayer only (`multiplayer supported="false"`).
- The JSON files are gitignored and not part of this repository — they are generated at runtime.
- `fillTypes.json` is written once per session since fill type definitions do not change while a map is loaded.
