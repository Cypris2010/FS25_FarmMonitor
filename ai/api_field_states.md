# FS25 Field State APIs — Referenz

Implementiert via DensityMapModifier (Ansatz aus FS25_FarmlandOverview by Fetty42).
Aktueller Stand: v0.4.x — `FarmMonitor.lua`, Funktionen `exportFields`, `buildFieldSoilSamplers`, `computeSoilStatus`, `buildSoilFieldMask`, `initSoilState`, `stepSoilExport`.

## Hauptreferenz: FS25_FarmlandOverview (Fetty42)
- URL: https://www.farming-simulator.com/mod.php?mod_id=313618
- Zeigt den DensityMapModifier-Ansatz für alle Bodenzustände
- **Wichtig:** `field:getFieldState()` wird NICHT verwendet — stattdessen direkte Density-Map-Abfragen

---

## Farmland-Iteration

```lua
local farmId = g_currentMission:getFarmId()

for _, farmland in pairs(g_farmlandManager.farmlands or {}) do
    if farmland ~= nil
        and farmland.showOnFarmlandsScreen
        and farmland.field ~= nil
    then
        local owned = (farmland.farmId == farmId)
        farmland.areaInHa        -- Grundstücksfläche in ha (inkl. Straßen/Ränder)
        farmland.field.areaHa    -- reine Feldfläche in ha
        farmland.name            -- Feldnummer als String ("1", "12", …)
        farmland.id              -- numerische Farmland-ID
        farmland.farmId          -- Besitzer-Farm-ID (0 = niemand)
    end
end
```

**Wichtig:** Es werden ALLE sichtbaren Felder iteriert (owned + unowned).
Unowned Felder erhalten im Export nur Polygon + Position, keine Bodenanalyse.

---

## Feldpolygon

```lua
-- Statisches Polygon (Property, kein Methodenaufruf):
local poly = field.densityMapPolygon   -- für Export (points als Arrays)
if poly ~= nil and poly.pointsX ~= nil then
    for i, wx in ipairs(poly.pointsX) do
        local wz = poly.pointsZ[i]
        -- wx/wz = Weltkoordinaten
    end
end

-- Methoden-Aufruf für DensityMapModifier:
local poly = field:getDensityMapPolygon()   -- für applyToModifier()
poly:applyToModifier(modifier)
```

---

## Feldmittelpunkt

```lua
local cx, cz = field:getCenterOfFieldWorldPosition()
-- cx/cz können nil sein → immer prüfen
```

---

## Fruchttyp & Wachstumsstufe

```lua
if cx ~= nil then
    local ftIdx, gs = FSDensityMapUtil.getFruitTypeIndexAtWorldPos(cx, cz)
    if ftIdx ~= nil and ftIdx > 0 then
        local ft = g_fruitTypeManager:getFruitTypeByIndex(ftIdx)
        if ft ~= nil then
            ft.name                        -- interner Name (z.B. "WHEAT")
            ft.fillType.title              -- Anzeigename (z.B. "Weizen")
            gs                             -- aktueller Wachstums-Stage (Integer)
            ft.minHarvestingGrowthState    -- ab dieser Stufe erntereif
            ft.maxHarvestingGrowthState    -- letzte Erntestufe
            ft.cutState                    -- Haupt-Stage nach Ernte
            ft.cutStates                   -- Tabelle aller Schnitt-Stages {[stage]=true}
            ft.witheredState               -- Verwitterungsstufe

            -- Boolean-Klassifizierung:
            ft:getIsHarvestReady(gs)   -- erntereif?
            ft:getIsPreparable(gs)     -- Vorbereitung nötig (z.B. Raps walzen)?
            ft:getIsCut(gs)            -- abgeerntet/gemäht?
            ft:getIsWithered(gs)       -- vertrocknet?

            -- Saatgutbedarf:
            ft.seedUsagePerSqm         -- Liter/m² (kann nil sein)
            -- lph = ft.seedUsagePerSqm * 10000  → Liter/ha
        end
    end
end
```

**Sonderfall Post-Harvest-Stages:** Manche Mod-Früchte definieren Stages nach der Ernte
(z.B. Reifenspuren) mit `isCut=false`. Alle Stages oberhalb des höchsten bekannten
CutStage werden als "gemäht" behandelt:
```lua
if not harvestReady and not isCut and not withered and not needsPreparation then
    local maxCutStage = ft.cutState or 0
    if ft.cutStates then
        for k, _ in pairs(ft.cutStates) do
            if k > maxCutStage then maxCutStage = k end
        end
    end
    if maxCutStage > 0 and gs > maxCutStage then isCut = true end
end
```

---

## Density-Map Sampler aufbauen (`buildFieldSoilSamplers`)

Erzeugt pro Layer einen Sampler-Eintrag `{modifier, filter, maxValue}`.
Weed und Stone sind optional (mit `pcall` abgesichert).

```lua
local function buildFieldSoilSamplers()
    local fgs = g_currentMission.fieldGroundSystem
    if fgs == nil or FieldDensityMap == nil then return nil end

    local layers = {
        mulch = FieldDensityMap.STUBBLE_SHRED_LEVEL,
        plow  = FieldDensityMap.PLOW_LEVEL,
        roll  = FieldDensityMap.ROLLER_LEVEL,
        spray = FieldDensityMap.SPRAY_LEVEL,
        lime  = FieldDensityMap.LIME_LEVEL,
    }

    local samplers = {}
    for key, layerId in pairs(layers) do
        local mapId, firstCh, numCh = fgs:getDensityMapData(layerId)
        if mapId ~= nil then
            local modifier = DensityMapModifier.new(mapId, firstCh, numCh, g_terrainNode)
            local filter   = DensityMapFilter.new(modifier)
            local maxVal   = fgs:getMaxValue(layerId)   -- fgs.getMaxValue prüfen!
            samplers[key]  = { modifier = modifier, filter = filter, maxValue = maxVal }
        end
    end

    -- Weed optional (pcall weil System ggf. nicht immer vorhanden):
    if g_currentMission.weedSystem ~= nil then
        local ok, mapId, firstCh, numCh = pcall(function()
            return g_currentMission.weedSystem:getDensityMapData()
        end)
        if ok and mapId ~= nil then
            local mod = DensityMapModifier.new(mapId, firstCh, numCh, g_terrainNode)
            samplers.weed = { modifier = mod, filter = DensityMapFilter.new(mod), maxValue = 9 }
        end
    end

    -- Stone optional:
    if g_currentMission.stoneSystem ~= nil then
        local ok, mapId, firstCh, numCh = pcall(function()
            return g_currentMission.stoneSystem:getDensityMapData()
        end)
        if ok and mapId ~= nil then
            local mod = DensityMapModifier.new(mapId, firstCh, numCh, g_terrainNode)
            samplers.stone = { modifier = mod, filter = DensityMapFilter.new(mod) }
        end
    end

    return samplers
end
```

Layer-Konstanten (`FieldDensityMap.*`):

| Key | Konstante | Bedeutung | Wertebereich |
|---|---|---|---|
| `plow` | `PLOW_LEVEL` | Pflugzustand | 0/1 |
| `spray` | `SPRAY_LEVEL` | Düngung | 0/1/2 |
| `lime` | `LIME_LEVEL` | Kalk | 0/1/2/3 |
| `mulch` | `STUBBLE_SHRED_LEVEL` | Mulch | 0/1 |
| `roll` | `ROLLER_LEVEL` | Walze (1 = braucht Walze) | 0/1 |
| `weed` | weedSystem | Unkraut | 0–9 (penalizing: 3/4/5) |
| `stone` | stoneSystem | Steine | 0–4 (Steine: 2/3/4) |

---

## Prozentualen Flächenanteil berechnen (`computeSoilStatus`)

```lua
-- Polygon auf Modifier anwenden:
local function applyPolygon(field, modifier)
    local poly = field:getDensityMapPolygon()  -- Methoden-Aufruf!
    if poly == nil then return false end
    poly:applyToModifier(modifier)
    return true
end

-- Einzelwert abfragen:
local function areaForValue(modifier, filter, value)
    filter:setValueCompareParams(DensityValueCompareType.EQUAL, value)
    local _, area, total = modifier:executeGet(filter)
    return area or 0, total or 0
end

-- Prozentwert:
local function pct(area, total)
    if total == nil or total <= 0 then return 0 end
    return (area / total) * 100
end
```

---

## Schwellwert-Logik (implementiert in `computeSoilStatus`)

| Layer | Rückgabewert | Logik |
|---|---|---|
| **Mulch** | `s.mulchPct` (0–100) | Anteil mit Wert=1 |
| **Plow** | `s.plowPct` (0–100) | Anteil mit Wert=1 |
| **Roller** | `s.needsRollingPct` (0–100) | Anteil mit Wert=1 (hoher Wert = viel braucht Walze) |
| **Spray** | `s.fertPct` (0/50/100) | v=2 ≥ 90% → 100; v=2 > 0% und a1 ≥ a0 → 50; v=1 ≥ 90% → 50; sonst 0 |
| **Lime** | `s.limePct` (0/33.3/66.7/100) | v=3 ≥ 90% → 100; Dominanz von a0/a1/a2 → 0/33.3/66.7 |
| **Weed** | `s.weedPct` (0–100) | Anteil mit Werten 3+4+5 |
| **Stone** | `s.stonePct` (0–100) | Anteil mit Werten 2+3+4 |

Schwellwerte im Dashboard:
- Pflug/Mulch: `>= 90%` → ok
- Walze: `needsRollingPct <= 10%` → ok
- Unkraut: `>= 10%` → Warnung
- Steine: `>= 0.1%` → Warnung

---

## Ernte-Bonus (Yield Multiplier)

Respektiert Spieleinstellungen aus `missionInfo` — wenn z.B. Kalk nicht benötigt wird,
ist `limeF = 1` unabhängig vom tatsächlichen Kalkwert.

```lua
local yieldSettings = {
    plowingRequired = mission.missionInfo.plowingRequiredEnabled ~= false,
    limeRequired    = mission.missionInfo.limeRequired ~= false,
    weedsEnabled    = mission.missionInfo.weedsEnabled ~= false,
}

local sprayF  = (soil.fertPct or 0) / 100
local plowF   = (not yieldSettings.plowingRequired) and 1
                or (((soil.plowPct or 0) >= 90) and 1 or 0)
local limeF   = (not yieldSettings.limeRequired) and 1
                or ((soil.limePct or 0) / 100)
local weedPen = (not yieldSettings.weedsEnabled) and 0
                or ((soil.weedPct or 0) >= 10 and 1 or 0)
local weedBon = math.max(0, 1 - weedPen)   -- invertiert: 1 = kein Unkraut
local mulchF  = (((soil.mulchPct or 0) >= 90) and 1 or 0)
local rollF   = (((soil.needsRollingPct or 100) <= 10) and 1 or 0)

-- pcall weil engine-Funktion optional:
local ok, m = pcall(mission.getHarvestScaleMultiplier, mission,
    fruitTypeIndex, sprayF, plowF, limeF, weedBon, mulchF, rollF)
-- m = z.B. 1.15 → yieldBonusPct = +15.0%
if ok and type(m) == "number" then
    yieldBonusPct = MathUtil.round((m - 1.0) * 1000) / 10
end
```

---

## Materialbedarf (`fields.json`)

Sprühmengen aus `g_sprayTypeManager`:
```lua
local function sprayLph(name)
    local st = g_sprayTypeManager:getSprayTypeByName(name)  -- "LIME", "FERTILIZER", "HERBICIDE"
    if st == nil or st.litersPerSecond == nil then return 0 end
    return st.litersPerSecond * 36000  -- l/h
end
-- Gesamtmenge: lph * fieldAreaHa
```

Saatgutmenge aus FruitTypeDesc:
```lua
local lph   = ft.seedUsagePerSqm * 10000       -- l/ha
local total = lph * field.areaHa                -- Gesamtliter
```

---

## `fields.json` — Export-Struktur

Pro Feld:

| Feld | Typ | Bedeutung |
|---|---|---|
| `id` | string | Feldnummer (farmland.name) |
| `farmlandId` | int | Farmland-ID |
| `owned` | bool | Eigenes Feld? |
| `cx`, `cz` | number | Feldmittelpunkt (Weltkoordinaten) |
| `polygon.x`, `polygon.z` | Array | Feldumriss (Weltkoordinaten) |
| `area` | number | Grundstücksfläche in ha |
| `fieldArea` | number | Reine Feldfläche in ha (nur owned) |
| `fruitType` | string | Interner Fruchtname (z.B. "WHEAT") |
| `fruitTitle` | string | Anzeigename (z.B. "Weizen") |
| `growthStage` | int | Aktueller Wachstums-Stage |
| `minHarvest` | int | Erster erntereifer Stage |
| `maxHarvest` | int | Letzter erntereifer Stage |
| `harvestReady` | bool | Erntereif? |
| `needsPreparation` | bool | Vorbereitung nötig? |
| `withered` | bool | Vertrocknet? |
| `cut` | bool | Abgeerntet/gemäht? |
| `yieldBonusPct` | number\|nil | Ernte-Bonus in % (z.B. 15.0) |
| `mulchPct` | number | Gemulchte Fläche % |
| `plowPct` | number | Gepflügte Fläche % |
| `needsRollingPct` | number | Fläche die Walze braucht % |
| `fertPct` | number | Gedüngte Fläche (0/50/100) |
| `limePct` | number | Gekalkter Anteil (0/33.3/66.7/100) |
| `weedPct` | number | Unkrautbefall % |
| `stonePct` | number | Steinbedeckung % |
| `seedLph` | number\|nil | Saatgutbedarf l/ha |
| `seedTotal` | number\|nil | Saatgutbedarf total (l) |
| `matLimeLph` / `matLimeTotal` | number\|nil | Kalkbedarf l/ha und total |
| `matFertLph` / `matFertTotal` | number\|nil | Düngerbedarf l/ha und total |
| `matHerbLph` / `matHerbTotal` | number\|nil | Herbizid l/ha und total |

**Unowned Felder** erhalten nur: `id`, `farmlandId`, `owned:false`, `cx`, `cz`, `polygon`, `area`.

---

## `fieldMeta.json` — Bodenlayer-Maximalwerte (einmalig pro Session)

```json
{
  "savegameId": "...",
  "sprayLevelMax": 2,
  "limeLevelMax": 3,
  "plowLevelMax": 1,
  "stubbleShredLevelMax": 1,
  "weedStateMax": 15,
  "stoneLevelMax": 4
}
```

`weedStateMax` wird aus Kanal-Anzahl der Density-Map berechnet: `2^numCh - 1`.

---

## Karten-View: Grid-basierter Soil-Scan (`layer_*.json`)

Ergänzend zur Per-Feld-Analyse gibt es einen flächendeckenden Raster-Scan für
den Karten-View (Marching-Squares-Rendering im Dashboard).

### Konfiguration

```lua
FarmMonitor.soilScanMode  = "owned"   -- "owned" oder "all"
FarmMonitor.soilResolution = 128      -- Grid-Auflösung (128×128)
FarmMonitor.soilFieldMask = nil       -- Boolean-Array [zi*res+xi+1]
```

### Feldmaske (`buildSoilFieldMask`)

Bestimmt vorab welche Grid-Zellen innerhalb von Feldpolygonen liegen.
Alle anderen Zellen werden beim Scan übersprungen → ~80% weniger `executeGet`-Aufrufe.

**Algorithmus:**
1. Farmlands nach `soilScanMode` filtern (owned vs. alle)
2. Polygone aus `farmland.field.densityMapPolygon` laden (min. 3 Punkte)
3. Bounding-Box (AABB) pro Polygon berechnen
4. Für jede Grid-Zelle: erst AABB-Test (schnell), dann Ray-Casting Point-in-Polygon (genau)

```lua
local function pointInPolygon(wx, wz, px, pz)
    local inside = false
    local j = #px
    for i = 1, #px do
        if ((pz[i] > wz) ~= (pz[j] > wz)) and
           (wx < (px[j] - px[i]) * (wz - pz[i]) / (pz[j] - pz[i]) + px[i]) then
            inside = not inside
        end
        j = i
    end
    return inside
end
-- AABB-Vorfilter: if wx < p.minX or wx > p.maxX or wz < p.minZ or wz > p.maxZ then skip
```

### Scan-Layer (`initSoilState` + `stepSoilExport`)

Jeder Layer hat einen `noDataVal` — der Wert für Zellen außerhalb aller Felder.
Dieser muss semantisch korrekt sein damit Marching-Squares außerhalb der Felder
nichts rendert:

| Layer | noDataVal | Grund |
|---|---|---|
| weed | 0 | `above:true` — 0 = kein Unkraut (kein Overlay) |
| stone | 0 | `above:true` — 0 = keine Steine |
| plow | 255 | `above:false` — hoher Wert = gepflügt (kein Overlay) |
| spray | 255 | `above:false` — hoher Wert = gedüngt |
| lime | 255 | `above:false` — hoher Wert = gekalkt |
| mulch | 255 | `above:false` — hoher Wert = gemulcht |
| roller | 0 | `above:true` — 0 = braucht keine Walze |

```lua
-- In stepSoilExport: Maske prüfen, noDataVal schreiben statt scannen
if mask ~= nil and not mask[zi * res + xi + 1] then
    st.values[#st.values + 1] = layer.noDataVal   -- kein executeGet!
else
    -- ... DensityMapModifier scan ...
end
```

### IPC-Befehl `soilScan.setMode`

```xml
<command cmd="soilScan.setMode" mode="owned"/>
<command cmd="soilScan.setMode" mode="all"/>
```

Beim Empfang: `soilScanMode` setzen → Maske neu aufbauen → `soilState = nil` (Scan-Neustart).

---

## Wichtige Hinweise

- `field:getFieldState()` ist unzuverlässig — immer DensityMapModifier verwenden
- `buildFieldSoilSamplers()` wird pro Export-Zyklus neu aufgebaut (60s Intervall)
- Feldpolygon für DensityMapModifier: `field:getDensityMapPolygon()` (Methode), für Export: `field.densityMapPolygon` (Property)
- `DensityValueCompareType.EQUAL` ist der einzige verwendete Vergleichstyp
- Weed/Stone-System mit `pcall` absichern — nicht auf allen Karten vorhanden
- Farmland-Iteration iteriert immer ALLE Felder; `owned`-Flag im Exportobjekt unterscheidet
