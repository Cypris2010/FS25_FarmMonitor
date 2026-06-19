# File-based IPC — Dashboard → Lua Command Channel

Bidirektionale Kommunikation: Dashboard sendet Befehle ins Spiel über Dateien.

## Datenfluss

```
Dashboard (Browser) → POST /api/command
  → Go Server schreibt commands.xml
    → Lua Mod erkennt Datei (1s Polling)
      → Command ausführen im Spiel
        → commands.ack schreiben
```

## Protokoll im Detail

### 1. Dashboard → Go Server

```
POST /api/command
Content-Type: application/json

{"cmd":"production.setOutputMode","uniqueId":"placeabled1...","fillType":"LETTUCE","mode":"sell"}
```

Response: `{"id":"1779..."}` (Nanosekunden-Timestamp als ID)

### 2. Go Server → Datei

Go schreibt `commands.xml` ins modSettings-Verzeichnis:

```xml
<?xml version="1.0" encoding="utf-8"?>
<commands count="1">
  <command id="1779..." cmd="production.setOutputMode"
           uniqueId="placeabled1..." fillType="LETTUCE" mode="sell"/>
</commands>
```

Keine separate Flag-Datei nötig — `fileExists()` auf die XML-Datei selbst ist der Trigger.

### 3. Lua Mod — Polling & Verarbeitung

```lua
-- In update(), 1x pro Sekunde:
if fileExists(paths.commandsXml) then
    local xmlId = loadXMLFile("FMCommands", paths.commandsXml)
    deleteFile(paths.commandsXml)   -- at-most-once: ZUERST löschen!
    -- Commands lesen via getXMLString(xmlId, "commands.command(i)#attr")
    -- Dispatcher aufrufen
    -- commands.ack schreiben
end
```

**At-most-once Semantik:** Datei wird vor der Verarbeitung gelöscht. Crasht das Spiel mittendrin → Command geht verloren, wird aber nie doppelt ausgeführt.

### 4. ACK

Lua schreibt nach Verarbeitung `commands.ack`:
```json
{"processed":["1779..."]}
```

Go Server liest dies aktuell nicht aus (fire-and-forget). Kann für Fehlerbehandlung in Zukunft genutzt werden.

## Command-Dispatcher

Lua-seitig ein einfacher Dispatcher mit Handler-Tabelle:

```lua
local handlers = {
    ["production.setOutputMode"]  = FarmMonitor.cmdSetProductionOutputMode,
    ["production.spawnPallets"]   = FarmMonitor.cmdSpawnPallets,
    -- weitere Commands hier eintragen
}
```

Fehler werden per `pcall` gefangen und geloggt — ein fehlerhafter Command bricht nicht die ganze Queue ab.

## Multiplayer-Architektur für Placeable-Befehle

### Das Problem

Commands werden vom Client-Prozess verarbeitet (Lua liest die lokale `commands.xml`). Für Befehle die Server-Autorität brauchen (z.B. Paletten spawnen), muss der Command zum Server weitergeleitet werden.

`getPlaceableByUniqueId(uniqueId)` schlägt auf dem Server fehl wenn die `uniqueId` vom Client stammt — die IDs sind prozess-lokal und stimmen auf dem Dedicated Server nicht überein.

### Die Lösung

**Nicht** den uniqueId-String zum Server schicken und dort nachschlagen — stattdessen `pp` direkt via `NetworkUtil.writeNodeObject/readNodeObject` übertragen (gleiche Technik wie PSC's eigene Events und FarmMonitor's AutoDrive-Fahrzeug-Events).

```
SP / Listen-Server-Host:
  commands.xml → processCommands() → cmdXxx() → Direktaufruf ✅

MP-Client / Dedicated-Server-Joiner (g_server == nil, g_client ~= nil):
  commands.xml → processCommands() → cmdXxx() →
    pp lokal auflösen (klappt auf eigenem Prozess) →
    FarmMonitorXxxEvent.new(pp, ...) →
    NetworkUtil.writeNodeObject(pp) über Netz →
    Server: NetworkUtil.readNodeObject() → Direktaufruf ✅
```

## Implementierter Command: production.setOutputMode

Ändert den Ausgangsmodus eines Produktionspunkts.

**Parameter:**
- `uniqueId` — Placeable-UniqueId (identisch mit Dashboard-Daten)
- `fillType` — Fülltyp-Name (z.B. `"LETTUCE"`, `"WHEAT"`)
- `mode` — `"keep"` / `"sell"` / `"deliver"` / `"store"`

**Lua-Implementierung:**
```lua
local placeable = g_currentMission.placeableSystem:getPlaceableByUniqueId(uniqueId)
local pp = placeable.spec_productionPoint.productionPoint
local ft = g_fillTypeManager:getFillTypeByName(fillType)
pp:setOutputDistributionMode(ft.index, modeConstant)
ProductionPointOutputModeEvent.sendEvent(pp, ft.index, modeConstant, true)
```

Modus-Mapping:
```lua
keep    → ProductionPoint.OUTPUT_MODE.KEEP
sell    → ProductionPoint.OUTPUT_MODE.DIRECT_SELL
deliver → ProductionPoint.OUTPUT_MODE.AUTO_DELIVER
store   → ProductionPoint.OUTPUT_MODE.STORE  (nur mit PSC-Mod)
```

**Wichtig:** `setOutputDistributionMode` direkt aufrufen — `sendEvent` allein hat keine Wirkung in SP.

## Dashboard UX

1. Klick auf Output-Mode-Badge öffnet modales Overlay (Backdrop + zentriertes Fenster)
2. 4 Icons zur Auswahl, aktiver Modus highlighted
3. Nach Auswahl: sofortiger optimistic Update (neues Icon), pulsierender Hintergrund bis SSE-Update
4. SSE-Update (~10s) re-rendert den View → Pulse stoppt

## Datei-Pfade

Alle im modSettings-Verzeichnis (`~/Library/Application Support/FarmingSimulator2025/modSettings/FS25_FarmMonitor/`):

| Datei | Erstellt von | Inhalt |
|---|---|---|
| `commands.xml` | Go Server | Queue mit Commands (wird nach Verarbeitung gelöscht) |
| `commands.ack` | Lua Mod | Verarbeitete Command-IDs |

## Warum XML statt JSON?

FS25 Lua Sandbox erlaubt `io.open` nur im **Schreibmodus**. Lesen ist geblockt. `loadXMLFile` / `getXMLString` sind die einzigen verfügbaren Funktionen zum Lesen von Dateien.

`deleteXMLFile` existiert nicht in FS25 Lua — xmlId wird einfach nicht freigegeben (vernachlässigbares Memory Leak, da Commands selten sind).

## Implementierter Command: production.spawnPallets

Spawnt eine oder mehrere Paletten aus dem Lager einer PSC-Produktionsanlage.

**Benötigt:** Mod `FS25_ProductionStorageControl` geladen.

**Parameter:**
- `uniqueId` — Placeable-UniqueId der Produktionsanlage
- `fillType` — Fülltyp-Name (z.B. `"WHEAT"`, `"BUTTER"`)
- `amount` — Anzahl zu spawnender Paletten (String, wird zu Integer konvertiert)

**SP / Listen-Server-Host** (`g_server ~= nil`):
```lua
-- pp lokal auflösen, dann direkt:
pp:ReceiveSpawnEvent(farmId, fillTypeIndex, pendingLiters,
    width, height, length, capacity, 1, customEnvironment,
    nil, amount, 0, 0, 0)
```

**MP-Client / Dedicated-Server-Joiner** (`g_server == nil and g_client ~= nil`):
```lua
-- pp lokal auflösen (getPlaceableByUniqueId klappt auf eigenem Prozess),
-- dann via NetworkUtil zum Server:
conn:sendEvent(FarmMonitorSpawnPalletsEvent.new(
    pp, farmId, fillTypeIndex, pendingLiters,
    width, height, length, capacity, customEnvironment, amount
))
-- Server: NetworkUtil.readNodeObject() → pp:ReceiveSpawnEvent() direkt
```

**Warum nicht PSC's eigenes Event?**  
`productionStorageControl_EventSpawn` liegt in PSC's Lua-`_ENV` und ist von FarmMonitor aus nicht zugänglich (Sandbox-Isolation). `pp:ReceiveSpawnEvent()` als Prototype-Methode hingegen ist sichtbar.

**customEnvironment-Bug (behoben):**  
Der PalletInfoCache muss den tatsächlichen Key aus `fillType.pallets` speichern (z.B. `"VANILLA"` oder `"FS25_SomeMod"`), nicht hardcoded `"VANILLA"`. Falscher Key → `item.filename = nil` → stiller Fehlschlag ohne Log-Ausgabe.

---

## Implementierter Command: soilScan.setLayers (server-generiert)

Sonderfall: Dieser Command wird **nicht vom Dashboard**, sondern **vom Go-Server selbst**
erzeugt. Der Server aggregiert, welche Bodenlayer in den verbundenen Browsern angezeigt
werden, und sagt Lua, nur diese zu scannen (On-Demand-Scan).

**Parameter:**
- `layers` — kommaseparierte Liste aktiver Layer (z.B. `"weed,stone"`), leer = kein Scan

**Presence-Pipeline (statt direktem sendCommand):**
```
Browser ──POST /api/soil/presence {clientId, layers}──▶ Go-Server
   (alle 15 s, nur solange Map-View offen; sofort bei Layer-Toggle/View-Wechsel)
Go-Server: presence[clientId] = {layers, lastSeen}; prune > TTL 45 s; Union bilden
   Union geändert? ──▶ appendCommand(soilScan.setLayers, layers="…") in commands.xml
Lua cmdSoilScanSetLayers: soilActiveLayers setzen → soilState = nil (Scan-Neustart)
```

**Warum server-seitig:** Mehrere Browser können unterschiedliche Layer aktivieren — nur der
Server sieht alle Clients und kann die Union bilden. TTL macht es selbstheilend
(geschlossener Tab läuft aus). Details: `ai/performance_optimizations.md` → „On-Demand Soil-Scan".

Der Go-Server-`command`-Struct hat dafür ein zusätzliches Feld `Layers` (`layers,attr`); das
atomare Schreiben von commands.xml ist in die wiederverwendbare Funktion `appendCommand()`
ausgelagert (genutzt von `handleCommand` und der Presence-Reconcile-Logik).

## Erweiterung um neue Commands

1. Handler-Funktion schreiben: `FarmMonitor:cmdMeinCommand(cmd)`
2. In `dispatchCommand` registrieren: `["mein.command"] = FarmMonitor.cmdMeinCommand`
3. Go-Server: `command`-Struct hat generische Felder (`UniqueID`, `FillType`, `Mode`, `Amount`) — für weitere Parameter ggf. erweitern (z.B. `Layers` für `soilScan.setLayers`)
4. Braucht der Command Server-Autorität im MP? → eigenes `FarmMonitorXxxEvent` mit `NetworkUtil.writeNodeObject/readNodeObject` implementieren (Muster: `FarmMonitorSpawnPalletsEvent`)
