# FS25 Courseplay — API Referenz für FarmMonitor

Quellen:
- https://github.com/Courseplay/Courseplay_FS25
- https://courseplay.github.io/CourseplayHelpFS25/

## Wichtiger Unterschied zu AutoDrive

Courseplay registriert **keine `vehicle.cp`-Tabelle** — stattdessen werden Funktionen direkt
auf dem Vehicle-Objekt via `SpecializationUtil.registerFunction` registriert.

**Kein globales `hasCourseplay`-Flag** (anders als `hasAutoDrive`): Da der interne Mod-Name
nicht garantiert stabil ist, wird CP rein per-vehicle erkannt via `vehicle.getIsCpActive ~= nil`.
Das ist sicherer und braucht keine `g_modIsLoaded`-Abhängigkeit.

## Erkennung (per Fahrzeug)

```lua
-- Primärcheck — Funktion auf vehicle registriert?
if vehicle.getIsCpActive ~= nil then
    local active = vehicle:getIsCpActive()  -- bool
end
```

## Implementierter Export-Block (FarmMonitor.lua)

```lua
local cpActive               = nil
local cpJobType              = nil
local cpInfoText             = nil
local cpWaypointCurrent      = nil
local cpWaypointTotal        = nil
local cpRemainingTime        = nil
local cpNumBalesLeft         = nil
local cpWaitingForUnload     = nil
local cpHarvesterManeuvering = nil
if vehicle.getIsCpActive ~= nil then
    pcall(function()
        if not vehicle:getIsCpActive() then return end
        cpActive = true
        -- Job-Typ via dedizierte Methoden (cross-sandbox sicher)
        if vehicle:getIsCpFieldWorkActive() then
            cpJobType = "fieldWork"
        elseif vehicle:getIsCpCombineUnloaderActive() then
            cpJobType = "combineUnloader"
        else
            -- Fallback für BaleFinder, BunkerSilo, SiloLoader
            local j = vehicle.getJob and vehicle:getJob()
            if j and j.name then cpJobType = j.name end
        end
        -- CpStatus (MP-sicher, synced)
        if vehicle.getCpStatus then
            local st = vehicle:getCpStatus()
            if st then
                if st.currentWaypointIx and st.currentWaypointIx > 0 then
                    cpWaypointCurrent = st.currentWaypointIx
                end
                if st.numberOfWaypoints and st.numberOfWaypoints > 0 then
                    cpWaypointTotal = st.numberOfWaypoints
                end
                if st.remainingTimeText and st.remainingTimeText ~= "" then
                    cpRemainingTime = st.remainingTimeText
                end
                if st.numBalesLeftOver and st.numBalesLeftOver > 0 then
                    cpNumBalesLeft = st.numBalesLeftOver
                end
            end
        end
        -- Höchstpriorisierter aktiver Info-Text (Stopp-Grund)
        if vehicle.getCpActiveInfoTexts then
            local texts = vehicle:getCpActiveInfoTexts()
            for _, t in pairs(texts) do
                if t and t.name then
                    cpInfoText = t.name  -- z.B. "IS_STUCK", "NEEDS_UNLOADING"
                    break
                end
            end
        end
        -- Mähdrescher-spezifische Flags
        if vehicle.getIsCpHarvesterWaitingForUnload then
            if vehicle:getIsCpHarvesterWaitingForUnload() then
                cpWaitingForUnload = true
            end
            if vehicle:getIsCpHarvesterManeuvering() then
                cpHarvesterManeuvering = true
            end
        end
    end)
end
```

## Kern-API (Übersicht)

```lua
-- Allgemeiner Status
vehicle:getIsCpActive()                        -- bool: CP-Job läuft
vehicle:getIsCpDriveToFieldWorkActive()        -- bool: fährt zum Startpunkt

-- Job-Typen (dedizierte Methoden, cross-sandbox sicher)
vehicle:getIsCpFieldWorkActive()               -- → cpJobType = "fieldWork"
vehicle:getIsCpCombineUnloaderActive()         -- → cpJobType = "combineUnloader"

-- Weitere Job-Typen (nur via job.name fallback)
-- "baleFinder", "bunkerSilo", "siloLoader"

-- Mähdrescher-spezifisch
vehicle:getIsCpHarvesterWaitingForUnload()     -- bool
vehicle:getIsCpHarvesterWaitingForUnloadInPocket()
vehicle:getIsCpHarvesterWaitingForUnloadAfterPulledBack()
vehicle:getIsCpHarvesterManeuvering()          -- bool: Wendemanöver / Pocket / PullBack

-- Kurs-Info
vehicle:hasCpCourse()
local course = vehicle:getFieldWorkCourse()
course:getNumberOfWaypoints()
course:getCurrentWaypointIx()
course:getProgress()      -- fraction, currentIx, isDone (3 Werte)
course:getLength()        -- Gesamtlänge in Metern

-- Status-Objekt (MP-sicher)
local status = vehicle:getCpStatus()
status.currentWaypointIx           -- aktueller Wegpunkt (Feldarbeit)
status.numberOfWaypoints           -- Gesamtzahl
status.remainingTimeText           -- z.B. "12 min"
status.numBalesLeftOver            -- verbleibende Ballen (Ballensuche)
status.compactionPercentage        -- 0–100 (Bunker-Silo)
status.fillLevelLeftOver           -- Liter verbleibend (Silo-Lader)
status.fillLevelPercentageLeftOver

-- Drive Strategy State (nur SP/Server)
local strategy = vehicle:getCpDriveStrategy()
strategy:getStateAsString()    -- State-Name als String
strategy:isWorking()
strategy:isDone()

-- Info-Texte (Stopp-Gründe, MP-synced)
local texts = vehicle:getCpActiveInfoTexts()
-- {id → CpInfoTextElement}, jedes Element mit .name (String)
```

## Job-Typen (vehicles.json → cpJobType)

| Wert | Bedeutung | Erkennung |
|---|---|---|
| `"fieldWork"` | Feldarbeit (Kurs abfahren) | `getIsCpFieldWorkActive()` |
| `"combineUnloader"` | Mähdrescher-Entlader | `getIsCpCombineUnloaderActive()` |
| `"baleFinder"` | Ballensuche und -sammlung | `job.name` fallback |
| `"bunkerSilo"` | Bunker-Silo verdichten | `job.name` fallback |
| `"siloLoader"` | Silo laden (Schaufel) | `job.name` fallback |

## InfoTextManager-Konstanten (als String in `cpInfoText`)

### Fehler → `badge-cp-alert`
| Name | Bedeutung |
|---|---|
| `IS_STUCK` | Fahrzeug feststeckend |
| `ERROR_STOPPED` | Generischer CP-Fehler |
| `ERROR_NO_PATH_FOUND` | Pathfinder gescheitert |
| `IS_COMPLETELY_BROKEN` | Braucht Reparatur |
| `FUEL_IS_EMPTY` | Tank leer |
| `NEEDS_FILLING` | Behälter leer |
| `ERROR_CUTTER_NOT_SUPPORTED` | Schneidwerk nicht unterstützt |
| `ERROR_WRONG_SEASON` | Falsche Jahreszeit |
| `ERROR_WRONG_MISSION_FRUIT_TYPE` | Falsche Frucht für Mission |
| `ERROR_PALLETS_ARE_FULL` | Paletten voll |
| `ERROR_PALLETS_ARE_EMPTY` | Keine Paletten |
| `ERROR_TOO_FAR_FROM_FIELD` | Zu weit vom Feld |
| `ERROR_GROUND_UNLOAD_NOT_SUPPORTED` | Bodenentladung nicht möglich |

### Warnung → `badge-cp-warn`
| Name | Bedeutung |
|---|---|
| `NEEDS_UNLOADING` | Voll, wartet auf Entladung |
| `FUEL_IS_LOW` | Kraftstoff niedrig |
| `BLOCKED_BY_OBJECT` | Durch Objekt blockiert |
| `OUT_OF_MONEY` | Kein Geld |
| `WRONG_BALE_WRAP_TYPE` | Falscher Ballenwickeltyp |
| `WAITING_FOR_RAIN_TO_FINISH` | Wartet auf Regenende |
| `WAITING_FOR_SNOW_TO_CLEAR` | Wartet bis Schnee weg |

### Info (kein eigenes Badge — normal amber)
| Name | Bedeutung |
|---|---|
| `WAITING_FOR_UNLOADER` | Mähdrescher wartet auf Entlader |
| `DRIVING_TO_COMBINE` | Entlader fährt zum Mähdrescher |
| `DRIVING_TO_SELF_UNLOAD` | Fährt zur Selbstentladung |
| `WORK_FINISHED` | Arbeit abgeschlossen |

## Drive Strategy States

### Feldarbeit (`AIDriveStrategyFieldWorkCourse`)
```
INITIAL, WORKING, PREPARING, WAITING_FOR_LOWER, WAITING_FOR_LOWER_DELAYED,
WAITING_FOR_STOP, WAITING_FOR_WEATHER, TURNING, TEMPORARY, RETURNING_TO_START,
DRIVING_TO_WORK_START_WAYPOINT, WAITING_FOR_PATHFINDER,
WAITING_FOR_FIELD_BOUNDARY_DETECTION
```

### Ballensuche (`AIDriveStrategyFindBales`)
```
INITIAL, SEARCHING_FOR_NEXT_BALE, WAITING_FOR_PATHFINDER, DRIVING_TO_NEXT_BALE,
APPROACHING_BALE, WORKING_ON_BALE, REVERSING_AFTER_PATHFINDER_FAILURE,
REVERSING_DUE_TO_OBSTACLE_AHEAD, DRIVING_TO_START_MARKER,
WAITING_FOR_IMPLEMENTS_TO_FOLD, WAITING_FOR_FIELD_BOUNDARY_DETECTION
```

### Bunker-Silo (`AIDriveStrategyBunkerSilo`)
```
INITIAL, DRIVING_TO_SILO, DRIVING_TO_PARK_POSITION, WAITING_AT_PARK_POSITION,
WAITING_FOR_PREPARING, DRIVING_INTO_SILO, DRIVING_OUT_OF_SILO, DRIVING_TURN,
DRIVING_TEMPORARY_OUT_OF_SILO
```

### Silo-Lader (`AIDriveStrategySiloLoader`)
```
WAITING_FOR_PREPARING, DRIVING_ALIGNMENT_COURSE, WORKING, FINISHED
```

### Mähdrescher-Entlader (`AIDriveStrategyUnloadCombine`)
```
IDLE, WAITING_FOR_PATHFINDER, MOVING_BACK, MOVING_BACK_WITH_TRAILER_FULL,
DRIVING_TO_COMBINE, DRIVING_TO_MOVING_COMBINE, UNLOADING_MOVING_COMBINE,
UNLOADING_STOPPED_COMBINE, DRIVING_TO_SELF_UNLOAD, WAITING_FOR_AUGER_PIPE_TO_OPEN,
UNLOADING_AUGER_WAGON, MOVING_TO_NEXT_FILL_NODE, MOVING_AWAY_FROM_UNLOAD_TRAILER,
DRIVE_TO_FIELD_UNLOAD_POSITION, UNLOADING_ON_THE_FIELD, DRIVE_TO_FIELD_UNLOAD_PARK_POSITION
```

### Mähdrescher (Ernte-States)
```
UNLOADING_ON_FIELD, STOPPING_FOR_UNLOAD, WAITING_FOR_UNLOAD_ON_FIELD,
PULLING_BACK_FOR_UNLOAD, WAITING_FOR_UNLOAD_AFTER_PULLED_BACK,
REVERSING_TO_MAKE_A_POCKET, MAKING_POCKET, WAITING_FOR_UNLOAD_IN_POCKET,
WAITING_FOR_UNLOADER_TO_LEAVE, RETURNING_FROM_POCKET,
DRIVING_TO_SELF_UNLOAD, SELF_UNLOADING, RETURNING_FROM_SELF_UNLOAD
```

## Dashboard-Implementierung

### Badge-Farben: Orange/Amber-Familie

```css
.fleet-badge.badge-cp       { color: #ffb74d; }  /* amber — Normalbetrieb */
.fleet-badge.badge-cp-alert { color: #f48fb1; }  /* coral — Fehler/Stuck (wie AD-Alert) */
.fleet-badge.badge-cp-warn  { color: #ffe082; }  /* gelb  — Voll/Tankt/Blockiert */
```

Absichtlich von AutoDrive Cyan (`#4dd0e1`) getrennt. Kein `.badge-cp-work` — der Job-Typ-Text
gibt genug Kontext, eine vierte Stufe wäre semantisch schwach.

### Speed-Block-Färbung

```css
.fleet-speed-block.cp-active { background: rgba(255,183,77,.12); }
.fleet-speed-block.cp-active .fleet-speed-val  { color: #ffb74d; }
.fleet-speed-block.cp-active .fleet-speed-unit { color: #ffb74d; opacity: 0.8; }
/* identisch für .vd-header-speed.cp-active im Detail-View */
```

### JS-Konstanten (dashboard.html)

```js
const CP_ALERT_TEXTS = new Set([
  'IS_STUCK', 'ERROR_STOPPED', 'ERROR_NO_PATH_FOUND', 'IS_COMPLETELY_BROKEN',
  'FUEL_IS_EMPTY', 'NEEDS_FILLING', 'ERROR_CUTTER_NOT_SUPPORTED',
  'ERROR_WRONG_SEASON', 'ERROR_WRONG_MISSION_FRUIT_TYPE',
  'ERROR_PALLETS_ARE_FULL', 'ERROR_PALLETS_ARE_EMPTY',
  'ERROR_TOO_FAR_FROM_FIELD', 'ERROR_GROUND_UNLOAD_NOT_SUPPORTED'
]);
const CP_WARN_TEXTS = new Set([
  'NEEDS_UNLOADING', 'FUEL_IS_LOW', 'BLOCKED_BY_OBJECT', 'OUT_OF_MONEY',
  'WRONG_BALE_WRAP_TYPE', 'WAITING_FOR_RAIN_TO_FINISH', 'WAITING_FOR_SNOW_TO_CLEAR'
]);
const CP_JOB_LABELS = {
  fieldWork: 'CP Feldarbeit', combineUnloader: 'CP Entlader',
  baleFinder: 'CP Ballen', bunkerSilo: 'CP Silo', siloLoader: 'CP Laden'
};
```

### Badge-Hierarchie (`_cpStatusBadge`)

Priorität von oben nach unten — erster Match gewinnt:

| Priorität | Badge-Text | Klasse | Bedingung |
|---|---|---|---|
| 1 | CP Feststeckend / CP Kein Pfad / CP Tank leer / CP Reparatur / CP Fehler | `badge-cp-alert` | `cpInfoText` ∈ `CP_ALERT_TEXTS` |
| 2 | CP Voll / CP Tankt / CP Blockiert / CP Wetter / CP Wartet | `badge-cp-warn` | `cpInfoText` ∈ `CP_WARN_TEXTS` |
| 3 | CP Wartet auf Entlader | `badge-cp-warn` | `cpWaitingForUnload` |
| 4 | CP Feldarbeit / CP Entlader / CP Ballen / CP Silo / CP Laden | `badge-cp` | `cpJobType` |
| 5 | Courseplay | `badge-cp` | Fallback |

### Priorität statusLabel / statusBadge (Fleet- und Detail-View)

```
adActive  →  cpActive  →  motorRunning (isAIActive / isEntered / Motor läuft)  →  Geparkt
```

AD hat immer Vorrang vor CP. Beide können nie gleichzeitig aktiv sein.

### CP-Banner im Detail-View (`vd-cp-banner`)

HTML-Element nach `vd-ad-banner`:
```html
<div class="vd-cp-banner" id="vd-cp-banner"></div>
```

Inhalt wenn `rootState.cpActive === true`:
- **Zeile 1:** Job-Label + optional `· Manövriert` / `· Wartet auf Entlader`
- **Zeile 2 (wenn vorhanden):** Wegpunkt `X / Y`, verbleibende Zeit, Ballen-Anzahl, Info-Text-Name

### Fleet-Footer

Wenn CP aktiv: `CP Feldarbeit · 42/187 · 12 min` in der Footer-Zeile der Karte.
Verwendet `CP_JOB_LABELS[state.cpJobType]`, Wegpunkt und `cpRemainingTime`.

## JSON-Felder in `vehicles.json`

| Feld | Typ | Beschreibung |
|---|---|---|
| `cpActive` | bool | CP-Job läuft |
| `cpJobType` | string | Job-Typ (s.o.) oder nil |
| `cpInfoText` | string | Aktiver Stopp-Grund (InfoText-Name) oder nil |
| `cpWaypointCurrent` | int | Aktueller Wegpunkt (nur Feldarbeit) |
| `cpWaypointTotal` | int | Gesamtzahl Wegpunkte |
| `cpRemainingTime` | string | z.B. „12 min" |
| `cpNumBalesLeft` | int | Verbleibende Ballen (Ballensuche) |
| `cpWaitingForUnload` | bool | Mähdrescher wartet auf Entlader |
| `cpHarvesterManeuvering` | bool | Mähdrescher manövriert |
