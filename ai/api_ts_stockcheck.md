# FS25 TSStockCheck — API Referenz

Quelle: FS25_TSStockCheck (Time Saving Stock Check) von twproductions  
Hauptdatei: `gui/InGameMenuTSStockCheck.lua`

## Lagermengen — alle Quellen

### 1. Silos
```lua
thisPlaceable.spec_silo.storages[n].fillLevels  -- {fillTypeIndex → fillLevel}
-- ownerFarmId check: thisStorage.ownerFarmId == g_currentMission:getFarmId()
```

### 2. Silo-Erweiterungen
```lua
thisPlaceable.spec_siloExtension.storage.fillLevels
```

### 3. Tierställe (Husbandry Outputs)
```lua
thisPlaceable.spec_husbandry.storage.fillLevels
-- nur wenn: spec_husbandry.loadingStation.supportedFillTypes[fillTypeIndex] == true
```

### 4. Bienenstock-Paletten
```lua
thisPlaceable.spec_beehivePalletSpawner.fillType       -- fillTypeIndex
thisPlaceable.spec_beehivePalletSpawner.pendingLiters  -- Menge
```

### 5. Mistlager (Manure Heap)
```lua
thisPlaceable.spec_manureHeap.manureHeap.fillLevels
```

### 6. Fahrsilo (Bunker Silo) — mit Fermentierungsstatus
```lua
local bunkerSilo = thisPlaceable.spec_bunkerSilo.bunkerSilo
bunkerSilo.inputFillType      -- Eingangsfülltyp
bunkerSilo.outputFillType     -- Ausgangsfülltyp (nach Fermentierung)
bunkerSilo.fillLevel
bunkerSilo.fermentingPercent
bunkerSilo.compactedPercent
bunkerSilo.state  -- BunkerSilo.STATE_FILL / STATE_CLOSED / STATE_DRAIN / STATE_FERMENTED
-- Bei STATE_DRAIN/FERMENTED → outputFillType verwenden statt inputFillType
```

### 7. Object Storage Mod (z.B. Ballenlager-Mods)
```lua
thisPlaceable.spec_objectStorageMod.objectStorage.storageAreasByFillType
-- [fillTypeIndex][someNum].objects[x]
-- object.fillType, object.fillLevel
-- object.isFermenting, object.fermentingPercentage
```

### 8. Giants Object Storage (Vanilla-Paletten/Ballenlager)
```lua
thisPlaceable.spec_objectStorage.objectInfos[n]
-- objectInfo.objects[x]:
--   object.baleAttributes.fillLevel / .fillType / .uniqueId
--   object.baleObject.fillLevel / .fillType / .isFermenting / .fermentingPercentage
--   object.palletAttributes.fillLevel / .fillType
-- Achtung: numObjects vs #objects für Server-Modus berücksichtigen
```

### 9. Produktions-Outputs
```lua
g_currentMission.productionChainManager.productionPoints[v]
thisProd.outputFillTypeIdsArray[x]  -- fillTypeIndex
thisProd.storage:getFillLevel(fillType)
thisProd:getOwnerFarmId()
```

### 10. Loose Paletten & Shipping Container
```lua
g_currentMission.vehicleSystem.vehicles
vehicle.isPallet
vehicle.spec_fillUnit.fillUnits[1].fillType
vehicle.spec_fillUnit.fillUnits[1].fillLevel
vehicle.spec_woodContainer ~= nil  -- → Shipping Container
```

### 11. Loose Ballen
```lua
g_currentMission.itemSystem.itemsToSave
bale = item.item
bale:isa(Bale)
bale.fillType, bale.fillLevel
bale.isFermenting, bale.fermentingPercentage
bale.uniqueId  -- zur Deduplizierung mit Object Storage!
```

## Preise

### Aktueller Preis
```lua
local priceMultiplier = EconomyManager.getPriceMultiplier()
filltype.pricePerLiter * priceMultiplier          -- Basispreis
station:getEffectiveFillTypePrice(fillType)       -- echter Preis an Station
```

### Maximalpreis (über alle 12 Perioden)
```lua
for period = SeasonPeriod.EARLY_SPRING, SeasonPeriod.LATE_WINTER do
    local periodprice = fillType.pricePerLiter * (fillType.economy.factors[period] or 1.0)
end
```

### Preistrend
```lua
station:getCurrentPricingTrend(fillType)
Utils.isBitSet(trend, SellingStation.PRICE_FALLING)
Utils.isBitSet(trend, SellingStation.PRICE_CLIMBING)
Utils.isBitSet(trend, SellingStation.PRICE_GREAT_DEMAND)
station.greatDemandFillType  -- welcher Fülltyp gerade Hochnachfrage hat
```

## Verkaufsstationen

```lua
g_currentMission.storageSystem:getUnloadingStations()
station:isa(SellingStation)
station.hideFromPricesMenu
station.acceptedFillTypes             -- {fillTypeIndex → true/false}
station:getName()
station.ownerFarmId ~= g_currentMission:getFarmId()  -- nicht eigene Station
```

## Farbcodes Preisanzeige
- **Blau** (great): currentValue >= maxValue (≥ 100%)
- **Dunkelgrün** (up): currentValue >= maxValue * 0.95
- **Hellgelb** (over): currentValue >= maxValue * 0.90
- **Weiß** (normal): unter 90%

## Wichtige Hinweise
- uniqueId-Deduplizierung zwischen Object Storage und Ballen-Liste notwendig
- Bunker Silo: bei STATE_DRAIN/FERMENTED outputFillType statt inputFillType verwenden
- FarmId-Check immer: `ownerFarmId == g_currentMission:getFarmId()`
- `g_currentMission.missionInfo.economicDifficulty` für Schwierigkeitsgrad
