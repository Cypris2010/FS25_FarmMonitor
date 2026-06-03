# FarmMonitor — Performance-Optimierungen

Analysiert auf Branch `0.4.10`. Stand: 2026-06-03.

## Bereits umgesetzt (0.4.10-dev17)

### Soil-Layer Scan
- **Problem:** Bodendaten-Layer (Pflug, Dünger, Kalk, Unkraut, Steine, Mulch, Walze) wurden bei 512×512 Auflösung abgetastet — 262.144 Zellen pro Layer, je mehrere `DensityMapModifier.executeGet`-GPU-Aufrufe → spürbare CPU-Last
- **Fix:** Auflösung 512×512 → 128×128 (16× weniger Zellen), `rowsPerTick` 4 → 2 (halbierte Tick-Last)
- **Ergebnis:** ~32× weniger GPU-Calls pro Tick, keine sichtbare Qualitätseinbuße (Dashboard rendert Overlays sowieso unscharf)
- **Dateien:** `FarmMonitor.lua` — `initSoilState()`, Variablen `res` und `rowsPerTick`

---

## Offen — priorisiert nach Impact

### 1. Fahrzeug-Export Interval erhöhen
- **Aktuell:** `vehicleInterval = 2000` ms → iteriert alle Vehicles, FillUnits, Paletten, Mounts 5× pro 10s-Zyklus
- **Vorschlag:** 3000–4000 ms
- **Impact:** mittel — halbierte Iterationslast über den teuersten Export
- **Aufwand:** trivial — eine Zeile
- **Datei:** `FarmMonitor.lua` Zeile ~12

### 2. Dirty-Check — nur schreiben wenn Daten sich geändert haben
- **Aktuell:** Alle Exports schreiben JSON + Datei bei jedem Intervall, unabhängig von Änderungen
- **Vorschlag:** Letzten Zustand cachen, nur bei Änderung schreiben
- **Besonders effektiv für:**
  - `silos.json` — ändert sich nur bei aktiver Be-/Entladung
  - `goods.json` — gleicher Rhythmus wie Silos
  - `fields.json` (60s) — Wachstum ändert sich nur alle paar Spielminuten
  - `weather.json` (30s) — oft stundenlang stabil
- **Nicht sinnvoll für:** `vehicles.json` — Positionen ändern sich fast immer
- **Implementierungsoptionen:**
  - *String-Hash:* JSON-String bauen, hashen, mit letztem Hash vergleichen → einfach, spart nur Disk-Write
  - *Shallow-Compare:* Nur Füllstände als Zahlen vergleichen → effizienter, spart auch Serialisierung
- **Impact:** mittel | **Aufwand:** mittel

### 3. Export-Staggering — Lastspitzen verteilen
- **Aktuell:** `collectAndSave()` schreibt Silos + Productions + Husbandries + Goods alles im selben Tick alle 10s
- **Vorschlag:** Separate Intervalle je ~2.5s versetzt:
  - Silos @ 0s, Productions @ 2.5s, Husbandries @ 5s, Goods @ 7.5s
- **Impact:** klein | **Aufwand:** mittel

### 4. Field Sampler cachen
- **Aktuell:** `buildFieldSoilSamplers()` erstellt alle `DensityMapModifier`-Objekte jede 60s neu
- **Vorschlag:** Sampler einmal aufbauen und wiederverwenden — MapIDs sind zwischen Frames stabil, nur bei Savegame-Wechsel neu bauen
- **Datei:** `FarmMonitor.lua`, Funktion `buildFieldSoilSamplers()` ~Zeile 2288
- **Impact:** klein | **Aufwand:** einfach

### 5. Command-Interval erhöhen
- **Aktuell:** `commandInterval = 1000` ms → `fileExists()` 60× pro Minute
- **Vorschlag:** 2000–3000 ms — Commands sind user-getriggert, keine Echtzeit-Reaktion nötig
- **Datei:** `FarmMonitor.lua` Zeile ~16
- **Impact:** minimal | **Aufwand:** trivial

---

## Export-Zyklen Übersicht

| Export | Interval | Funktion | Dateien |
|---|---|---|---|
| Haupt-Export | 10 s | `collectAndSave()` | silos, productions, husbandries, goods |
| Fahrzeuge | 2 s | `collectAndSaveVehicles()` | vehicles.json |
| Fahrzeug-Meta | 10 s | `collectAndSaveVehicleMeta()` | vehicleMeta.json |
| Felder | 60 s | `collectAndSaveFields()` | fields.json |
| Wetter | 30 s | `collectAndSaveWeather()` | weather.json |
| Soil-Layer | kontinuierlich (2 rows/tick) | `stepSoilExport()` | layer_*.json (7 Layer) |
| IPC Commands | 1 s | `processCommands()` | commands.xml → commands_ack.json |
| AutoDrive Markers | 60 s | `exportAutoDriveMarkers()` | autoDriveMarkers.json |

---

## SQLite in Lua — nicht möglich

Die FS25 Lua-Sandbox gibt ausschließlich `io.open`, Giants XML-APIs und Game-APIs frei. Externe C-Extensions wie `lsqlite3` sind nicht verfügbar — kein einziger öffentlicher FS25-Mod nutzt SQLite in Lua. Für historische Daten und Zeitreihen ist die **Go-Server-Seite** der einzig sinnvolle Ort (→ Roadmap v0.8.0).
