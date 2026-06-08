# FS25 ProductionStorageControl (PSC) — API Referenz

Mod von: braeven · Version: 1.0.1.0  
Pfad: `~/Library/Application Support/FarmingSimulator2025/mods/FS25_ProductionStorageControl/`

## Was der Mod tut

PSC erweitert alle Produktionsanlagen um:
- Einen vierten Ausgangsmodus **Einlagern** (`STORE`) — Ware bleibt im Produktionslager, keine Paletten werden gespawnt
- Manuelles Spawnen von Paletten auf Knopfdruck
- Der Vanilla-Modus `KEEP` (Auslagern) wird im Spiel in „Spawnen" umbenannt

---

## Erkennung im Lua-Mod

```lua
local hasPSC = g_modIsLoaded["FS25_ProductionStorageControl"]
```

Dieser Check muss vor jedem Zugriff auf `OUTPUT_MODE.STORE` erfolgen — ohne PSC ist die Konstante `nil`.

---

## Neuer Output-Mode-Konstante

```lua
-- PSC setzt dies global:
ProductionPoint.OUTPUT_MODE.STORE = 3
```

Vanilla-Werte (zur Referenz):

| Konstante | Wert | Bedeutung |
|---|---|---|
| `ProductionPoint.OUTPUT_MODE.KEEP` | 0 | Auslagern (Paletten spawnen) |
| `ProductionPoint.OUTPUT_MODE.DIRECT_SELL` | 1 | Direktverkauf |
| `ProductionPoint.OUTPUT_MODE.AUTO_DELIVER` | 2 | Automatisch liefern |
| `ProductionPoint.OUTPUT_MODE.STORE` | 3 | **Einlagern (PSC)** |

---

## Internes State-Tracking

PSC verwaltet STORE-Einträge in einer eigenen Tabelle auf dem ProductionPoint:

```lua
pp.outputFillTypeIdsStorage   -- {fillTypeIndex → true} für alle STORE-Ausgänge
```

`getOutputDistributionMode` / `setOutputDistributionMode` sind von PSC überschrieben und beziehen sich auf diese Tabelle.

---

## Ausgangsmodus lesen (mit PSC)

```lua
local m = pp:getOutputDistributionMode(fillTypeId)
local mode = "keep"
if m == ProductionPoint.OUTPUT_MODE.DIRECT_SELL then mode = "sell"
elseif m == ProductionPoint.OUTPUT_MODE.AUTO_DELIVER then mode = "deliver"
elseif hasPSC and m == ProductionPoint.OUTPUT_MODE.STORE then mode = "store"
end
```

---

## Ausgangsmodus setzen (mit MP-Sync)

```lua
pp:setOutputDistributionMode(fillTypeId, ProductionPoint.OUTPUT_MODE.STORE)
ProductionPointOutputModeEvent.sendEvent(pp, fillTypeId, ProductionPoint.OUTPUT_MODE.STORE, true)
```

**Wichtig:** `setOutputDistributionMode` direkt aufrufen — `sendEvent` allein hat in Singleplayer keine Wirkung.

---

## Savegame-Persistenz

PSC registriert eigene Savegame-Pfade (`storageFillType`) und serialisiert `outputFillTypeIdsStorage` in die Savegame-XML. Der Modus wird beim Laden korrekt wiederhergestellt.

---

## Dashboard-Integration

### goods.json

Das Root-Objekt von `goods.json` enthält ein `hasPSC`-Flag:

```json
{ "hasPSC": true, "goods": [...] }
```

Dieses Flag wird im Dashboard verwendet, um den STORE-Modus im „Ausgangsmodus wählen"-Modal anzuzeigen oder auszublenden.

### storageLocations

Lagerorte die Produktionsausgänge sind, enthalten bei aktivem PSC auch `"store"` als möglichen `outputMode`:

```json
{
  "uniqueId": "placeable...",
  "name": "Meierei",
  "liters": 5000,
  "sourceType": "production",
  "ppUniqueId": "placeable...",
  "fillType": "BUTTER",
  "outputMode": "store"
}
```

---

## Cooldown-Mechanismus

PSC setzt beim Umschalten des Modus einen 4-Sekunden-Cooldown auf den PalletSpawner (`palletSpawnCooldown = g_time + 4000`), damit nicht versehentlich Paletten gespawnt werden.

---

## Paletten-Spawn: production.spawnPallets

### Lua-Sandbox-Problem

PSC's `productionStorageControl_EventSpawn` ist eine globale Variable **in PSC's eigenem `_ENV`**. FarmMonitor kann sie nicht referenzieren — der Zugriff ergibt immer `nil`, auch wenn `g_modIsLoaded["FS25_ProductionStorageControl"] == true`.

### Prototype-Erweiterung (sichtbar für alle Mods)

PSC fügt `ProductionPoint:ReceiveSpawnEvent(...)` als Methode auf dem globalen Prototype hinzu. Diese ist von FarmMonitor aus aufrufbar:

```lua
pp:ReceiveSpawnEvent(
    ownerFarmId, fillTypeIndex, pendingLiters,
    width, height, length,
    capacity, type,        -- type=1 für Palette via ft.pallets[customEnvironment]
    customEnvironment,     -- Environment-Key (z.B. "VANILLA" oder Mod-Name)
    treeId,                -- nil für normale Paletten
    amount,
    color1, color2, color3 -- 0, 0, 0 für Standardfarben
)
```

**Wichtig:** `customEnvironment` muss der **tatsächliche Key** aus `fillType.pallets` sein (z.B. `"VANILLA"`, `"FS25_SomeMod"`), nicht hardcoded `"VANILLA"`. Falscher Key → `item.filename = nil` → stiller Spawn-Fehlschlag.

### PalletInfoCache — Korrekte customEnvironment-Ermittlung

```lua
-- RICHTIG: tatsächlichen Key speichern
local palletKey  = "VANILLA"
local palletFile = ft.pallets["VANILLA"]
if palletFile == nil then
    for k, f in pairs(ft.pallets) do palletKey = k; palletFile = f; break end
end
-- palletKey in Cache speichern, nicht hardcoded "VANILLA"
```

### Multiplayer-Architektur (SP / Listen-Server / Dedicated Server)

Das Problem: `g_currentMission.placeableSystem:getPlaceableByUniqueId(uniqueId)` schlägt auf dem Dedicated Server fehl wenn die `uniqueId` vom Client kommt — die IDs stimmen prozessübergreifend nicht überein (gleiches Problem wie `vehicle.rootNode`).

**Lösung: `NetworkUtil.writeNodeObject/readNodeObject` für `pp`** — exakt wie PSC's eigenes Event:

```
Singleplayer / Listen-Server-Host (g_server ~= nil):
  → pp lokal auflösen → ReceiveSpawnEvent() direkt aufrufen ✅

MP-Client / Dedicated-Server-Joiner (g_server == nil, g_client ~= nil):
  → pp lokal auflösen (klappt auf eigenem Prozess)
  → FarmMonitorSpawnPalletsEvent.new(pp, ...) senden
  → Server empfängt Event, liest pp via NetworkUtil.readNodeObject()
  → Server ruft pp:ReceiveSpawnEvent() direkt auf ✅ (kein uniqueId-Lookup!)
```

### FarmMonitorSpawnPalletsEvent (Kurzreferenz)

```lua
-- Senden (Client):
conn:sendEvent(FarmMonitorSpawnPalletsEvent.new(
    pp, farmId, ft.index, pendingLiters,
    info.width, info.height, info.length,
    info.capacity, info.customEnvironment, amount
))

-- writeStream:
NetworkUtil.writeNodeObject(streamId, self.pp)  -- ← Kern-Fix: kein uniqueId-String
streamWriteInt32  / Float32 / Bool / String  -- farmId, fillTypeIndex, pendingLiters, ...

-- readStream (Server):
self.pp = NetworkUtil.readNodeObject(streamId)  -- pp direkt, ohne Lookup

-- run (Server):
self.pp:ReceiveSpawnEvent(self.farmId, self.fillTypeIndex, self.pendingLiters, ...)
```
