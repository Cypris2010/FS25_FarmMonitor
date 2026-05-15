-- FarmMonitor.lua
-- Collects data from silos, productions and animal husbandries,
-- then writes each category to its own JSON file in the modSettings directory.

local modName = g_currentModName  -- capture before it gets reset

FarmMonitor = {}
FarmMonitor.updateInterval    = 10000  -- milliseconds between exports
FarmMonitor.timer             = 0
FarmMonitor.paths             = {}
FarmMonitor.fillTypesExported   = false
FarmMonitor.animalFoodExported  = false
FarmMonitor.fieldMetaExported   = false
FarmMonitor.savegameName        = nil
FarmMonitor.savegameId          = nil
FarmMonitor.savegameDirectory   = nil

addModEventListener(FarmMonitor)

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function FarmMonitor:loadMap(name)
    local outputDir = getUserProfileAppPath() .. "modSettings/" .. modName .. "/"
    createFolder(outputDir)

    FarmMonitor.paths.silos       = outputDir .. "silos.json"
    FarmMonitor.paths.productions = outputDir .. "productions.json"
    FarmMonitor.paths.husbandries = outputDir .. "husbandries.json"
    FarmMonitor.paths.fillTypes   = outputDir .. "fillTypes.json"
    FarmMonitor.paths.animalFood  = outputDir .. "animalFood.json"
    FarmMonitor.paths.fieldMeta   = outputDir .. "fieldMeta.json"
    FarmMonitor.paths.goods       = outputDir .. "goods.json"
    FarmMonitor.paths.fields      = outputDir .. "fields.json"
    print("[FarmMonitor] Mod loaded. Output directory: " .. outputDir)
end

function FarmMonitor:deleteMap()
end

function FarmMonitor:update(dt)
    if g_currentMission == nil or not g_currentMission.isMissionStarted then
        return
    end
    if g_dedicatedServer ~= nil then return end

    -- Detect savegame change: reset state so files are re-exported for the new savegame
    local currentDir = g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory
    if currentDir ~= FarmMonitor.savegameDirectory then
        FarmMonitor.savegameDirectory  = currentDir
        FarmMonitor.savegameName       = nil
        FarmMonitor.savegameId         = nil
        FarmMonitor.fillTypesExported  = false
        FarmMonitor.animalFoodExported = false
        FarmMonitor.fieldMetaExported  = false
        FarmMonitor.timer              = 0
    end

    if FarmMonitor.savegameName == nil then
        FarmMonitor.savegameName, FarmMonitor.savegameId = FarmMonitor:readSavegameInfo()
    end

    if not FarmMonitor.fillTypesExported then
        FarmMonitor:exportFillTypes()
        FarmMonitor.fillTypesExported = true
    end

    if not FarmMonitor.animalFoodExported then
        FarmMonitor:exportAnimalFood()
        FarmMonitor.animalFoodExported = true
    end

    if not FarmMonitor.fieldMetaExported then
        FarmMonitor:exportFieldMeta()
        FarmMonitor.fieldMetaExported = true
    end

    FarmMonitor.timer = FarmMonitor.timer + dt
    if FarmMonitor.timer >= FarmMonitor.updateInterval then
        FarmMonitor.timer = 0
        FarmMonitor:collectAndSave()
    end
end

function FarmMonitor:draw() end
function FarmMonitor:mouseEvent(posX, posY, isDown, isUp, button) end
function FarmMonitor:keyEvent(unicode, sym, modifier, isDown) end

-- ---------------------------------------------------------------------------
-- Data collection
-- ---------------------------------------------------------------------------

function FarmMonitor:writeJSON(path, data)
    local file = io.open(path, "w")
    if file then
        file:write(FarmMonitor:encodeJSON(data))
        file:close()
    else
        print("[FarmMonitor] ERROR: Could not open file: " .. path)
    end
end

function FarmMonitor:collectAndSave()
    local ok, err = pcall(function()
        local ts           = getDate("%Y-%m-%dT%H:%M:%S")
        local farmId       = g_currentMission:getFarmId()
        local savegameName = FarmMonitor.savegameName
        local savegameId   = FarmMonitor.savegameId

        FarmMonitor:writeJSON(FarmMonitor.paths.silos, FarmMonitor.obj(
            "timestamp", ts, "farmId", farmId, "savegame", savegameName, "savegameId", savegameId,
            "silos",     FarmMonitor:collectSilos()
        ))
        FarmMonitor:writeJSON(FarmMonitor.paths.productions, FarmMonitor.obj(
            "timestamp",   ts, "farmId", farmId, "savegame", savegameName, "savegameId", savegameId,
            "productions", FarmMonitor:collectProductions()
        ))
        FarmMonitor:writeJSON(FarmMonitor.paths.husbandries, FarmMonitor.obj(
            "timestamp",   ts, "farmId", farmId, "savegame", savegameName, "savegameId", savegameId,
            "husbandries", FarmMonitor:collectHusbandries()
        ))
        FarmMonitor:writeJSON(FarmMonitor.paths.goods, FarmMonitor.obj(
            "timestamp", ts, "farmId", farmId, "savegame", savegameName, "savegameId", savegameId,
            "goods",     FarmMonitor:collectGoods()
        ))
        FarmMonitor:writeJSON(FarmMonitor.paths.fields, FarmMonitor.obj(
            "timestamp", ts, "farmId", farmId, "savegame", savegameName, "savegameId", savegameId,
            "fields",    FarmMonitor:collectFields()
        ))
    end)

    if not ok then
        print("[FarmMonitor] ERROR during collect: " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- FillType registry  (written once on first update)
-- ---------------------------------------------------------------------------

function FarmMonitor:exportFillTypes()
    local ok, err = pcall(function()
        local entries = {}
        local fillTypes = g_fillTypeManager.fillTypes
        if fillTypes == nil then return end

        for _, ft in ipairs(fillTypes) do
            if ft ~= nil and ft.name ~= nil then
                table.insert(entries, FarmMonitor.obj(
                    "name",               ft.name,
                    "title",              ft.title or ft.name,
                    "hudOverlayFilename", ft.hudOverlayFilename or ""
                ))
            end
        end

        table.sort(entries, function(a, b) return a.name < b.name end)

        FarmMonitor:writeJSON(FarmMonitor.paths.fillTypes, FarmMonitor.obj(
            "savegameId", FarmMonitor.savegameId,
            "fillTypes",  entries
        ))
        print("[FarmMonitor] fillTypes.json written (" .. #entries .. " entries)")
    end)

    if not ok then
        print("[FarmMonitor] ERROR writing fillTypes.json: " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- Animal food registry  (written once on first update)
-- ---------------------------------------------------------------------------

function FarmMonitor:exportAnimalFood()
    local ok, err = pcall(function()
        local animalFoodSystem = g_currentMission and g_currentMission.animalFoodSystem
        if animalFoodSystem == nil then return end

        local result = {}

        for _, animalType in ipairs(g_currentMission.animalSystem.types or {}) do
            if animalType ~= nil and animalType.name ~= nil then
                local animalFood = animalFoodSystem:getAnimalFood(animalType.typeIndex)
                if animalFood ~= nil and animalFood.groups ~= nil then
                    local consumptionType = "SERIAL"
                    if animalFood.consumptionType == AnimalFoodSystem.FOOD_CONSUME_TYPE_PARALLEL then
                        consumptionType = "PARALLEL"
                    end
                    local groups = {}
                    for _, group in ipairs(animalFood.groups) do
                        local fillTypeNames = {}
                        for _, ftIndex in ipairs(group.fillTypes or {}) do
                            local name = g_fillTypeManager:getFillTypeNameByIndex(ftIndex)
                            if name ~= nil then
                                table.insert(fillTypeNames, name)
                            end
                        end
                        table.insert(groups, FarmMonitor.obj(
                            "title",           group.title or "",
                            "productionWeight", group.productionWeight or 0,
                            "eatWeight",        group.eatWeight or 0,
                            "fillTypes",        fillTypeNames
                        ))
                    end
                    result[animalType.name] = FarmMonitor.obj(
                        "consumptionType", consumptionType,
                        "groups",          groups
                    )
                end
            end
        end

        FarmMonitor:writeJSON(FarmMonitor.paths.animalFood, FarmMonitor.obj(
            "savegameId", FarmMonitor.savegameId,
            "animalFood", result
        ))
        print("[FarmMonitor] animalFood.json written")
    end)

    if not ok then
        print("[FarmMonitor] ERROR writing animalFood.json: " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- Savegame name  (read once, cached in FarmMonitor.savegameName)
-- ---------------------------------------------------------------------------

function FarmMonitor:readSavegameInfo()
    local missionInfo = g_currentMission and g_currentMission.missionInfo
    if missionInfo == nil or missionInfo.savegameDirectory == nil then return nil, nil end
    local xmlPath = missionInfo.savegameDirectory .. "/careerSavegame.xml"
    local name, savegameId = nil, nil
    local ok, err = pcall(function()
        local xmlFile = XMLFile.load("FarmMonitor_savegame", xmlPath)
        if xmlFile ~= nil then
            name = xmlFile:getString("careerSavegame.settings.savegameName")
            local mapId       = missionInfo.mapId or xmlFile:getString("careerSavegame.settings.mapId") or "unknown"
            local creationDate = xmlFile:getString("careerSavegame.settings.creationDate") or "unknown"
            savegameId = mapId .. "_" .. creationDate
            xmlFile:delete()
        end
    end)
    if not ok then
        print("[FarmMonitor] WARNING: Could not read savegame info: " .. tostring(err))
    end
    return name, savegameId
end

-- ---------------------------------------------------------------------------
-- Silos
-- ---------------------------------------------------------------------------

function FarmMonitor:collectSilos()
    local result = FarmMonitor.arr()
    local farmId = g_currentMission:getFarmId()

    if g_currentMission.placeableSystem == nil then return result end

    for _, placeable in ipairs(g_currentMission.placeableSystem.placeables) do
        -- Standard silo
        if placeable.spec_silo ~= nil then
            local owned = (placeable.ownerFarmId == farmId or placeable.ownerFarmId == 0)
            if owned and placeable.spec_silo.storages ~= nil then
                for _, storage in ipairs(placeable.spec_silo.storages) do
                    if storage.ownerFarmId == farmId or storage.ownerFarmId == 0 then
                        local contents = FarmMonitor:readFillLevels(storage)
                        if #contents > 0 then
                            table.insert(result, {
                                uniqueId = placeable:getUniqueId() or "",
                                name     = FarmMonitor:placeableName(placeable),
                                type     = "silo",
                                capacity = storage.capacity or 0,
                                contents = contents,
                            })
                        end
                    end
                end
            end
        end

        -- Silo extension
        if placeable.spec_siloExtension ~= nil then
            local storage = placeable.spec_siloExtension.storage
            if storage ~= nil and (storage.ownerFarmId == farmId or storage.ownerFarmId == 0) then
                local contents = FarmMonitor:readFillLevels(storage)
                if #contents > 0 then
                    table.insert(result, {
                        uniqueId = placeable:getUniqueId() or "",
                        name     = FarmMonitor:placeableName(placeable),
                        type     = "siloExtension",
                        capacity = storage.capacity or 0,
                        contents = contents,
                    })
                end
            end
        end
    end

    return result
end

-- ---------------------------------------------------------------------------
-- Productions
-- ---------------------------------------------------------------------------

function FarmMonitor:collectProductions()
    local result = FarmMonitor.arr()
    local farmId = g_currentMission:getFarmId()

    if g_currentMission.placeableSystem == nil then return result end

    for _, placeable in ipairs(g_currentMission.placeableSystem.placeables) do
        local spec = placeable.spec_productionPoint
        if spec ~= nil and spec.productionPoint ~= nil and placeable.ownerFarmId == farmId then
            local pp = spec.productionPoint
            -- Inputs: all fill types stored as input for this production point
            local inputs = FarmMonitor.arr()
            if pp.inputFillTypeIds ~= nil then
                for fillTypeId, _ in pairs(pp.inputFillTypeIds) do
                    local level    = pp:getFillLevel(fillTypeId)
                    local capacity = pp:getCapacity(fillTypeId)
                    if level > 0 or capacity > 0 then
                        table.insert(inputs, FarmMonitor.obj(
                            "fillType", g_fillTypeManager:getFillTypeNameByIndex(fillTypeId) or "UNKNOWN",
                            "title",    FarmMonitor:fillTypeTitle(fillTypeId),
                            "level",    MathUtil.round(level),
                            "capacity", MathUtil.round(capacity)
                        ))
                    end
                end
            end

            -- Outputs: all fill types stored as output for this production point
            local outputs = FarmMonitor.arr()
            if pp.outputFillTypeIdsArray ~= nil then
                for _, fillTypeId in ipairs(pp.outputFillTypeIdsArray) do
                    local level    = pp:getFillLevel(fillTypeId)
                    local capacity = pp:getCapacity(fillTypeId)
                    if level > 0 or capacity > 0 then
                        table.insert(outputs, FarmMonitor.obj(
                            "fillType", g_fillTypeManager:getFillTypeNameByIndex(fillTypeId) or "UNKNOWN",
                            "title",    FarmMonitor:fillTypeTitle(fillTypeId),
                            "level",    MathUtil.round(level),
                            "capacity", MathUtil.round(capacity)
                        ))
                    end
                end
            end

            -- Production chains: only status info, no recipe details
            local chains = FarmMonitor.arr()
            for _, prod in ipairs(pp.productions) do
                local status = "unknown"
                if prod.status ~= nil then
                    if prod.status == ProductionPoint.PROD_STATUS.RUNNING then
                        status = "running"
                    elseif prod.status == ProductionPoint.PROD_STATUS.INACTIVE then
                        status = "inactive"
                    else
                        status = "stopped"
                    end
                end
                table.insert(chains, FarmMonitor.obj(
                    "id",             prod.id or "",
                    "name",           prod.name or "",
                    "status",         status,
                    "cyclesPerMonth", MathUtil.round(prod.cyclesPerMonth or 0)
                ))
            end

            table.insert(result, FarmMonitor.obj(
                "uniqueId",    placeable:getUniqueId() or "",
                "name",        pp:getName() or "",
                "inputs",      inputs,
                "outputs",     outputs,
                "productions", chains
            ))
        end
    end

    return result
end

-- ---------------------------------------------------------------------------
-- Animal husbandries
-- ---------------------------------------------------------------------------

function FarmMonitor:collectHusbandries()
    local result = FarmMonitor.arr()
    local farmId = g_currentMission:getFarmId()

    if g_currentMission.placeableSystem == nil then return result end

    for _, placeable in ipairs(g_currentMission.placeableSystem.placeables) do
        if placeable.spec_husbandry ~= nil and placeable.ownerFarmId == farmId then
            local entry = {
                uniqueId    = placeable:getUniqueId() or "",
                name        = FarmMonitor:placeableName(placeable),
                animalType  = FarmMonitor:getAnimalType(placeable),
                numAnimals  = FarmMonitor:countAnimals(placeable),
                maxAnimals  = FarmMonitor:maxAnimals(placeable),
                food        = FarmMonitor:getFoodInfo(placeable),
                foodTotal   = FarmMonitor:getFoodTotal(placeable),
                water       = FarmMonitor:getWaterInfo(placeable),
                straw       = FarmMonitor:getStrawInfo(placeable),
                health      = FarmMonitor:getHealthInfo(placeable),
                outputs     = FarmMonitor.arr(),
            }

            -- Husbandry output storage (milk, eggs, wool, manure, …)
            -- Iterate all fill types via official API to catch outputs with level=0.
            -- Exclude STRAW (bedding input) and WATER (drinking input).
            if placeable.getHusbandryCapacity ~= nil then
                for _, ft in ipairs(g_fillTypeManager.fillTypes or {}) do
                    if ft ~= nil and ft.index ~= nil then
                        local ftName = ft.name or "UNKNOWN"
                        if ftName ~= "STRAW" and ftName ~= "WATER" then
                            local capacity = placeable:getHusbandryCapacity(ft.index)
                            if capacity > 0 then
                                local level = placeable:getHusbandryFillLevel(ft.index)
                                table.insert(entry.outputs, {
                                    fillType = ftName,
                                    title    = ft.title or ftName,
                                    level    = MathUtil.round(level),
                                    capacity = MathUtil.round(capacity),
                                })
                            end
                        end
                    end
                end
            end

            table.insert(result, entry)
        end
    end

    return result
end

-- ---------------------------------------------------------------------------
-- Goods (aggregated fill levels + prices across all storage sources)
-- ---------------------------------------------------------------------------

function FarmMonitor:collectGoods()
    local farmId = g_currentMission:getFarmId()
    local totals    = {}   -- fillTypeIndex -> total liters
    local locations = {}   -- fillTypeIndex -> { locationName -> liters }
    local seenBaleIds = {}

    local function addAmount(fillTypeIndex, amount, locationId, locationName)
        if fillTypeIndex == nil or amount == nil or amount <= 0 then return end
        totals[fillTypeIndex] = (totals[fillTypeIndex] or 0) + amount
        if locationId ~= nil then
            if locations[fillTypeIndex] == nil then locations[fillTypeIndex] = {} end
            local loc = locations[fillTypeIndex][locationId]
            if loc == nil then
                locations[fillTypeIndex][locationId] = { name = locationName or locationId, liters = amount }
            else
                loc.liters = loc.liters + amount
            end
        end
    end

    if g_currentMission.placeableSystem then
        for _, placeable in ipairs(g_currentMission.placeableSystem.placeables) do
            local ownedByFarm = (placeable.ownerFarmId == farmId or placeable.ownerFarmId == 0)
            local locId   = tostring(placeable:getUniqueId() or "")
            local locName = FarmMonitor:placeableName(placeable)

            -- Silos
            if placeable.spec_silo ~= nil and ownedByFarm then
                for _, storage in ipairs(placeable.spec_silo.storages or {}) do
                    if storage.ownerFarmId == farmId or storage.ownerFarmId == 0 then
                        for ftIdx, level in pairs(storage.fillLevels or {}) do
                            addAmount(ftIdx, level, locId, locName)
                        end
                    end
                end
            end

            -- Silo extensions
            if placeable.spec_siloExtension ~= nil then
                local storage = placeable.spec_siloExtension.storage
                if storage ~= nil and (storage.ownerFarmId == farmId or storage.ownerFarmId == 0) then
                    for ftIdx, level in pairs(storage.fillLevels or {}) do
                        addAmount(ftIdx, level, locId, locName)
                    end
                end
            end

            -- Husbandry output storage (only accepted output fill types)
            if placeable.spec_husbandry ~= nil and ownedByFarm then
                local spec    = placeable.spec_husbandry
                local storage = spec.storage
                if storage ~= nil and storage.fillLevels ~= nil then
                    for ftIdx, level in pairs(storage.fillLevels) do
                        local supported = spec.loadingStation == nil
                            or spec.loadingStation.supportedFillTypes == nil
                            or spec.loadingStation.supportedFillTypes[ftIdx]
                        if supported then addAmount(ftIdx, level, locId, locName) end
                    end
                end
            end

            -- Productions (outputs only — inputs are consumed goods, not freely sellable)
            if placeable.spec_productionPoint ~= nil and placeable.ownerFarmId == farmId then
                local pp = placeable.spec_productionPoint.productionPoint
                if pp ~= nil then
                    for _, ftIdx in ipairs(pp.outputFillTypeIdsArray or {}) do
                        addAmount(ftIdx, pp:getFillLevel(ftIdx), locId, locName)
                    end
                end
            end

            -- Bunker silos
            if placeable.spec_bunkerSilo ~= nil and ownedByFarm then
                local bs = placeable.spec_bunkerSilo.bunkerSilo
                if bs ~= nil and bs.fillLevel ~= nil and bs.fillLevel > 0 then
                    local ftIdx = bs.inputFillType
                    if bs.state == BunkerSilo.STATE_DRAIN or bs.state == BunkerSilo.STATE_FERMENTED then
                        ftIdx = bs.outputFillType
                    end
                    addAmount(ftIdx, bs.fillLevel, locId, locName)
                end
            end

            -- Giants Object Storage (vanilla pallets/bale storage)
            if placeable.spec_objectStorage ~= nil and ownedByFarm then
                for _, objInfo in ipairs(placeable.spec_objectStorage.objectInfos or {}) do
                    for _, obj in ipairs(objInfo.objects or {}) do
                        if obj.baleAttributes ~= nil then
                            if obj.baleAttributes.uniqueId then seenBaleIds[obj.baleAttributes.uniqueId] = true end
                            addAmount(obj.baleAttributes.fillType, obj.baleAttributes.fillLevel, locId, locName)
                        elseif obj.baleObject ~= nil then
                            if obj.baleObject.uniqueId then seenBaleIds[obj.baleObject.uniqueId] = true end
                            addAmount(obj.baleObject.fillType, obj.baleObject.fillLevel, locId, locName)
                        elseif obj.palletAttributes ~= nil then
                            addAmount(obj.palletAttributes.fillType, obj.palletAttributes.fillLevel, locId, locName)
                        end
                    end
                end
            end

            -- Object Storage Mod (e.g. bale storage mods)
            if placeable.spec_objectStorageMod ~= nil and ownedByFarm then
                local os = placeable.spec_objectStorageMod.objectStorage
                if os ~= nil and os.storageAreasByFillType ~= nil then
                    for ftIdx, areas in pairs(os.storageAreasByFillType) do
                        for _, area in pairs(areas) do
                            for _, obj in ipairs(area.objects or {}) do
                                addAmount(ftIdx, obj.fillLevel, locId, locName)
                            end
                        end
                    end
                end
            end

            -- Manure heap
            if placeable.spec_manureHeap ~= nil and ownedByFarm then
                local heap = placeable.spec_manureHeap.manureHeap
                if heap ~= nil then
                    for ftIdx, level in pairs(heap.fillLevels or {}) do
                        addAmount(ftIdx, level, locId, locName)
                    end
                end
            end

            -- Beehive pallet spawner (pending liters)
            if placeable.spec_beehivePalletSpawner ~= nil and ownedByFarm then
                local spec = placeable.spec_beehivePalletSpawner
                addAmount(spec.fillType, spec.pendingLiters, locId, locName)
            end
        end
    end

    -- Loose pallets & shipping containers
    if g_currentMission.vehicleSystem ~= nil then
        for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles or {}) do
            if vehicle.isPallet and (vehicle.ownerFarmId == farmId or vehicle.ownerFarmId == 0) then
                local spec = vehicle.spec_fillUnit
                if spec ~= nil and spec.fillUnits ~= nil and spec.fillUnits[1] ~= nil then
                    local fu = spec.fillUnits[1]
                    addAmount(fu.fillType, fu.fillLevel, "Loose Pallets")
                end
            end
        end
    end

    -- Loose bales (deduplicated against Object Storage)
    if g_currentMission.itemSystem ~= nil then
        for _, item in ipairs(g_currentMission.itemSystem.itemsToSave or {}) do
            local bale = item.item
            if bale ~= nil and bale.isa ~= nil and bale:isa(Bale) then
                if bale.ownerFarmId == farmId or bale.ownerFarmId == 0 then
                    if bale.uniqueId == nil or not seenBaleIds[bale.uniqueId] then
                        addAmount(bale.fillType, bale.fillLevel, "Loose Bales")
                    end
                end
            end
        end
    end

    -- Collect selling stations (non-hidden, non-own)
    local stations = {}
    if g_currentMission.storageSystem ~= nil then
        for _, station in pairs(g_currentMission.storageSystem:getUnloadingStations() or {}) do
            if station:isa(SellingStation) and not station.hideFromPricesMenu then
                table.insert(stations, station)
            end
        end
    end

    -- Economic difficulty multiplier — same factor used by getEffectiveFillTypePrice internally
    -- EconomyManager.getPriceMultiplier() is a static call (matches TSStockCheck usage)
    local priceMult = EconomyManager.getPriceMultiplier()

    -- Build result: one entry per fill type with totals + price data
    local result = FarmMonitor.arr()

    for ftIdx, totalLevel in pairs(totals) do
        if totalLevel > 0 then
            local ft = g_fillTypeManager:getFillTypeByIndex(ftIdx)
            if ft ~= nil then
                -- All selling stations that accept this fill type
                local sellingStationEntries = FarmMonitor.arr()
                for _, station in ipairs(stations) do
                    if station.acceptedFillTypes and station.acceptedFillTypes[ftIdx] then
                        local price = station:getEffectiveFillTypePrice(ftIdx)
                        local t     = station:getCurrentPricingTrend(ftIdx)
                        local trend
                        if Utils.isBitSet(t, SellingStation.PRICE_GREAT_DEMAND) then
                            trend = "GREAT_DEMAND"
                        elseif Utils.isBitSet(t, SellingStation.PRICE_CLIMBING) then
                            trend = "CLIMBING"
                        elseif Utils.isBitSet(t, SellingStation.PRICE_FALLING) then
                            trend = "FALLING"
                        else
                            trend = "STABLE"
                        end
                        table.insert(sellingStationEntries, FarmMonitor.obj(
                            "name",  station:getName() or "",
                            "price", MathUtil.round(price * 10000) / 10000,
                            "value", MathUtil.round(totalLevel * price),
                            "trend", trend
                        ))
                    end
                end
                table.sort(sellingStationEntries, function(a, b) return (a.price or 0) > (b.price or 0) end)

                -- Max theoretical price over all 12 season periods
                -- Apply priceMult (economic difficulty) so maxPrice is comparable to
                -- getEffectiveFillTypePrice() which already includes this factor.
                local maxPrice   = 0
                local bestPeriod = 1
                if ft.economy ~= nil and ft.economy.factors ~= nil and ft.pricePerLiter ~= nil then
                    for period = SeasonPeriod.EARLY_SPRING, SeasonPeriod.LATE_WINTER do
                        local p = ft.pricePerLiter * (ft.economy.factors[period] or 1.0) * priceMult
                        if p > maxPrice then
                            maxPrice   = p
                            bestPeriod = period
                        end
                    end
                end

                -- Storage locations for this fill type
                local storageLocationEntries = FarmMonitor.arr()
                if locations[ftIdx] ~= nil then
                    for locId, loc in pairs(locations[ftIdx]) do
                        table.insert(storageLocationEntries, FarmMonitor.obj(
                            "uniqueId", locId,
                            "name",     loc.name,
                            "liters",   MathUtil.round(loc.liters)
                        ))
                    end
                    table.sort(storageLocationEntries, function(a, b) return (a.liters or 0) > (b.liters or 0) end)
                end

                table.insert(result, FarmMonitor.obj(
                    "fillType",        ft.name,
                    "title",           ft.title or ft.name,
                    "totalLiters",     MathUtil.round(totalLevel),
                    "maxPrice",        MathUtil.round(maxPrice * 10000) / 10000,
                    "maxValue",        MathUtil.round(totalLevel * maxPrice),
                    "bestPeriod",      bestPeriod,
                    "storageLocations", storageLocationEntries,
                    "sellingStations", sellingStationEntries
                ))
            end
        end
    end

    table.sort(result, function(a, b) return (a.maxValue or 0) > (b.maxValue or 0) end)
    return result
end

-- ---------------------------------------------------------------------------
-- Fields
-- ---------------------------------------------------------------------------

function FarmMonitor:exportFieldMeta()
    local ok, err = pcall(function()
        local fgs = g_currentMission.fieldGroundSystem
        local meta = {}

        if fgs ~= nil then
            meta.sprayLevelMax        = fgs:getMaxValue(FieldDensityMap.SPRAY_LEVEL) or 0
            meta.limeLevelMax         = fgs:getMaxValue(FieldDensityMap.LIME_LEVEL)  or 0
            meta.plowLevelMax         = fgs:getMaxValue(FieldDensityMap.PLOW_LEVEL)  or 0

            local _, _, mulchChannels = fgs:getDensityMapData(FieldDensityMap.STUBBLE_SHRED_LEVEL)
            meta.stubbleShredLevelMax = mulchChannels ~= nil and (2 ^ mulchChannels - 1) or 0
        end

        local ws = g_currentMission.weedSystem
        if ws ~= nil then
            local _, _, weedChannels = ws:getDensityMapData()
            meta.weedStateMax = weedChannels ~= nil and (2 ^ weedChannels - 1) or 0
        end

        local ss = g_currentMission.stoneSystem
        if ss ~= nil then
            local _, stoneMax = ss:getMinMaxValues()
            meta.stoneLevelMax = stoneMax or 0
        end

        FarmMonitor:writeJSON(FarmMonitor.paths.fieldMeta, FarmMonitor.obj(
            "savegameId",         FarmMonitor.savegameId,
            "sprayLevelMax",      meta.sprayLevelMax        or 0,
            "limeLevelMax",       meta.limeLevelMax         or 0,
            "plowLevelMax",       meta.plowLevelMax         or 0,
            "stubbleShredLevelMax", meta.stubbleShredLevelMax or 0,
            "weedStateMax",       meta.weedStateMax         or 0,
            "stoneLevelMax",      meta.stoneLevelMax        or 0
        ))
        print("[FarmMonitor] fieldMeta.json written")
    end)

    if not ok then
        print("[FarmMonitor] ERROR writing fieldMeta.json: " .. tostring(err))
    end
end

function FarmMonitor:collectFields()
    local result = FarmMonitor.arr()
    local farmId = g_currentMission:getFarmId()

    if g_farmlandManager == nil then return result end

    for _, farmland in pairs(g_farmlandManager.farmlands or {}) do
        if farmland ~= nil
            and farmland.showOnFarmlandsScreen
            and farmland.farmId == farmId
            and farmland.field ~= nil
        then
            local field  = farmland.field
            local areaHa = farmland.areaInHa or field.areaHa or 0

            -- Fruit type via density map at field centre (same API as FarmlandOverview)
            local fruitTypeName        = ""
            local fruitTypeTitle       = ""
            local growthStage          = 0
            local numGrowthStates      = 0
            local harvestReady         = false
            local withered             = false
            local isCut                = false
            local estimatedYieldLiters = 0

            local ok1, cx, cz = pcall(function() return field:getCenterOfFieldWorldPosition() end)
            if ok1 and cx ~= nil then
                local fruitTypeIndex, gs = FSDensityMapUtil.getFruitTypeIndexAtWorldPos(cx, cz)
                if fruitTypeIndex ~= nil and fruitTypeIndex > 0 then
                    local ft = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
                    if ft ~= nil then
                        fruitTypeName   = ft.name or ""
                        fruitTypeTitle  = (ft.fillType and ft.fillType.title) or ft.name or ""
                        numGrowthStates = ft.numGrowthStates or 0
                        growthStage     = gs or 0

                        local minH = ft.minHarvestingGrowthState or 0
                        local maxH = ft.maxHarvestingGrowthState or 0
                        harvestReady = (minH > 0 and growthStage >= minH and growthStage <= maxH)

                        local cutSt = ft.cutState or -1
                        isCut    = (cutSt >= 0 and growthStage == cutSt)
                        -- ft.witheredState is a direct attribute on FruitTypeDesc
                        local wSt = ft.witheredState or -1
                        withered = (wSt >= 0 and growthStage == wSt)

                        if harvestReady and ft.literPerSqm ~= nil then
                            local areaM2     = areaHa * 10000
                            local multiplier = 1.0
                            local ok2, m = pcall(function() return field:getHarvestScaleMultiplier() end)
                            if ok2 and m ~= nil then multiplier = m end
                            estimatedYieldLiters = MathUtil.round(ft.literPerSqm * areaM2 * multiplier)
                        end
                    end
                end
            end

            -- Soil state via field:getFieldState()
            local plowLevel         = 0
            local sprayLevel        = 0
            local limeLevel         = 0
            local weedState         = 0
            local stubbleShredLevel = 0
            local stoneLevel        = 0

            local ok3, fs = pcall(function() return field:getFieldState() end)
            if ok3 and fs ~= nil then
                plowLevel         = fs.plowLevel         or 0
                sprayLevel        = fs.sprayLevel        or 0
                limeLevel         = fs.limeLevel         or 0
                weedState         = fs.weedState         or 0
                stubbleShredLevel = fs.stubbleShredLevel or 0
                stoneLevel        = fs.stoneLevel        or 0
            end

            table.insert(result, FarmMonitor.obj(
                "id",                  farmland.name or tostring(farmland.id or 0),
                "area",                MathUtil.round(areaHa * 100) / 100,
                "fruitType",           fruitTypeName,
                "fruitTitle",          fruitTypeTitle,
                "growthStage",         growthStage,
                "numGrowthStates",     numGrowthStates,
                "harvestReady",        harvestReady,
                "withered",            withered,
                "cut",                 isCut,
                "estimatedYieldLiters", estimatedYieldLiters,
                "plowLevel",           plowLevel,
                "sprayLevel",          sprayLevel,
                "limeLevel",           limeLevel,
                "weedState",           weedState,
                "stubbleShredLevel",   stubbleShredLevel,
                "stoneLevel",          stoneLevel
            ))
        end
    end

    table.sort(result, function(a, b)
        local na, nb = tonumber(a.id), tonumber(b.id)
        if na ~= nil and nb ~= nil then return na < nb end
        return tostring(a.id) < tostring(b.id)
    end)
    return result
end

-- ---------------------------------------------------------------------------
-- Husbandry helpers
-- ---------------------------------------------------------------------------

function FarmMonitor:countAnimals(placeable)
    local total = 0
    local spec = placeable.spec_husbandryAnimals
    if spec ~= nil and spec.clusterSystem ~= nil then
        local clusters = spec.clusterSystem:getClusters()
        for _, cluster in pairs(clusters) do
            if cluster.getNumAnimals ~= nil then
                total = total + cluster:getNumAnimals()
            elseif cluster.numAnimals ~= nil then
                total = total + cluster.numAnimals
            end
        end
    end
    return total
end

function FarmMonitor:maxAnimals(placeable)
    local spec = placeable.spec_husbandryAnimals
    if spec ~= nil then
        if spec.maxNumOfAnimals ~= nil then return spec.maxNumOfAnimals end
    end
    if placeable.getMaxNumOfAnimals ~= nil then
        return placeable:getMaxNumOfAnimals()
    end
    return 0
end

function FarmMonitor:getAnimalType(placeable)
    local spec = placeable.spec_husbandryAnimals
    if spec ~= nil then
        -- spec.animalType is the full type object loaded from XML
        if spec.animalType ~= nil and spec.animalType.name ~= nil then
            return spec.animalType.name
        end
        -- fallback: look up via animalSystem
        if spec.animalTypeIndex ~= nil then
            local animalSystem = g_currentMission and g_currentMission.animalSystem
            if animalSystem ~= nil and animalSystem.types ~= nil then
                local t = animalSystem.types[spec.animalTypeIndex]
                if t ~= nil then return t.name or "unknown" end
            end
        end
    end
    return "unknown"
end

function FarmMonitor:getFoodInfo(placeable)
    -- Use the base-game getFoodInfos() method when available
    if placeable.getFoodInfos ~= nil then
        local ok, infos = pcall(function() return placeable:getFoodInfos() end)
        if ok and type(infos) == "table" then
            local entries = FarmMonitor.arr()
            for _, info in ipairs(infos) do
                if not info.ignoreCapacity then
                    table.insert(entries, {
                        title    = info.title or "",
                        value    = MathUtil.round(info.value or 0),
                        capacity = MathUtil.round(info.capacity or 0),
                    })
                end
            end
            return entries
        end
    end

    -- Fallback: read spec_husbandryFood directly
    local spec = placeable.spec_husbandryFood
    if spec ~= nil then
        local level    = spec.fillLevel or 0
        local capacity = spec.capacity  or 0
        if capacity > 0 then
            return {{ title = "Food", value = MathUtil.round(level), capacity = MathUtil.round(capacity) }}
        end
    end

    return FarmMonitor.arr()
end

function FarmMonitor:getFoodTotal(placeable)
    if placeable.getTotalFood == nil or placeable.getFoodCapacity == nil then return nil end
    local capacity = placeable:getFoodCapacity()
    if capacity <= 0 then return nil end
    local value = placeable:getTotalFood()
    return {
        value    = MathUtil.round(value),
        capacity = MathUtil.round(capacity),
        ratio    = MathUtil.round(value / capacity * 100) / 100,
    }
end

function FarmMonitor:getWaterInfo(placeable)
    if placeable.spec_husbandryWater == nil then return nil end
    if placeable.getHusbandryCapacity == nil then return nil end
    local waterFt = g_fillTypeManager:getFillTypeByName("WATER")
    if waterFt == nil then return nil end
    local capacity = placeable:getHusbandryCapacity(waterFt.index)
    if capacity <= 0 then return nil end
    return {
        value    = MathUtil.round(placeable:getHusbandryFillLevel(waterFt.index)),
        capacity = MathUtil.round(capacity),
    }
end

function FarmMonitor:getStrawInfo(placeable)
    if placeable.getHusbandryCapacity == nil then return nil end
    local strawFt = g_fillTypeManager:getFillTypeByName("STRAW")
    if strawFt == nil then return nil end
    local capacity = placeable:getHusbandryCapacity(strawFt.index)
    if capacity <= 0 then return nil end
    return {
        value    = MathUtil.round(placeable:getHusbandryFillLevel(strawFt.index)),
        capacity = MathUtil.round(capacity),
    }
end

function FarmMonitor:getHealthInfo(placeable)
    local spec = placeable.spec_husbandryAnimals
    if spec == nil or spec.clusterSystem == nil then return nil end
    local clusters = spec.clusterSystem:getClusters()
    local numClusters = #clusters
    if numClusters == 0 then return nil end
    local health = 0
    for _, cluster in ipairs(clusters) do
        health = health + (cluster.health or 0)
    end
    return MathUtil.round(health / numClusters)
end

-- ---------------------------------------------------------------------------
-- Generic helpers
-- ---------------------------------------------------------------------------

function FarmMonitor:readFillLevels(storage)
    local contents = FarmMonitor.arr()
    if storage.fillLevels == nil then return contents end
    for fillTypeId, level in pairs(storage.fillLevels) do
        if level > 0 then
            table.insert(contents, {
                fillType = g_fillTypeManager:getFillTypeNameByIndex(fillTypeId) or "UNKNOWN",
                title    = FarmMonitor:fillTypeTitle(fillTypeId),
                level    = MathUtil.round(level),
            })
        end
    end
    return contents
end

function FarmMonitor:fillTypeTitle(fillTypeId)
    local ft = g_fillTypeManager:getFillTypeByIndex(fillTypeId)
    if ft ~= nil then return ft.title or ft.name or "?" end
    return "?"
end

function FarmMonitor:placeableName(placeable)
    if placeable.getName ~= nil then
        return placeable:getName() or "?"
    end
    return "?"
end

-- ---------------------------------------------------------------------------
-- JSON encoder  (pretty-printed, ordered objects via __order)
-- ---------------------------------------------------------------------------

-- Use arr() to create a table that always serialises as a JSON array (even when empty).
function FarmMonitor.arr(t)
    t = t or {}
    t.__isArray = true
    return t
end

-- Use obj() to build an object with guaranteed key order:
--   obj("name","Foo", "level",100, "capacity",200)
function FarmMonitor.obj(...)
    local t   = {}
    local ord = {}
    local args = {...}
    for i = 1, #args, 2 do
        local k = args[i]
        t[k] = args[i + 1]
        table.insert(ord, k)
    end
    t.__order = ord
    return t
end

function FarmMonitor:encodeJSON(value, indent)
    indent = indent or 0
    local pad    = string.rep("    ", indent)
    local padIn  = string.rep("    ", indent + 1)
    local t      = type(value)

    if value == nil then
        return "null"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        if value ~= value then return "null" end
        return string.format("%g", value)
    elseif t == "string" then
        local escaped = value
            :gsub('\\', '\\\\')
            :gsub('"',  '\\"')
            :gsub('\n', '\\n')
            :gsub('\r', '\\r')
            :gsub('\t', '\\t')
        return '"' .. escaped .. '"'
    elseif t == "table" then
        -- Ordered object (has __order key)
        if value.__order ~= nil then
            local parts = {}
            for _, k in ipairs(value.__order) do
                local v   = value[k]
                local key = '"' .. tostring(k) .. '"'
                table.insert(parts, padIn .. key .. ": " .. FarmMonitor:encodeJSON(v, indent + 1))
            end
            if #parts == 0 then return "{}" end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
        end

        -- Plain array (explicit marker or non-empty numeric table)
        local isArray = (value.__isArray == true) or (#value > 0)
        if isArray and value.__isArray == nil then
            for k, _ in pairs(value) do
                if type(k) ~= "number" then isArray = false break end
            end
        end

        if isArray then
            local parts = {}
            for _, v in ipairs(value) do
                table.insert(parts, padIn .. FarmMonitor:encodeJSON(v, indent + 1))
            end
            if #parts == 0 then return "[]" end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
        else
            -- Unordered object (fallback)
            local parts = {}
            for k, v in pairs(value) do
                if k ~= "__order" then
                    local key = '"' .. tostring(k) .. '"'
                    table.insert(parts, padIn .. key .. ": " .. FarmMonitor:encodeJSON(v, indent + 1))
                end
            end
            if #parts == 0 then return "{}" end
            table.sort(parts)
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
        end
    else
        return '"[' .. t .. ']"'
    end
end
