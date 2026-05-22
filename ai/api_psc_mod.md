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
