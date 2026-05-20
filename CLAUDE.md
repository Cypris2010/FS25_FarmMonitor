# FS25 FarmMonitor

A Farming Simulator 25 mod that exports live farm data to JSON and serves a local web dashboard for real-time monitoring.

## AI context references

@ROADMAP.md
@ai/api_ts_stockcheck.md
@ai/api_field_states.md
@ai/api_growth_stages.md
@ai/multiplayer_analysis.md

## Architecture

Two independent components:

| Component | Path | Language | Purpose |
|---|---|---|---|
| Lua mod | `FS25_FarmMonitor/` | Lua | Runs inside FS25, writes JSON every 10 s |
| Dashboard server | `Server/` | Go | Serves the SPA dashboard, watches JSON files |

### Data flow

```
FS25 game → FarmMonitor.lua → JSON files → Go server (SSE) → Browser dashboard
```

The Go binary embeds `dashboard.html` at compile time (`//go:embed dashboard.html`). No separate frontend build step exists.

## Key files

- `FS25_FarmMonitor/FarmMonitor.lua` — entire mod logic (data collection + custom JSON encoder)
- `FS25_FarmMonitor/modDesc.xml` — mod metadata, version string
- `Server/server.go` — Go HTTP server (SSE broker, file watcher, `/api/data`, `/api/events`)
- `Server/dashboard.html` — single-file SPA (embedded into the binary)
- `scripts/test_deploy.sh` — build + local deploy script (macOS only)

## Development

### Build & deploy locally (macOS)

```bash
./scripts/test_deploy.sh
```

This builds the Go binary, moves it to the project root as `farmmonitor`, and zips the mod folder into the FS25 mods directory.

### Build server only

```bash
cd Server
go build -o farmmonitor        # macOS / Linux
go build -o farmmonitor.exe    # Windows
./farmmonitor
```

### Run dashboard

```bash
./farmmonitor                          # auto-detects modSettings path
./farmmonitor -host 0.0.0.0 -port 9000  # LAN access
./farmmonitor -data /custom/path        # manual data dir
```

Dashboard: **http://localhost:8080**

## JSON output files

Written to `~/Library/Application Support/FarmingSimulator2025/modSettings/FS25_FarmMonitor/` on macOS.

| File | Updated | Notes |
|---|---|---|
| `silos.json` | every 10 s | Silo and silo-extension fill levels |
| `productions.json` | every 10 s | Production point inputs, outputs, chain status |
| `husbandries.json` | every 10 s | Animal counts, food/water/straw, health, outputs |
| `fillTypes.json` | once per session | All fill type names and HUD icon paths |
| `animalFood.json` | once per session | Food group recipes per animal type |

These files are gitignored — they are generated at runtime only.

## Constraints

- **Singleplayer only** (`multiplayer supported="false"` in modDesc.xml)
- Current version: **0.2.4** (set in `modDesc.xml` and git tags)
- Lua serialises empty arrays as `{}` — the dashboard handles this transparently
- The Go server polls JSON files every 2 s for changes and pushes SSE updates to all connected clients

## Release

Releases are published to GitHub. The workflow triggers on version tags (without `v` prefix). Pre-built binaries are provided for macOS Apple Silicon, macOS Intel, and Windows.

## FS25 Lua reference

When anything about the FS25 Lua API is unclear (game globals, specs, callbacks, modDesc structure, etc.), research it in:

**https://github.com/Dukefarming/FS25-lua-scripting**

Check there before guessing API behaviour or field names.

## Mod installation (for testing)

1. Copy `FS25_FarmMonitor/` (or the ZIP) into `~/Library/Application Support/FarmingSimulator2025/mods/`
2. Enable mod in FS25 mod manager
3. Load a savegame — JSON files appear within the first update cycle (~10 s)
