# FS25 AutoDrive — API Referenz für FarmMonitor

Quelle: FS25_AutoDrive 3.0.x by Stephan-S  
Relevante Dateien: `scripts/Specialization.lua`, `scripts/ExternalInterface.lua`, `scripts/Modes/*.lua`

## Wichtig: Mod-Sandboxing

FS25 führt jeden Mod in einem eigenen Lua-Sandbox aus. `ADGraphManager` und `AutoDrive` sind aus FarmMonitor heraus **nicht zugänglich** (immer `nil`). Nur Methoden, die auf dem `vehicle.ad`-Objekt direkt aufrufbar sind, können genutzt werden.

## Fahrzeug-Zugriff

```lua
-- Prüfen ob Fahrzeug AutoDrive hat:
if vehicle.ad ~= nil and vehicle.ad.stateModule ~= nil then
    local sm = vehicle.ad.stateModule
end

-- WICHTIG: Fahrzeug per rootNode suchen, NICHT getVehicleByUniqueId()
-- vehicles.json exportiert vehicle.rootNode als "id" (tostring)
-- getVehicleByUniqueId() erwartet eine andere interne ID
local function findVehicleByNodeId(nodeId)
    for _, v in pairs(g_currentMission.vehicleSystem.vehicles) do
        if v ~= nil and v.rootNode ~= nil and tostring(v.rootNode) == nodeId then
            return v
        end
    end
    return nil
end
```

## StateModule API (`vehicle.ad.stateModule`)

```lua
local sm = vehicle.ad.stateModule

-- Status lesen:
sm:isActive()             -- bool: fährt AD gerade?
sm:getMode()              -- int: aktueller Modus (1–5)
sm:getName()              -- string: Fahrername
sm:getFirstMarkerName()   -- string: Name des 1. Ziels (oder nil)
sm.firstMarker            -- table: aktuelles Ziel-Objekt (direkt, kein Getter)
sm.secondMarker           -- table: 2. Ziel-Objekt (direkt)
sm.remainingDriveTime     -- number: verbleibende Fahrtzeit in ms (oder nil)

-- Konfigurieren:
sm:setMode(modeNum)            -- Modus setzen (1–5)
sm:setFirstMarker(markerIndex) -- Ziel 1 setzen (markerIndex aus autoDriveMarkers.json)
sm:setSecondMarker(markerIndex)-- Ziel 2 setzen
sm:setFillType(fillTypeIndex)  -- Fülltyp setzen (g_fillTypeManager:getFillTypeByName)
sm:getCurrentMode()            -- Mode-Objekt zurückgeben (hat :start(), :reset(), :stop())

-- Erster/Zweiter Marker-ID (Waypoint-ID, nicht markerIndex):
sm:getFirstMarkerId()     -- int: interne Waypoint-ID (nicht markerIndex!)
sm:getSecondMarkerId()
sm:getFirstMarker()       -- table: Marker-Objekt mit .id (waypoint), .name, .group
```

## AutoDrive Modi

| ID | Name | Marker 1 | Marker 2 | FillType |
|---|---|---|---|---|
| 1 | DriveTO | Ziel | — | — |
| 2 | PickupAndDeliver | Abholpunkt | Lieferpunkt | ✓ |
| 3 | DeliverTo | Lieferpunkt | — | ✓ |
| 4 | Load | Ladepunkt | — | ✓ |
| 5 | CombineUnloader | Wartepunkt | Entladeort | — |

Modus 6 (BGA) ist vollautomatisch und wird in FarmMonitor nicht unterstützt.

## Aktives Fahrziel erkennen (`adCurrentTarget`)

Für die Hervorhebung des gerade angefahrenen Ziels muss `modeObj.state` ausgewertet werden.
`modeObj = sm:getCurrentMode()` — zugänglich aus FarmMonitor-Sandbox.

### Modus 2 — PickupAndDeliver
States sind **Integer** (`PickupAndDeliverMode.STATE_* = 1/2/3/...`):
```lua
-- STATE_PICKUP = 2, STATE_PICKUP_FROM_NEXT_TARGET = 8 → Ziel 1
-- STATE_DELIVER = 3, STATE_DELIVER_TO_NEXT_TARGET = 7 → Ziel 2
if s == 2 or s == 8 then adCurrentTarget = 1
elseif s == 3 or s == 7 then adCurrentTarget = 2
end
```

### Modus 5 — CombineUnloader
States sind **Lua-Tabellen** (`CombineUnloaderMode.STATE_* = {}`), **keine Integer**.
Vergleich funktioniert via Klassen-Metatable: `modeObj.state == modeObj.STATE_DRIVE_TO_UNLOAD`
(identisch zu `self.state == self.STATE_DRIVE_TO_UNLOAD` im AutoDrive-Code selbst).

```lua
-- Marker 1 (firstMarker)  = Wartepunkt (Warteposition nahe Feld)
-- Marker 2 (secondMarker) = Entladeort (Ablieferungsstation)
-- STATE_DRIVE_TO_UNLOAD       → fährt zu Entladeort  → adCurrentTarget = 2
-- STATE_DRIVE_TO_START        → fährt zu Wartepunkt  → adCurrentTarget = 1
-- STATE_WAIT_TO_BE_CALLED     → wartet am Wartepunkt → adCurrentTarget = 1
local modeObj = sm:getCurrentMode()
if modeObj and modeObj.state then
    if modeObj.state == modeObj.STATE_DRIVE_TO_UNLOAD then
        adCurrentTarget = 2   -- Entladeort = Marker 2 (secondMarker)
    elseif modeObj.state == modeObj.STATE_DRIVE_TO_START
        or modeObj.state == modeObj.STATE_WAIT_TO_BE_CALLED then
        adCurrentTarget = 1   -- Wartepunkt = Marker 1 (firstMarker)
    end
end
```

### Modi 1 / 3 / 4 (ein Ziel)
Kein State-Check nötig — `adCurrentTarget = 1` als Fallback wenn AD aktiv.

### Wichtig: `sm:getFirstMarkerName()` ist statisch
Gibt immer den **konfigurierten** Marker 1 zurück, nicht das aktuell angefahrene Ziel.
Nicht geeignet für Ziel-Erkennung während der Fahrt.

## Start / Stop

```lua
-- RICHTIG: Mode:start() aufrufen — ruft startAutoDrive() intern selbst auf
-- FALSCH: startAutoDrive() zuerst aufrufen, dann mode:start()
-- (Reihenfolge bricht interne Initialisierung)

local sm = vehicle.ad.stateModule
local currentMode = sm:getCurrentMode()

if not sm:isActive() then
    currentMode:start()   -- startet AD + Navigation in einem Schritt
else
    vehicle:stopAutoDrive()   -- erst stoppen
    currentMode:start()       -- dann neu starten
end

-- Stoppen:
vehicle:stopAutoDrive()   -- setzt isActive=false, reset aller Module
```

### Warum nicht `vehicle:startAutoDrive()` direkt?

`vehicle:startAutoDrive()` (in Specialization.lua) setzt `isActive=true`, weist einen Helfer zu und broadcastet `AutoDriveStartStopEvent`. Es startet aber **keine Navigation**. Jeder Mode's `:start()` ruft `startAutoDrive()` intern selbst auf (wenn `not isActive()`). Deshalb: nur `currentMode:start()` aufrufen.

## Marker-Export (ohne ADGraphManager-Zugriff)

Da `ADGraphManager` aus FarmMonitor nicht zugänglich ist, wird ein Iterator-Trick verwendet:
`sm:setFirstMarker(id)` läuft im AutoDrive-Sandbox-Kontext und hat Zugriff auf den internen Graphen.

```lua
local savedMarker = sm.firstMarker   -- direkt lesen (kein Getter → kein dirty flag)

for id = 1, 2000 do
    sm:setFirstMarker(id)             -- setzt internen Marker im AD-Kontext
    local m = sm.firstMarker          -- direkt lesen
    if m ~= nil and m.isADDebug ~= true then
        -- m.markerIndex = ID (1-basiert, sequenziell)
        -- m.name = Anzeigename
        -- m.group = Gruppe (oder nil → "All")
        -- m.id = interne Waypoint-ID (für Pfadberechnung)
    end
end

-- Originalmarker wiederherstellen (direkt aufs Feld, kein setFirstMarker → kein dirty flag)
sm.firstMarker = savedMarker
```

### Dirty Flag Batching
FS25 batched dirty flags: 2000 schnelle `setFirstMarker()`-Aufrufe erzeugen nur **1 Netzwerk-Sync** (finaler Zustand). Safe für Multiplayer.

### Inkrementeller Export (alle 60 Sekunden)
- Erster Lauf: Vollscan ab ID 1
- Folgeläufe: Schnelltest mit ID `lastMaxId+1`; nur re-exportieren wenn neue Marker vorhanden
- Cache in `FarmMonitor.autoDriveMarkerCache` (Lua-Tabelle, kein JSON-Read)

## Marker-Objekt Felder

```lua
m.markerIndex   -- int: ID die setFirstMarker() akzeptiert (1-basiert)
m.name          -- string: Anzeigename
m.group         -- string: Gruppenname (oder nil)
m.id            -- int: interne Waypoint-ID im AD-Graphen
m.isADDebug     -- bool: Debug-Marker → überspringen
```

## IPC-Befehlsformat

Commands werden per `commands.xml` übertragen (File-IPC-Pattern, siehe `ai/file_ipc_commands.md`).

```xml
<command cmd="autodrive.configure" uniqueId="888436" mode="1" marker1="22" marker2="" fillType=""/>
<command cmd="autodrive.startStop"  uniqueId="888436" mode="start"/>
<command cmd="autodrive.startStop"  uniqueId="888436" mode="stop"/>
```

- `uniqueId` = `tostring(vehicle.rootNode)` (aus `vehicles.json` → `id`-Feld)
- `marker1`/`marker2` = `m.markerIndex` aus `autoDriveMarkers.json`
- `fillType` = Fülltyp-Name (String, z.B. `"WHEAT"`)

## Dashboard-Besonderheiten

### onclick-Attribut: Kein JSON.stringify für IDs

```js
// FALSCH — JSON.stringify("888436") erzeugt "888436" mit Anführungszeichen
//          → bricht HTML-Attribut: onclick="_adStartStop("888436", 'start')"
onclick="_adStartStop(${JSON.stringify(id)}, 'start')"

// RICHTIG — einfache Anführungszeichen
onclick="_adStartStop('${id}', 'start')"
```

### ID-Vergleich: String vs Number

`vehicles.json` exportiert `id` als **Zahl** (rootNode-Handle).  
`openVehicleDetail()` übergibt ID als **String** (onclick-Attribut).  
Bei `Array.find()` strict equality (`===`) schlägt der Vergleich fehl:

```js
// FALSCH:
stateList.find(s => s.id === id)           // 733657 === '733657' → false

// RICHTIG:
stateList.find(s => String(s.id) === String(id))
```

Bei Object-Key-Zugriff (`stateById[id]`) funktioniert es automatisch da JS Keys immer Strings sind.

## JSON-Export (`autoDriveMarkers.json`)

```json
{
  "savegameId": "...",
  "markers": [
    { "id": 22, "name": "Wald 107", "group": "Wälder" }
  ],
  "groups": ["Alle", "Wälder", "Höfe"]
}
```

- `id` = `m.markerIndex` (das was `setFirstMarker()` akzeptiert)
- Export alle 60 Sekunden, inkrementell
- Wird in `Server/server.go` als Slow-File überwacht und per SSE gepusht
