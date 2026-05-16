# FS25 Field State APIs — Referenz

Implementiert in v0.6.0 via DensityMapModifier (Ansatz aus FS25_FarmlandOverview by Fetty42).

## Hauptreferenz: FS25_FarmlandOverview (Fetty42)
- URL: https://www.farming-simulator.com/mod.php?mod_id=313618
- Zeigt den DensityMapModifier-Ansatz für alle Bodenzustände
- **Wichtig:** `field:getFieldState()` wird NICHT verwendet — stattdessen direkte Density-Map-Abfragen

## Farmland-Iteration

```lua
for _, farmland in pairs(g_farmlandManager.farmlands or {}) do
    if farmland.showOnFarmlandsScreen
        and farmland.farmId == g_currentMission:getFarmId()
        and farmland.field ~= nil
    then
        farmland.areaInHa        -- Grundstücksfläche in ha
        farmland.field.areaHa    -- Feldfläche in ha
        farmland.name            -- Feldnummer als String
        farmland.farmId          -- Besitzer-Farm-ID
    end
end
```

## Fruchttyp & Wachstumsstufe

```lua
local x, z = field:getCenterOfFieldWorldPosition()
local fruitTypeIndex, growthStage = FSDensityMapUtil.getFruitTypeIndexAtWorldPos(x, z)
local ft = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)

ft.name                        -- interner Name (z.B. "WHEAT")
ft.fillType.title              -- Anzeigename (z.B. "Weizen")
ft.minHarvestingGrowthState    -- ab dieser Stufe erntereif
ft.maxHarvestingGrowthState    -- letzte Erntestufe
ft.cutState                    -- Stufe nach Ernte (gemäht)
ft.witheredState               -- Verwitterungsstufe
ft.minPreparingGrowthState     -- Vorbereitungsphase (z.B. Mais)
ft.maxPreparingGrowthState
ft.literPerSqm                 -- Ertrag in Liter/m²
```

## Density-Map Sampler aufbauen

```lua
local fgs = g_currentMission.fieldGroundSystem
-- Layer abrufen:
local mapId, firstCh, numCh = fgs:getDensityMapData(FieldDensityMap.PLOW_LEVEL)
local modifier = DensityMapModifier.new(mapId, firstCh, numCh, g_terrainNode)
local filter   = DensityMapFilter.new(modifier)
local maxVal   = fgs:getMaxValue(FieldDensityMap.PLOW_LEVEL)
```

Verfügbare Layer-Konstanten (`FieldDensityMap.*`):

| Konstante | Bedeutung | Wertebereich |
|---|---|---|
| `PLOW_LEVEL` | Pflugzustand | 0/1 |
| `SPRAY_LEVEL` | Düngung | 0/1/2 |
| `LIME_LEVEL` | Kalk | 0/1/2/3 |
| `STUBBLE_SHRED_LEVEL` | Mulch | 0/1 |
| `ROLLER_LEVEL` | Walze (1 = muss noch gewalzt werden) | 0/1 |

Unkraut und Steine separat:
```lua
local mapId, firstCh, numCh = g_currentMission.weedSystem:getDensityMapData()
local mapId, firstCh, numCh = g_currentMission.stoneSystem:getDensityMapData()
-- Steine: Werte 2/3/4 = vorhandene Steine, 1 = keine
```

## Prozentualen Flächenanteil berechnen

```lua
-- Polygon des Feldes auf den Modifier anwenden:
field:getDensityMapPolygon():applyToModifier(modifier)

-- Fläche für einen bestimmten Wert ermitteln:
filter:setValueCompareParams(DensityValueCompareType.EQUAL, value)
local _, area, totalArea = modifier:executeGet(filter)
local pct = (area / totalArea) * 100
```

## Schwellwert-Logik (wie FS25_FarmlandOverview)

| Status | Logik |
|---|---|
| **Pflug** | `plowPct >= 90` → ok |
| **Dünger** | `v=2 >= 90%` → 100%; `v=2 > 0%` → 50%; `v=1 >= 90%` → 50%; sonst 0% |
| **Kalk** | `v=3 >= 90%` → 100%; Dominanz von v=0/1/2 → 0/33.3/66.7% |
| **Mulch** | `mulchPct >= 90` → ok |
| **Walze** | `needsRollingPct <= 10` → gewalzt (Wert 1 = braucht Walze) |
| **Unkraut** | Werte 3+4+5 = penalizing; `>= 10%` → Warnung |
| **Steine** | Werte 2+3+4 = Steine vorhanden; `>= 0.1%` → Warnung |

## Ernte-Bonus (Yield Multiplier)

```lua
-- 7 Parameter: fruitTypeIndex, fert(0-1), plow(0/1), lime(0-1), weedBonus(0-1), mulch(0/1), roll(0/1)
local ok, m = pcall(g_currentMission.getHarvestScaleMultiplier, g_currentMission,
    fruitTypeIndex, sprayF, plowF, limeF, weedBonusF, mulchFlag, rollFlag)
-- Gibt z.B. 1.15 zurück → +15% Bonus
-- weedBonusF = 1 - weedPenaltyFactor (invertiert!)
```

## Wichtige Hinweise

- `field:getFieldState()` funktioniert möglicherweise nicht zuverlässig — DensityMapModifier ist der robuste Weg
- Density Maps müssen einmal pro Export-Zyklus aufgebaut werden (`buildFieldSoilSamplers()`)
- `DensityValueCompareType.EQUAL` ist der einzige verwendete Vergleichstyp
- Feldpolygon muss vor jeder Messung neu per `applyToModifier()` gesetzt werden
