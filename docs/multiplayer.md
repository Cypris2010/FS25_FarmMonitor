# FarmMonitor — Multiplayer-Verhalten

## Grundprinzip

Jeder Spieler installiert den Mod lokal. Die Mod-Instanz läuft auf jeder Maschine separat:

- **Host/Server**: hat vollen Zugriff auf das Savegame, schreibt JSON-Dateien in sein lokales `modSettings`
- **Client**: läuft in einer eingeschränkten Umgebung, schreibt JSON-Dateien in sein eigenes lokales `modSettings`

Jeder Spieler betreibt seinen eigenen `farmmonitor`-Server (Go-Binary) und sieht nur seine eigene Farm.

## Savegame-Identifikation

### Problem
`careerSavegame.xml` existiert nur auf der Host-Maschine. Clients können sie nicht lesen.

### Lösung: Network Event beim Client-Join

1. **Server** liest beim Start `careerSavegame.xml` → ermittelt `savegameName` und `savegameId` (`mapId_creationDate`)
2. **Client** joinet → Server sendet `FarmMonitorSavegameEvent` mit diesen Werten direkt an den neuen Client
3. **Client** empfängt das Event → setzt `savegameName`/`savegameId` mit den echten Server-Werten

### Wartemechanismus
Der Client blockiert alle JSON-Exports bis das Event empfangen wurde (`savegameInfoReady = true`).
Timeout: **10 Sekunden** — danach werden Fallback-Werte verwendet:
- `savegameName` = `"unknown"`
- `savegameId` = `mapId_savegameSlot` (z.B. `FS25_Haut-Beyleron_savegame0`)

## Dedicated Server

```lua
if g_dedicatedServer ~= nil then return end
```

Auf Dedicated Servers läuft kein lokaler Spieler — `getFarmId()` gibt `SPECTATOR_FARM_ID` zurück → alle Farm-Checks liefern leere Listen. Der `isServer`-Guard überspringt die komplette `update()`-Logik, damit kein unnötiger Aufwand entsteht.

## Bekannte Einschränkungen

| Feature | Status |
|---|---|
| JSON-Export (Silos, Felder, Tiere etc.) | ✅ funktioniert für jeden Spieler lokal |
| Savegame-Name im JSON | ✅ Client erhält echten Wert via Network Event |
| AutoDrive-Steuerung (IPC-Commands) | ⚠️ Nur für Host getestet — Client-Fahrzeuge nicht verifiziert |
| Shared Dashboard (alle Spieler sehen dasselbe) | ❌ nicht implementiert — jeder sieht nur sein eigenes `modSettings` |
| Dedicated Server | ❌ nicht unterstützt (`isServer`-Guard greift) |

## Network Events

| Event | Richtung | Inhalt | Zeitpunkt |
|---|---|---|---|
| `FarmMonitorSavegameEvent` | Server → Client | `savegameName`, `savegameId` | `onClientJoined` |

## Savegame-Wechsel im laufenden Betrieb

`update()` vergleicht `missionInfo.savegameDirectory` mit dem gecachten Wert. Bei Änderung werden alle `*Exported`-Flags und `savegameInfoReady` zurückgesetzt — der gesamte Initialisierungszyklus (inkl. Network-Event-Warten auf dem Client) läuft erneut.
