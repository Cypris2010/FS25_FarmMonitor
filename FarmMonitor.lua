-- FarmMonitor.lua
-- Collects data from silos, productions and animal husbandries,
-- then writes each category to its own JSON file in the mod directory.

local modDirectory = g_currentModDirectory  -- capture before it gets reset

FarmMonitor = {}
FarmMonitor.updateInterval    = 10000  -- milliseconds between exports
FarmMonitor.timer             = 0
FarmMonitor.paths             = {}
FarmMonitor.fillTypesExported = false

addModEventListener(FarmMonitor)

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function FarmMonitor:loadMap(name)
    FarmMonitor.paths.silos       = modDirectory .. "silos.json"
    FarmMonitor.paths.productions = modDirectory .. "productions.json"
    FarmMonitor.paths.husbandries = modDirectory .. "husbandries.json"
    FarmMonitor.paths.fillTypes   = modDirectory .. "fillTypes.json"
    print("[FarmMonitor] Mod loaded. Output directory: " .. modDirectory)
end

function FarmMonitor:deleteMap()
end

function FarmMonitor:update(dt)
    if g_currentMission == nil or not g_currentMission.isMissionStarted then
        return
    end

    if not FarmMonitor.fillTypesExported then
        FarmMonitor:exportFillTypes()
        FarmMonitor.fillTypesExported = true
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
        local ts     = getDate("%Y-%m-%dT%H:%M:%S")
        local farmId = g_currentMission:getFarmId()

        FarmMonitor:writeJSON(FarmMonitor.paths.silos, FarmMonitor.obj(
            "timestamp", ts, "farmId", farmId,
            "silos",     FarmMonitor:collectSilos()
        ))
        FarmMonitor:writeJSON(FarmMonitor.paths.productions, FarmMonitor.obj(
            "timestamp",   ts, "farmId", farmId,
            "productions", FarmMonitor:collectProductions()
        ))
        FarmMonitor:writeJSON(FarmMonitor.paths.husbandries, FarmMonitor.obj(
            "timestamp",   ts, "farmId", farmId,
            "husbandries", FarmMonitor:collectHusbandries()
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

        FarmMonitor:writeJSON(FarmMonitor.paths.fillTypes, entries)
        print("[FarmMonitor] fillTypes.json written (" .. #entries .. " entries)")
    end)

    if not ok then
        print("[FarmMonitor] ERROR writing fillTypes.json: " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- Silos
-- ---------------------------------------------------------------------------

function FarmMonitor:collectSilos()
    local result = {}
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
    local result = {}
    local farmId = g_currentMission:getFarmId()

    if g_currentMission.productionChainManager == nil then return result end

    for _, pp in ipairs(g_currentMission.productionChainManager.productionPoints) do
        if pp:getOwnerFarmId() == farmId then
            -- Inputs: all fill types stored as input for this production point
            local inputs = {}
            if pp.inputFillTypeIds ~= nil then
                for fillTypeId, _ in pairs(pp.inputFillTypeIds) do
                    local level    = pp.storage:getFillLevel(fillTypeId)
                    local capacity = pp.storage:getCapacity(fillTypeId)
                    if capacity > 0 then
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
            local outputs = {}
            if pp.outputFillTypeIdsArray ~= nil then
                for _, fillTypeId in ipairs(pp.outputFillTypeIdsArray) do
                    local level    = pp.storage:getFillLevel(fillTypeId)
                    local capacity = pp.storage:getCapacity(fillTypeId)
                    if capacity > 0 then
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
            local chains = {}
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
    local result = {}
    local farmId = g_currentMission:getFarmId()

    if g_currentMission.placeableSystem == nil then return result end

    for _, placeable in ipairs(g_currentMission.placeableSystem.placeables) do
        if placeable.spec_husbandry ~= nil and placeable.ownerFarmId == farmId then
            local entry = {
                name        = FarmMonitor:placeableName(placeable),
                animalType  = FarmMonitor:getAnimalType(placeable),
                numAnimals  = FarmMonitor:countAnimals(placeable),
                maxAnimals  = FarmMonitor:maxAnimals(placeable),
                food        = FarmMonitor:getFoodInfo(placeable),
                water       = FarmMonitor:getWaterInfo(placeable),
                outputs     = {},
            }

            -- Husbandry output storage (milk, eggs, wool, …)
            if placeable.spec_husbandry.storage ~= nil then
                local storage = placeable.spec_husbandry.storage
                for fillTypeId, level in pairs(storage.fillLevels or {}) do
                    if level > 0 then
                        local capacity = 0
                        if storage.capacities ~= nil then
                            capacity = storage.capacities[fillTypeId] or 0
                        end
                        table.insert(entry.outputs, {
                            fillType = g_fillTypeManager:getFillTypeNameByIndex(fillTypeId) or "UNKNOWN",
                            title    = FarmMonitor:fillTypeTitle(fillTypeId),
                            level    = MathUtil.round(level),
                            capacity = MathUtil.round(capacity),
                        })
                    end
                end
            end

            table.insert(result, entry)
        end
    end

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
    local spec = placeable.spec_husbandryFood
    if spec ~= nil and spec.animalTypeIndex ~= nil and g_animalTypeManager ~= nil then
        local t = g_animalTypeManager:getTypeByIndex(spec.animalTypeIndex)
        if t ~= nil then return t.name or t.typeName or "unknown" end
    end
    return "unknown"
end

function FarmMonitor:getFoodInfo(placeable)
    -- Use the base-game getFoodInfos() method when available
    if placeable.getFoodInfos ~= nil then
        local ok, infos = pcall(function() return placeable:getFoodInfos() end)
        if ok and type(infos) == "table" then
            local entries = {}
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

    return {}
end

function FarmMonitor:getWaterInfo(placeable)
    local spec = placeable.spec_husbandryWater
    if spec == nil then return nil end

    local level    = spec.fillLevel or 0
    local capacity = spec.capacity  or 0
    return {
        value    = MathUtil.round(level),
        capacity = MathUtil.round(capacity),
    }
end

-- ---------------------------------------------------------------------------
-- Generic helpers
-- ---------------------------------------------------------------------------

function FarmMonitor:readFillLevels(storage)
    local contents = {}
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

        -- Plain array
        local isArray = (#value > 0)
        if isArray then
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
