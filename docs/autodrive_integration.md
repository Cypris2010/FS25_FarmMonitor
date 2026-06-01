# AutoDrive Integration — Vollständiges Konzept

Dieses Dokument beschreibt alle verfügbaren AutoDrive-Steuerungsoptionen, welche davon ins FarmMonitor-Dashboard integriert werden, und wie die Implementierung für Singleplayer und Multiplayer funktionieren soll.

## Inhaltsverzeichnis

1. [Architektur: SP vs. MP](#architektur-sp-vs-mp)
2. [Fahrmodi (Mode-Button)](#fahrmodi)
3. [HUD-Aktionen (Buttons)](#hud-aktionen)
4. [State-Felder für vehicles.json](#state-felder-für-vehiclesjson)
5. [Vehicle Settings](#vehicle-settings)
6. [Neue IPC-Commands](#neue-ipc-commands)
7. [Implementierungsplan](#implementierungsplan)

---

## Architektur: SP vs. MP

### Zwei Kategorien von AD-Operationen

AutoDrive unterscheidet intern zwischen zwei Arten von Änderungen:

| Kategorie | Was | AD-Kanal | FarmMonitor-Kanal |
|---|---|---|---|
| **State-Änderungen** | Mode, Marker, FillType, LoopCounter, SpeedLimit, Start/Stop, Continue, Park | `AutoDriveHudInputEventEvent` + dirty flag → alle Clients | `FarmMonitorADCommandEvent` (neu) |
| **Settings-Änderungen** | Vehicle Settings (CornerSpeed, AutoRefuel, etc.) | `AutoDriveUpdateSettingsEvent` → alle Clients | `FarmMonitorADCommandEvent` (neu) |

### Warum FarmMonitor keinen direkten AD-Event-Zugriff hat

FS25 führt jeden Mod in einer eigenen Lua-Sandbox aus. `AutoDriveHudInputEventEvent`, `AutoDriveUpdateSettingsEvent`, `ADInputManager` etc. sind aus FarmMonitors Scope **nicht sichtbar** (`nil`). Nur Methoden auf `vehicle.ad.stateModule` und `vehicle.ad.settings[name]` sind erreichbar, weil sie auf dem Fahrzeugobjekt selbst liegen.

### Lösungsarchitektur

```
Dashboard → Go Server → commands.xml

FarmMonitor:processCommands()   ← läuft auf JEDEM Spieler (Host + MP-Client)

  ┌─ g_server ~= nil (Host / SP) ──────────────────────────────────────────┐
  │                                                                          │
  │  State-Änderung:    sm:setFirstMarker(x) etc. → raiseDirtyFlag()        │
  │                     AD broadcastet automatisch an alle Clients           │
  │                                                                          │
  │  Settings-Änderung: vehicle.ad.settings[name].current = value           │
  │                     + pcall(AutoDriveUpdateSettingsEvent.sendEvent, v)   │
  │                       (broadcast wenn AD-Klasse zugänglich)             │
  └──────────────────────────────────────────────────────────────────────────┘

  ┌─ g_client ~= nil (MP-Client) ──────────────────────────────────────────┐
  │                                                                          │
  │  FarmMonitorADCommandEvent.sendToServer(cmd)                            │
  │    → g_client:getServerConnection():sendEvent(...)                      │
  │      → Server-FarmMonitor empfängt → dispatchCommand(cmd)               │
  │        → g_server ~= nil → direkter Aufruf (s.o.)                      │
  └──────────────────────────────────────────────────────────────────────────┘
```

### `FarmMonitorADCommandEvent` — Stream-Format

```lua
-- writeStream (Client → Server):
streamWriteString(streamId, cmd.cmd)        -- Command-Name
streamWriteString(streamId, cmd.uniqueId)   -- vehicle rootNode als String
streamWriteString(streamId, cmd.mode)
streamWriteString(streamId, cmd.marker1)
streamWriteString(streamId, cmd.marker2)
streamWriteString(streamId, cmd.fillType)
streamWriteString(streamId, cmd.setting)    -- Setting-Name (für settings-Commands)
streamWriteString(streamId, cmd.value)      -- Setting-Wert als String
streamWriteString(streamId, cmd.amount)     -- für Zahlen-Inkremente

-- readStream (Server): cmd-Table rekonstruieren → FarmMonitor:dispatchCommand(cmd)
```

---

## Fahrmodi

Der Mode-Button zeigt den aktuellen Fahrmodus und wechselt zyklisch.

| Mode-ID | Name (DE) | Beschreibung | Marker 1 | Marker 2 | FillType |
|---|---|---|---|---|---|
| 1 | Fahre zum Ziel | Punkt-zu-Punkt, keine weitere Aktion | Ziel | — | — |
| 2 | Nur Abladen | Fährt zum Abladeort und entlädt | Abladeort | — | ✓ |
| 3 | Abholen und Abliefern | Voller Zyklus: laden → abladen → wiederholen | Ladeort | Abladeort | ✓ |
| 4 | Abholen → Ziel (ohne Abladen) | Lädt auf, liefert zum Ziel ohne Entladen | Ladeort | Lieferort | ✓ |
| 5 | Abfahrer (CombineUnloader) | Folgt Drescher, entleert, fährt zur Station | Wartepunkt | Entladeort | — |

**Code-Konstanten:**
```lua
AutoDrive.MODE_DRIVETO           = 1
AutoDrive.MODE_DELIVERTO         = 2
AutoDrive.MODE_PICKUPANDDELIVER  = 3
AutoDrive.MODE_LOAD              = 4
AutoDrive.MODE_UNLOAD            = 5
```

---

## HUD-Aktionen

### Bereits implementiert ✅

| Aktion | IPC-Command | Code |
|---|---|---|
| Start / Stop | `autodrive.startStop mode=start\|stop` | `sm:getCurrentMode():start()` / `vehicle:stopAutoDrive()` |
| Modus setzen | `autodrive.configure mode=1..5` | `sm:setMode(n)` |
| Marker 1 setzen | `autodrive.configure marker1=id` | `sm:setFirstMarker(id)` |
| Marker 2 setzen | `autodrive.configure marker2=id` | `sm:setSecondMarker(id)` |
| FillType setzen | `autodrive.configure fillType=NAME` | `sm:setFillType(index)` |

### Noch zu implementieren ❌

#### Aktions-Buttons

| Aktion | Neuer IPC-Command | Code (Server-Seite) | Sichtbarkeit |
|---|---|---|---|
| **Weiterfahren** | `autodrive.continue` | `sm:getCurrentMode():continue()` | immer |
| **Parken** | `autodrive.park` | Parkziel→setFirstMarker + setMode(1) + start | immer (grau wenn kein Parkziel) |
| **Ziele tauschen** | `autodrive.swapTargets` | `setFirstMarker(second)` + `setSecondMarker(first)` | immer |
| **Automatisch tanken** | `autodrive.refuel` | findet nächste Tankstation via `ADTriggerManager` + start | immer |
| **Automatisch reparieren** | `autodrive.repair` | findet nächste Werkstatt + start | immer |

#### Zähler & Geschwindigkeit

| Aktion | IPC-Command | Code | Werte |
|---|---|---|---|
| **Loop-Counter setzen** | `autodrive.loopCounter value=N` | `sm:changeLoopCounter(increment, fast)` | 0 = ∞, 1–99 |
| **Straßen-Speed** | `autodrive.speedLimit value=N` | `sm:increaseSpeedLimit()` / `decreaseSpeedLimit()` | 2–Fahrzeugmax km/h |
| **Feld-Speed** | `autodrive.fieldSpeedLimit value=N` | `sm:increaseFieldSpeedLimit()` / `decreaseFieldSpeedLimit()` | 2–Fahrzeugmax km/h |

#### Toggle-Buttons (Modi-abhängig)

| Aktion | IPC-Command | Code | Sichtbar in Modi |
|---|---|---|---|
| **Beladen nach Füllstand** | `autodrive.toggleLoadByFill` | `sm:toggleLoadByFillLevel()` | 3, 4 |
| **Auto-Entladeziel** | `autodrive.toggleAutoUnload` | `sm:toggleAutomaticUnloadTarget()` | 3, 4, 5 |
| **Auto-Beladeziel** | `autodrive.toggleAutoPickup` | `sm:toggleAutomaticPickupTarget()` | 3, 4 |
| **Helper nach Stopp neu starten** | `autodrive.toggleStartHelper` | `sm:toggleStartHelper()` | immer |
| **Helper-Typ wechseln** | `autodrive.toggleUsedHelper` | `sm:toggleUsedHelper()` | immer |

---

## State-Felder für `vehicles.json`

Diese Felder müssen im Lua-Export ergänzt werden damit das Dashboard die Buttons korrekt rendert:

### Bereits exportiert ✅

```lua
adActive          -- sm:isActive()
adMode            -- sm:getMode()
adDriverName      -- sm.driverName
adDestination     -- sm.firstMarker.name
adDestination2    -- sm.secondMarker.name
adRemainingTime   -- sm.remainingDriveTime
adBlocked         -- vehicle.ad.specialDrivingModule.isBlocked
adError           -- vehicle.ad.isStoppingWithError
adOnRouteToRefuel -- vehicle.ad.onRouteToRefuel
adOnRouteToPark   -- vehicle.ad.onRouteToPark
adIsLoading       -- vehicle.ad.trailerModule.isLoading
adIsUnloading     -- vehicle.ad.trailerModule.isUnloading
adModeState       -- Mode-5-Sub-State-String
```

### Noch zu exportieren ❌

```lua
-- Zähler & Geschwindigkeit
adLoopCounter      = sm:getLoopCounter()             -- 0=∞, 1–99
adLoopsDone        = sm:getLoopsDone()               -- absolvierte Schleifen
adSpeedLimit       = sm:getSpeedLimit()              -- km/h Straße
adFieldSpeedLimit  = sm:getFieldSpeedLimit()         -- km/h Feld

-- Toggles (für Button-Zustand im Dashboard)
adFillType         = sm:getFillType()                -- FillType-Index (für Dropdown-Vorauswahl)
adLoadByFillLevel  = sm:getLoadByFillLevel()         -- bool, nur Modi 3/4
adAutoUnloadTarget = sm:getAutomaticUnloadTarget()   -- bool, nur Modi 3/4/5
adAutoPickupTarget = sm:getAutomaticPickupTarget()   -- bool, nur Modi 3/4
adStartHelper      = sm:getStartHelper()             -- bool
adUsedHelper       = sm:getUsedHelper()              -- 1=CP, 2=AIVE, 3=AI, 5=keiner

-- Park
adParkDestination  = sm:getParkDestinationAtJobFinished()  -- markerIndex, -1=kein Ziel gesetzt

-- Task-Info
adCurrentTaskInfo  = sm:getCurrentLocalizedTaskInfo()      -- lokalisierter Task-Text

-- Harvester
adHarvesterPairingOk = sm:getHarvesterPairingOk()   -- bool (für CombineUnloader-Modus)
```

**Export-Konditionen:**
- `adLoadByFillLevel` / `adAutoUnloadTarget` / `adAutoPickupTarget` nur exportieren wenn Modus es erfordert (oder immer — Dashboard filtert selbst)
- `adParkDestination` immer exportieren (Dashboard zeigt Park-Button grau wenn `-1`)
- Alle neuen Felder nur wenn `vehicle.ad ~= nil` (wie bestehende AD-Felder)

---

## Vehicle Settings

Diese Einstellungen aus dem In-Game „Vehicle Settings – AutoDrive"-Panel.

### Änderungs-Mechanismus

```
Server:  vehicle.ad.settings[name].current = valueIndex
         vehicle.ad.settings[name].new     = valueIndex
         pcall(AutoDriveUpdateSettingsEvent.sendEvent, vehicle)
         -- broadcast an alle Clients (falls AD-Klasse erreichbar)

Client:  FarmMonitorADCommandEvent.sendToServer({
           cmd="autodrive.setting", uniqueId=...,
           setting="cornerSpeed", value="15"  -- valueIndex als String
         })
```

### Alle fahrzeugspezifischen Settings

| Setting-Name | Label (Screenshot) | Typ | Werte / Bereich |
|---|---|---|---|
| `cornerSpeed` | Corner speed | Zahl | 0.5–2.0 (×50%–200%) |
| `pipeOffset` | Pipe Offset | Zahl | −5.0 bis +5.0 m (Schritt 0.25) |
| `followDistance` | Distance combine | Zahl | 0 bis 8.0 m (Schritt 0.25) |
| `unloadFillLevel` | Unload fill level | Zahl | 0%, 10%, …, 85%, 90%, 95%, 99%, 100% |
| `exitField` | Field exit | Enum | 0=Standard (zurück zum Zielpunkt), 1=Hinterm Start-/Zielpunkt, 2=Nächstgelegener Wegpunkt |
| `restrictToField` | Restrict pathfinder to field | bool | false/true |
| `followOnlyOnField` | Restrict unloader to field | bool | false/true |
| `avoidFruit` | Avoid fruit | bool | false/true |
| `parkInField` | Park in field | bool | false/true |
| `rotateTargets` | Cycle Pickup and Deliver | Enum | NONE / ONLYPICKUP / ONLYDELIVER / PICKUPANDDELIVER |
| `autoRefuel` | Automatic Refueling | bool | false/true |
| `autoRepair` | Automatic Repairing | bool | false/true |
| `enableParkAtJobFinished` | Park at Job finished | bool | false/true |
| `autoTipSide` | Automatic Tip Side | bool | false/true |
| `autoTrailerCover` | Automatic Trailer Covers | bool | false/true |
| `ALUnload` | Autoload: Unload Position | Enum | 0=OFF, 1=Center, 2=Left, 3=Behind, 4=Right |
| `ALUnloadWaitTime` | Autoload: wait time un-/load | Zahl | 0s, 1s, 3s, 5s, 10s, 15s, 20s, 25s, 30s, 1min, 2min, 5min, 10min |

### Neuer IPC-Command: `autodrive.setting`

```xml
<command cmd="autodrive.setting" uniqueId="888436" setting="cornerSpeed" value="15"/>
```

- `setting` = Setting-Name (aus obiger Tabelle)
- `value` = **Index** in die `values`-Tabelle (1-basiert, Lua-Konvention), als String

**Lua-Handler (Server-Seite):**

```lua
function FarmMonitor:cmdAutoDriveSetting(cmd)
    local vehicle = FarmMonitor:findVehicleByNodeId(cmd.uniqueId)
    if vehicle == nil or vehicle.ad == nil or vehicle.ad.settings == nil then
        error("Vehicle/AD not found: " .. tostring(cmd.uniqueId))
    end
    local settingName = cmd.setting
    local valueIndex  = tonumber(cmd.value)
    if vehicle.ad.settings[settingName] == nil then
        error("Unknown AD setting: " .. tostring(settingName))
    end
    if valueIndex == nil or vehicle.ad.settings[settingName].values[valueIndex] == nil then
        error("Invalid value index: " .. tostring(valueIndex))
    end
    vehicle.ad.settings[settingName].current = valueIndex
    vehicle.ad.settings[settingName].new     = valueIndex
    -- Broadcast an andere Clients (best-effort, nur wenn AD-Klasse erreichbar)
    pcall(function()
        AutoDriveUpdateSettingsEvent.sendEvent(vehicle)
    end)
end
```

### Settings auch in `vehicles.json` exportieren

Damit das Dashboard die aktuellen Werte anzeigen kann:

```lua
-- In collectAndSaveVehicles(), innerhalb des AD-Blocks:
if vehicle.ad ~= nil and vehicle.ad.settings ~= nil then
    local adSettings = {}
    local settingNames = {
        "cornerSpeed", "pipeOffset", "followDistance", "unloadFillLevel",
        "exitField", "restrictToField", "followOnlyOnField", "avoidFruit",
        "parkInField", "rotateTargets", "autoRefuel", "autoRepair",
        "enableParkAtJobFinished", "autoTipSide", "autoTrailerCover",
        "ALUnload", "ALUnloadWaitTime"
    }
    for _, name in ipairs(settingNames) do
        local s = vehicle.ad.settings[name]
        if s ~= nil then
            adSettings[name] = s.current  -- Index (1-basiert)
        end
    end
    -- Werte auch als direkte Zahl (für Anzeige):
    -- vehicle.ad.settings["cornerSpeed"].values[s.current] → 0.85
end
```

---

## Neue IPC-Commands — Vollständige Liste

### State-Commands (via `FarmMonitorADCommandEvent` im MP-Client-Fall)

| Command | Parameter | Beschreibung |
|---|---|---|
| `autodrive.configure` | `mode`, `marker1`, `marker2`, `fillType` | bereits implementiert |
| `autodrive.startStop` | `mode=start\|stop` | bereits implementiert |
| `autodrive.continue` | `uniqueId` | Weiterfahren nach Pause |
| `autodrive.park` | `uniqueId` | Zum konfigurierten Parkziel fahren |
| `autodrive.swapTargets` | `uniqueId` | Marker 1 ↔ Marker 2 tauschen |
| `autodrive.loopCounter` | `uniqueId`, `value=N` | Loop-Counter direkt setzen (0=∞) |
| `autodrive.speedLimit` | `uniqueId`, `value=N` | Straßen-Speedlimit direkt setzen (km/h) |
| `autodrive.fieldSpeedLimit` | `uniqueId`, `value=N` | Feld-Speedlimit direkt setzen (km/h) |
| `autodrive.toggleLoadByFill` | `uniqueId` | Beladen nach Füllstand umschalten |
| `autodrive.toggleAutoUnload` | `uniqueId` | Auto-Entladeziel umschalten |
| `autodrive.toggleAutoPickup` | `uniqueId` | Auto-Beladeziel umschalten |
| `autodrive.toggleStartHelper` | `uniqueId` | Helper-Neustart nach Stopp umschalten |
| `autodrive.toggleUsedHelper` | `uniqueId` | Helper-Typ wechseln (AI→CP→AIVE→…) |

### Settings-Command (direkt auf `vehicle.ad.settings`)

| Command | Parameter | Beschreibung |
|---|---|---|
| `autodrive.setting` | `uniqueId`, `setting=NAME`, `value=INDEX` | Beliebigen Vehicle-Setting-Wert setzen |

---

## Implementierungsplan

### Phase 1 — Lua: Export + neue Commands (Basis)

1. `vehicles.json`: alle neuen State-Felder ergänzen (~15 Felder)
2. `vehicles.json`: `adSettings`-Objekt mit allen Vehicle-Settings
3. Neuer IPC-Handler: `autodrive.continue`
4. Neuer IPC-Handler: `autodrive.park`
5. Neuer IPC-Handler: `autodrive.swapTargets`
6. Neuer IPC-Handler: `autodrive.loopCounter`
7. Neuer IPC-Handler: `autodrive.speedLimit` / `autodrive.fieldSpeedLimit`
8. Neuer IPC-Handler: `autodrive.toggleLoadByFill` / `autodrive.toggleAutoUnload` / `autodrive.toggleAutoPickup`
9. Neuer IPC-Handler: `autodrive.toggleStartHelper` / `autodrive.toggleUsedHelper`
10. Neuer IPC-Handler: `autodrive.setting`
11. `FarmMonitorADCommandEvent` für MP-Client-Weiterleitung

### Phase 2 — Dashboard: Erweitertes AD-Panel

1. Loop-Counter Anzeige + ±-Buttons
2. Speed-Limit Anzeige + ±-Buttons (Straße + Feld)
3. Continue-Button
4. Park-Button (grau wenn kein Parkziel)
5. Swap-Targets-Button
6. Toggle-Buttons (LoadByFill, AutoUnload, AutoPickup, StartHelper, UsedHelper)
7. Vehicle-Settings-Panel (Accordion/Tab im Detail-View)
8. Alle Settings als editierbare Controls (Slider, Toggle, Dropdown)

### SP/MP-Kompatibilitätsmatrix nach Implementierung

| Szenario | State-Änderung | Settings-Änderung |
|---|---|---|
| Singleplayer | ✅ direkt | ✅ direkt |
| MP Host | ✅ direkt + AD broadcastet | ✅ direkt + pcall broadcast |
| MP Client | ✅ via FarmMonitorADCommandEvent → Host | ✅ via FarmMonitorADCommandEvent → Host |
| Dedicated Server | ❌ kein Dashboard | ❌ kein Dashboard |
