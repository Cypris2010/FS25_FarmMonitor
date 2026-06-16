# Multiplayer-Analyse FarmMonitor

## Grundprinzip

Jeder Spieler hat den Mod lokal installiert und führt ihn selbst aus:
- `io.open` schreibt ins **lokale** `getUserProfileAppPath()` des jeweiligen Clients → bestätigt
- `getFarmId()` gibt die eigene Farm-ID zurück → jeder sieht nur seine eigene Farm
- JSON-Export läuft auf dem Client, nicht auf dem Dedicated Server

## Szenarios im Überblick

| Szenario | `g_currentMission.isServer` | `g_server` | `g_client` | JSON-Export | IPC-Befehle |
|---|---|---|---|---|---|
| Singleplayer | `true` | ≠ nil | ≠ nil | ✅ Client = Server | lokal |
| Listen-Server (Host) | `true` | ≠ nil | ≠ nil | ✅ Host | lokal |
| Listen-Server (Joiner) | `false` | `nil` | ≠ nil | ✅ Client | via Event → Server |
| Dedicated Server (DS-Prozess) | `true` | ≠ nil | `nil` | ❌ kein lokaler Spieler | — |
| Dedicated Server (Joiner) | `false` | `nil` | ≠ nil | ✅ Client | via Event → DS |

## Dedicated Server — kein JSON-Export

Auf dem Dedicated Server läuft FarmMonitor zwar (als Mod), aber:
- `getFarmId()` gibt `AccessHandler.SPECTATOR_FARM_ID` zurück → keine Farm-Daten
- `isServer`-Guard in `update()` verhindert unnötigen Export-Aufwand
- Es werden **keine JSON-Dateien** auf dem Server geschrieben

Jeder verbundene Client exportiert seine eigenen JSON-Dateien lokal und nutzt seinen eigenen Go-Server (Dashboard auf `localhost:8080`).

## IPC-Befehle im Multiplayer

### Das Problem: uniqueId-Lookup schlägt auf dem Server fehl

Placeable-Befehle (spawnPallets, setOutputMode, etc.) enthalten eine `uniqueId` aus dem Client-JSON.
`g_currentMission.placeableSystem:getPlaceableByUniqueId(uniqueId)` funktioniert nur auf demselben Prozess, der das JSON exportiert hat. Auf dem Dedicated Server schlägt der Lookup fehl — die IDs stimmen nicht überein.

Gleiches Problem wie `vehicle.rootNode` für Fahrzeuge.

### Lösung: NetworkUtil für Placeables (wie PSC's eigene Events)

Für Placeable-Befehle die Server-Autorität brauchen (z.B. `production.spawnPallets`):

```
MP-Client (isServer=false):
  1. Löst pp lokal auf via getPlaceableByUniqueId() ← klappt auf eigenem Prozess
  2. Sendet FarmMonitorSpawnPalletsEvent mit NetworkUtil.writeNodeObject(pp)
  3. Server empfängt Event, liest pp via NetworkUtil.readNodeObject()
  4. Server ruft pp:ReceiveSpawnEvent() direkt auf — kein uniqueId-Lookup nötig
```

Das ist exakt das Muster von PSC's eigenem `productionStorageControl_EventSpawn`.

### Lösung: isServer-Check für andere Befehle

Für Befehle die nur Server-State lesen/setzen (z.B. `setOutputMode` via `ProductionPointOutputModeEvent`):
```lua
-- ProductionPointOutputModeEvent ist ein offizielles FS25-Event → MP-sync automatisch
pp:setOutputDistributionMode(ft.index, mode)
ProductionPointOutputModeEvent.sendEvent(pp, ft.index, mode, true)
```

Hier ist kein eigenes Event nötig — FS25 übernimmt die Synchronisation.

## Lua-Sandbox-Isolation

FS25 gibt jedem Mod eine eigene `_ENV`. Globale Variablen anderer Mods (z.B. `productionStorageControl_EventSpawn` aus PSC) sind von FarmMonitor aus **nicht zugänglich**, auch wenn der Mod geladen ist. `g_modIsLoaded["FS25_ProductionStorageControl"] == true` sagt nichts darüber aus ob PSC's Globals sichtbar sind.

Lösung: eigene Events verwenden (FarmMonitorSpawnPalletsEvent) statt PSC-Globals.

Ausnahme: **Prototype-Modifikationen** (z.B. `function ProductionPoint:ReceiveSpawnEvent(...)`) sind auf dem globalen `ProductionPoint`-Table und damit von allen Mods sichtbar.

## isServer-Guard in update()

Der Dedicated Server führt `update()` aus, aber ohne aktiven Spieler/Farm sind alle Export-Funktionen leer:
```lua
function FarmMonitor:update(dt)
    if not g_currentMission.isServer then return end  -- nur auf Server/SP exportieren
    -- ...
end
```

Auf einem MP-Client (Joiner) läuft `update()` ebenfalls und exportiert die Client-Daten.
