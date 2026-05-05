# FS25 FarmMonitor

A Farming Simulator 25 mod that exports live farm data to JSON files every 10 seconds and includes a local web dashboard for real-time monitoring.

## Features

- **Live JSON export** — silos, productions, animal husbandries, fill types and animal food recipes written to the modSettings folder
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
| `animalFood.json` | Food group recipes per animal type (fill types, percentages) | once on map load |

All files are written to the modSettings directory:
- **macOS:** `~/Library/Application Support/FarmingSimulator2025/modSettings/FS25_FarmMonitor/`
- **Windows:** `Documents/My Games/FarmingSimulator2025/modSettings/FS25_FarmMonitor/`

## Dashboard

The dashboard is a single-page app served by a small Go binary (`farmmonitor`). It connects to the server via Server-Sent Events and re-renders automatically whenever the mod writes new data (~every 10 s).

The server automatically detects the JSON data directory from the FS25 modSettings folder — no need to run it from a specific location.

### Start — Download (empfohlen)

Download the latest binary for your OS from the [Releases page](https://github.com/Cypris2010/FS25_FarmMonitor/releases):

| OS | File |
|---|---|
| macOS (Apple Silicon) | `farmmonitor-macos-apple` |
| macOS (Intel) | `farmmonitor-macos-intel` |
| Windows | `farmmonitor-windows.exe` |

**macOS:** Make the file executable before running:
```bash
chmod +x farmmonitor-macos-apple
./farmmonitor-macos-apple
```

> **Note:** macOS may block the binary on first launch. Go to **System Settings → Privacy & Security** and click **Allow Anyway**, or run:
> ```bash
> xattr -d com.apple.quarantine farmmonitor-macos-apple
> ```

**Windows:** Double-click `farmmonitor-windows.exe` or run it from the terminal.

### Start — Build from source (optional)

Requires [Go](https://go.dev/dl/) to be installed.

```bash
cd path/to/FS25_FarmMonitor/Server
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
| `-data` | auto-detected | Path to the directory containing the JSON data files |

```bash
./farmmonitor -host 0.0.0.0 -port 9000
./farmmonitor -data /custom/path/to/json/files
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
3. Load a savegame — the JSON files appear in the modSettings folder within the first few seconds.
4. Build and start the dashboard server from the `Server` folder (see above).

## JSON structure

### silos.json
```json
{
  "timestamp": "2026-05-03T22:49:23",
  "farmId": 1,
  "savegame": "Mein Hof",
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
  "savegame": "Mein Hof",
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
  "savegame": "Mein Hof",
  "husbandries": [
    {
      "name": "Kuhstall",
      "animalType": "COW",
      "numAnimals": 24,
      "maxAnimals": 30,
      "food":      [ { "title": "Mischration", "value": 800, "capacity": 1000 } ],
      "foodTotal": { "value": 800, "capacity": 1000, "ratio": 0.8 },
      "water":     { "value": 600, "capacity": 1000 },
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
| `food` | array | Food trough entries with `title`, `value` and `capacity` per group |
| `foodTotal` | object\|null | Combined food level `{ value, capacity, ratio }` — `null` if stall has no food trough |
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

### animalFood.json
```json
{
  "PIG": [
    { "title": "Mais Sorghum",                 "percentage": 50, "fillTypes": ["CORN", "SORGHUM"] },
    { "title": "Weizen Gerste Hafer",          "percentage": 25, "fillTypes": ["WHEAT", "BARLEY", "OAT"] },
    { "title": "Sojabohnen Raps Sonnenblumen", "percentage": 20, "fillTypes": ["SOYBEAN", "CANOLA", "SUNFLOWER"] },
    { "title": "Kartoffeln Zuckerrüben …",     "percentage":  5, "fillTypes": ["POTATO", "SUGARBEET"] }
  ],
  "COW": [
    { "title": "Futter", "percentage": 100, "fillTypes": ["FORAGE_MIXING"] }
  ]
}
```

One entry per animal type. The `percentage` field is the share of this food group in the total recipe (sum of all groups = 100). Use this together with `foodTotal` from `husbandries.json` to calculate how much of each fill type a stall needs.

## Notes

- Singleplayer only (`multiplayer supported="false"`).
- The JSON files are gitignored and not part of this repository — they are generated at runtime.
- `fillTypes.json` and `animalFood.json` are written once per session since their definitions do not change while a map is loaded.
- The `savegame` field in each JSON file contains the savegame name from `careerSavegame.xml` — useful for identifying which save is currently active when multiple saves exist.
- The dashboard server can be started from any directory — it automatically locates the JSON files in the modSettings folder. Use `-data` to override the path manually.
- Lua serialises empty arrays as `{}` (empty object) rather than `[]`. The dashboard handles this transparently.
