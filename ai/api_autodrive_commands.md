# FarmMonitor — AutoDrive Command-System Dokumentation

## Übersicht: Zwei Wege je nach Kontext

FarmMonitor nutzt **zwei unterschiedliche Mechanismen** um AutoDrive-Befehle umzusetzen,
abhängig vom Befehlstyp und ob SP oder MP vorliegt.

---

## Weg 1 — FarmMonitorADCommandEvent (alle Befehle außer Settings)

Wird verwendet für:
- `autodrive.configure` (Mode, Marker, FillType)
- `autodrive.startStop`
- `autodrive.nextTarget`
- `autodrive.continue`
- `autodrive.park`
- `autodrive.swapTargets`
- `autodrive.loopCounter`
- `autodrive.speedLimit`
- `autodrive.fieldSpeedLimit`
- `autodrive.toggleLoadByFill`
- `autodrive.toggleAutoUnload`
- `autodrive.toggleAutoPickup`
- `autodrive.toggleStartHelper`
- `autodrive.toggleUsedHelper`

### Singleplayer / Listen-Server Host

```
Dashboard → Go-Server → commands.xml → FarmMonitor Lua
                                            ↓
                                    adBegin() → g_server != nil → return true
                                            ↓
                                    Handler direkt ausführen
                                    (sm:setMode / sm:start / sm:toggle... etc.)
```

### Dedicated Server / Joining Client

```
Dashboard → Go-Server → commands.xml → FarmMonitor Lua (Client)
                                            ↓
                                    adBegin() → g_server == nil → pure client
                                            ↓
                                    FarmMonitorADCommandEvent → Netzwerk → DS
                                            ↓
                                    FarmMonitorADCommandEvent:run()
                                            ↓
                                    dispatchCommand() → Handler
                                            ↓
                                    adBegin() → g_server != nil → return true
                                            ↓
                                    Handler direkt ausführen
```

### Warum dieser Weg für diese Befehle?

Diese Befehle rufen echte AutoDrive StateModule-Methoden auf:
- `sm:getCurrentMode():start()` / `vehicle:stopAutoDrive()`
- `sm:setMode()`, `sm:setFirstMarker()`, `sm:setFillType()`
- `sm:increaseSpeedLimit()` / `sm:decreaseSpeedLimit()`
- `sm:toggleLoadByFillLevel()` etc.

Diese Methoden müssen auf dem Server ausgeführt werden (Spiellogik ist server-autoritativ).
`FarmMonitorADCommandEvent` übernimmt den Transport Client → Server.

---

## Weg 2 — AutoDriveUpdateSettingsEvent (nur Settings)

Wird verwendet für:
- `autodrive.setting` (generisch)
- `autodrive.pipeOffset`
- `autodrive.followDistance`
- `autodrive.unloadFillLevel`
- `autodrive.cornerSpeed`
- `autodrive.preCallLevel`
- `autodrive.chaseSide`
- `autodrive.rotateTargets` / `exitField` / `restrictToField` / `avoidFruit`
- `autodrive.parkInField` / `autoRefuel` / `autoRepair` etc.

### Singleplayer / Listen-Server Host

```
Dashboard → Go-Server → commands.xml → FarmMonitor Lua
                                            ↓
                                    g_server != nil (kein pure client)
                                            ↓
                                    s.current = valueIndex
                                    s.new     = valueIndex
                                            ↓
                                    g_server:broadcastEvent(AutoDriveUpdateSettingsEvent)
                                    → alle Clients erhalten den neuen Wert
```

### Dedicated Server / Joining Client

```
Dashboard → Go-Server → commands.xml → FarmMonitor Lua (Client)
                                            ↓
                                    g_server == nil → pure client
                                            ↓
                               ┌────────────────────────────────┐
                               │ 1. s.current = valueIndex      │
                               │    (lokales Feedback sofort)   │
                               └────────────────────────────────┘
                                            ↓
                               AutoDriveUpdateSettingsEvent.sendEvent(vehicle)
                               (genau wie AutoDrives eigene UI)
                                            ↓ g_client → g_server
                                    Dedicated Server (AutoDrive Code)
                                            ↓
                               AutoDriveUpdateSettingsEvent:readStream()
                                    → s.current = valueIndex (auf Server)
                                    → AutoDriveUpdateSettingsEvent.sendEvent()
                                            ↓ Broadcast
                               alle Clients (inkl. ursprünglicher Client)
                                    → s.current = valueIndex (auf Client)
```

### Warum dieser Weg für Settings?

AutoDrive Settings (`vehicle.ad.settings[name]`) haben **keine** eigene Setter-API.
Der einzige korrekte Weg sie zu ändern ist `AutoDriveUpdateSettingsEvent` —
genau das was AutoDrives eigene In-Game-UI verwendet.

Würde man Settings über `FarmMonitorADCommandEvent` (Weg 1) auf dem Server setzen,
müsste man anschließend manuell broadcasten. Das schlägt auf Dedicated Servern fehl,
weil `AutoDriveUpdateSettingsEvent` aus FarmMonitors Sandbox zwar aufrufbar ist,
aber `AutoDrive.gui.ADSettings:forceLoadGUISettings()` intern fehlschlägt.

**Fallback:** Falls `AutoDriveUpdateSettingsEvent.sendEvent()` auf dem Client wirft
(z.B. nicht erreichbar), fällt der Code auf `FarmMonitorADCommandEvent` zurück.
Dann setzt der Server den Wert direkt — ohne Broadcast an alle Clients.

---

## Zusammenfassung

| Befehlsgruppe | SP / Listen-Host | DS / Joining Client |
|---|---|---|
| configure, startStop, nextTarget, continue, park, swapTargets | direkt via StateModule API | FarmMonitorADCommandEvent → Server → StateModule API |
| speedLimit, fieldSpeedLimit, loopCounter | direkt via StateModule increment/decrement | FarmMonitorADCommandEvent → Server → StateModule API |
| toggleLoadByFill, toggleAutoUnload, etc. | direkt via `sm:toggleXxx()` | FarmMonitorADCommandEvent → Server → `sm:toggleXxx()` |
| **Settings** (pipeOffset, restrictToField, etc.) | direkt `s.current` + broadcastEvent | Client: `s.current` lokal + AutoDriveUpdateSettingsEvent → Server → Broadcast |

---

## FarmMonitorADCommandEvent — übertragene Felder

```xml
<command cmd="autodrive.configure"
         uniqueId="471894"   <!-- rootNode (SP-Fallback) -->
         netId="12345"       <!-- NetworkUtil ID (MP-safe, primärer Lookup) -->
         mode="2"
         marker1="22"
         marker2="15"
         fillType="WHEAT"
         setting=""          <!-- für autodrive.setting -->
         value=""/>          <!-- für Zahlenwerte (speedLimit, loopCounter, settingIndex) -->
```

## resolveVehicle() — Fahrzeug-Lookup

Wird in beiden Wegen verwendet:

```lua
-- 1. NetworkUtil (MP-safe, gleiche ID auf allen Prozessen)
NetworkUtil.getObject(tonumber(cmd.netId))
-- 2. Fallback: rootNode-Iteration (nur in SP zuverlässig)
for _, v in pairs(g_currentMission.vehicleSystem.vehicles) do
    if tostring(v.rootNode) == cmd.uniqueId then return v end
end
```
