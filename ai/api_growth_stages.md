# FS25 Growth Stages — API Referenz

Relevant für v0.6.0 Feldübersicht.

## Quellen
- GDN LUADOC FruitTypeDesc: https://gdn.giants-software.com/documentation_scripting_fs25.php?version=script&category=37&class=416
- additionalFieldInfo (Praxisbeispiel): https://github.com/yumi-modding/FS25_additionalFieldInfo
- ContractBoost (Praxisbeispiel): https://github.com/GMNGjoy/FS25_ContractBoost
- SDK Stubs (Methodensignaturen): https://github.com/rtmnet/sdk / https://github.com/MyGameSteamOfficial/fs25-lua-api

## Grundprinzip

Growth Stages sind **pro Fruchttyp unterschiedlich** — Werte und Namen kommen aus der jeweiligen Frucht-XML.
Es gibt keine global gültige Zahl-zu-Bedeutung-Tabelle.
`numGrowthStates` = Grenze zwischen "wächst noch" und "Sonderzustand".

## State-Sequenz (vollständig)

```
0                                          → Feld leer (keine Saat)
1 … numGrowthStates                        → Wachstum (isGrowing = true in XML)

--- für Früchte OHNE Vorbereitungsschritt ---
minHarvestingGrowthState                   → erster erntereifer Stage
  …
maxHarvestingGrowthState                   → letzter erntereifer Stage

--- für Früchte MIT Vorbereitungsschritt (z.B. Raps) ---
minPreparingGrowthState                    → Vorbereitung nötig (Walzen)
  …
maxPreparingGrowthState
preparedGrowthState                        → vorbereitet → jetzt erntereif

--- immer danach ---
witheredState                              → vertrocknet (Erntzeit verpasst)
cutState / cutStates[n]                    → abgeerntet / gemäht

--- nur bei nachwachsenden Pflanzen (Gras, Ackergras) ---
firstRegrowthState … numGrowthStates       → nachwächst
```

## Attribute auf FruitTypeDesc

```lua
local ft = g_fruitTypeManager:getFruitTypeByIndex(fieldState.fruitTypeIndex)

ft.numGrowthStates           -- Anzahl echter Wachstums-Stages (isGrowing=true)
ft.minHarvestingGrowthState  -- erster erntereifer Stage
ft.maxHarvestingGrowthState  -- letzter erntereifer Stage
ft.minForageGrowthState      -- Grünfutter-Ernte ab hier
ft.maxForageGrowthState      -- Grünfutter-Ernte bis hier
ft.minPreparingGrowthState   -- Vorbereitung ab hier (-1 wenn nicht vorhanden)
ft.maxPreparingGrowthState   -- Vorbereitung bis hier
ft.preparedGrowthState       -- Stage nach Vorbereitung
ft.witheredState             -- vertrocknet (integer)
ft.cutState                  -- Haupt-Schnitt-Stage (integer)
ft.cutStates                 -- Tabelle aller Schnitt-Stages {[stage]=true}
ft.mulchedState              -- gemulcht
ft.rolledCutState            -- gewalzt nach Schnitt
ft.firstRegrowthState        -- erster Nachwuchs-Stage
ft.regrows                   -- bool: wächst nach?
ft.growthStateToName         -- {[integer] → string} State-Name aus XML
ft.nameToGrowthState         -- {[string] → integer} Rückwärts-Lookup
```

## Boolean-Methoden (robuster als growthStateToName-Strings)

```lua
ft:getIsGrowing(s)      -- true wenn 0 < s <= numGrowthStates (und < minPreparing)
ft:getIsHarvestable(s)  -- true wenn erntebar (harvestReady und nicht withered)
ft:getIsHarvestReady(s) -- true wenn spezifisch in Ernte-Stage
ft:getIsWithered(s)     -- true wenn vertrocknet
ft:getIsCut(s)          -- true wenn gemäht/abgeerntet
ft:getIsPreparable(s)   -- true wenn Vorbereitung nötig (Raps walzen)
ft:getIsHarvestableInPeriod(growthMode, seasonPeriod)
ft:getIsPlantableInPeriod(growthMode, seasonPeriod)
ft:getGrowthStateName(s)           -- gibt State-Name-String zurück
ft:getGrowthStateByName("name")    -- gibt State-Integer zurück
```

## Bestätigte growthStateToName-Strings (aus Mod-Code)

| String | Bedeutung | Quelle |
|---|---|---|
| `"harvestReady"` | Erntereifer Stage | additionalFieldInfo |
| `"greenBig"` | Gras groß (erntereif) | ContractBoost |
| `"HARVESTED"` | Nach Ernte (als nameToGrowthState-Key) | ContractBoost |

**Wichtig:** Die String-Namen sind fruchttyp-spezifisch und XML-definiert.
Für produktiven Code lieber die Boolean-Methoden verwenden.

## Empfohlenes State-Klassifizierungs-Pattern für v0.6.0

```lua
local function classifyGrowthState(ft, s)
    if s == 0 then
        return "empty"
    elseif ft:getIsWithered(s) then
        return "withered"
    elseif ft:getIsCut(s) then
        return "cut"
    elseif ft:getIsHarvestReady(s) then
        return "harvestReady"
    elseif ft:getIsPreparable(s) then
        return "needsPreparation"
    elseif ft:getIsGrowing(s) then
        return "growing"
    else
        return "unknown"  -- sollte nicht vorkommen
    end
end

-- Wachstumsfortschritt (nur wenn growing):
local progress = s / ft.numGrowthStates  -- 0.0 – 1.0
```

## Zugriff auf Felddaten

```lua
for _, farmland in pairs(g_farmlandManager.farmlands) do
    if farmland.isOwned and farmland.field ~= nil then
        local data = farmland.field.fieldState   -- oder field:getFieldState()
        local fruitTypeIndex = data.lastFruitTypeIndex  -- oder fruitTypeIndex
        local growthState    = data.lastGrowthState     -- oder growthState
        local ft = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)

        if ft ~= nil then
            local class    = classifyGrowthState(ft, growthState)
            local progress = (class == "growing") and (growthState / ft.numGrowthStates) or nil
            local harvest  = data:getHarvestScaleMultiplier()  -- potenzielle Ernte
        end
    end
end
```
