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
- `savegameId` = `mapId_unknown` (z.B. `FS25_Haut-Beyleron_unknown`)
- Hinweis: `careerSavegame.xml` ist auf dem Client nicht verfügbar — das Datum kann nur via Network Event vom Server übertragen werden

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
| AutoDrive-Steuerung (IPC-Commands) | ⚠️ Nur für Host getestet — Client-Pfad geplant (siehe unten) |
| Shared Dashboard (alle Spieler sehen dasselbe) | ❌ nicht implementiert — jeder sieht nur sein eigenes `modSettings` |
| Dedicated Server | ❌ nicht unterstützt (`isServer`-Guard greift) |

## Network Events

| Event | Richtung | Inhalt | Zeitpunkt |
|---|---|---|---|
| `FarmMonitorSavegameEvent` | Server → Client | `savegameName`, `savegameId` | `onClientJoined` |
| `FarmMonitorADCommandEvent` | Client → Server | kompletter `cmd`-Table (cmd, uniqueId, mode, marker1, marker2, fillType) | bei AD-IPC-Command auf Client (geplant) |

---

## AutoDrive IPC-Commands auf MP-Clients (geplant)

### Problem: Sandbox-Isolation

FS25 führt jeden Mod in einer eigenen Lua-Sandbox aus. FarmMonitor kann AD-interne Event-Klassen wie `AutoDriveHudInputEventEvent` nicht direkt instanziieren — sie sind in FarmMonitors Scope `nil`.

Der aktuelle Code ruft `sm:setFirstMarker()`, `sm:setMode()` etc. direkt auf dem `vehicle.ad.stateModule`-Objekt auf. Das funktioniert auf dem **Host** (Server), weil die Methodenrümpfe im AD-Kontext laufen und von dort auf `ADGraphManager` etc. zugreifen. Auf einem **MP-Client** hingegen werden diese Änderungen nur lokal vorgenommen — beim nächsten Sync überschreibt der Server den Client-State wieder.

### Lösung: `FarmMonitorADCommandEvent` (Client → Server)

FarmMonitor bekommt ein eigenes leichtgewichtiges Event, das den kompletten Command-Table vom Client an den Server-FarmMonitor weiterleitet. Der Server führt dann die direkten AD-Aufrufe aus, die dann über ADs eigenen `raiseDirtyFlag()`-Mechanismus an alle Clients propagiert werden.

### Vollständiger Ablauf

```
Dashboard → Go Server → commands.xml

FarmMonitor:processCommands()       ← läuft auf JEDEM Client (inkl. Host)
  → cmd = {cmd="autodrive.configure", uniqueId=..., mode=2, marker1=22, ...}
  → cmdAutoDriveConfigure(cmd)

    ┌─ g_server ~= nil (Host / Singleplayer) ──────────────────────────────┐
    │  sm:setMode(modeNum)           ← direkt, funktioniert heute schon     │
    │  sm:setFirstMarker(mid)                                                │
    │  sm:setSecondMarker(mid)                                               │
    │  sm:setFillType(ft.index)                                              │
    │  → raiseDirtyFlag() → AD broadcastet State an alle Clients            │
    └───────────────────────────────────────────────────────────────────────┘

    ┌─ g_client ~= nil (MP-Client) ────────────────────────────────────────┐
    │  FarmMonitorADCommandEvent.sendToServer(cmd)                           │
    │    → g_client:getServerConnection():sendEvent(...)                     │
    │                                                                        │
    │  Server empfängt FarmMonitorADCommandEvent:readStream()                │
    │    → FarmMonitor:dispatchCommand(cmd)    ← gleicher Handler-Code!      │
    │      → cmdAutoDriveConfigure()                                         │
    │        → g_server ~= nil → direkter sm-Aufruf                         │
    │          → raiseDirtyFlag() → AD broadcastet an alle Clients          │
    └───────────────────────────────────────────────────────────────────────┘
```

`cmdAutoDriveStartStop` folgt demselben Muster.

### Benötigte Änderungen

**1. Neues Event `FarmMonitorADCommandEvent`** (analog zu `FarmMonitorRequestEvent`):

```lua
-- writeStream (Client → Server):
streamWriteString(streamId, cmd.cmd)       -- "autodrive.configure" / "autodrive.startStop"
streamWriteString(streamId, cmd.uniqueId)  -- vehicle rootNode als String
streamWriteString(streamId, cmd.mode)
streamWriteString(streamId, cmd.marker1)
streamWriteString(streamId, cmd.marker2)
streamWriteString(streamId, cmd.fillType)

-- readStream (Server empfängt → direkt weiterleiten):
local cmd = { cmd=..., uniqueId=..., mode=..., marker1=..., marker2=..., fillType=... }
FarmMonitor:dispatchCommand(cmd)
```

**2. `cmdAutoDriveConfigure` und `cmdAutoDriveStartStop` — Branch ergänzen:**

```lua
if g_server ~= nil then
    -- Host/SP: direkter Aufruf (aktuelles Verhalten)
    sm:setMode(tonumber(cmd.mode))
    sm:setFirstMarker(tonumber(cmd.marker1))
    -- ...
else
    -- MP-Client: an Server-FarmMonitor weiterleiten
    FarmMonitorADCommandEvent.sendToServer(cmd)
end
```

**3. Kein Umbau von `processCommands()` nötig** — der bestehende `g_dedicatedServer ~= nil then return end`-Guard bleibt korrekt. Dedicated Server hat kein lokales Dashboard, also keine Commands.

### Was sich nicht ändert

| Bereich | Grund |
|---|---|
| Marker-Export-Iterator-Trick | `ADGraphManager` ist im AD-Kontext der `sm`-Methode zugänglich — funktioniert auf Clients |
| Status-Lesen (`isActive`, `mode` etc.) | AD synchronisiert State laufend via `readUpdateStream` Server→Client |
| Ack-Datei | wird sofort nach Parsing geschrieben, unabhängig ob lokal oder weitergeleitet |

## Savegame-Wechsel im laufenden Betrieb

`update()` vergleicht `missionInfo.savegameDirectory` mit dem gecachten Wert. Bei Änderung werden alle `*Exported`-Flags und `savegameInfoReady` zurückgesetzt — der gesamte Initialisierungszyklus (inkl. Network-Event-Warten auf dem Client) läuft erneut.
