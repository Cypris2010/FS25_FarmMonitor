# FS25 Field State APIs — Referenz

Relevant für v0.5.0 Feldübersicht.

## Hauptreferenz: additionalFieldInfo Mod
- URL: https://github.com/yumi-modding/FS25_additionalFieldInfo
- Zeigt wie man über `g_farmlandManager.farmlands` iteriert
- Key APIs: `data.lastFruitTypeIndex`, `data.lastGrowthState`, `fruitType.growthStateToName`, `data:getHarvestScaleMultiplier()`

## Offizielle FS25 Lua API
- URL: https://github.com/MyGameSteamOfficial/fs25-lua-api
- `field:getFieldState()` gibt Objekt mit allen Feldzuständen

## Weitere Quellen
- GIANTS LUADOC: https://gdn.giants-software.com/thread.php?categoryId=3&threadId=15711
- BetterContracts (Praxisbeispiel): https://github.com/Mmtrx/FS25_BetterContracts/blob/main/betterContracts.lua
- FSDensityMapUtil (rohe N/P/K Werte): https://gdn.giants-software.com/thread.php?categoryId=22&threadId=8834

## Verfügbare Feldzustände

### Basis (immer verfügbar via field:getFieldState())
```lua
fieldState.plowLevel         -- Pflugzustand
fieldState.sprayLevel        -- Düngezustand (allgemein)
fieldState.limeLevel         -- Kalkzustand
fieldState.weedState         -- Unkraut
fieldState.weedFactor
fieldState.stubbleShredLevel -- Mulchzustand
fieldState.stoneLevel        -- Steine
fieldState.waterLevel        -- Bodenfeuchtigkeit (Basis)
```

### Nur mit PrecisionFarming DLC
```lua
-- Prüfung:
if g_modIsLoaded["FS25_precisionFarming"] then
    -- N/P/K Werte (Stickstoff, Phosphor, Kalium)
    -- Detaillierte Bodenfeuchtigkeit
end
```
