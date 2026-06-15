![FS25 FarmMonitor](assets/git-social-banner.png)

![Downloads](https://img.shields.io/github/downloads/Cypris2010/FS25_FarmMonitor/total)

# FS25 FarmMonitor

FS25 FarmMonitor gives your Farming Simulator 25 game a second screen. A lightweight Lua mod continuously exports silo levels, production chains, animal husbandries, goods, and field states as JSON, while a small Go server picks them up and pushes live updates to a dark-themed web dashboard via Server-Sent Events — no browser refresh needed. Keep an eye on your entire farm from a second monitor, a tablet on the desk, or any device on your local network.

![Silos](docs/screenshots/screenshot_silos.png)
*Silos — Füllstände aller Silos und Lagergebäude*

![Produktionen](docs/screenshots/screenshot_produktionen.png)
*Produktionen — Ein- und Ausgänge aller Produktionsketten*

![Tierställe](docs/screenshots/screenshot_tierstalle.png)
*Tierställe — Belegung, Fütterung, Gesundheit und Ausgänge pro Stall*

![Warenübersicht](docs/screenshots/screenshot_waren.png)
*Warenübersicht — Lagerbestände, Verkaufspreise und Preistrend-Indikatoren*

![Felder](docs/screenshots/screenshot_felder.png)
*Felder — Feldzustand, Bodenpflege, Bedarfsrechner und Ernteschätzung*

## Features

The dashboard updates automatically every few seconds — no refresh needed. All views are accessible via the sidebar.

### Overview
A quick summary of your entire farm at a glance: KPI tiles show how many silos are active, how many production chains are running, how many animal stalls need attention, and how many alerts are currently open. Below the tiles sits a prioritised alert list that surfaces the most urgent issues across all categories — so you always know what needs attention first without having to browse through individual views.

### Silos & Storage
Fill-level bars for every storage location on your farm — silos, silo extensions, bunker silos (with fermentation progress and compaction level), bale and pallet storage buildings, and manure heaps. Filter buttons at the top let you narrow the view to a specific storage type. Each entry shows its current fill levels by commodity so you always know what you have and how much space is left.

### Productions
Input and output bars for every production chain on your farm, colour-coded by fill level so you can spot bottlenecks instantly. Each card shows whether the chain is currently running, idle or stopped, and lists all ingredients and products with their current stock and capacity. Clicking any input ingredient takes you directly to that commodity in the Goods view.

Beyond monitoring, you can control your productions directly from the dashboard: change the output mode for any product (auto-store, direct sale, or pallet output) without opening the game, and trigger the immediate ejection of a full pallet for any output — right from the browser. This works for any production building that supports pallet output, including mod productions.

### Animals
Per-stall cards showing current and maximum occupancy, all food groups with fill levels (with smart weighting for parallel feeders like pigs, where not every group is equally important), water and straw levels, average animal health and all outputs like milk, manure or eggs. Alert status is colour-coded — OK, Watch, Warning or Critical — and thresholds are fully configurable per resource type in the Settings view.

### Goods
An aggregated overview of everything you own, sorted by commodity. Each row shows your total stock across all storage types on the farm, the current best selling price available at any station on the map, the seasonal maximum price and the best month to sell, the current trend (rising, falling or high demand), and a colour-coded rating of how the current price compares to the seasonal peak.

From the Goods view you can also act directly: for any commodity that is produced by one or more of your production buildings, you can change the output mode or trigger a pallet ejection across all relevant productions at once — without having to visit each production card individually.

### Fields
Per-field cards covering everything you need to plan your next farm run. Each card shows the current crop, growth stage with a visual progress bar, a harvest-ready badge when the time has come, and an estimated yield bonus based on your soil conditions. Seven soil condition bars — ploughing, fertilising, liming, mulching, rolling, weed coverage and stone coverage — give you a complete picture of field health at a glance.

An interactive seed calculator lets you select any crop per field and instantly shows you the required seed quantity in litres per hectare and as a total for that field. The same calculator covers lime, fertiliser and herbicide so you can plan your refill runs before you even get on the tractor. Your crop selection is saved in the browser so you don't lose it when switching views.

### Fleet
Cards for every vehicle on your farm showing current speed, fuel, AdBlue and battery levels, damage status, assigned driver and total operating hours. Clicking a card opens the detail panel with a full breakdown of all tanks, attached implements, purchase price, working width and vehicle colour. The fleet view supports filtering by shop category, free-text search by name, status filters and a "last moved" sort mode that puts recently active vehicles at the top.

**AutoDrive** status is shown directly on each fleet card — current mode, destination, remaining drive time and detailed state badges for every situation (loading, unloading, waiting for combine, driving to refuel or park, blocked, error, …). The vehicle detail panel includes a full AutoDrive control tab where you can set the operating mode, assign departure and destination markers, select the commodity to transport, and start or stop the route — all from the browser, without switching back to the game.

**Courseplay** job type, current waypoint progress and estimated remaining time are displayed on the fleet card and in the detail panel alongside AutoDrive whenever both mods are active.

### Map
An interactive map built on the farm's overview image. Field outlines are drawn as accurate polygons with field numbers placed at the centre of each field. All map hotspots — selling stations, production buildings, fuel stations, the shop, animal pastures and more — appear as colour-coded pins with tooltips. Live vehicle positions are updated every two seconds with smooth movement and direction arrows so you can follow your fleet in real time.

The map supports mouse wheel zoom, click-and-drag panning and pinch-to-zoom on touch devices. You can click any vehicle or hotspot pin to jump directly to the corresponding entry in the Fleet or Productions view.

### Alerts & Settings
The Alerts view consolidates every active warning and critical state across all categories — animals, productions, silos and fields — in one place, sorted by severity. In Settings you can adjust the warn and critical thresholds for food, water, straw, storage outputs and stall occupancy to match how you run your farm. You can also hide individual placeables from the dashboard per savegame, keeping the views clean when you have buildings you don't actively manage.

---

**Multiplayer:** every player runs the mod locally and sees their own farm's data. Singleplayer and player-hosted multiplayer are fully supported.

## How it works

FarmMonitor has two independent parts that communicate through plain JSON files on disk — no network connection between them is required.

**Inside the game (Lua mod)**
A lightweight Lua mod runs inside Farming Simulator 25 and hooks into the game's `update()` loop. Every 10 seconds it reads live data from the game's internal APIs — silo fill levels, production chains, animal stalls, vehicle states, field conditions — and writes everything out as JSON files to the FS25 modSettings directory. Some data that rarely changes (fill type definitions, fruit type growth stages, animal food recipes) is written only once when the map is loaded. Field soil conditions are sampled every 60 seconds via low-level density map queries.

The mod never reads from or writes to the internet, never opens any ports, and never modifies any game state on its own.

**Outside the game (Go server)**
A small Go binary (`farmmonitor`) watches the JSON files for changes using a file watcher. Whenever a file is updated the server parses it and immediately pushes the new data to all connected browser clients via Server-Sent Events (SSE). The dashboard HTML and all assets are embedded directly in the binary — there is no separate install step and no internet dependency.

**In the browser (dashboard)**
The dashboard is a single-page app that opens a persistent SSE connection to the server and re-renders any section that received new data. Because SSE is a one-way push channel, the browser never has to poll — updates appear automatically as soon as the mod writes them.

```
FS25 (game process)
  └── FarmMonitor.lua          ← reads game APIs every 10 s
        └── writes JSON files  ← modSettings folder on disk

farmmonitor (Go binary)
  └── watches JSON files       ← file watcher, no polling delay
        └── pushes SSE events  ← to all open browser tabs

Browser (dashboard)
  └── SSE connection           ← persistent, automatic updates
```

IPC commands (AutoDrive control, production output mode changes, pallet ejection, player teleport) travel the same path in reverse: the dashboard sends an HTTP request to the Go server, which writes an XML command file to the modSettings folder, and the Lua mod reads and executes it on the next update tick.

## What it exports

| File | Content | Updated |
|---|---|---|
| `silos.json` | All silo and silo extension fill levels | every 10 s |
| `productions.json` | Production point inputs, outputs and chain status | every 10 s |
| `husbandries.json` | Animal counts, food/water/straw levels, health and outputs (milk, manure, …) | every 10 s |
| `goods.json` | Aggregated fill levels per fill type across all storages, with current and max prices, price trends and best selling month | every 10 s |
| `fields.json` | Per-field fruit type, growth stage, harvest readiness, projected yield, soil conditions and material need estimates | every 60 s |
| `fillTypes.json` | All fill type names, titles and HUD icon paths | once on map load |
| `fruitTypes.json` | All fruit types with growth stage definitions, harvest stages, yield per m² and seed usage per m² | once on map load |
| `animalFood.json` | Food group recipes per animal type (consumption type, fill types, production and eat weights) | once on map load |

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

Requires [Go 1.22+](https://go.dev/dl/) to be installed.

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
| Overview | KPI tiles (silo count, active productions, stall count, open alerts) and a prioritised alert list |
| Silos | Fill-level bars for every silo, silo extension, bunker silo, bale/pallet storage and manure heap; filterable by type |
| Productions | Input/output bars and chain status (running / inactive / stopped) per production point; click inputs to jump to Goods |
| Animals | Per-stall cards with occupancy, food groups (smart-weighted), water, straw, health and outputs |
| Goods | Stock per fill type across all storages, with current and max prices, price trend indicator and best selling month |
| Fields | Per-field growth bar, projected yield, soil condition bars, interactive seed calculator, and material need estimates |
| Fleet | Fleet cards with speed, fuel, damage and driver; detail panel with implements and AutoDrive / Courseplay control |
| Map | Interactive map with field outlines, hotspot pins and live vehicle positions; zoom, pan and touch support |
| Alerts | Consolidated list of all active warnings and critical states across all categories |
| Settings | Configure alert thresholds for inputs, outputs and occupancy; toggle placeable visibility per savegame |

### Editing the dashboard view

Each section (Silos, Productions, Tierställe) has an **„Ansicht bearbeiten"** button in the top-right corner of the section header.

- **Normal mode** — hidden placeables are not shown
- **Edit mode** — all placeables are shown; a green eye means visible, a grey crossed-out eye means hidden; hidden cards are dimmed
- Clicking the eye icon on any card toggles its visibility immediately and saves the setting to the server

Settings are stored per savegame (identified by `savegameId`) so hiding a silo on one map does not affect other savegames.

## Server settings storage

The server persists two kinds of settings using the platform config directory:

| Kind | API | File location |
|---|---|---|
| Global dashboard settings | `GET/PUT /api/settings` | `<configDir>/FS25_FarmMonitor/settings.json` |
| Per-savegame placeable visibility | `GET/PUT /api/savegame/{savegameId}` | `<configDir>/FS25_FarmMonitor/savegames/<hash>.json` |

Platform config directories:
- **macOS:** `~/Library/Application Support/`
- **Windows:** `%APPDATA%\`
- **Linux:** `~/.config/`

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
  "savegameId": "MapUS_2026-02-15",
  "silos": [
    {
      "uniqueId": "abc-123",
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
  "savegameId": "MapUS_2026-02-15",
  "productions": [
    {
      "uniqueId": "def-456",
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
  "savegameId": "MapUS_2026-02-15",
  "husbandries": [
    {
      "uniqueId": "ghi-789",
      "name": "Kuhstall",
      "animalType": "COW",
      "numAnimals": 24,
      "maxAnimals": 30,
      "food":      [ { "title": "Mischration", "value": 800, "capacity": 1000 } ],
      "foodTotal": { "value": 800, "capacity": 1000, "ratio": 0.8 },
      "water":     { "value": 600, "capacity": 1000 },
      "straw":     { "value": 400, "capacity": 1000 },
      "health":    92,
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
| `uniqueId` | string | Persistent placeable ID from the savegame |
| `name` | string | Placeable name set by the player |
| `animalType` | string | Animal type identifier (e.g. `COW`, `PIG`) or `"unknown"` |
| `numAnimals` | number | Current animal count |
| `maxAnimals` | number | Maximum capacity |
| `food` | array | Food trough entries with `title`, `value` and `capacity` per group |
| `foodTotal` | object\|null | Combined food level `{ value, capacity, ratio }` — `null` if stall has no food trough |
| `water` | object\|null | Water level `{ value, capacity }` — `null` if stall has no water trough |
| `straw` | object\|null | Straw bedding level `{ value, capacity }` — `null` if stall uses no straw |
| `health` | number\|null | Average animal health 0–100 — `null` if no animals are present |
| `outputs` | array | Output storage entries with `fillType`, `title`, `level` and `capacity` |

### fillTypes.json
```json
{
  "savegameId": "MapUS_2026-02-15",
  "fillTypes": [
    {
      "name": "WHEAT",
      "title": "Weizen",
      "hudOverlayFilename": "dataS/menu/hud/fillTypes/hud_fill_wheat.png"
    }
  ]
}
```

Icon paths use two formats depending on their origin:
- **Base game:** `dataS/menu/hud/fillTypes/...` — relative to the FS25 installation directory
- **Mods:** absolute path to the mod folder

### animalFood.json
```json
{
  "savegameId": "MapUS_2026-02-15",
  "animalFood": {
    "PIG": {
      "consumptionType": "PARALLEL",
      "groups": [
        { "title": "Mais Sorghum",                 "productionWeight": 0.5,  "eatWeight": 0.5,  "fillTypes": ["CORN", "SORGHUM"] },
        { "title": "Weizen Gerste Hafer",          "productionWeight": 0.25, "eatWeight": 0.25, "fillTypes": ["WHEAT", "BARLEY", "OAT"] },
        { "title": "Sojabohnen Raps Sonnenblumen", "productionWeight": 0.2,  "eatWeight": 0.2,  "fillTypes": ["SOYBEAN", "CANOLA", "SUNFLOWER"] },
        { "title": "Kartoffeln Zuckerrüben …",     "productionWeight": 0.05, "eatWeight": 0.05, "fillTypes": ["POTATO", "SUGARBEET"] }
      ]
    },
    "COW": {
      "consumptionType": "SERIAL",
      "groups": [
        { "title": "TMR",  "productionWeight": 1.0, "eatWeight": 1.0, "fillTypes": ["FORAGE_MIXING"] },
        { "title": "Heu",  "productionWeight": 0.8, "eatWeight": 1.0, "fillTypes": ["DRYGRASS_WINDROW"] },
        { "title": "Gras", "productionWeight": 0.4, "eatWeight": 1.0, "fillTypes": ["GRASS_WINDROW"] }
      ]
    }
  }
}
```

One entry per animal type.

| Field | Description |
|---|---|
| `consumptionType` | `PARALLEL` — all groups consumed simultaneously (e.g. pigs); `SERIAL` — groups are alternatives, best available is used (e.g. cows) |
| `productionWeight` | Productivity factor this group provides (0–1). For `PARALLEL`: also the share of total consumption |
| `eatWeight` | Consumption share for `PARALLEL` animals (0–1, all groups sum to 1). Used to scale alert thresholds so minor components don't trigger false alarms |
| `fillTypes` | Fill type identifiers accepted by this group |

### savegameId

All five JSON files include a `savegameId` field composed of `mapId + "_" + creationDate` (e.g. `MapUS_2026-02-15`). This uniquely identifies the active savegame and is used by the dashboard server to scope visibility settings per save.

## Notes

- Multiplayer is supported — each player runs the mod locally and sees their own farm's data. Dedicated servers (no local player) are not supported.
- The JSON files are gitignored and not part of this repository — they are generated at runtime.
- `fillTypes.json` and `animalFood.json` are written once per session since their definitions do not change while a map is loaded.
- Lua serialises empty arrays as `{}` (empty object) rather than `[]`. The dashboard handles this transparently.
- The dashboard server can be started from any directory — it automatically locates the JSON files in the modSettings folder. Use `-data` to override the path manually.

## Credits

The following mods were used as references for FS25 Lua API patterns during development. No code was copied directly — they served as documentation where no official API reference exists.

| Mod | Author | Used for |
|---|---|---|
| [FS25_RealisticLivestockRM](https://github.com/rittermod/FS25_RealisticLivestockRM) | Ritter | `AnimalFoodSystem` API, food group patterns (`eatWeight`, `consumptionType`, `SERIAL`/`PARALLEL`), husbandry food level methods |
| [FS25_TSStockCheck](https://github.com/twproductions/FS25_TSStockCheck) | twproductions | Silo, silo-extension, husbandry storage and production storage access patterns |
| [FS25_additionalFieldInfo](https://github.com/yumi-modding/FS25_additionalFieldInfo) | yumi-modding | Field state iteration via `g_farmlandManager.farmlands` |
| [FS25_BetterContracts](https://github.com/Mmtrx/FS25_BetterContracts) | Mmtrx | Practical usage of field state APIs |
| [FS25_FarmlandOverview](https://www.farming-simulator.com/mod.php?mod_id=313618) | Fetty42 | `DensityMapModifier` approach for soil state sampling (mulch, plow, roll, fert, lime, weeds, stones) and `getHarvestScaleMultiplier` yield bonus |
| [FS25_fieldCalculator](https://www.farming-simulator.com/mod.php?mod_id=323639) | [Weekend Farmers] T4xs | Inspiration for the field need calculator (seed usage via `ft.seedUsagePerSqm`, spray type application rates via `g_sprayTypeManager`) |
| [FS25_LiveMap_Companion v2](https://www.farming-simulator.com/mod.php?mod_id=340236) | Achimobil | Confirmed the `overview.dds` 50%-centre convention (`imgW * 0.50`) used for map coordinate conversion; vehicle export patterns |
| [FS25_VG_Livemap](https://www.modhub.us/farming-simulator-2025-mods/fs25-vg-livemap/) | VG-Modding | Hotspot export structure and general map-view architecture reference |
| [FS25_AutoDrive](https://github.com/Stephan-S/FS25_AutoDrive) | Stephan Schlosser | AutoDrive integration — see note below |

### AutoDrive integration

FarmMonitor integrates with [FS25_AutoDrive](https://github.com/Stephan-S/FS25_AutoDrive) by Stephan Schlosser (MIT License) to display AutoDrive status information and allow basic control from the dashboard.

**FarmMonitor does not bundle or distribute any AutoDrive files.**

If AutoDrive is installed, the FarmMonitor server reads `FS25_AutoDrive.zip` directly from the user's own FS25 mods folder at startup. Icons are extracted from that ZIP, recoloured in memory to match the dashboard's colour scheme, and cached for the current session only. Nothing is written to disk and nothing is redistributed. If AutoDrive is not installed, the integration is silently skipped.

The Lua side interacts with AutoDrive through two mechanisms:

- **`vehicle.ad` StateModule API** — reading vehicle state (`stateModule:isActive()`, `stateModule:getMode()`, marker names, remaining time, etc.) and sending control commands (`sm:setMode()`, `sm:setFirstMarker()`, `currentMode:start()`, `vehicle:stopAutoDrive()`, …). These are the methods documented in AutoDrive's `scripts/ExternalInterface.lua` and `scripts/Specialization.lua`.
- **`AutoDriveUpdateSettingsEvent`** — changing AutoDrive settings (pipe offset, follow distance, corner speed, restrict-to-field, etc.) by firing the same internal network event that AutoDrive's own in-game UI uses. This is the only correct way to change settings and have them synced to all clients; direct field writes alone are not sufficient in multiplayer. `vehicle.ad.settings[name]` is also read directly to query the current value.

The full technical breakdown of both command paths (singleplayer, listen-server, dedicated server) is documented in [`ai/api_autodrive_commands.md`](ai/api_autodrive_commands.md).

## Third-party libraries

| Library | License | Used for |
|---|---|---|
| [Tabler Icons](https://tabler.io/icons) | [MIT](https://github.com/tabler/tabler-icons/blob/main/LICENSE) © 2020-2026 Paweł Kuna | Icons in the dashboard UI |
| [game-icons.net](https://game-icons.net) — "Thrust Bend" by [Delapouite](https://delapouite.com) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) | Vehicle type icon |
| [game-icons.net](https://game-icons.net) — "Gas Pump" by [Delapouite](https://delapouite.com) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) | Fuel icon |
| [game-icons.net](https://game-icons.net) — "Auto Repair" by [Lorc](https://lorcblog.blogspot.com) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) | Vehicle repair icon |
| [game-icons.net](https://game-icons.net) — "Cow", "Sheep", "Chicken", "Horse Head", "Goose", "Rabbit" by [Delapouite](https://delapouite.com) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) | Animal icons in husbandry view and map hotspot pins |
| [game-icons.net](https://game-icons.net) — "Pig" by [Skoll](https://game-icons.net/about.html#authors) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) | Pig icon in husbandry view and map hotspot pins |
| [game-icons.net](https://game-icons.net) — "Sell Card" by [Delapouite](https://delapouite.com) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) | Selling station icon on map |
| [polylabel](https://github.com/mapbox/polylabel) by Mapbox | [ISC](https://github.com/mapbox/polylabel/blob/master/LICENSE) © 2016 Mapbox | Pole of inaccessibility for field number placement on map |

Full license texts are listed in [`THIRD_PARTY_NOTICES`](THIRD_PARTY_NOTICES).
