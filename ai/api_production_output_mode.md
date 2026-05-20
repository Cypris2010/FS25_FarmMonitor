# FS25 ProductionPoint — Output Distribution Mode API

## Ausgangsmodus lesen

```lua
local mode = pp:getOutputDistributionMode(fillTypeId)
```

## Ausgangsmodus setzen

```lua
pp:setOutputDistributionMode(fillTypeId, newMode)
```

Mit MP-Synchronisation (bevorzugt):
```lua
ProductionPointOutputModeEvent.sendEvent(pp, fillTypeId, newMode, noEventSend)
```

## Verfügbare Konstanten

| Konstante | Bedeutung |
|---|---|
| `ProductionPoint.OUTPUT_MODE.DIRECT_SELL` | Direktverkauf (Gebühr je nach Schwierigkeitsgrad) |
| `ProductionPoint.OUTPUT_MODE.AUTO_DELIVER` | Automatisch liefern an andere Produktionen |
| `ProductionPoint.OUTPUT_MODE.STORE` | Paletten produzieren / einlagern |
| `ProductionPoint.OUTPUT_MODE.KEEP` | Im angeschlossenen Silo lagern |

## Placeable direkt per uniqueId ansprechen

`PlaceableSystem` führt intern eine Hash-Map — O(1)-Lookup, kein Loop nötig.
Die `uniqueId` aus dem Dashboard (`placeable:getUniqueId()`) ist exakt der Key.

```lua
local placeable = g_currentMission.placeableSystem:getPlaceableByUniqueId(uniqueId)

if placeable ~= nil and placeable.spec_productionPoint ~= nil then
    local pp = placeable.spec_productionPoint.productionPoint
    pp:setOutputDistributionMode(fillTypeId, ProductionPoint.OUTPUT_MODE.STORE)
end
```

## Hinweise

- `getUniqueId()` gibt einen **String** zurück (kein Integer, kein Node-Handle)
- Ist persistent über Save/Load-Zyklen
- Analog: `g_currentMission.vehicleSystem:getVehicleByUniqueId(uniqueId)` für Fahrzeuge
- `nodeId` (I3D Scene Graph) ist **nicht** geeignet — ändert sich bei Szenen-Reload
- `NetworkUtil.getObjectId()` ist für Netzwerk-Sync gedacht, nicht für persistente Referenzen
