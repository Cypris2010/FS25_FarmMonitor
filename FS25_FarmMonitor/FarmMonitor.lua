-- FarmMonitor.lua
-- Collects data from silos, productions and animal husbandries,
-- then writes each category to its own JSON file in the modSettings directory.

local modName = g_currentModName  -- capture before it gets reset

FarmMonitor = {}
FarmMonitor.updateInterval    = 10000  -- milliseconds between exports
FarmMonitor.timer             = 0
FarmMonitor.fieldInterval     = 60000  -- milliseconds between field exports
FarmMonitor.fieldTimer        = 60000  -- start at max so first export fires immediately
FarmMonitor.commandInterval   = 1000   -- milliseconds between command checks
FarmMonitor.commandTimer      = 0
FarmMonitor.paths             = {}
FarmMonitor.fillTypesExported   = false
FarmMonitor.animalFoodExported  = false
FarmMonitor.fruitTypesExported  = false
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

    FarmMonitor.paths.silos        = outputDir .. "silos.json"
    FarmMonitor.paths.productions  = outputDir .. "productions.json"
    FarmMonitor.paths.husbandries  = outputDir .. "husbandries.json"
    FarmMonitor.paths.fillTypes    = outputDir .. "fillTypes.json"
    FarmMonitor.paths.animalFood   = outputDir .. "animalFood.json"
    FarmMonitor.paths.goods        = outputDir .. "goods.json"
    FarmMonitor.paths.fields       = outputDir .. "fields.json"
    FarmMonitor.paths.fruitTypes   = outputDir .. "fruitTypes.json"
    FarmMonitor.paths.commandsXml = outputDir .. "commands.xml"
    FarmMonitor.paths.commandsAck = outputDir .. "commands.ack"
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
        FarmMonitor.fruitTypesExported = false
        FarmMonitor.timer              = 0
        FarmMonitor.fieldTimer         = FarmMonitor.fieldInterval  -- trigger field export on next tick
    end

    if FarmMonitor.savegameName == nil then
        FarmMonitor.savegameName, FarmMonitor.savegameId = FarmMonitor:readSavegameInfo()
    end

    if not FarmMonitor.fillTypesExported then
        FarmMonitor:exportFillTypes()
        FarmMonitor.fillTypesExported = true
    end

    if not FarmMonitor.fruitTypesExported then
        FarmMonitor:exportFruitTypes()
        FarmMonitor.fruitTypesExported = true
    end

    if not FarmMonitor.animalFoodExported then
        FarmMonitor:exportAnimalFood()
        FarmMonitor.animalFoodExported = true
    end

    FarmMonitor.timer = FarmMonitor.timer + dt
    if FarmMonitor.timer >= FarmMonitor.updateInterval then
        FarmMonitor.timer = 0
        FarmMonitor:collectAndSave()
    end

    FarmMonitor.fieldTimer = FarmMonitor.fieldTimer + dt
    if FarmMonitor.fieldTimer >= FarmMonitor.fieldInterval then
        FarmMonitor.fieldTimer = 0
        FarmMonitor:collectAndSaveFields()
    end

    FarmMonitor.commandTimer = FarmMonitor.commandTimer + dt
    if FarmMonitor.commandTimer >= FarmMonitor.commandInterval then
        FarmMonitor.commandTimer = 0
        FarmMonitor:processCommands()
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
-- Fruit type growth stage registry  (written once per session)
-- ---------------------------------------------------------------------------

function FarmMonitor:exportFruitTypes()
    local ok, err = pcall(function()
        local entries = {}
        local fruitTypes = g_fruitTypeManager and g_fruitTypeManager.fruitTypes
        if fruitTypes == nil then return end

        for _, ft in ipairs(fruitTypes) do
            if ft ~= nil and ft.name ~= nil then
                -- Collect all named growth stages from growthStateToName
                local stages = {}
                if ft.growthStateToName then
                    for stageIndex, stageName in pairs(ft.growthStateToName) do
                        table.insert(stages, FarmMonitor.obj(
                            "index", stageIndex,
                            "name",  stageName
                        ))
                    end
                    table.sort(stages, function(a, b) return a.index < b.index end)
                end

                -- Find max cut stage across all cutStates entries
                local maxCutStage = ft.cutState or 0
                if ft.cutStates then
                    for k, _ in pairs(ft.cutStates) do
                        if k > maxCutStage then maxCutStage = k end
                    end
                end

                table.insert(entries, FarmMonitor.obj(
                    "name",              ft.name,
                    "title",             (ft.fillType and ft.fillType.title) or ft.name,
                    "numGrowthStates",   ft.numGrowthStates or 0,
                    "minHarvest",        ft.minHarvestingGrowthState or 0,
                    "maxHarvest",        ft.maxHarvestingGrowthState or 0,
                    "witheredState",     ft.witheredState or -1,
                    "cutState",          ft.cutState or -1,
                    "maxCutStage",       maxCutStage,
                    "minForage",         ft.minForageGrowthState or -1,
                    "maxForage",         ft.maxForageGrowthState or -1,
                    "literPerSqm",       ft.literPerSqm or 0,
                    "seedUsagePerSqm",   ft.seedUsagePerSqm or 0,
                    "allowsSeeding",     ft.allowsSeeding == true,
                    "stages",            stages
                ))
            end
        end

        table.sort(entries, function(a, b) return a.name < b.name end)

        FarmMonitor:writeJSON(FarmMonitor.paths.fruitTypes, FarmMonitor.obj(
            "savegameId", FarmMonitor.savegameId,
            "fruitTypes", entries
        ))
        print("[FarmMonitor] fruitTypes.json written (" .. #entries .. " fruit types)")
    end)

    if not ok then
        print("[FarmMonitor] ERROR writing fruitTypes.json: " .. tostring(err))
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
            -- Collect fillTypes needed by active/stopped chains via prod.inputs[n].type
            local activeInputFillTypes = {}
            for _, prod in ipairs(pp.productions) do
                if prod.status ~= ProductionPoint.PROD_STATUS.INACTIVE then
                    for _, input in ipairs(prod.inputs or {}) do
                        if input.type ~= nil then
                            activeInputFillTypes[input.type] = true
                        end
                    end
                end
            end

            -- Inputs: include entries with level=0 when needed by active chains
            local inputs = FarmMonitor.arr()
            if pp.inputFillTypeIds ~= nil then
                for fillTypeId, _ in pairs(pp.inputFillTypeIds) do
                    local level    = pp:getFillLevel(fillTypeId)
                    local capacity = pp:getCapacity(fillTypeId)
                    local needed   = activeInputFillTypes[fillTypeId] == true
                    if level > 0 or capacity > 0 or needed then
                        table.insert(inputs, FarmMonitor.obj(
                            "fillType", g_fillTypeManager:getFillTypeNameByIndex(fillTypeId) or "UNKNOWN",
                            "title",    FarmMonitor:fillTypeTitle(fillTypeId),
                            "level",    MathUtil.round(level),
                            "capacity", MathUtil.round(capacity),
                            "needed",   needed
                        ))
                    end
                end
            end

            -- Collect fillTypes produced by active/stopped chains
            local activeOutputFillTypes = {}
            for _, prod in ipairs(pp.productions) do
                if prod.status ~= ProductionPoint.PROD_STATUS.INACTIVE then
                    for _, output in ipairs(prod.outputs or {}) do
                        if output.type ~= nil then
                            activeOutputFillTypes[output.type] = true
                        end
                    end
                end
            end

            -- Outputs: show if level>0 OR produced by an active/stopped chain
            local outputs = FarmMonitor.arr()
            if pp.outputFillTypeIdsArray ~= nil then
                local hasPSC = g_modIsLoaded["FS25_ProductionStorageControl"]
                for _, fillTypeId in ipairs(pp.outputFillTypeIdsArray) do
                    local level    = pp:getFillLevel(fillTypeId)
                    local capacity = pp:getCapacity(fillTypeId)
                    local needed   = activeOutputFillTypes[fillTypeId] == true
                    if level > 0 or capacity > 0 or needed then
                        local mode = "keep"
                        local m = pp:getOutputDistributionMode(fillTypeId)
                        if m == ProductionPoint.OUTPUT_MODE.DIRECT_SELL then
                            mode = "sell"
                        elseif m == ProductionPoint.OUTPUT_MODE.AUTO_DELIVER then
                            mode = "deliver"
                        elseif hasPSC and m == ProductionPoint.OUTPUT_MODE.STORE then
                            mode = "store"
                        end
                        table.insert(outputs, FarmMonitor.obj(
                            "fillType",   g_fillTypeManager:getFillTypeNameByIndex(fillTypeId) or "UNKNOWN",
                            "title",      FarmMonitor:fillTypeTitle(fillTypeId),
                            "level",      MathUtil.round(level),
                            "capacity",   MathUtil.round(capacity),
                            "outputMode", mode,
                            "needed",     needed
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
                local chainInputs = FarmMonitor.arr()
                for _, input in ipairs(prod.inputs or {}) do
                    if input.type ~= nil then
                        table.insert(chainInputs, FarmMonitor.obj(
                            "fillType",       g_fillTypeManager:getFillTypeNameByIndex(input.type) or "UNKNOWN",
                            "title",          FarmMonitor:fillTypeTitle(input.type),
                            "amountPerCycle", MathUtil.round(input.amount or 0)
                        ))
                    end
                end
                local chainOutputs = FarmMonitor.arr()
                for _, output in ipairs(prod.outputs or {}) do
                    if output.type ~= nil then
                        table.insert(chainOutputs, FarmMonitor.obj(
                            "fillType",       g_fillTypeManager:getFillTypeNameByIndex(output.type) or "UNKNOWN",
                            "title",          FarmMonitor:fillTypeTitle(output.type),
                            "amountPerCycle", MathUtil.round(output.amount or 0)
                        ))
                    end
                end
                table.insert(chains, FarmMonitor.obj(
                    "id",             prod.id or "",
                    "name",           prod.name or "",
                    "status",         status,
                    "cyclesPerMonth", MathUtil.round(prod.cyclesPerMonth or 0),
                    "inputs",         chainInputs,
                    "outputs",        chainOutputs
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
-- Fields  (density-map approach, based on FS25_FarmlandOverview by Fetty42)
-- ---------------------------------------------------------------------------

local function buildFieldSoilSamplers()
    local mission = g_currentMission
    if mission == nil or mission.fieldGroundSystem == nil or FieldDensityMap == nil then
        return nil
    end

    local fgs  = mission.fieldGroundSystem
    local layers = {
        mulch  = FieldDensityMap.STUBBLE_SHRED_LEVEL,
        plow   = FieldDensityMap.PLOW_LEVEL,
        roll   = FieldDensityMap.ROLLER_LEVEL,
        spray  = FieldDensityMap.SPRAY_LEVEL,
        lime   = FieldDensityMap.LIME_LEVEL,
    }

    local samplers = {}
    for key, layerId in pairs(layers) do
        local mapId, firstCh, numCh = fgs:getDensityMapData(layerId)
        if mapId ~= nil then
            local modifier = DensityMapModifier.new(mapId, firstCh, numCh, g_terrainNode)
            local filter   = DensityMapFilter.new(modifier)
            local maxVal   = nil
            if fgs.getMaxValue ~= nil then
                maxVal = fgs:getMaxValue(layerId)
            end
            samplers[key] = { modifier = modifier, filter = filter, maxValue = maxVal }
        end
    end

    if mission.weedSystem ~= nil and mission.weedSystem.getDensityMapData ~= nil then
        local ok, mapId, firstCh, numCh = pcall(function()
            return mission.weedSystem:getDensityMapData()
        end)
        if ok and mapId ~= nil then
            local modifier = DensityMapModifier.new(mapId, firstCh, numCh, g_terrainNode)
            samplers.weed = { modifier = modifier, filter = DensityMapFilter.new(modifier), maxValue = 9 }
        end
    end

    if mission.stoneSystem ~= nil and mission.stoneSystem.getDensityMapData ~= nil then
        local ok, mapId, firstCh, numCh = pcall(function()
            return mission.stoneSystem:getDensityMapData()
        end)
        if ok and mapId ~= nil then
            local modifier = DensityMapModifier.new(mapId, firstCh, numCh, g_terrainNode)
            samplers.stone = { modifier = modifier, filter = DensityMapFilter.new(modifier) }
        end
    end

    return samplers
end

local function applyPolygon(field, modifier)
    local poly = field:getDensityMapPolygon()
    if poly == nil then return false end
    poly:applyToModifier(modifier)
    return true
end

local function areaForValue(modifier, filter, value)
    filter:setValueCompareParams(DensityValueCompareType.EQUAL, value)
    local _, area, total = modifier:executeGet(filter)
    return area or 0, total or 0
end

local function pct(area, total)
    if total == nil or total <= 0 then return 0 end
    return (area / total) * 100
end

local function computeSoilStatus(field, samplers)
    if field == nil or samplers == nil then return {} end
    local s = {}

    -- Mulch: 0/1 binary; report % covered
    if samplers.mulch then
        local m, f = samplers.mulch.modifier, samplers.mulch.filter
        if applyPolygon(field, m) then
            local a, tot = areaForValue(m, f, 1)
            s.mulchPct = pct(a, tot)
        end
    end

    -- Plow: 0/1 binary
    if samplers.plow then
        local m, f = samplers.plow.modifier, samplers.plow.filter
        if applyPolygon(field, m) then
            local a, tot = areaForValue(m, f, 1)
            s.plowPct = pct(a, tot)
        end
    end

    -- Roll: 0/1 (value=1 means "needs rolling" → invert: rolled = low coverage)
    if samplers.roll then
        local m, f = samplers.roll.modifier, samplers.roll.filter
        if applyPolygon(field, m) then
            local a, tot = areaForValue(m, f, 1)
            s.needsRollingPct = pct(a, tot)
        end
    end

    -- Fertilizer (0/1/2): gating with 90% threshold
    if samplers.spray then
        local m, f   = samplers.spray.modifier, samplers.spray.filter
        local maxVal = samplers.spray.maxValue or 2
        if applyPolygon(field, m) then
            local a2, tot = areaForValue(m, f, math.min(2, maxVal))
            local a1, _   = areaForValue(m, f, math.min(1, maxVal))
            local p2 = pct(a2, tot)
            local p1 = pct(a1, tot)
            if maxVal >= 2 and p2 >= 90 then
                s.fertPct = 100
            elseif maxVal >= 2 and p2 > 0 then
                local a0 = math.max(0, tot - a1 - a2)
                s.fertPct = (a1 >= a0) and 50 or 0
            else
                s.fertPct = (p1 >= 90) and 50 or 0
            end
        end
    end

    -- Lime (0/1/2/3): multi-step with 90% gating on top value
    if samplers.lime then
        local m, f   = samplers.lime.modifier, samplers.lime.filter
        local maxVal = samplers.lime.maxValue or 3
        if applyPolygon(field, m) then
            local a3, tot = areaForValue(m, f, math.min(3, maxVal))
            local a2, _   = areaForValue(m, f, math.min(2, maxVal))
            local a1, _   = areaForValue(m, f, math.min(1, maxVal))
            local p3 = pct(a3, tot)
            if maxVal >= 3 and p3 >= 90 then
                s.limePct = 100
            else
                local a0 = math.max(0, tot - a1 - a2 - a3)
                if a2 >= a1 and a2 >= a0 then
                    s.limePct = 66.7
                elseif a1 >= a0 then
                    s.limePct = 33.3
                else
                    s.limePct = 0
                end
            end
        end
    end

    -- Weeds: penalizing if values 3/4/5 cover ≥ 10%
    if samplers.weed then
        local m, f = samplers.weed.modifier, samplers.weed.filter
        if applyPolygon(field, m) then
            local a3, tot = areaForValue(m, f, 3)
            local a4, _   = areaForValue(m, f, 4)
            local a5, _   = areaForValue(m, f, 5)
            s.weedPct = pct(a3 + a4 + a5, tot)
        end
    end

    -- Stones: any coverage > 0.1%
    if samplers.stone then
        local m, f = samplers.stone.modifier, samplers.stone.filter
        if applyPolygon(field, m) then
            local a2, tot = areaForValue(m, f, 2)
            local a3, _   = areaForValue(m, f, 3)
            local a4, _   = areaForValue(m, f, 4)
            s.stonePct = pct(a2 + a3 + a4, tot)
        end
    end

    return s
end

function FarmMonitor:collectAndSaveFields()
    local ok, err = pcall(function()
        local ts     = getDate("%Y-%m-%dT%H:%M:%S")
        local farmId = g_currentMission:getFarmId()
        FarmMonitor:writeJSON(FarmMonitor.paths.fields, FarmMonitor.obj(
            "timestamp",  ts,
            "farmId",     farmId,
            "savegame",   FarmMonitor.savegameName,
            "savegameId", FarmMonitor.savegameId,
            "fields",     FarmMonitor:collectFields()
        ))
    end)
    if not ok then
        print("[FarmMonitor] ERROR during field collect: " .. tostring(err))
    end
end

function FarmMonitor:collectFields()
    local result  = FarmMonitor.arr()
    local farmId  = g_currentMission:getFarmId()
    local mission = g_currentMission
    if g_farmlandManager == nil then return result end

    local yieldSettings = {
        plowingRequired = (mission.missionInfo ~= nil) and (mission.missionInfo.plowingRequiredEnabled ~= false),
        limeRequired    = (mission.missionInfo ~= nil) and (mission.missionInfo.limeRequired ~= false),
        weedsEnabled    = (mission.missionInfo ~= nil) and (mission.missionInfo.weedsEnabled ~= false),
    }

    local samplers = buildFieldSoilSamplers()

    -- Spray type application rates (liters per hectare = litersPerSecond * 36000)
    local function sprayLph(name)
        if g_sprayTypeManager == nil then return 0 end
        local st = g_sprayTypeManager:getSprayTypeByName(name)
        if st == nil or st.litersPerSecond == nil then return 0 end
        return st.litersPerSecond * 36000
    end
    local limeLph  = sprayLph("LIME")
    local fertLph  = sprayLph("FERTILIZER")
    local herbLph  = sprayLph("HERBICIDE")

    for _, farmland in pairs(g_farmlandManager.farmlands or {}) do
        if farmland ~= nil
            and farmland.showOnFarmlandsScreen
            and farmland.farmId == farmId
            and farmland.field ~= nil
        then
            local field  = farmland.field
            local areaHa      = farmland.areaInHa or 0
            local fieldAreaHa = field.areaHa or 0

            -- Fruit type & growth state via density map at field centre
            local fruitTypeName        = ""
            local fruitTypeTitle       = ""
            local growthStage          = 0
            local minHarvest           = 0
            local maxHarvest           = 0
            local harvestReady         = false
            local withered             = false
            local isCut                = false
            local fruitTypeIndex       = nil
            local needsPreparation     = false
            local seedLph              = nil
            local seedTotal            = nil

            local cx, cz = field:getCenterOfFieldWorldPosition()
            if cx ~= nil then
                local ftIdx, gs = FSDensityMapUtil.getFruitTypeIndexAtWorldPos(cx, cz)
                if ftIdx ~= nil and ftIdx > 0 then
                    fruitTypeIndex = ftIdx
                    local ft = g_fruitTypeManager:getFruitTypeByIndex(ftIdx)
                    if ft ~= nil then
                        fruitTypeName     = ft.name or ""
                        fruitTypeTitle    = (ft.fillType and ft.fillType.title) or ft.name or ""
                        growthStage       = gs or 0
                        minHarvest        = ft.minHarvestingGrowthState or 0
                        maxHarvest        = ft.maxHarvestingGrowthState or 0
                        harvestReady      = ft:getIsHarvestReady(growthStage)
                        needsPreparation  = ft:getIsPreparable(growthStage)
                        isCut             = ft:getIsCut(growthStage)
                        withered          = ft:getIsWithered(growthStage)
                        -- Fallback: custom map crops may define post-harvest stages
                        -- (e.g. tyre tracks) with isCut="false". Any stage above the
                        -- highest known cut stage is treated as harvested.
                        if not harvestReady and not isCut and not withered and not needsPreparation then
                            local maxCutStage = ft.cutState or 0
                            if ft.cutStates then
                                for k, _ in pairs(ft.cutStates) do
                                    if k > maxCutStage then maxCutStage = k end
                                end
                            end
                            if maxCutStage > 0 and growthStage > maxCutStage then
                                isCut = true
                            end
                        end
                        -- Seed requirement for this fruit type
                        if ft.seedUsagePerSqm ~= nil and ft.seedUsagePerSqm > 0 then
                            local lph = ft.seedUsagePerSqm * 10000
                            seedLph   = MathUtil.round(lph * 10) / 10
                            seedTotal = MathUtil.round(lph * fieldAreaHa)
                        end
                    end
                end
            end

            -- Soil status via density maps
            local soil = {}
            if samplers ~= nil and cx ~= nil then
                soil = computeSoilStatus(field, samplers)
            end

            -- Harvest yield multiplier via engine function
            local yieldBonus = nil
            if fruitTypeIndex ~= nil and mission.getHarvestScaleMultiplier ~= nil then
                local sprayF  = (soil.fertPct or 0) / 100
                local plowF   = (not yieldSettings.plowingRequired) and 1 or (((soil.plowPct or 0) >= 90) and 1 or 0)
                local limeF   = (not yieldSettings.limeRequired)    and 1 or ((soil.limePct or 0) / 100)
                local weedPen = (not yieldSettings.weedsEnabled)    and 0 or ((soil.weedPct or 0) >= 10 and 1 or 0)
                local weedBon = math.max(0, 1 - weedPen)
                local mulchF  = (((soil.mulchPct or 0) >= 90) and 1 or 0)
                local rollF   = (((soil.needsRollingPct or 100) <= 10) and 1 or 0)
                local ok, m = pcall(mission.getHarvestScaleMultiplier, mission,
                    fruitTypeIndex, sprayF, plowF, limeF, weedBon, mulchF, rollF)
                if ok and type(m) == "number" then
                    yieldBonus = MathUtil.round((m - 1.0) * 1000) / 10  -- % with 1 decimal
                end
            end

            table.insert(result, FarmMonitor.obj(
                "id",              farmland.name or tostring(farmland.id or 0),
                "farmlandId",      farmland.id or 0,
                "area",            MathUtil.round(areaHa * 100) / 100,
                "fieldArea",       MathUtil.round(fieldAreaHa * 100) / 100,
                "fruitType",       fruitTypeName,
                "fruitTitle",      fruitTypeTitle,
                "growthStage",     growthStage,
                "minHarvest",      minHarvest,
                "maxHarvest",      maxHarvest,
                "harvestReady",       harvestReady,
                "needsPreparation",  needsPreparation,
                "withered",          withered,
                "cut",               isCut,
                "yieldBonusPct",   yieldBonus,
                "mulchPct",        soil.mulchPct        or 0,
                "plowPct",         soil.plowPct         or 0,
                "needsRollingPct", soil.needsRollingPct or 0,
                "fertPct",         soil.fertPct         or 0,
                "limePct",         soil.limePct         or 0,
                "weedPct",         soil.weedPct         or 0,
                "stonePct",        soil.stonePct        or 0,
                "seedLph",         seedLph,
                "seedTotal",       seedTotal,
                "matLimeLph",      limeLph > 0 and MathUtil.round(limeLph)             or nil,
                "matLimeTotal",    limeLph > 0 and MathUtil.round(limeLph * fieldAreaHa) or nil,
                "matFertLph",      fertLph > 0 and MathUtil.round(fertLph)             or nil,
                "matFertTotal",    fertLph > 0 and MathUtil.round(fertLph * fieldAreaHa) or nil,
                "matHerbLph",      herbLph > 0 and MathUtil.round(herbLph)             or nil,
                "matHerbTotal",    herbLph > 0 and MathUtil.round(herbLph * fieldAreaHa) or nil
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
-- Command processing (file-based IPC: Go server → Lua mod)
-- ---------------------------------------------------------------------------

function FarmMonitor:processCommands()
    if not fileExists(FarmMonitor.paths.commandsXml) then return end

    local xmlId = loadXMLFile("FMCommands", FarmMonitor.paths.commandsXml)
    if xmlId == nil or xmlId == 0 then return end

    -- Delete file before processing (at-most-once semantics)
    deleteFile(FarmMonitor.paths.commandsXml)

    local count = getXMLInt(xmlId, "commands#count") or 0
    local processed = {}

    for i = 0, count - 1 do
        local base = string.format("commands.command(%d)", i)
        local cmd = {
            id       = getXMLString(xmlId, base .. "#id")       or "",
            cmd      = getXMLString(xmlId, base .. "#cmd")      or "",
            uniqueId = getXMLString(xmlId, base .. "#uniqueId") or "",
            fillType = getXMLString(xmlId, base .. "#fillType") or "",
            mode     = getXMLString(xmlId, base .. "#mode")     or "",
        }
        if cmd.cmd ~= "" then
            local ok, err = pcall(FarmMonitor.dispatchCommand, FarmMonitor, cmd)
            if ok then
                table.insert(processed, cmd.id)
            else
                print("[FarmMonitor] Command error (" .. tostring(cmd.cmd) .. "): " .. tostring(err))
            end
        end
    end

    local parts = {}
    for _, id in ipairs(processed) do
        table.insert(parts, '"' .. id .. '"')
    end
    local ack = io.open(FarmMonitor.paths.commandsAck, "w")
    if ack then
        ack:write('{"processed":[' .. table.concat(parts, ",") .. ']}')
        ack:close()
    end
end

function FarmMonitor:dispatchCommand(cmd)
    local handlers = {
        ["production.setOutputMode"] = FarmMonitor.cmdSetProductionOutputMode,
    }
    local handler = handlers[cmd.cmd]
    if handler then
        handler(FarmMonitor, cmd)
    else
        print("[FarmMonitor] Unknown command: " .. tostring(cmd.cmd))
    end
end

function FarmMonitor:cmdSetProductionOutputMode(cmd)
    local modeMap = {
        keep    = ProductionPoint.OUTPUT_MODE.KEEP,
        sell    = ProductionPoint.OUTPUT_MODE.DIRECT_SELL,
        deliver = ProductionPoint.OUTPUT_MODE.AUTO_DELIVER,
        store   = ProductionPoint.OUTPUT_MODE.STORE,
    }
    local mode = modeMap[cmd.mode]
    if mode == nil then error("Unknown mode: " .. tostring(cmd.mode)) end

    local placeable = g_currentMission.placeableSystem:getPlaceableByUniqueId(cmd.uniqueId)
    if placeable == nil or placeable.spec_productionPoint == nil then
        error("Production placeable not found: " .. tostring(cmd.uniqueId))
    end

    local pp = placeable.spec_productionPoint.productionPoint
    local ft = g_fillTypeManager:getFillTypeByName(cmd.fillType)
    if ft == nil then error("FillType not found: " .. tostring(cmd.fillType)) end

    pp:setOutputDistributionMode(ft.index, mode)
    ProductionPointOutputModeEvent.sendEvent(pp, ft.index, mode, true)
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
