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
    ["production.setOutputMode"] = FarmMonitor.cmdSetProductionOutputMode,
    -- weitere Commands hier eintragen
}
```

Fehler werden per `pcall` gefangen und geloggt — ein fehlerhafter Command bricht nicht die ganze Queue ab.

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

## Erweiterung um neue Commands

1. Handler-Funktion schreiben: `FarmMonitor:cmdMeinCommand(cmd)`
2. In `dispatchCommand` registrieren: `["mein.command"] = FarmMonitor.cmdMeinCommand`
3. Go-Server: `command`-Struct hat generische Felder (`UniqueID`, `FillType`, `Mode`) — für weitere Parameter ggf. erweitern
