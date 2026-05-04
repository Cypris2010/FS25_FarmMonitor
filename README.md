# FS25 FarmMonitor

A Farming Simulator 25 mod that exports live farm data to JSON files every 10 seconds and includes a local web dashboard for real-time monitoring.

## Features

- **Live JSON export** — silos, productions, animal husbandries and fill types written to the mod folder every 10 s
- **Web dashboard** — dark FS25-themed SPA with sidebar navigation, auto-refresh via Server-Sent Events and responsive layout
- **Views:** Overview (KPI tiles + active alerts), Silos, Productions, Animal Husbandries, Alerts, Settings
- **Tierställe detail page** — per-stall cards with occupancy, food, water and output progress bars, computed status (OK / Watch / Warning / Critical) and a warning band for urgent issues

## What it exports

| File | Content | Updated |
|---|---|---|
| `silos.json` | All silo and silo extension fill levels | every 10 s |
| `productions.json` | Production point inputs, outputs and chain status | every 10 s |
| `husbandries.json` | Animal counts, food/water/straw levels, health and outputs (milk, manure, …) | every 10 s |
| `fillTypes.json` | All fill type names, titles and HUD icon paths | once on map load |

All files are written to the mod directory:
```
<FS25 user data>/mods/FS25_FarmMonitor/
```

## Dashboard

The dashboard is a single-page app served by a small Go binary (`farmmonitor`). It connects to the server via Server-Sent Events and re-renders automatically whenever the mod writes new data (~every 10 s). [Go](https://go.dev/dl/) must be installed to build or run it.

### Start

```bash
# Navigate to the mod folder
cd "~/Library/Application Support/FarmingSimulator2025/mods/FS25_FarmMonitor"    # macOS
cd "%USERPROFILE%\Documents\My Games\FarmingSimulator2025\mods\FS25_FarmMonitor"  # Windows

# Option A — run directly without a build step
go run .

# Option B — build the binary once, then run it
go build -o farmmonitor      # macOS / Linux
go build -o farmmonitor.exe  # Windows

./farmmonitor
```

Open **http://localhost:8080** in a browser.

### Options

| Flag | Default | Description |
|---|---|---|
| `-port` | `8080` | HTTP listen port |
| `-host` | `127.0.0.1` | Listen address — use `0.0.0.0` for LAN / tablet access |

```bash
./farmmonitor -host 0.0.0.0 -port 9000
```

### Navigation

| View | Description |
|---|---|
| Overview | KPI tiles (silo count, productions, stalls, open alerts) and a prioritised alert list |
| Silos | Fill-level bars for every silo and silo extension |
| Productions | Input/output bars and chain status (running / inactive / stopped) per production point |
| Tierställe | Per-stall cards with occupancy, food, water, outputs and computed status |
| Alerts | Consolidated list of all active warnings across all categories |

## Installation

1. Copy the `FS25_FarmMonitor` folder into your FS25 mods directory:
   - **macOS:** `~/Library/Application Support/FarmingSimulator2025/mods/`
   - **Windows:** `Documents/My Games/FarmingSimulator2025/mods/`
2. Enable the mod in the in-game mod manager.
3. Load a savegame — the JSON files appear in the mod folder within the first few seconds.
4. Start the dashboard server from the mod folder (see above).

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
      "inputs":  [ { "fillType": "WHEAT", "title": "Weizen", "level": 1200, "capacity": 5000 } ],
      "outputs": [ { "fillType": "BREAD", "title": "Brot",   "level":  300, "capacity": 1000 } ],
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
      "food":    [ { "title": "Mischration", "value": 800, "capacity": 1000 } ],
      "water":   { "value": 600, "capacity": 1000 },
      "straw":   { "value": 400, "capacity": 1000 },
      "health":  92,
      "outputs": [
        { "fillType": "MILK",   "title": "Milch", "level": 4200, "capacity": 10000 },
        { "fillType": "MANURE", "title": "Mist",  "level":  800, "capacity":  5000 }
      ]
    }
  ]
}
```

Field reference:

| Field | Type | Description |
|---|---|---|
| `name` | string | Stall name |
| `animalType` | string | Animal type identifier (e.g. `COW`, `PIG`) or `"unknown"` |
| `numAnimals` | number | Current animal count |
| `maxAnimals` | number | Maximum capacity |
| `food` | array | Food trough entries with `title`, `value` and `capacity` |
| `water` | object\|null | Water level `{ value, capacity }` — `null` if stall has no water trough |
| `straw` | object\|null | Straw bedding level `{ value, capacity }` — `null` if stall uses no straw |
| `health` | number\|null | Average animal health 0–100 — `null` if no animals are present |
| `outputs` | array | Output storage entries with `fillType`, `title`, `level` and `capacity` (milk, manure, liquid manure, eggs, wool, …) |

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

## Notes

- Singleplayer only (`multiplayer supported="false"`).
- The JSON files are gitignored and not part of this repository — they are generated at runtime.
- `fillTypes.json` is written once per session since fill type definitions do not change while a map is loaded.
- The dashboard server must be started from the mod folder so it can locate the JSON files.
- Lua serialises empty arrays as `{}` (empty object) rather than `[]`. The dashboard handles this transparently.
