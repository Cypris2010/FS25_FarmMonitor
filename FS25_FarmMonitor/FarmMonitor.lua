-- FarmMonitor.lua
-- Collects data from silos, productions and animal husbandries,
-- then writes each category to its own JSON file in the modSettings directory.

local modName = g_currentModName  -- capture before it gets reset

FarmMonitor = {}
FarmMonitor.updateInterval    = 10000  -- milliseconds between exports
FarmMonitor.timer             = 0
FarmMonitor.fieldInterval     = 60000  -- milliseconds between field exports
FarmMonitor.fieldTimer        = 60000  -- start at max so first export fires immediately
FarmMonitor.vehicleInterval     = 2000   -- milliseconds between vehicle exports
FarmMonitor.vehicleTimer        = 0
FarmMonitor.vehicleMetaInterval = 10000  -- milliseconds between vehicle meta exports
FarmMonitor.vehicleMetaTimer    = 10000  -- start at max so first export fires immediately
FarmMonitor.commandInterval   = 1000   -- milliseconds between command checks
FarmMonitor.commandTimer      = 0
FarmMonitor.weatherInterval   = 30000  -- milliseconds between weather exports
FarmMonitor.weatherTimer      = 30000  -- start at max so first export fires immediately
FarmMonitor.soilState         = nil    -- incremental soil export state machine
FarmMonitor.paths             = {}
FarmMonitor.modInfoExported       = false
FarmMonitor.fillTypesExported   = false
FarmMonitor.animalFoodExported  = false
FarmMonitor.fruitTypesExported  = false
FarmMonitor.mapMetaExported     = false
FarmMonitor.fieldMetaExported   = false
FarmMonitor.hotspotsExported          = false
FarmMonitor.vehicleCategoriesExported = false
FarmMonitor.autoDriveMarkersExported  = false
FarmMonitor.savegameName        = nil
FarmMonitor.savegameId          = nil
FarmMonitor.savegameDirectory   = nil
FarmMonitor.savegameInfoReady   = false  -- true once savegame info is known (server: after XML read; client: after event or timeout)
FarmMonitor.savegameInfoTimeout = 10000  -- ms: give up waiting for server event after this long
FarmMonitor.savegameRequestSent = false  -- true once client has sent FarmMonitorRequestEvent to server
FarmMonitor.palletInfoCache     = nil  -- built once per session by buildPalletInfoCache()

addModEventListener(FarmMonitor)

-- ---------------------------------------------------------------------------
-- Network Event: Savegame Info (Server → Client on join)
-- ---------------------------------------------------------------------------

FarmMonitorSavegameEvent = {}
FarmMonitorSavegameEvent_mt = Class(FarmMonitorSavegameEvent, Event)
InitEventClass(FarmMonitorSavegameEvent, "FarmMonitorSavegameEvent")

function FarmMonitorSavegameEvent.emptyNew()
    return Event.new(FarmMonitorSavegameEvent_mt)
end

function FarmMonitorSavegameEvent.new(savegameName, savegameId)
    local self = FarmMonitorSavegameEvent.emptyNew()
    self.savegameName = savegameName or "unknown"
    self.savegameId   = savegameId   or "unknown"
    return self
end

function FarmMonitorSavegameEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.savegameName)
    streamWriteString(streamId, self.savegameId)
end

function FarmMonitorSavegameEvent:readStream(streamId, connection)
    self.savegameName = streamReadString(streamId)
    self.savegameId   = streamReadString(streamId)
    self:run(connection)
end

function FarmMonitorSavegameEvent:run(connection)
    -- Called on the client after receiving the event from the server
    FarmMonitor.savegameName      = self.savegameName
    FarmMonitor.savegameId        = self.savegameId
    FarmMonitor.savegameInfoReady = true
    print("[FarmMonitor] Received savegame info from server: name=" .. self.savegameName .. " id=" .. self.savegameId)
end

-- ---------------------------------------------------------------------------
-- Network Event: Request savegame info (Client → Server)
-- ---------------------------------------------------------------------------

FarmMonitorRequestEvent = {}
FarmMonitorRequestEvent_mt = Class(FarmMonitorRequestEvent, Event)
InitEventClass(FarmMonitorRequestEvent, "FarmMonitorRequestEvent")

function FarmMonitorRequestEvent.emptyNew()
    return Event.new(FarmMonitorRequestEvent_mt)
end

function FarmMonitorRequestEvent.new()
    return FarmMonitorRequestEvent.emptyNew()
end

function FarmMonitorRequestEvent:writeStream(streamId, connection)
    -- no payload needed
end

function FarmMonitorRequestEvent:readStream(streamId, connection)
    self:run(connection)
end

function FarmMonitorRequestEvent:run(connection)
    -- Called on the SERVER when a client requests savegame info
    if FarmMonitor.savegameName ~= nil and FarmMonitor.savegameId ~= nil then
        connection:sendEvent(FarmMonitorSavegameEvent.new(FarmMonitor.savegameName, FarmMonitor.savegameId))
        print("[FarmMonitor] Sent savegame info to requesting client: " .. FarmMonitor.savegameId)
    else
        print("[FarmMonitor] RequestEvent received but savegame info not yet available")
    end
end

-- ---------------------------------------------------------------------------
-- Network Event: Forward AD command (Client → Server)
-- ---------------------------------------------------------------------------
-- Problem: rootNode handles are process-local — the same vehicle has a
-- different rootNode on the client (e.g. 471894) and on the server (e.g. 338812).
-- Therefore findVehicleByNodeId() always fails when run on the server with a
-- client-side rootNode ID.
--
-- Solution: FarmMonitorADCommandEvent forwards the full IPC cmd table from the
-- client to the server via FS25's built-in network stream. On the server the
-- command is executed with authority using resolveVehicle(), which uses
-- NetworkUtil.getObject(netId) — a network-synchronised ID that is identical
-- on client and server in all scenarios:
--   • Singleplayer:          client = server → both paths work
--   • Non-dedicated MP:      host runs server + client in same process → works
--   • Dedicated server:      separate processes → netId is the only correct path
--
-- In SP the if-guard (g_server == nil and g_client ~= nil) is false, so the
-- event is never sent and the command runs locally without any overhead.

FarmMonitorADCommandEvent = {}
FarmMonitorADCommandEvent_mt = Class(FarmMonitorADCommandEvent, Event)
InitEventClass(FarmMonitorADCommandEvent, "FarmMonitorADCommandEvent")

function FarmMonitorADCommandEvent.emptyNew()
    return Event.new(FarmMonitorADCommandEvent_mt)
end

function FarmMonitorADCommandEvent.new(cmd)
    local self = FarmMonitorADCommandEvent.emptyNew()
    self.cmd = cmd
    return self
end

function FarmMonitorADCommandEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.cmd.cmd      or "")
    streamWriteString(streamId, self.cmd.uniqueId or "")
    streamWriteString(streamId, self.cmd.netId    or "")  -- NetworkUtil object ID (MP-safe, same on all processes)
    streamWriteString(streamId, self.cmd.mode     or "")
    streamWriteString(streamId, self.cmd.marker1  or "")
    streamWriteString(streamId, self.cmd.marker2  or "")
    streamWriteString(streamId, self.cmd.fillType or "")
    streamWriteString(streamId, self.cmd.setting  or "")  -- for autodrive.setting
    streamWriteString(streamId, self.cmd.value    or "")  -- for setting/loopCounter/speedLimit
end

function FarmMonitorADCommandEvent:readStream(streamId, connection)
    self.cmd = {
        cmd      = streamReadString(streamId),
        uniqueId = streamReadString(streamId),
        netId    = streamReadString(streamId),
        mode     = streamReadString(streamId),
        marker1  = streamReadString(streamId),
        marker2  = streamReadString(streamId),
        fillType = streamReadString(streamId),
        setting  = streamReadString(streamId),
        value    = streamReadString(streamId),
    }
    self:run(connection)
end

function FarmMonitorADCommandEvent:run(connection)
    -- Called on the server: execute the AD command with server authority.
    -- resolveVehicle() uses netId (NetworkUtil) as primary lookup, rootNode as fallback.
    print("[FarmMonitor] FarmMonitorADCommandEvent received on server, dispatching: " .. tostring(self.cmd.cmd))
    local ok, err = pcall(FarmMonitor.dispatchCommand, FarmMonitor, self.cmd)
    if not ok then
        print("[FarmMonitor] FarmMonitorADCommandEvent dispatch error: " .. tostring(err))
    end
end

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
    FarmMonitor.paths.fieldMeta    = outputDir .. "fieldMeta.json"
    FarmMonitor.paths.fruitTypes   = outputDir .. "fruitTypes.json"
    FarmMonitor.paths.mapMeta      = outputDir .. "mapMeta.json"
    FarmMonitor.paths.hotspots     = outputDir .. "hotspots.json"
    FarmMonitor.paths.vehicles     = outputDir .. "vehicles.json"
    FarmMonitor.paths.vehicleMeta       = outputDir .. "vehicleMeta.json"
    FarmMonitor.paths.vehicleCategories = outputDir .. "vehicleCategories.json"
    FarmMonitor.paths.autoDriveMarkers  = outputDir .. "autoDriveMarkers.json"
    FarmMonitor.paths.modInfo           = outputDir .. "modInfo.json"
    FarmMonitor.paths.weather           = outputDir .. "weather.json"
    FarmMonitor.paths.commandsXml = outputDir .. "commands.xml"
    FarmMonitor.paths.commandsAck = outputDir .. "commands.ack"
    FarmMonitor.paths.config      = outputDir .. "config.xml"
    FarmMonitor.paths.outputDir   = outputDir
    FarmMonitor:loadConfig()
    print("[FarmMonitor] Mod loaded. Output directory: " .. outputDir)
end

function FarmMonitor:loadConfig()
    local path = FarmMonitor.paths.config
    local defaults = {
        mainInterval     = 10,
        vehicleInterval  = 2,
        fieldInterval    = 60,
        weatherInterval  = 30,
        commandInterval  = 1,
        soilResolution   = 128,
        soilRowsPerTick  = 2,
    }

    local cfg = {}
    if fileExists(path) then
        local ok, err = pcall(function()
            local xmlId = loadXMLFile("FMConfig", path)
            if xmlId == nil or xmlId == 0 then error("loadXMLFile failed") end
            local function getInt(key, default)
                local v = getXMLInt(xmlId, "farmMonitor." .. key)
                return (v ~= nil and v > 0) and v or default
            end
            cfg.mainInterval    = getInt("exportIntervals.main#seconds",    defaults.mainInterval)
            cfg.vehicleInterval = getInt("exportIntervals.vehicles#seconds", defaults.vehicleInterval)
            cfg.fieldInterval   = getInt("exportIntervals.fields#seconds",   defaults.fieldInterval)
            cfg.weatherInterval = getInt("exportIntervals.weather#seconds",  defaults.weatherInterval)
            cfg.commandInterval = getInt("exportIntervals.commands#seconds", defaults.commandInterval)
            cfg.soilResolution  = getInt("soilMap.resolution#value",         defaults.soilResolution)
            cfg.soilRowsPerTick = getInt("soilMap.rowsPerTick#value",        defaults.soilRowsPerTick)
            delete(xmlId)
        end)
        if not ok then
            print("[FarmMonitor] WARNING: Could not read config.xml, using defaults. Error: " .. tostring(err))
            cfg = defaults
        end
    else
        cfg = defaults
        -- Write default config so user can discover and edit it
        local f = io.open(path, "w")
        if f then
            f:write('<?xml version="1.0" encoding="utf-8"?>\n')
            f:write('<farmMonitor>\n')
            f:write('    <!-- Export intervals in seconds -->\n')
            f:write('    <exportIntervals>\n')
            f:write('        <main seconds="'     .. defaults.mainInterval     .. '"/>\n')
            f:write('        <vehicles seconds="' .. defaults.vehicleInterval  .. '"/>\n')
            f:write('        <fields seconds="'   .. defaults.fieldInterval    .. '"/>\n')
            f:write('        <weather seconds="'  .. defaults.weatherInterval  .. '"/>\n')
            f:write('        <commands seconds="' .. defaults.commandInterval  .. '"/>\n')
            f:write('    </exportIntervals>\n')
            f:write('    <!-- Soil map quality: resolution 64/128/256, rowsPerTick 1-8 -->\n')
            f:write('    <soilMap>\n')
            f:write('        <resolution value="'   .. defaults.soilResolution  .. '"/>\n')
            f:write('        <rowsPerTick value="'  .. defaults.soilRowsPerTick .. '"/>\n')
            f:write('    </soilMap>\n')
            f:write('</farmMonitor>\n')
            f:close()
            print("[FarmMonitor] Created default config.xml at: " .. path)
        end
    end

    -- Apply to runtime variables (convert seconds → milliseconds)
    FarmMonitor.updateInterval      = cfg.mainInterval    * 1000
    FarmMonitor.vehicleInterval     = cfg.vehicleInterval * 1000
    FarmMonitor.fieldInterval       = cfg.fieldInterval   * 1000
    FarmMonitor.weatherInterval     = cfg.weatherInterval * 1000
    FarmMonitor.commandInterval     = cfg.commandInterval * 1000
    FarmMonitor.soilResolution      = cfg.soilResolution
    FarmMonitor.soilRowsPerTick     = cfg.soilRowsPerTick

    print("[FarmMonitor] Config loaded:")
    print(string.format("[FarmMonitor]   Haupt-Export    : %d s", cfg.mainInterval))
    print(string.format("[FarmMonitor]   Fahrzeuge       : %d s", cfg.vehicleInterval))
    print(string.format("[FarmMonitor]   Felder          : %d s", cfg.fieldInterval))
    print(string.format("[FarmMonitor]   Wetter          : %d s", cfg.weatherInterval))
    print(string.format("[FarmMonitor]   IPC-Commands    : %d s", cfg.commandInterval))
    print(string.format("[FarmMonitor]   Soil-Aufloesung : %d px", cfg.soilResolution))
    print(string.format("[FarmMonitor]   Soil-RowsPerTick: %d", cfg.soilRowsPerTick))
end

function FarmMonitor:deleteMap()
end

function FarmMonitor:update(dt)
    if g_currentMission == nil or not g_currentMission.isMissionStarted then
        return
    end

    -- Detect savegame change: reset state so files are re-exported for the new savegame
    local currentDir = g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory
    if currentDir ~= FarmMonitor.savegameDirectory then
        FarmMonitor.savegameDirectory  = currentDir
        FarmMonitor.savegameName        = nil
        FarmMonitor.savegameId          = nil
        FarmMonitor.savegameInfoReady   = false
        FarmMonitor.savegameInfoTimeout = 10000
        FarmMonitor.savegameRequestSent = false
        FarmMonitor.fillTypesExported  = false
        FarmMonitor.animalFoodExported = false
        FarmMonitor.fruitTypesExported = false
        FarmMonitor.mapMetaExported    = false
        FarmMonitor.fieldMetaExported  = false
        FarmMonitor.hotspotsExported          = false
        FarmMonitor.vehicleCategoriesExported = false
        FarmMonitor.autoDriveLastMaxId        = 0
        FarmMonitor.autoDriveMarkerCache      = nil
        FarmMonitor.autoDriveRetryTimer       = 4500  -- ersten Versuch nach 0.5s
        FarmMonitor.timer              = 0
        FarmMonitor.fieldTimer         = FarmMonitor.fieldInterval      -- trigger field export on next tick
        FarmMonitor.soilState          = nil                             -- reset incremental soil export
        FarmMonitor.vehicleMetaTimer   = FarmMonitor.vehicleMetaInterval -- trigger meta export on next tick
    end

    if not FarmMonitor.savegameInfoReady then
        if g_server ~= nil then
            -- Singleplayer, MP host, or Dedicated Server: read directly from careerSavegame.xml
            FarmMonitor.savegameName, FarmMonitor.savegameId = FarmMonitor:readSavegameInfo()
            if FarmMonitor.savegameId == nil then
                -- savegameDirectory not yet available (new unsaved game) — use fallback and retry next tick
                local mi = g_currentMission and g_currentMission.missionInfo
                FarmMonitor.savegameName = FarmMonitor.savegameName or "unknown"
                FarmMonitor.savegameId   = ((mi and mi.mapId) or "unknown") .. "_unsaved"
                print("[FarmMonitor] savegameDirectory not yet set, using fallback id: " .. FarmMonitor.savegameId)
            end
            FarmMonitor.savegameInfoReady = true
        else
            -- MP client: request savegame info from server (pull model).
            if not FarmMonitor.savegameRequestSent and g_client ~= nil then
                local serverConn = g_client:getServerConnection()
                if serverConn ~= nil then
                    serverConn:sendEvent(FarmMonitorRequestEvent.new())
                    FarmMonitor.savegameRequestSent = true
                    print("[FarmMonitor] Sent savegame info request to server")
                end
            end
            -- Count down timeout — if it expires, proceed with fallbacks so exports aren't blocked forever.
            FarmMonitor.savegameInfoTimeout = FarmMonitor.savegameInfoTimeout - dt
            if FarmMonitor.savegameInfoTimeout <= 0 then
                local missionInfo = g_currentMission.missionInfo
                FarmMonitor.savegameName      = "unknown"
                FarmMonitor.savegameId        = ((missionInfo and missionInfo.mapId) or "unknown") .. "_unknown"
                FarmMonitor.savegameInfoReady = true
                print("[FarmMonitor] WARNING: Timed out waiting for savegame info from server, using fallbacks")
            end
            return  -- don't export anything yet
        end
    end

    -- Dedicated Server: savegame info is now set (so onClientJoined can send it),
    -- but skip all file exports — no local player, no output directory needed.
    if g_dedicatedServer ~= nil then return end

    if not FarmMonitor.modInfoExported then
        FarmMonitor:exportModInfo()
        FarmMonitor.modInfoExported = true
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

    if not FarmMonitor.mapMetaExported then
        FarmMonitor:exportMapMeta()
        FarmMonitor.mapMetaExported = true
    end

    if not FarmMonitor.fieldMetaExported then
        FarmMonitor:exportFieldMeta()
        FarmMonitor.fieldMetaExported = true
    end

    if not FarmMonitor.hotspotsExported then
        FarmMonitor:exportHotspots()
        FarmMonitor.hotspotsExported = true
    end

    -- vehicleCategories: retry each tick until shop system is ready
    if not FarmMonitor.vehicleCategoriesExported then
        if FarmMonitor:exportVehicleCategories() then
            FarmMonitor.vehicleCategoriesExported = true
        end
    end

    FarmMonitor.autoDriveRetryTimer = (FarmMonitor.autoDriveRetryTimer or 0) + dt
    if FarmMonitor.autoDriveRetryTimer >= 60000 then  -- alle 60 Sekunden prüfen
        FarmMonitor.autoDriveRetryTimer = 0
        FarmMonitor:exportAutoDriveMarkers()
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

    FarmMonitor.vehicleTimer = FarmMonitor.vehicleTimer + dt
    if FarmMonitor.vehicleTimer >= FarmMonitor.vehicleInterval then
        FarmMonitor.vehicleTimer = 0
        FarmMonitor:collectAndSaveVehicles()
    end

    FarmMonitor.vehicleMetaTimer = FarmMonitor.vehicleMetaTimer + dt
    if FarmMonitor.vehicleMetaTimer >= FarmMonitor.vehicleMetaInterval then
        FarmMonitor.vehicleMetaTimer = 0
        FarmMonitor:collectAndSaveVehicleMeta()
    end

    FarmMonitor.commandTimer = FarmMonitor.commandTimer + dt
    if FarmMonitor.commandTimer >= FarmMonitor.commandInterval then
        FarmMonitor.commandTimer = 0
        FarmMonitor:processCommands()
    end

    FarmMonitor.weatherTimer = FarmMonitor.weatherTimer + dt
    if FarmMonitor.weatherTimer >= FarmMonitor.weatherInterval then
        FarmMonitor.weatherTimer = 0
        FarmMonitor:collectAndSaveWeather()
    end

    -- Incremental soil layer export: runs every tick, samples a few rows at a time
    if FarmMonitor.soilState == nil then
        FarmMonitor.soilState = FarmMonitor:initSoilState()
    end
    if FarmMonitor.soilState ~= nil then
        FarmMonitor:stepSoilExport()
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
            "hasPSC",    g_modIsLoaded["FS25_ProductionStorageControl"] and true or false,
            "goods",     FarmMonitor:collectGoods()
        ))
    end)

    if not ok then
        print("[FarmMonitor] ERROR during collect: " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- Weather export (every 30 s)
-- ---------------------------------------------------------------------------

function FarmMonitor:collectAndSaveWeather()
    local ok, err = pcall(function()
        local env      = g_currentMission.environment
        local weather  = env.weather
        local forecast = weather.forecast
        local ts       = getDate("%Y-%m-%dT%H:%M:%S")

        local function weatherTypeName(idx)
            if idx == WeatherType.SUN            then return "SUN"
            elseif idx == WeatherType.RAIN       then return "RAIN"
            elseif idx == WeatherType.CLOUDY     then return "CLOUDY"
            elseif idx == WeatherType.SNOW       then return "SNOW"
            elseif idx == WeatherType.TWISTER    then return "TWISTER"
            elseif idx == WeatherType.THUNDER    then return "THUNDER"
            elseif idx == WeatherType.PARTIALLY_CLOUDY then return "PARTIALLY_CLOUDY"
            elseif idx == WeatherType.HAIL       then return "HAIL"
            end
            return "UNKNOWN"
        end

        local cur = forecast:getCurrentWeather()

        -- stündliche Vorhersage (nächste 6 Stunden)
        local hourly = {}
        for i = 0, 5 do
            local h = forecast:getHourlyForecast(i)
            if h ~= nil then
                local timeH = math.floor(h.time / 3600000)
                local timeM = math.floor((h.time % 3600000) / 60000)
                table.insert(hourly, FarmMonitor.obj(
                    "type",        weatherTypeName(h.forecastType),
                    "temperature", math.floor(h.temperature + 0.5),
                    "windSpeed",   math.floor(h.windSpeed * 3.6 + 0.5),
                    "windDir",     math.floor(h.windDirection + 0.5),
                    "time",        string.format("%02d:%02d", timeH, timeM)
                ))
            end
        end

        -- tagesweise Vorhersage (nächste 7 Tage)
        local daily = {}
        for i = 1, 7 do
            local d = forecast:getDailyForecast(i)
            if d ~= nil then
                local dayInPeriod = env.getDayInPeriodFromDay ~= nil and env:getDayInPeriodFromDay(d.day) or d.day
                local period      = env.getPeriodFromDay ~= nil and env:getPeriodFromDay(d.day) or nil
                local label = nil
                if period ~= nil and dayInPeriod ~= nil and g_i18n and g_i18n.formatDayInPeriod ~= nil then
                    local ok, result = pcall(function() return g_i18n:formatDayInPeriod(dayInPeriod, period, false) end)
                    if ok then label = result end
                end
                table.insert(daily, FarmMonitor.obj(
                    "type",     weatherTypeName(d.forecastType),
                    "high",     math.floor(d.highTemperature + 0.5),
                    "low",      math.floor(d.lowTemperature + 0.5),
                    "windSpeed",math.floor(d.windSpeed * 3.6 + 0.5),
                    "windDir",  math.floor(d.windDirection + 0.5),
                    "day",      d.day,
                    "dayInPeriod", dayInPeriod,
                    "period",   period,
                    "label",    label
                ))
            end
        end

        -- Windrichtung als Kompass-String
        local windDeg = math.floor(cur.windDirection + 0.5)
        local dirs = {"N","NO","O","SO","S","SW","W","NW"}
        local windCardinal = dirs[math.floor((windDeg % 360) / 45 + 1.5) % 8 + 1]

        FarmMonitor:writeJSON(FarmMonitor.paths.weather, FarmMonitor.obj(
            "timestamp", ts,
            "current", FarmMonitor.obj(
                "type",        weatherTypeName(cur.forecastType),
                "temperature", math.floor(cur.temperature + 0.5),
                "windSpeed",   math.floor(cur.windSpeed * 3.6 + 0.5),
                "windDir",     windDeg,
                "windCardinal",windCardinal,
                "isRaining",   weather:getIsRaining(),
                "rainScale",   math.floor(weather:getRainFallScale() * 100 + 0.5),
                "groundWet",   math.floor(weather:getGroundWetness() * 100 + 0.5)
            ),
            "hourly", hourly,
            "daily",  daily,
            "gameTime", FarmMonitor.obj(
                "hour",   env.currentHour,
                "minute", env.currentMinute,
                "isDay",  env.isSunOn,
                "period", env.currentPeriod,
                "dayInPeriod", env.currentDayInPeriod
            )
        ))
    end)

    if not ok then
        print("[FarmMonitor] ERROR during weather export: " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- Vehicle category registry  (written once; retries until shop is ready)
-- Returns true on success, false if shop not yet available
-- ---------------------------------------------------------------------------

function FarmMonitor:exportVehicleCategories()
    local ok, result = pcall(function()
        local shopMenu = g_gui and g_gui.screenControllers and g_gui.screenControllers[ShopMenu]
        if shopMenu == nil then return false end
        local vehiclePage = shopMenu.pageShopVehicles
        if vehiclePage == nil then return false end

        -- Sections (VEHICLES, EQUIPMENT, …)
        local sections = FarmMonitor.arr()
        if vehiclePage.categoryTypes then
            for _, detail in pairs(vehiclePage.categoryTypes) do
                if detail.name and detail.name ~= "OBJECTS" then
                    table.insert(sections, FarmMonitor.obj(
                        "id",    detail.name,
                        "title", detail.title or detail.name
                    ))
                end
            end
        end

        -- Categories per section (tractors, combines, trailers, …)
        local categories = FarmMonitor.arr()
        if vehiclePage.categories then
            for sectionId, entries in pairs(vehiclePage.categories) do
                if sectionId ~= "OBJECTS" then
                    for _, cat in pairs(entries) do
                        if cat.id then
                            table.insert(categories, FarmMonitor.obj(
                                "id",        cat.id,
                                "section",   sectionId,
                                "label",     cat.label or cat.id,
                                "sortValue", cat.sortValue or 0
                            ))
                        end
                    end
                end
            end
        end

        if #categories == 0 then return false end

        FarmMonitor:writeJSON(FarmMonitor.paths.vehicleCategories, FarmMonitor.obj(
            "savegameId", FarmMonitor.savegameId,
            "sections",   sections,
            "categories", categories
        ))
        print("[FarmMonitor] vehicleCategories.json written (" .. #categories .. " categories)")
        return true
    end)

    if not ok then
        -- pcall error (ShopMenu not yet loaded) — retry next tick silently
        return false
    end
    return result == true
end

-- ---------------------------------------------------------------------------
-- Mod info  (written once per session)
-- ---------------------------------------------------------------------------

function FarmMonitor:exportModInfo()
    local ok, err = pcall(function()
        local version = ""
        local mod = g_modManager:getModByName(modName)
        if mod ~= nil then version = mod.version or "" end
        FarmMonitor:writeJSON(FarmMonitor.paths.modInfo, FarmMonitor.obj(
            "modName", modName,
            "version", version
        ))
        print("[FarmMonitor] modInfo.json written (version=" .. version .. ")")
    end)
    if not ok then
        print("[FarmMonitor] ERROR writing modInfo.json: " .. tostring(err))
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
-- AutoDrive markers  (written once per session, if mod is loaded)
-- ---------------------------------------------------------------------------

function FarmMonitor:exportAutoDriveMarkers()
    if not (g_modIsLoaded and g_modIsLoaded["FS25_AutoDrive"]) then return end

    -- Fahrzeug mit AutoDrive-Modul auf unserer Farm finden
    local sm = nil
    local farmId = g_currentMission:getFarmId()
    for _, v in pairs(g_currentMission.vehicleSystem.vehicles) do
        if v.ownerFarmId == farmId and v.ad ~= nil and v.ad.stateModule ~= nil then
            sm = v.ad.stateModule
            break
        end
    end
    if sm == nil then return end  -- kein AD-Fahrzeug → nächster Versuch in 60s

    local ok, err = pcall(function()
        local savedMarker = sm.firstMarker
        local lastMaxId   = FarmMonitor.autoDriveLastMaxId or 0
        local startId     = lastMaxId + 1

        -- Inkrementeller Schnelltest: gibt es eine neue ID nach dem letzten bekannten Maximum?
        if lastMaxId > 0 then
            sm:setFirstMarker(startId)
            local probe = sm.firstMarker
            sm.firstMarker = savedMarker
            if probe == nil or probe.isADDebug == true then
                return  -- keine neuen Marker → nichts zu tun
            end
        end

        -- Vollscan ab startId (beim ersten Mal ab 1, danach ab lastMaxId+1)
        local newMarkers  = {}
        local groupSet    = {}
        local emptyStreak = 0
        local highestId   = lastMaxId

        -- Bestehende Gruppen aus Cache übernehmen (für inkrementellen Lauf)
        if lastMaxId > 0 and FarmMonitor.autoDriveMarkerCache then
            for _, m in ipairs(FarmMonitor.autoDriveMarkerCache) do
                if m.group then groupSet[m.group] = true end
            end
        end

        for id = startId, 5000 do
            sm:setFirstMarker(id)
            local m = sm.firstMarker
            if m ~= nil and m.isADDebug ~= true then
                local group = m.group or "All"
                groupSet[group] = true
                table.insert(newMarkers, { id = m.markerIndex, name = m.name, group = group })
                highestId   = math.max(highestId, id)
                emptyStreak = 0
            else
                emptyStreak = emptyStreak + 1
                if emptyStreak >= 200 then break end
            end
        end

        -- Originalmarker wiederherstellen (direkt — dirty flag batched, nur finaler Zustand wird gesynct)
        sm.firstMarker = savedMarker

        if #newMarkers == 0 then return end  -- nichts gefunden (erster Lauf, noch keine Marker)

        -- Neue Marker an Cache anhängen
        local allMarkers = FarmMonitor.autoDriveMarkerCache or {}
        for _, m in ipairs(newMarkers) do
            table.insert(allMarkers, m)
        end
        FarmMonitor.autoDriveLastMaxId    = highestId
        FarmMonitor.autoDriveMarkerCache  = allMarkers

        -- Gruppen sortieren
        local groups = FarmMonitor.arr()
        for groupName, _ in pairs(groupSet) do
            table.insert(groups, groupName)
        end
        table.sort(groups)

        -- JSON-Array aufbauen
        local markerArr = FarmMonitor.arr()
        for _, m in ipairs(allMarkers) do
            table.insert(markerArr, FarmMonitor.obj("id", m.id, "name", m.name, "group", m.group))
        end

        FarmMonitor:writeJSON(FarmMonitor.paths.autoDriveMarkers, FarmMonitor.obj(
            "savegameId", FarmMonitor.savegameId,
            "markers",    markerArr,
            "groups",     groups
        ))
        print("[FarmMonitor] autoDriveMarkers.json written (" .. #allMarkers .. " total, +" .. #newMarkers .. " neu)")
    end)

    if not ok then
        print("[FarmMonitor] autoDriveMarkers: pcall error: " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- Map metadata  (written once per session)
-- ---------------------------------------------------------------------------

function FarmMonitor:exportMapMeta()
    local ok, err = pcall(function()
        local mission     = g_currentMission
        local missionInfo = mission and mission.missionInfo
        if missionInfo == nil then return end

        local terrainSize = mission.terrainSize or 2048

        local mapName = ""
        local overviewDdsPath = ""
        if missionInfo.baseDirectory ~= nil then
            overviewDdsPath = missionInfo.baseDirectory .. "overview.dds"
        end
        if g_mapManager ~= nil and missionInfo.mapId ~= nil then
            local mapEntry = g_mapManager:getMapById(missionInfo.mapId)
            if mapEntry ~= nil then
                mapName = mapEntry.title or ""
                local cfgFile = mapEntry.configFilename or mapEntry.xmlFilename or mapEntry.filename or mapEntry.mapXMLFilename
                if cfgFile ~= nil and missionInfo.baseDirectory ~= nil then
                    local mapXMLPath = missionInfo.baseDirectory .. cfgFile
                    local xmlId = loadXMLFile("FarmMonitor_mapMeta", mapXMLPath)
                    if xmlId ~= nil and xmlId ~= 0 then
                        local imgFilename = getXMLString(xmlId, "map#imageFilename")
                        if imgFilename ~= nil and imgFilename ~= "" then
                            local resolved = Utils.getFilename(imgFilename, missionInfo.baseDirectory)
                            if resolved ~= nil and resolved ~= "" then
                                overviewDdsPath = resolved:gsub("%.png$", ".dds"):gsub("%.PNG$", ".dds")
                            end
                        end
                        delete(xmlId)
                    end
                end
            end
        end

        FarmMonitor:writeJSON(FarmMonitor.paths.mapMeta, FarmMonitor.obj(
            "savegameId",      FarmMonitor.savegameId,
            "terrainSize",     terrainSize,
            "mapName",         mapName,
            "overviewDdsPath", overviewDdsPath,
            "savegameDir",     missionInfo.savegameDirectory or ""
        ))
        print("[FarmMonitor] mapMeta.json written")
    end)
    if not ok then
        print("[FarmMonitor] ERROR writing mapMeta.json: " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- Hotspots  (written once per session)
-- ---------------------------------------------------------------------------

function FarmMonitor:exportHotspots()
    local ok, err = pcall(function()
        local result = FarmMonitor.arr()

        local function placeableType(placeable)
            if placeable.spec_sellingStation  ~= nil then return "SELLING_STATION"  end
            if placeable.spec_productionPoint ~= nil then return "PRODUCTION_POINT" end
            if placeable.spec_shopConfiguration ~= nil then return "SHOP"           end
            if placeable.spec_fuelStation     ~= nil then return "FUEL"             end
            if placeable.spec_beehivePalletSpawner ~= nil then return "BEE"         end
            if placeable.spec_husbandry       ~= nil then
                return FarmMonitor:getAnimalType(placeable)
            end
            return "MISC"
        end

        for _, placeable in pairs(g_currentMission.placeableSystem.placeables) do
            if placeable.spec_hotspots ~= nil and placeable.spec_hotspots.mapHotspots ~= nil then
                local pType = placeableType(placeable)
                for _, hotspot in pairs(placeable.spec_hotspots.mapHotspots) do
                    local x = hotspot.worldX
                    local z = hotspot.worldZ
                    if (x == nil or z == nil) and hotspot.getWorldPosition ~= nil then
                        local ok2, wx, _, wz = pcall(hotspot.getWorldPosition, hotspot)
                        if ok2 then x, z = wx, wz end
                    end
                    if x ~= nil and z ~= nil then
                        table.insert(result, FarmMonitor.obj(
                            "name", FarmMonitor:placeableName(placeable),
                            "type", pType,
                            "x",    MathUtil.round(x * 10) / 10,
                            "z",    MathUtil.round(z * 10) / 10
                        ))
                    end
                end
            end
        end

        FarmMonitor:writeJSON(FarmMonitor.paths.hotspots, FarmMonitor.obj(
            "savegameId", FarmMonitor.savegameId,
            "hotspots",   result
        ))
        print("[FarmMonitor] hotspots.json written (" .. #result .. " entries)")
    end)
    if not ok then
        print("[FarmMonitor] ERROR writing hotspots.json: " .. tostring(err))
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
-- Vehicles & Players
-- ---------------------------------------------------------------------------

function FarmMonitor:collectVehicles()
    local result = FarmMonitor.arr()
    local farmId = g_currentMission:getFarmId()

    -- Raw hotspot type numbers from FS25 (vehicle subclasses)
    local hotspotTypeNames = {}
    if MapHotspot then
        for k, v in pairs(MapHotspot) do
            if type(k) == "string" and type(v) == "number" then
                hotspotTypeNames[v] = k
            end
        end
    end

    local function vehicleTypeName(v)
        local t = v.mapHotspotType
        if t == nil then return "VEHICLE" end
        local constName = hotspotTypeNames[t] or ""
        if constName:find("COMBINE") then return "HARVESTER" end
        if constName:find("TRAILER") then return "TRAILER"   end
        if constName:find("TRUCK")   then return "TRUCK"     end
        if constName:find("CAR")     then return "CAR"       end
        if constName:find("TOOL")    then return "TOOL"      end
        if constName:find("TRACTOR") then return "TRACTOR"   end
        return "TRACTOR"
    end

    -- Mod availability flags (checked once per collect cycle)
    local hasEnhancedVehicle  = g_modIsLoaded["FS25_EnhancedVehicle"]  == true
    local hasVehicleInspector = g_modIsLoaded["FS25_VehicleInspector"] == true
    local hasAutoDrive        = g_modIsLoaded["FS25_AutoDrive"]        == true


    -- Build fuel fillType index lookup once for the whole loop
    local fuelFillTypeIndices = {}
    if g_fillTypeManager and g_fillTypeManager.fillTypes then
        for idx, ft in ipairs(g_fillTypeManager.fillTypes) do
            if ft.name == "DIESEL" or ft.name == "ELECTRICCHARGE" or ft.name == "METHANE" then
                fuelFillTypeIndices[idx] = ft.name
            end
        end
    end

    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        -- skip pallets, bales, shipping containers — only real machines
        if vehicle.isPallet or vehicle.isShippingContainer then
        elseif vehicle.mapHotspotType == nil then
        elseif vehicle.rootNode == nil then
        elseif vehicle.getOwnerFarmId == nil or vehicle:getOwnerFarmId() ~= farmId then
        else
            local x, _, z = getWorldTranslation(vehicle.rootNode)
            local dx, _, dz = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
            local rot = -MathUtil.getYRotationFromDirection(dx, dz) + math.pi

            local fillPct = nil
            local fillLiter = nil
            local fuelPct = nil
            local fuelLiter = nil
            local tanks   = FarmMonitor.arr()
            if vehicle.spec_fillUnit ~= nil and vehicle.spec_fillUnit.fillUnits ~= nil then
                local totalLevel, totalCap = 0, 0
                local fuelLevel,  fuelCap  = 0, 0
                local mainTankEntry = nil   -- showOnHud non-fuel tank (game-defined primary cargo)
                for _, fu in ipairs(vehicle.spec_fillUnit.fillUnits) do
                    local level = fu.fillLevel or 0
                    local cap   = fu.capacity  or 0
                    -- ignore math.huge (unlimited) tanks for aggregates
                    if cap < 1e9 then
                        totalLevel = totalLevel + level
                        totalCap   = totalCap   + cap
                        if fuelFillTypeIndices[fu.fillType] then
                            fuelLevel = fuelLevel + level
                            fuelCap   = fuelCap   + cap
                        elseif cap > 0 then
                            -- per-tank entry: immer exportieren, auch wenn leer/UNKNOWN
                            local ft = g_fillTypeManager and g_fillTypeManager:getFillTypeByIndex(fu.fillType)
                            local ftName = ft and ft.name or ""
                            if ftName == "UNKNOWN" then ftName = "" end
                            local entry = FarmMonitor.obj(
                                "name",  ftName,
                                "pct",   MathUtil.round(level / cap * 100),
                                "liter", MathUtil.round(level),
                                "cap",   MathUtil.round(cap)
                            )
                            table.insert(tanks, entry)
                            -- Main cargo tank = first showOnHud non-fuel unit (game-defined)
                            if mainTankEntry == nil and fu.showOnHud == true then
                                mainTankEntry = entry
                            end
                        end
                    end
                end
                -- Mark main cargo tank so the dashboard can highlight it
                if mainTankEntry ~= nil then
                    mainTankEntry.main = true
                    table.insert(mainTankEntry.__order, "main")
                end
                if totalCap > 0 then
                    fillPct   = MathUtil.round(totalLevel / totalCap * 100)
                    fillLiter = MathUtil.round(totalLevel)
                end
                if fuelCap > 0 then
                    fuelPct   = MathUtil.round(fuelLevel / fuelCap * 100)
                    fuelLiter = MathUtil.round(fuelLevel)
                end
            end

            -- ── Loaded pallets ───────────────────────────────────────────
            local pallets = FarmMonitor.arr()
            pcall(function()
                local palletMap = {}
                local function addPalletObj(obj)
                    if obj == nil or not obj.isPallet then return end
                    local spec = obj.spec_fillUnit
                    if spec == nil or spec.fillUnits == nil then return end
                    for _, fu in ipairs(spec.fillUnits) do
                        local cap = fu.capacity or 0
                        if cap > 0 then
                            local ftIdx = fu.fillType or 0
                            local level = MathUtil.round(fu.fillLevel or 0)
                            local ft = g_fillTypeManager and g_fillTypeManager:getFillTypeByIndex(ftIdx)
                            local ftName  = (ft and ft.name) or ""
                            if ftName == "UNKNOWN" then ftName = "" end
                            local ftTitle = (ft and ft.title) or ftName
                            if palletMap[ftIdx] == nil then
                                palletMap[ftIdx] = {name = ftName, title = ftTitle, count = 0, litersEach = MathUtil.round(cap), totalLiters = 0}
                            end
                            palletMap[ftIdx].count = palletMap[ftIdx].count + 1
                            palletMap[ftIdx].totalLiters = palletMap[ftIdx].totalLiters + level
                            break -- one entry per pallet
                        end
                    end
                end
                -- Method 1: dynamic mount attacher (object IS the key)
                if vehicle.spec_dynamicMountAttacher ~= nil then
                    local mounts = vehicle.spec_dynamicMountAttacher.dynamicMountedObjects
                    if mounts ~= nil then
                        for obj, _ in pairs(mounts) do
                            addPalletObj(obj)
                        end
                    end
                end
                -- Method 2: tension belts (pallets strapped to flatbed)
                if vehicle.spec_tensionBelts ~= nil then
                    local spec = vehicle.spec_tensionBelts
                    if spec.objectsToJoint ~= nil then
                        for _, objectData in pairs(spec.objectsToJoint) do
                            addPalletObj(objectData.object)
                        end
                    end
                end
                for _, pd in pairs(palletMap) do
                    table.insert(pallets, FarmMonitor.obj(
                        "name",        pd.name,
                        "title",       pd.title,
                        "count",       pd.count,
                        "litersEach",  pd.litersEach,
                        "totalLiters", pd.totalLiters
                    ))
                end
            end)

            local damage = 0
            local wear   = 0
            if vehicle.spec_wearable ~= nil then
                if vehicle.spec_wearable.getDamageAmount ~= nil then
                    local ok2, val = pcall(function() return vehicle.spec_wearable:getDamageAmount() end)
                    if ok2 and val then damage = MathUtil.round(val * 100) end
                end
                if vehicle.spec_wearable.getWearTotalAmount ~= nil then
                    local ok3, val = pcall(function() return vehicle.spec_wearable:getWearTotalAmount() end)
                    if ok3 and val then wear = MathUtil.round(val * 100) end
                end
            end

            local isEntered    = vehicle.spec_enterable ~= nil and vehicle.spec_enterable.isEntered == true
            local isAIActive   = vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive() == true
            local driverName   = nil
            if isEntered and vehicle.spec_enterable ~= nil then
                local uid = vehicle.spec_enterable.controllerUserId
                if uid and g_currentMission.userManager ~= nil then
                    local user = g_currentMission.userManager:getUserByUserId(uid)
                    if user ~= nil then driverName = user:getNickname() end
                end
            end
            local motorRunning = vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted() == true
            local motorized    = vehicle.spec_motorized ~= nil
            local speed = 0
            if vehicle.getLastSpeed ~= nil then
                local ok, s = pcall(function() return vehicle:getLastSpeed() end)
                if ok and s and s > 0 then speed = MathUtil.round(s * 10) / 10 end
            end
            if speed == 0 then
                speed = MathUtil.round((vehicle.lastSpeed or vehicle.lastSpeedReal or 0) * 3.6 * 10) / 10
            end

            -- rootId: ID of the root vehicle in the attachment chain
            local rootId = tostring(vehicle.rootNode)
            if vehicle.rootVehicle ~= nil and vehicle.rootVehicle.rootNode ~= nil then
                rootId = tostring(vehicle.rootVehicle.rootNode)
            end

            -- netId: network-synchronised object ID via NetworkUtil — identical on client
            -- and server in all MP scenarios (SP, player-hosted, dedicated server).
            -- Used by the dashboard to identify vehicles in IPC commands cross-process.
            local netId = FarmMonitor:getNetworkId(vehicle)

            local name = ""
            if vehicle.getName ~= nil then name = vehicle:getName() or "" end

            -- ── Enhanced Vehicle (optional mod) ──────────────────────────
            local evFrontDiff = nil
            local evRearDiff  = nil
            local evDriveMode = nil
            if hasEnhancedVehicle and vehicle.vData ~= nil and vehicle.vData.is ~= nil then
                pcall(function()
                    if vehicle.vData.is[1] ~= nil then evFrontDiff = vehicle.vData.is[1] == true end
                    if vehicle.vData.is[2] ~= nil then evRearDiff  = vehicle.vData.is[2] == true end
                    if vehicle.vData.is[3] ~= nil then evDriveMode = vehicle.vData.is[3] end
                    -- 0=2WD, 1=4WD, 2=FWD
                end)
            end

            -- ── Vehicle Inspector SpeedControl (optional mod) ─────────────
            local viPresets   = nil
            local viActiveKey = nil
            if hasVehicleInspector and vehicle.spec_speedControl ~= nil then
                local sc = vehicle.speedControl
                if sc ~= nil and sc.keys ~= nil then
                    pcall(function()
                        viPresets = FarmMonitor.arr()
                        for i = 1, 3 do
                            local k = sc.keys[i]
                            if k then
                                table.insert(viPresets, FarmMonitor.obj(
                                    "speed",    MathUtil.round(k.speed or 0),
                                    "isActive", k.isActive == true
                                ))
                            end
                        end
                        viActiveKey = sc.currentKey
                    end)
                end
            end

            -- ── AutoDrive (optional mod) ─────────────────────────────────
            -- ── Courseplay (optional mod) ─────────────────────────────────
            local cpActive               = nil
            local cpJobType              = nil
            local cpInfoText             = nil
            local cpWaypointCurrent      = nil
            local cpWaypointTotal        = nil
            local cpRemainingTime        = nil
            local cpNumBalesLeft         = nil
            local cpWaitingForUnload     = nil
            local cpHarvesterManeuvering = nil
            if vehicle.getIsCpActive ~= nil then
                pcall(function()
                    if not vehicle:getIsCpActive() then return end
                    cpActive = true
                    if vehicle:getIsCpFieldWorkActive() then
                        cpJobType = "fieldWork"
                    elseif vehicle:getIsCpCombineUnloaderActive() then
                        cpJobType = "combineUnloader"
                    else
                        local j = vehicle.getJob and vehicle:getJob()
                        if j and j.name then cpJobType = j.name end
                    end
                    if vehicle.getCpStatus then
                        local st = vehicle:getCpStatus()
                        if st then
                            if st.currentWaypointIx and st.currentWaypointIx > 0 then
                                cpWaypointCurrent = st.currentWaypointIx
                            end
                            if st.numberOfWaypoints and st.numberOfWaypoints > 0 then
                                cpWaypointTotal = st.numberOfWaypoints
                            end
                            if st.remainingTimeText and st.remainingTimeText ~= "" then
                                cpRemainingTime = st.remainingTimeText
                            end
                            if st.numBalesLeftOver and st.numBalesLeftOver > 0 then
                                cpNumBalesLeft = st.numBalesLeftOver
                            end
                        end
                    end
                    if vehicle.getCpActiveInfoTexts then
                        local texts = vehicle:getCpActiveInfoTexts()
                        for _, t in pairs(texts) do
                            if t and t.name then
                                cpInfoText = t.name
                                break
                            end
                        end
                    end
                    if vehicle.getIsCpHarvesterWaitingForUnload then
                        if vehicle:getIsCpHarvesterWaitingForUnload() then
                            cpWaitingForUnload = true
                        end
                        if vehicle:getIsCpHarvesterManeuvering() then
                            cpHarvesterManeuvering = true
                        end
                    end
                end)
            end

            local adActive           = nil
            local adMode             = nil
            local adDriverName       = nil
            local adDestination      = nil
            local adDestination2     = nil
            local adRemainingTime    = nil
            local adFillType         = nil
            local adLoopCounter      = nil
            local adLoopsDone        = nil
            local adCurrentTarget    = nil
            local adBlocked          = nil
            local adError            = nil
            local adOnRouteToRefuel  = nil
            local adOnRouteToPark    = nil
            local adIsLoading        = nil
            local adIsUnloading      = nil
            local adModeState        = nil
            local adSpeedLimit       = nil
            local adFieldSpeedLimit  = nil
            local adLoadByFillLevel  = nil
            local adAutoUnloadTarget = nil
            local adAutoPickupTarget = nil
            local adStartHelper      = nil
            local adUsedHelper       = nil
            local adParkDestination  = nil
            local adCurrentTaskInfo  = nil
            local adHarvesterPairingOk = nil
            local adSettings           = nil
            if hasAutoDrive and vehicle.ad ~= nil and vehicle.ad.stateModule ~= nil then
                pcall(function()
                    local sm = vehicle.ad.stateModule
                    adActive      = sm:isActive() == true
                    adMode        = sm:getMode()
                    adDriverName  = sm:getName()
                    adDestination = sm:getFirstMarkerName()
                    if sm.secondMarker ~= nil then
                        adDestination2 = sm.secondMarker.name
                    end
                    local t = sm.remainingDriveTime
                    if t and t > 0 then adRemainingTime = MathUtil.round(t) end
                    -- Fill type only for modes that use it (2=PickupAndDeliver, 3=DeliverTo, 4=Load)
                    if adMode == 2 or adMode == 3 or adMode == 4 then
                        local ftIdx = sm:getFillType()
                        if ftIdx and ftIdx > 1 then
                            local ft = g_fillTypeManager:getFillTypeByIndex(ftIdx)
                            if ft then adFillType = ft.name end
                        end
                    end
                    -- Loop counter (0 = infinite, always export when AD present)
                    -- Use individual pcalls: AD uses metatables, nil-checks on methods don't work
                    local ok_lc, lc = pcall(function() return sm:getLoopCounter() end)
                    if ok_lc and lc ~= nil then
                        adLoopCounter = lc
                        local ok_ld, ld = pcall(function() return sm:getLoopsDone() end)
                        if ok_ld and ld ~= nil then adLoopsDone = ld end
                    end
                    -- Current active target leg
                    if adMode == 2 then
                        -- PickupAndDeliver: state-based detection
                        local ok_gm, modeObj = pcall(function() return sm:getCurrentMode() end)
                        if ok_gm and modeObj and modeObj.state then
                            local s = modeObj.state
                            if s == 2 or s == 8 then adCurrentTarget = 1
                            elseif s == 3 or s == 7 then adCurrentTarget = 2
                            end
                        end
                    elseif adMode == 5 and adDestination2 ~= nil then
                        -- CombineUnloader: table-based states, compare via class metatable
                        -- Marker 1 (firstMarker)  = Wartepunkt (wait/start near field)
                        -- Marker 2 (secondMarker) = Entladeort (unload delivery point)
                        local ok_gm, modeObj = pcall(function() return sm:getCurrentMode() end)
                        if ok_gm and modeObj and modeObj.state then
                            if modeObj.state == modeObj.STATE_DRIVE_TO_UNLOAD then
                                adCurrentTarget = 2   -- driving to unload = Marker 2
                            elseif modeObj.state == modeObj.STATE_DRIVE_TO_START
                                or modeObj.state == modeObj.STATE_WAIT_TO_BE_CALLED then
                                adCurrentTarget = 1   -- at/towards wait point = Marker 1
                            end
                        end
                    end
                    -- Extended AD state fields
                    if vehicle.ad.isStoppingWithError == true then adError = true end
                    if vehicle.ad.onRouteToRefuel == true then adOnRouteToRefuel = true end
                    if vehicle.ad.onRouteToPark   == true then adOnRouteToPark   = true end
                    if vehicle.ad.specialDrivingModule ~= nil
                        and vehicle.ad.specialDrivingModule.isBlocked == true then
                        adBlocked = true
                    end
                    if vehicle.ad.trailerModule ~= nil then
                        if vehicle.ad.trailerModule.isLoading   == true then adIsLoading   = true end
                        if vehicle.ad.trailerModule.isUnloading == true then adIsUnloading = true end
                    end
                    -- Mode state string (CombineUnloader mode 5 — table-based states)
                    if adActive and adMode == 5 then
                        local ok_ms, ms = pcall(function() return sm:getCurrentMode() end)
                        if ok_ms and ms and ms.state then
                            if     ms.state == ms.STATE_WAIT_TO_BE_CALLED          then adModeState = "waitToBeCalled"
                            elseif ms.state == ms.STATE_DRIVE_TO_COMBINE           then adModeState = "driveToCombine"
                            elseif ms.state == ms.STATE_FOLLOW_COMBINE
                                or ms.state == ms.STATE_ACTIVE_UNLOAD_COMBINE
                                or ms.state == ms.STATE_FOLLOW_CURRENT_UNLOADER    then adModeState = "followCombine"
                            elseif ms.state == ms.STATE_DRIVE_TO_UNLOAD            then adModeState = "driveToUnload"
                            elseif ms.state == ms.STATE_DRIVE_TO_START             then adModeState = "driveToStart"
                            elseif ms.state == ms.STATE_REVERSE_FROM_BAD_LOCATION  then adModeState = "reverseFromBadLocation"
                            end
                        end
                    end
                    -- Speed limits
                    local ok_sl, sl = pcall(function() return sm:getSpeedLimit() end)
                    if ok_sl and sl and sl > 0 then adSpeedLimit = MathUtil.round(sl) end
                    local ok_fsl, fsl = pcall(function() return sm:getFieldSpeedLimit() end)
                    if ok_fsl and fsl and fsl > 0 then adFieldSpeedLimit = MathUtil.round(fsl) end
                    -- Toggle states
                    local ok_lbfl, lbfl = pcall(function() return sm:getLoadByFillLevel() end)
                    if ok_lbfl then adLoadByFillLevel = lbfl == true end
                    local ok_aut, aut = pcall(function() return sm:getAutomaticUnloadTarget() end)
                    if ok_aut then adAutoUnloadTarget = aut == true end
                    local ok_apt, apt = pcall(function() return sm:getAutomaticPickupTarget() end)
                    if ok_apt then adAutoPickupTarget = apt == true end
                    local ok_sh, sh = pcall(function() return sm:getStartHelper() end)
                    if ok_sh then adStartHelper = sh == true end
                    local ok_uh, uh = pcall(function() return sm:getUsedHelper() end)
                    if ok_uh and uh ~= nil then adUsedHelper = uh end
                    -- Park destination (-1 = none configured)
                    local ok_pd, pd = pcall(function() return sm:getParkDestinationAtJobFinished() end)
                    if ok_pd then adParkDestination = pd end
                    -- Current task info string
                    local ok_ti, ti = pcall(function() return sm:getCurrentLocalizedTaskInfo() end)
                    if ok_ti and ti and ti ~= "" then adCurrentTaskInfo = ti end
                    -- Harvester pairing ok (CombineUnloader mode 5 only)
                    if adMode == 5 then
                        local ok2, pairing = pcall(function() return sm:getHarvesterPairingOk() end)
                        if ok2 and pairing == true then adHarvesterPairingOk = true end
                    end
                    -- Vehicle settings (current index per setting)
                    if vehicle.ad.settings ~= nil then
                        adSettings = {}
                        for _, sName in ipairs({
                            "cornerSpeed", "pipeOffset", "followDistance", "unloadFillLevel",
                            "exitField", "restrictToField", "followOnlyOnField", "avoidFruit",
                            "parkInField", "rotateTargets", "autoRefuel", "autoRepair",
                            "enableParkAtJobFinished", "autoTipSide", "autoTrailerCover",
                            "ALUnload", "ALUnloadWaitTime",
                            "preCallLevel", "callSecondUnloader", "activeUnloading", "chaseSide"
                        }) do
                            local s = vehicle.ad.settings[sName]
                            if s ~= nil then adSettings[sName] = s.current end
                        end
                    end
                end)
            end

            table.insert(result, FarmMonitor.obj(
                "id",          tostring(vehicle.rootNode),
                "netId",       netId,
                "name",        name,
                "type",        vehicleTypeName(vehicle),
                "x",           MathUtil.round(x * 10) / 10,
                "z",           MathUtil.round(z * 10) / 10,
                "rot",         MathUtil.round(rot * 1000) / 1000,
                "fillPct",     fillPct,
                "fillLiter",   fillLiter,
                "fuelPct",     fuelPct,
                "fuelLiter",   fuelLiter,
                "tanks",       tanks,
                "pallets",     pallets,
                "damage",      damage,
                "wear",        wear,
                "isEntered",   isEntered,
                "driverName",  driverName,
                "isAIActive",  isAIActive,
                "motorRunning", motorRunning,
                "motorized",   motorized,
                "speed",       speed,
                "rootId",      rootId,
                "evFrontDiff", evFrontDiff,
                "evRearDiff",  evRearDiff,
                "evDriveMode", evDriveMode,
                "viPresets",        viPresets,
                "viActiveKey",      viActiveKey,
                "adActive",         adActive,
                "adMode",           adMode,
                "adDriverName",     adDriverName,
                "adDestination",    adDestination,
                "adDestination2",   adDestination2,
                "adRemainingTime",  adRemainingTime,
                "adFillType",       adFillType,
                "adLoopCounter",    adLoopCounter,
                "adLoopsDone",      adLoopsDone,
                "adCurrentTarget",   adCurrentTarget,
                "adBlocked",         adBlocked,
                "adError",           adError,
                "adOnRouteToRefuel", adOnRouteToRefuel,
                "adOnRouteToPark",   adOnRouteToPark,
                "adIsLoading",       adIsLoading,
                "adIsUnloading",     adIsUnloading,
                "adModeState",           adModeState,
                "adSpeedLimit",          adSpeedLimit,
                "adFieldSpeedLimit",     adFieldSpeedLimit,
                "adLoadByFillLevel",     adLoadByFillLevel,
                "adAutoUnloadTarget",    adAutoUnloadTarget,
                "adAutoPickupTarget",    adAutoPickupTarget,
                "adStartHelper",         adStartHelper,
                "adUsedHelper",          adUsedHelper,
                "adParkDestination",     adParkDestination,
                "adCurrentTaskInfo",     adCurrentTaskInfo,
                "adHarvesterPairingOk",  adHarvesterPairingOk,
                "adIsHarvester",         vehicle.spec_combine ~= nil or nil,
                "adSettings",            adSettings,
                "cpActive",              cpActive,
                "cpJobType",             cpJobType,
                "cpInfoText",            cpInfoText,
                "cpWaypointCurrent",     cpWaypointCurrent,
                "cpWaypointTotal",       cpWaypointTotal,
                "cpRemainingTime",       cpRemainingTime,
                "cpNumBalesLeft",        cpNumBalesLeft,
                "cpWaitingForUnload",    cpWaitingForUnload,
                "cpHarvesterManeuvering", cpHarvesterManeuvering
            ))
        end
    end

    if g_currentMission.playerSystem ~= nil then
        for _, player in pairs(g_currentMission.playerSystem.players) do
            if player ~= nil and player.rootNode ~= nil then
                local x, _, z = getWorldTranslation(player.rootNode)
                local playerName = (player.networkInformation and player.networkInformation.playerName) or "Player"
                table.insert(result, FarmMonitor.obj(
                    "id",      "player_" .. tostring(player.rootNode),
                    "name",    playerName,
                    "type",    "PLAYER",
                    "x",       MathUtil.round(x * 10) / 10,
                    "z",       MathUtil.round(z * 10) / 10,
                    "rot",     0,
                    "fillPct", nil
                ))
            end
        end
    end

    return result
end

-- ---------------------------------------------------------------------------
-- Helper: Placeable-Ankerliste für Paletten-Gruppierung
-- ---------------------------------------------------------------------------

function FarmMonitor:buildPlaceableAnchors(farmId)
    local anchors = {}
    if g_currentMission.placeableSystem == nil then return anchors end
    for _, placeable in ipairs(g_currentMission.placeableSystem.placeables) do
        if (placeable.ownerFarmId == farmId or placeable.ownerFarmId == 0) and placeable.rootNode ~= nil then
            local x, _, z = getWorldTranslation(placeable.rootNode)
            table.insert(anchors, {
                id   = placeable:getUniqueId() or "",
                name = FarmMonitor:placeableName(placeable),
                x    = x,
                z    = z,
            })
        end
    end
    return anchors
end

function FarmMonitor:nearestAnchor(anchors, px, pz, radius2)
    local bestId   = "outside"
    local bestName = "Außenbereich"
    local bestDist = math.huge
    for _, anchor in ipairs(anchors) do
        local dx = px - anchor.x
        local dz = pz - anchor.z
        local d2 = dx*dx + dz*dz
        if d2 < radius2 and d2 < bestDist then
            bestDist = d2
            bestId   = anchor.id
            bestName = anchor.name
        end
    end
    return bestId, bestName
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

        -- Bunker Silo (Fahrsilo / Keilsilo)
        if placeable.spec_bunkerSilo ~= nil and (placeable.ownerFarmId == farmId or placeable.ownerFarmId == 0) then
            local bs = placeable.spec_bunkerSilo.bunkerSilo
            if bs ~= nil and bs.fillLevel ~= nil and bs.fillLevel > 0 then
                local ftIdx = bs.inputFillType
                if bs.state == BunkerSilo.STATE_DRAIN or bs.state == BunkerSilo.STATE_FERMENTED then
                    ftIdx = bs.outputFillType
                end
                local stateStr = "FILL"
                if     bs.state == BunkerSilo.STATE_CLOSED     then stateStr = "CLOSED"
                elseif bs.state == BunkerSilo.STATE_DRAIN      then stateStr = "DRAIN"
                elseif bs.state == BunkerSilo.STATE_FERMENTED  then stateStr = "FERMENTED"
                end
                table.insert(result, {
                    uniqueId          = placeable:getUniqueId() or "",
                    name              = FarmMonitor:placeableName(placeable),
                    type              = "bunkerSilo",
                    fillLevel         = MathUtil.round(bs.fillLevel),
                    fillType          = g_fillTypeManager:getFillTypeNameByIndex(ftIdx) or "UNKNOWN",
                    fillTypeTitle     = FarmMonitor:fillTypeTitle(ftIdx),
                    fermentingPercent = bs.fermentingPercent or 0,
                    compactedPercent  = bs.compactedPercent or 0,
                    state             = stateStr,
                })
            end
        end

        -- Object Storage (vanilla pallets / bale storage)
        if placeable.spec_objectStorage ~= nil and (placeable.ownerFarmId == farmId or placeable.ownerFarmId == 0) then
            local contents = FarmMonitor.arr()
            for i, objInfo in ipairs(placeable.spec_objectStorage.objectInfos or {}) do
                local ftIdx, totalLevel, count = nil, 0, 0
                for _, obj in ipairs(objInfo.objects or {}) do
                    local thisFt, thisLevel
                    if obj.baleAttributes ~= nil then
                        thisFt    = obj.baleAttributes.fillType
                        thisLevel = obj.baleAttributes.fillLevel
                    elseif obj.baleObject ~= nil then
                        thisFt    = obj.baleObject.fillType
                        thisLevel = obj.baleObject.fillLevel
                    elseif obj.palletAttributes ~= nil then
                        thisFt    = obj.palletAttributes.fillType
                        thisLevel = obj.palletAttributes.fillLevel
                    end
                    if thisFt ~= nil and thisLevel ~= nil and thisLevel > 0 then
                        if ftIdx == nil then ftIdx = thisFt end
                        totalLevel = totalLevel + thisLevel
                        count      = count + 1
                    end
                end
                if count > 0 and ftIdx ~= nil then
                    table.insert(contents, {
                        fillType        = g_fillTypeManager:getFillTypeNameByIndex(ftIdx) or "UNKNOWN",
                        title           = FarmMonitor:fillTypeTitle(ftIdx),
                        level           = MathUtil.round(totalLevel),
                        count           = count,
                        objectInfoIndex = i,
                    })
                end
            end
            if #contents > 0 then
                table.insert(result, {
                    uniqueId = placeable:getUniqueId() or "",
                    name     = FarmMonitor:placeableName(placeable),
                    type     = "objectStorage",
                    contents = contents,
                })
            end
        end

        -- Object Storage Mod (e.g. bale storage mods)
        if placeable.spec_objectStorageMod ~= nil and (placeable.ownerFarmId == farmId or placeable.ownerFarmId == 0) then
            local os = placeable.spec_objectStorageMod.objectStorage
            if os ~= nil and os.storageAreasByFillType ~= nil then
                local byFillType = {}
                for ftIdx, areas in pairs(os.storageAreasByFillType) do
                    for _, area in pairs(areas) do
                        for _, obj in ipairs(area.objects or {}) do
                            if obj.fillLevel ~= nil and obj.fillLevel > 0 then
                                if byFillType[ftIdx] == nil then byFillType[ftIdx] = { level = 0, count = 0 } end
                                byFillType[ftIdx].level = byFillType[ftIdx].level + obj.fillLevel
                                byFillType[ftIdx].count = byFillType[ftIdx].count + 1
                            end
                        end
                    end
                end
                local contents = FarmMonitor.arr()
                for ftIdx, d in pairs(byFillType) do
                    table.insert(contents, {
                        fillType = g_fillTypeManager:getFillTypeNameByIndex(ftIdx) or "UNKNOWN",
                        title    = FarmMonitor:fillTypeTitle(ftIdx),
                        level    = MathUtil.round(d.level),
                        count    = d.count,
                    })
                end
                if #contents > 0 then
                    table.insert(result, {
                        uniqueId = placeable:getUniqueId() or "",
                        name     = FarmMonitor:placeableName(placeable),
                        type     = "objectStorageMod",
                        contents = contents,
                    })
                end
            end
        end
    end

    -- Loose Paletten: gruppiert nach nächstem eigenem Placeable (Radius 75m)
    local anchors = FarmMonitor:buildPlaceableAnchors(farmId)
    local RADIUS2 = 75 * 75
    local groups  = {}

    if g_currentMission.vehicleSystem ~= nil then
        for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles or {}) do
            if vehicle.isPallet and (vehicle.ownerFarmId == farmId or vehicle.ownerFarmId == 0) then
                local spec = vehicle.spec_fillUnit
                if spec ~= nil and spec.fillUnits ~= nil and spec.fillUnits[1] ~= nil then
                    local fu = spec.fillUnits[1]
                    if fu.fillType ~= nil and fu.fillLevel ~= nil and fu.fillLevel > 0 then
                        local px, py, pz = getWorldTranslation(vehicle.rootNode)
                        local bestId, bestName = FarmMonitor:nearestAnchor(anchors, px, pz, RADIUS2)
                        if groups[bestId] == nil then
                            groups[bestId] = { name = bestName, byFillType = {}, sumX = 0, sumY = 0, sumZ = 0, palletCount = 0 }
                        end
                        groups[bestId].sumX = groups[bestId].sumX + px
                        groups[bestId].sumY = groups[bestId].sumY + py
                        groups[bestId].sumZ = groups[bestId].sumZ + pz
                        groups[bestId].palletCount = groups[bestId].palletCount + 1
                        local ftIdx = fu.fillType
                        if groups[bestId].byFillType[ftIdx] == nil then
                            groups[bestId].byFillType[ftIdx] = { level = 0, count = 0 }
                        end
                        groups[bestId].byFillType[ftIdx].level = groups[bestId].byFillType[ftIdx].level + fu.fillLevel
                        groups[bestId].byFillType[ftIdx].count = groups[bestId].byFillType[ftIdx].count + 1
                    end
                end
            end
        end
    end

    for groupId, group in pairs(groups) do
        local contents = FarmMonitor.arr()
        for ftIdx, d in pairs(group.byFillType) do
            table.insert(contents, {
                fillType = g_fillTypeManager:getFillTypeNameByIndex(ftIdx) or "UNKNOWN",
                title    = FarmMonitor:fillTypeTitle(ftIdx),
                level    = MathUtil.round(d.level),
                count    = d.count,
            })
        end
        if #contents > 0 then
            local n  = group.palletCount
            local cx = MathUtil.round(group.sumX / n * 100) / 100
            local cy = MathUtil.round(group.sumY / n * 100) / 100
            local cz = MathUtil.round(group.sumZ / n * 100) / 100
            table.insert(result, {
                uniqueId = "pallets_" .. groupId,
                name     = group.name,
                type     = "loosePallets",
                posX     = cx,
                posY     = cy,
                posZ     = cz,
                contents = contents,
            })
        end
    end

    return result
end

-- ---------------------------------------------------------------------------
-- PSC Pallet Info Cache (built once per session)
-- ---------------------------------------------------------------------------

function FarmMonitor:buildPalletInfoCache()
    FarmMonitor.palletInfoCache = {}
    local fillTypes = g_fillTypeManager.fillTypes or {}
    for _, ft in ipairs(fillTypes) do
        if ft ~= nil and ft.index ~= nil and ft.pallets ~= nil then
            -- Prefer VANILLA, fall back to first available environment
            local palletFile = ft.pallets["VANILLA"]
            if palletFile == nil then
                for _, f in pairs(ft.pallets) do palletFile = f; break end
            end
            if palletFile ~= nil then
                local ok, xmlFile = pcall(XMLFile.load, "PSC_PalletCache_" .. ft.index, palletFile, Vehicle.xmlSchema)
                if ok and xmlFile ~= nil then
                    local capacity = FillUnit.getCapacityFromXml(xmlFile)
                    local size     = StoreItemUtil.getSizeValues(palletFile, "vehicle", 0, {})
                    xmlFile:delete()
                    if capacity ~= nil and capacity > 0 then
                        FarmMonitor.palletInfoCache[ft.index] = {
                            capacity          = capacity,
                            width             = (size and size.width)  or 1,
                            height            = (size and size.height) or 1,
                            length            = (size and size.length) or 1,
                            customEnvironment = ft.pallets["VANILLA"] ~= nil and "VANILLA" or "VANILLA",
                        }
                    end
                end
            end
        end
    end
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

            -- PSC: annotate outputs with spawn options (vanilla pallets)
            if g_modIsLoaded["FS25_ProductionStorageControl"] and pp.palletSpawner ~= nil then
                if FarmMonitor.palletInfoCache == nil then FarmMonitor:buildPalletInfoCache() end
                local ftToPallet = pp.palletSpawner.fillTypeIdToPallet
                for _, output in ipairs(outputs) do
                    local ft = g_fillTypeManager:getFillTypeByName(output.fillType)
                    if ft ~= nil then
                        local spawnerSupports = ftToPallet ~= nil and ftToPallet[ft.index] ~= nil
                        local info = FarmMonitor.palletInfoCache[ft.index]
                        if spawnerSupports and info ~= nil and output.level > 0 then
                            local maxP = math.floor(output.level / info.capacity)
                            if (output.level - maxP * info.capacity) >= 1 then maxP = maxP + 1 end
                            output.spawnOptions = FarmMonitor.obj(
                                "capacity", info.capacity,
                                "max",      maxP
                            )
                            table.insert(output.__order, "spawnOptions")
                        end
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
                    local hasPSC = g_modIsLoaded["FS25_ProductionStorageControl"]
                    for _, ftIdx in ipairs(pp.outputFillTypeIdsArray or {}) do
                        addAmount(ftIdx, pp:getFillLevel(ftIdx), locId, locName)
                        -- Annotate with production output metadata for Waren-View
                        if locations[ftIdx] ~= nil and locations[ftIdx][locId] ~= nil then
                            local m = pp:getOutputDistributionMode(ftIdx)
                            local mode = "keep"
                            if m == ProductionPoint.OUTPUT_MODE.DIRECT_SELL then mode = "sell"
                            elseif m == ProductionPoint.OUTPUT_MODE.AUTO_DELIVER then mode = "deliver"
                            elseif hasPSC and m == ProductionPoint.OUTPUT_MODE.STORE then mode = "store"
                            end
                            local loc = locations[ftIdx][locId]
                            loc.sourceType   = "production"
                            loc.ppUniqueId   = locId
                            loc.fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(ftIdx) or "UNKNOWN"
                            loc.outputMode   = mode
                        end
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

    -- Loose pallets & shipping containers — gruppiert nach nächstem Placeable
    if g_currentMission.vehicleSystem ~= nil then
        local anchors = FarmMonitor:buildPlaceableAnchors(farmId)
        local RADIUS2 = 75 * 75
        for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles or {}) do
            if vehicle.isPallet and (vehicle.ownerFarmId == farmId or vehicle.ownerFarmId == 0) then
                local spec = vehicle.spec_fillUnit
                if spec ~= nil and spec.fillUnits ~= nil and spec.fillUnits[1] ~= nil then
                    local fu = spec.fillUnits[1]
                    if fu.fillType ~= nil and fu.fillLevel ~= nil and fu.fillLevel > 0 then
                        local px, _, pz = getWorldTranslation(vehicle.rootNode)
                        local bestId, bestName = FarmMonitor:nearestAnchor(anchors, px, pz, RADIUS2)
                        addAmount(fu.fillType, fu.fillLevel, "pallets_" .. bestId, "Paletten: " .. bestName)
                    end
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
                        local entry
                        if loc.sourceType == "production" then
                            entry = FarmMonitor.obj(
                                "uniqueId",   locId,
                                "name",       loc.name,
                                "liters",     MathUtil.round(loc.liters),
                                "sourceType", loc.sourceType,
                                "ppUniqueId", loc.ppUniqueId,
                                "fillType",   loc.fillTypeName,
                                "outputMode", loc.outputMode
                            )
                        else
                            entry = FarmMonitor.obj(
                                "uniqueId", locId,
                                "name",     loc.name,
                                "liters",   MathUtil.round(loc.liters)
                            )
                        end
                        table.insert(storageLocationEntries, entry)
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

-- ---------------------------------------------------------------------------
-- Field metadata  (written once per session — density-map max values)
-- ---------------------------------------------------------------------------

function FarmMonitor:exportFieldMeta()
    local ok, err = pcall(function()
        local mission = g_currentMission
        if mission == nil or mission.fieldGroundSystem == nil or FieldDensityMap == nil then return end
        local fgs = mission.fieldGroundSystem

        local sprayMax = 2
        local limeMax  = 3
        local plowMax  = 1
        local mulchMax = 1
        if fgs.getMaxValue ~= nil then
            sprayMax = fgs:getMaxValue(FieldDensityMap.SPRAY_LEVEL)         or sprayMax
            limeMax  = fgs:getMaxValue(FieldDensityMap.LIME_LEVEL)          or limeMax
            plowMax  = fgs:getMaxValue(FieldDensityMap.PLOW_LEVEL)          or plowMax
            mulchMax = fgs:getMaxValue(FieldDensityMap.STUBBLE_SHRED_LEVEL) or mulchMax
        end

        -- Weed: derive max value from number of density-map channels (2^numCh - 1)
        local weedMax = 15
        if mission.weedSystem ~= nil and mission.weedSystem.getDensityMapData ~= nil then
            local wok, _, _, numCh = pcall(function() return mission.weedSystem:getDensityMapData() end)
            if wok and numCh ~= nil and numCh > 0 then
                weedMax = math.pow(2, numCh) - 1
            end
        end

        FarmMonitor:writeJSON(FarmMonitor.paths.fieldMeta, FarmMonitor.obj(
            "savegameId",           FarmMonitor.savegameId,
            "sprayLevelMax",        sprayMax,
            "limeLevelMax",         limeMax,
            "plowLevelMax",         plowMax,
            "stubbleShredLevelMax", mulchMax,
            "weedStateMax",         weedMax,
            "stoneLevelMax",        4
        ))
    end)
    if not ok then
        print("[FarmMonitor] ERROR writing fieldMeta.json: " .. tostring(err))
    end
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

-- ---------------------------------------------------------------------------
-- Vehicle meta  (static attributes, written every 10 s)
-- ---------------------------------------------------------------------------

function FarmMonitor:collectVehicleMeta()
    local result = FarmMonitor.arr()
    local farmId = g_currentMission:getFarmId()

    local fuelFillTypeIndices = {}
    if g_fillTypeManager and g_fillTypeManager.fillTypes then
        for idx, ft in ipairs(g_fillTypeManager.fillTypes) do
            if ft.name == "DIESEL" or ft.name == "ELECTRICCHARGE" or ft.name == "METHANE" then
                fuelFillTypeIndices[idx] = ft.name
            end
        end
    end

    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if not (vehicle.isPallet or vehicle.isShippingContainer)
            and vehicle.rootNode ~= nil
            and vehicle.getOwnerFarmId ~= nil
            and vehicle:getOwnerFarmId() == farmId
        then
            -- Use vehicle.xmlFile.filename (GarageMenu approach) with configFileName as fallback
            local xmlPath = (vehicle.xmlFile and vehicle.xmlFile.filename)
                         or vehicle.configFileName
                         or ""

            if xmlPath ~= "" then
                -- Store item lookup: categoryName, brand (single pcall)
                local brand    = ""
                local category = ""
                if g_storeManager then
                    local ok2, si = pcall(function()
                        return g_storeManager:getItemByXMLFilename(xmlPath)
                    end)
                    if ok2 and si then
                        category = si.categoryName or ""
                        if si.brandIndex and g_brandManager then
                            local b = g_brandManager:getBrandByIndex(si.brandIndex)
                            if b then brand = b.title or "" end
                        end
                    end
                end

                -- Only include vehicles with a meaningful shop category
                if category ~= "" then
                    local name = ""
                    if vehicle.getName ~= nil then name = vehicle:getName() or "" end

                    local propState = "owned"
                    local ps = vehicle.propertyState
                    if ps == 3 then propState = "leased"
                    elseif ps == 4 then propState = "mission" end

                    local fuelType = nil
                    local fuelCap  = 0
                    if vehicle.spec_fillUnit ~= nil and vehicle.spec_fillUnit.fillUnits ~= nil then
                        for _, fu in ipairs(vehicle.spec_fillUnit.fillUnits) do
                            local cap = fu.capacity or 0
                            if cap < 1e9 then
                                local ftName = fuelFillTypeIndices[fu.fillType]
                                if ftName then
                                    fuelType = fuelType or ftName
                                    fuelCap  = fuelCap  + cap
                                end
                            end
                        end
                    end

                    local opHours = 0
                    if vehicle.operatingTime and vehicle.operatingTime > 0 then
                        opHours = MathUtil.round(vehicle.operatingTime / 3600 * 10) / 10
                    end

                    local motorKw = nil
                    if vehicle.spec_motorized ~= nil then
                        local kw = vehicle.spec_motorized.peakMotorPower
                                or (vehicle.spec_motorized.motor and vehicle.spec_motorized.motor.peakMotorPower)
                                or (vehicle.spec_motorized.motor and vehicle.spec_motorized.motor.maxMotorPower)
                        if kw ~= nil and kw > 0 then motorKw = MathUtil.round(kw) end
                    end

                    -- Working width (largest workArea, or sprayer width as fallback)
                    local workWidth = 0
                    if vehicle.spec_workArea ~= nil and vehicle.spec_workArea.workAreas ~= nil then
                        for _, area in ipairs(vehicle.spec_workArea.workAreas) do
                            local w = area.workWidth or 0
                            if w > workWidth then workWidth = w end
                        end
                    end
                    if workWidth == 0 and vehicle.spec_sprayer ~= nil then
                        local ok, w = pcall(function()
                            return vehicle.spec_sprayer.usageScale
                               and vehicle.spec_sprayer.usageScale.workingWidth
                        end)
                        if ok and w and w > 0 then workWidth = w end
                    end
                    workWidth = workWidth > 0 and (MathUtil.round(workWidth * 10) / 10) or nil

                    -- Vehicle colors (designColor + baseColor, fallback to any available color config)
                    local color1 = nil
                    local color2 = nil
                    if vehicle.configurations and vehicle.configurationData then
                        local function getVehicleColor(configName)
                            local idx = vehicle.configurations[configName]
                            if not idx then return nil end
                            local configData = vehicle.configurationData[configName]
                            if not configData then return nil end
                            local entry = configData[idx]
                            local c = entry and entry.color
                            if not c then
                                local ok, res = pcall(ConfigurationUtil.getColorByConfigId, vehicle, configName, idx)
                                if ok and res then c = res end
                            end
                            if c and type(c) == "table" then
                                local r = math.min(255, math.max(0, MathUtil.round((c[1] or 0) * 255)))
                                local g = math.min(255, math.max(0, MathUtil.round((c[2] or 0) * 255)))
                                local b = math.min(255, math.max(0, MathUtil.round((c[3] or 0) * 255)))
                                return string.format("#%02x%02x%02x", r, g, b)
                            end
                            return nil
                        end
                        -- Preferred color configs first
                        local ok1, r1 = pcall(getVehicleColor, "designColor")
                        if ok1 then color1 = r1 end
                        local ok2, r2 = pcall(getVehicleColor, "baseColor")
                        if ok2 then color2 = r2 end
                        -- Fallback: scan all configurationData for any entry with a color
                        if color1 == nil or color2 == nil then
                            for configName, _ in pairs(vehicle.configurationData) do
                                if configName ~= "designColor" and configName ~= "baseColor" then
                                    local ok, col = pcall(getVehicleColor, configName)
                                    if ok and col then
                                        if color1 == nil then
                                            color1 = col
                                        elseif color2 == nil and col ~= color1 then
                                            color2 = col
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end

                    table.insert(result, FarmMonitor.obj(
                        "id",        tostring(vehicle.rootNode),
                        "name",      name,
                        "brand",     brand,
                        "category",  category,
                        "propState", propState,
                        "age",       vehicle.age or 0,
                        "price",     MathUtil.round(vehicle.price or 0),
                        "opHours",   opHours,
                        "fuelType",  fuelType,
                        "fuelCap",   MathUtil.round(fuelCap),
                        "motorKw",   motorKw,
                        "workWidth", workWidth,
                        "color1",    color1,
                        "color2",    color2
                    ))
                end
            end
        end
    end

    return result
end

function FarmMonitor:collectAndSaveVehicleMeta()
    local ok, err = pcall(function()
        local ts     = getDate("%Y-%m-%dT%H:%M:%S")
        local farmId = g_currentMission:getFarmId()
        FarmMonitor:writeJSON(FarmMonitor.paths.vehicleMeta, FarmMonitor.obj(
            "timestamp",  ts,
            "farmId",     farmId,
            "savegameId", FarmMonitor.savegameId,
            "vehicles",   FarmMonitor:collectVehicleMeta()
        ))
    end)
    if not ok then
        print("[FarmMonitor] ERROR during vehicleMeta collect: " .. tostring(err))
    end
end

function FarmMonitor:initSoilState()
    if not g_currentMission or not g_currentMission.isMissionStarted then return nil end
    local mission = g_currentMission
    local fgs = mission.fieldGroundSystem
    if fgs == nil or FieldDensityMap == nil or DensityCoordType == nil then return nil end
    local outputDir = FarmMonitor.paths.outputDir
    if outputDir == nil then return nil end

    local terrainSize = mission.terrainSize or 2048
    local res = FarmMonitor.soilResolution or 128

    local defs = {
        { name = "weed",   getMap = function() return mission.weedSystem and mission.weedSystem:getDensityMapData() end, maxVal = 9 },
        { name = "stone",  getMap = function() return mission.stoneSystem and mission.stoneSystem:getDensityMapData() end, maxVal = 4 },
        { name = "plow",   getMap = function() return fgs:getDensityMapData(FieldDensityMap.PLOW_LEVEL) end,           minVal = 1 },
        { name = "spray",  getMap = function() return fgs:getDensityMapData(FieldDensityMap.SPRAY_LEVEL) end,          maxVal = fgs:getMaxValue(FieldDensityMap.SPRAY_LEVEL) },
        { name = "lime",   getMap = function() return fgs:getDensityMapData(FieldDensityMap.LIME_LEVEL) end,           maxVal = fgs:getMaxValue(FieldDensityMap.LIME_LEVEL) },
        { name = "mulch",  getMap = function() return fgs:getDensityMapData(FieldDensityMap.STUBBLE_SHRED_LEVEL) end,  minVal = 1 },
        { name = "roller", getMap = function() return fgs:getDensityMapData(FieldDensityMap.ROLLER_LEVEL) end,         minVal = 1 },
    }

    -- Build cached modifier/filter per layer (mapId is stable across frames)
    local layers = {}
    for _, def in ipairs(defs) do
        local ok, mapId, firstCh, numCh = pcall(def.getMap)
        if ok and mapId ~= nil then
            local mod = DensityMapModifier.new(mapId, firstCh, numCh, g_terrainNode)
            layers[#layers + 1] = {
                name   = def.name,
                mod    = mod,
                flt    = DensityMapFilter.new(mod),
                maxVal = def.maxVal,
                minVal = def.minVal or 1,
            }
        end
    end

    if #layers == 0 then return nil end

    return {
        layers      = layers,
        outputDir   = outputDir,
        terrainSize = terrainSize,
        res         = res,
        cellSize    = terrainSize / res,
        half        = terrainSize / 2,
        rowsPerTick = FarmMonitor.soilRowsPerTick or 2,
        layerIdx    = 1,          -- C: current layer in round-robin
        currentRow  = 0,          -- A: next row to sample
        values      = {},         -- accumulator for current layer
    }
end

function FarmMonitor:stepSoilExport()
    local st = FarmMonitor.soilState
    local layer = st.layers[st.layerIdx]
    if layer == nil then return end

    local mod      = layer.mod
    local flt      = layer.flt
    local maxVal   = layer.maxVal
    local minVal   = layer.minVal
    local res      = st.res
    local cellSize = st.cellSize
    local half     = st.half
    local endRow   = math.min(st.currentRow + st.rowsPerTick - 1, res - 1)

    for zi = st.currentRow, endRow do
        for xi = 0, res - 1 do
            local wx = -half + xi * cellSize
            local wz = -half + zi * cellSize
            mod:setParallelogramWorldCoords(
                wx, wz, wx + cellSize, wz, wx, wz + cellSize,
                DensityCoordType.POINT_POINT_POINT)

            local v = 0
            if maxVal then
                for lv = maxVal, 1, -1 do
                    flt:setValueCompareParams(DensityValueCompareType.EQUAL, lv)
                    local _, area, _ = mod:executeGet(flt)
                    if area > 0 then
                        v = math.floor(lv / maxVal * 255)
                        break
                    end
                end
            else
                -- EQUAL-only scan: GREATER_OR_EQUAL not available in mod sandbox
                for lv = 7, minVal, -1 do
                    flt:setValueCompareParams(DensityValueCompareType.EQUAL, lv)
                    local _, area, _ = mod:executeGet(flt)
                    if area > 0 then v = 255; break end
                end
            end
            st.values[#st.values + 1] = v
        end
    end

    st.currentRow = endRow + 1

    if st.currentRow >= res then
        -- Layer complete — write file
        local name = layer.name
        local vals = st.values
        local writeOk, writeErr = pcall(function()
            local f = io.open(st.outputDir .. "layer_" .. name .. ".json", "w")
            if f == nil then error("cannot open file") end
            f:write('{"layer":"' .. name .. '","res":' .. res .. ',"data":[')
            f:write(table.concat(vals, ","))
            f:write(']}')
            f:close()
        end)
        if not writeOk then
            print("[FarmMonitor] ERROR writing layer_" .. name .. ": " .. tostring(writeErr))
        end

        -- Advance to next layer (C: round-robin)
        st.layerIdx   = (st.layerIdx % #st.layers) + 1
        st.currentRow = 0
        st.values     = {}
    end
end

function FarmMonitor:collectAndSaveVehicles()
    local ok, err = pcall(function()
        local ts     = getDate("%Y-%m-%dT%H:%M:%S")
        local farmId = g_currentMission:getFarmId()
        FarmMonitor:writeJSON(FarmMonitor.paths.vehicles, FarmMonitor.obj(
            "timestamp",  ts,
            "farmId",     farmId,
            "savegameId", FarmMonitor.savegameId,
            "vehicles",   FarmMonitor:collectVehicles()
        ))
    end)
    if not ok then
        print("[FarmMonitor] ERROR during vehicle collect: " .. tostring(err))
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
            and farmland.field ~= nil
        then
            local owned  = (farmland.farmId == farmId)
            local field  = farmland.field
            local areaHa      = farmland.areaInHa or 0
            local fieldAreaHa = field.areaHa or 0

            -- Field polygon (exported for all fields)
            local polygon = nil
            if field.densityMapPolygon ~= nil then
                local pxArr = FarmMonitor.arr()
                local pzArr = FarmMonitor.arr()
                local pts = field.densityMapPolygon
                if pts.pointsX ~= nil then
                    for i, v in ipairs(pts.pointsX) do
                        table.insert(pxArr, MathUtil.round(v * 10) / 10)
                        table.insert(pzArr, MathUtil.round((pts.pointsZ[i] or 0) * 10) / 10)
                    end
                end
                if #pxArr > 0 then
                    polygon = FarmMonitor.obj("x", pxArr, "z", pzArr)
                end
            end
            local cx, cz = field:getCenterOfFieldWorldPosition()

            -- For unowned fields: only export outline data, skip expensive calculations
            if not owned then
                table.insert(result, FarmMonitor.obj(
                    "id",         farmland.name or tostring(farmland.id or 0),
                    "farmlandId", farmland.id or 0,
                    "owned",      false,
                    "cx",         cx ~= nil and (MathUtil.round(cx * 10) / 10) or nil,
                    "cz",         cz ~= nil and (MathUtil.round(cz * 10) / 10) or nil,
                    "polygon",    polygon,
                    "area",       MathUtil.round(areaHa * 100) / 100
                ))
            else

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
                "owned",           true,
                "cx",              cx ~= nil and (MathUtil.round(cx * 10) / 10) or nil,
                "cz",              cz ~= nil and (MathUtil.round(cz * 10) / 10) or nil,
                "polygon",         polygon,
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
            end -- owned
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
            netId    = getXMLString(xmlId, base .. "#netId")    or "",  -- NetworkUtil object ID (MP-safe vehicle lookup)
            fillType = getXMLString(xmlId, base .. "#fillType") or "",
            mode     = getXMLString(xmlId, base .. "#mode")     or "",
            amount   = getXMLString(xmlId, base .. "#amount")   or "",
            x        = getXMLString(xmlId, base .. "#x")        or "",
            y        = getXMLString(xmlId, base .. "#y")        or "",
            z        = getXMLString(xmlId, base .. "#z")        or "",
            marker1         = getXMLString(xmlId, base .. "#marker1")         or "",
            marker2         = getXMLString(xmlId, base .. "#marker2")         or "",
            objectInfoIndex = getXMLString(xmlId, base .. "#objectInfoIndex") or "",
            value           = getXMLString(xmlId, base .. "#value")           or "",
            setting         = getXMLString(xmlId, base .. "#setting")         or "",
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
        ["production.setOutputMode"]      = FarmMonitor.cmdSetProductionOutputMode,
        ["production.spawnPallets"]       = FarmMonitor.cmdSpawnPallets,
        ["objectStorage.eject"]           = FarmMonitor.cmdEjectObjectStorage,
        ["player.teleportToPlaceable"]    = FarmMonitor.cmdTeleportToPlaceable,
        ["vehicle.enter"]                 = FarmMonitor.cmdEnterVehicle,
        ["vehicle.teleport"]              = FarmMonitor.cmdTeleportToVehicle,
        ["autodrive.configure"]           = FarmMonitor.cmdAutoDriveConfigure,
        ["autodrive.startStop"]           = FarmMonitor.cmdAutoDriveStartStop,
        ["autodrive.nextTarget"]          = FarmMonitor.cmdAutoDriveNextTarget,
        ["autodrive.continue"]            = FarmMonitor.cmdAutoDriveContinue,
        ["autodrive.park"]                = FarmMonitor.cmdAutoDrivePark,
        ["autodrive.swapTargets"]         = FarmMonitor.cmdAutoDriveSwapTargets,
        ["autodrive.loopCounter"]         = FarmMonitor.cmdAutoDriveLoopCounter,
        ["autodrive.speedLimit"]          = FarmMonitor.cmdAutoDriveSpeedLimit,
        ["autodrive.fieldSpeedLimit"]     = FarmMonitor.cmdAutoDriveFieldSpeedLimit,
        ["autodrive.toggleLoadByFill"]    = FarmMonitor.cmdAutoDriveToggle,
        ["autodrive.toggleAutoUnload"]    = FarmMonitor.cmdAutoDriveToggle,
        ["autodrive.toggleAutoPickup"]    = FarmMonitor.cmdAutoDriveToggle,
        ["autodrive.toggleStartHelper"]   = FarmMonitor.cmdAutoDriveToggle,
        ["autodrive.toggleUsedHelper"]    = FarmMonitor.cmdAutoDriveToggle,
        ["autodrive.setting"]             = FarmMonitor.cmdAutoDriveSetting,
        ["autodrive.pipeOffset"]          = FarmMonitor.cmdAutoDrivePipeOffset,
        ["autodrive.followDistance"]      = FarmMonitor.cmdAutoDriveFollowDistance,
        ["autodrive.unloadFillLevel"]     = FarmMonitor.cmdAutoDriveUnloadFillLevel,
        ["autodrive.cornerSpeed"]         = FarmMonitor.cmdAutoDriveCornerSpeed,
        ["autodrive.preCallLevel"]        = FarmMonitor.cmdAutoDrivePreCallLevel,
        ["autodrive.chaseSide"]           = FarmMonitor.cmdAutoDriveChaseSide,
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

function FarmMonitor:cmdTeleportToPlaceable(cmd)
    if g_localPlayer == nil then error("No local player (dedicated server?)") end
    -- Leave vehicle before teleporting (teleportTo has no effect while in a vehicle)
    if g_localPlayer.leaveVehicle ~= nil then
        pcall(function() g_localPlayer:leaveVehicle() end)
    end

    local x, y, z

    -- Loose pallets: coordinates sent directly in the command
    if cmd.x ~= "" and cmd.y ~= "" and cmd.z ~= "" then
        x = tonumber(cmd.x)
        y = tonumber(cmd.y)
        z = tonumber(cmd.z)
    else
        local placeable = g_currentMission.placeableSystem:getPlaceableByUniqueId(cmd.uniqueId)
        if placeable == nil then error("Placeable not found: " .. tostring(cmd.uniqueId)) end

        -- Use the in-game teleport node defined in the placeable's XML (entry point)
        if placeable.getHotspot ~= nil then
            local hotspot = placeable:getHotspot(1)
            if hotspot ~= nil and hotspot.getTeleportWorldPosition ~= nil then
                x, y, z = hotspot:getTeleportWorldPosition()
            end
        end

        -- Fallback: rootNode position + terrain height
        if x == nil and placeable.rootNode ~= nil then
            x, _, z = getWorldTranslation(placeable.rootNode)
            y = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
        end
    end

    if x == nil then error("Cannot determine teleport position for: " .. tostring(cmd.uniqueId)) end

    g_localPlayer:teleportTo(x, (y or 0) + 0.2, z)
end

function FarmMonitor:cmdEnterVehicle(cmd)
    if g_localPlayer == nil then error("No local player (dedicated server?)") end
    -- Find vehicle by rootNode id
    local targetId = cmd.uniqueId
    local vehicle = nil
    for _, v in pairs(g_currentMission.vehicleSystem.vehicles) do
        if v ~= nil and v.rootNode ~= nil and tostring(v.rootNode) == targetId then
            vehicle = v
            break
        end
    end
    if vehicle == nil then error("Vehicle not found: " .. tostring(targetId)) end
    -- Always enter the root vehicle of the attachment chain
    local rootVehicle = vehicle
    if vehicle.rootVehicle ~= nil then rootVehicle = vehicle.rootVehicle end
    g_localPlayer:requestToEnterVehicle(rootVehicle)
end

function FarmMonitor:cmdTeleportToVehicle(cmd)
    if g_localPlayer == nil then error("No local player (dedicated server?)") end
    -- Leave vehicle before teleporting
    if g_localPlayer.leaveVehicle ~= nil then
        pcall(function() g_localPlayer:leaveVehicle() end)
    end
    local targetId = cmd.uniqueId
    local vehicle = nil
    for _, v in pairs(g_currentMission.vehicleSystem.vehicles) do
        if v ~= nil and v.rootNode ~= nil and tostring(v.rootNode) == targetId then
            vehicle = v
            break
        end
    end
    if vehicle == nil then error("Vehicle not found: " .. tostring(targetId)) end

    local originX, originY, originZ = getWorldTranslation(vehicle.rootNode)
    local forwardX, forwardY, forwardZ = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
    -- Normalize forward vector
    local len = math.sqrt(forwardX*forwardX + forwardY*forwardY + forwardZ*forwardZ)
    if len > 0.0001 then
        forwardX, forwardY, forwardZ = forwardX/len, forwardY/len, forwardZ/len
    else
        forwardX, forwardY, forwardZ = 0, 0, 1
    end
    -- Teleport 6m in front of the vehicle
    local targetX = originX + forwardX * 6
    local targetZ = originZ + forwardZ * 6
    local targetY = getTerrainHeightAtWorldPos(g_terrainNode, targetX, 0, targetZ) + 0.2
    g_localPlayer:teleportTo(targetX, targetY, targetZ)
end

function FarmMonitor:cmdSpawnPallets(cmd)
    if not g_modIsLoaded["FS25_ProductionStorageControl"] then
        error("FS25_ProductionStorageControl not loaded")
    end

    local placeable = g_currentMission.placeableSystem:getPlaceableByUniqueId(cmd.uniqueId)
    if placeable == nil or placeable.spec_productionPoint == nil then
        error("Production not found: " .. tostring(cmd.uniqueId))
    end

    local pp = placeable.spec_productionPoint.productionPoint
    if pp.palletSpawner == nil then error("No pallet spawner on production") end

    local ft = g_fillTypeManager:getFillTypeByName(cmd.fillType)
    if ft == nil then error("FillType not found: " .. tostring(cmd.fillType)) end

    if FarmMonitor.palletInfoCache == nil then FarmMonitor:buildPalletInfoCache() end
    local info = FarmMonitor.palletInfoCache[ft.index]
    if info == nil then error("No pallet info for fillType: " .. tostring(cmd.fillType)) end

    local amount = math.max(1, math.floor(tonumber(cmd.amount) or 1))
    local available = pp:getFillLevel(ft.index)
    local maxP = math.floor(available / info.capacity)
    if (available - maxP * info.capacity) >= 1 then maxP = maxP + 1 end
    amount = math.min(amount, maxP)
    if amount <= 0 then error("Nothing to spawn for fillType: " .. tostring(cmd.fillType)) end

    local farmId       = g_currentMission:getFarmId()
    local pendingLiters = info.capacity * amount

    if g_currentMission.isServer then
        -- Server (listen-server host): autoritativer Direktaufruf
        pp:ReceiveSpawnEvent(
            farmId, ft.index, pendingLiters,
            info.width, info.height, info.length,
            info.capacity, 1, info.customEnvironment,
            nil, amount, 0, 0, 0
        )
    else
        -- Remote-Client: PSC-Netzwerkevent an Server senden
        -- (ReceiveSpawnEvent direkt aufzurufen erzeugt nur eine lokale Palette ohne Server-Sync)
        productionStorageControl_EventSpawn.sendEvent(
            pp, farmId, ft.index, pendingLiters,
            info.width, info.height, info.length,
            info.capacity, 1, info.customEnvironment,
            nil, amount, 0, 0, 0
        )
    end
end


-- ---------------------------------------------------------------------------
-- Object Storage commands
-- ---------------------------------------------------------------------------

function FarmMonitor:cmdEjectObjectStorage(cmd)
    local placeable = g_currentMission.placeableSystem:getPlaceableByUniqueId(cmd.uniqueId)
    if placeable == nil or placeable.spec_objectStorage == nil then
        error("Object storage not found: " .. tostring(cmd.uniqueId))
    end

    local objectInfoIndex = tonumber(cmd.objectInfoIndex)
    if objectInfoIndex == nil or objectInfoIndex < 1 then
        error("Invalid objectInfoIndex: " .. tostring(cmd.objectInfoIndex))
    end

    local objInfos = placeable.spec_objectStorage.objectInfos
    local objInfo  = objInfos and objInfos[objectInfoIndex]
    if objInfo == nil then
        error("objectInfoIndex out of range: " .. tostring(objectInfoIndex))
    end

    local available = #(objInfo.objects or {})
    local amount    = math.min(math.max(1, math.floor(tonumber(cmd.amount) or 1)), available)
    if amount <= 0 then
        error("Nothing to eject at objectInfoIndex: " .. tostring(objectInfoIndex))
    end

    if g_currentMission.isServer then
        placeable.spec_objectStorage:removeAbstractObjectsFromStorage(objectInfoIndex, amount, nil)
    else
        local ok, err = pcall(function()
            g_client:getServerConnection():sendEvent(
                PlaceableObjectStorageUnloadEvent.new(placeable, objectInfoIndex, amount)
            )
        end)
        if not ok then
            error("Failed to send PlaceableObjectStorageUnloadEvent: " .. tostring(err))
        end
    end
end

-- ---------------------------------------------------------------------------
-- AutoDrive commands
-- ---------------------------------------------------------------------------

-- Returns the FS25 network-synchronised object ID for a vehicle as a string,
-- or nil if unavailable (NetworkUtil not present or vehicle not registered).
-- This ID is identical on all processes (client, server, dedicated server).
function FarmMonitor:getNetworkId(vehicle)
    if NetworkUtil == nil or vehicle == nil then return nil end
    local ok, nid = pcall(NetworkUtil.getObjectId, vehicle)
    if ok and nid ~= nil and nid ~= 0 then
        return tostring(nid)
    end
    return nil
end

-- Fallback lookup by rootNode handle (string). Only reliable in SP where
-- client and server are the same process. Kept for backward compatibility.
function FarmMonitor:findVehicleByNodeId(nodeId)
    for _, v in pairs(g_currentMission.vehicleSystem.vehicles) do
        if v ~= nil and v.rootNode ~= nil and tostring(v.rootNode) == nodeId then
            return v
        end
    end
    return nil
end

-- Resolves a vehicle from an IPC command using a two-stage strategy:
--   1. NetworkUtil.getObject(cmd.netId)  — MP-safe: works in SP + all MP scenarios
--   2. rootNode iteration (cmd.uniqueId) — SP-only fallback if netId unavailable
-- Always use this instead of findVehicleByNodeId for commands that may be
-- forwarded to the server via FarmMonitorADCommandEvent.
function FarmMonitor:resolveVehicle(cmd)
    if cmd.netId ~= nil and cmd.netId ~= "" and NetworkUtil ~= nil then
        local ok, obj = pcall(NetworkUtil.getObject, tonumber(cmd.netId))
        if ok and obj ~= nil then return obj end
    end
    return FarmMonitor:findVehicleByNodeId(cmd.uniqueId)
end

function FarmMonitor:cmdAutoDriveConfigure(cmd)
    if not (g_modIsLoaded and g_modIsLoaded["FS25_AutoDrive"]) then
        error("AutoDrive not loaded")
    end

    -- MP-Client: forward to server via network event.
    -- On the client, direct AutoDrive API calls (sm:setMode, sm:setFirstMarker, …)
    -- are overwritten by the next server→client sync. The server must execute them.
    -- Guard: g_server == nil means we are a pure client (not SP, not listen-server host).
    if g_server == nil and g_client ~= nil then
        local serverConn = g_client:getServerConnection()
        if serverConn ~= nil then
            serverConn:sendEvent(FarmMonitorADCommandEvent.new(cmd))
            print("[FarmMonitor] AD configure forwarded to server via FarmMonitorADCommandEvent")
        else
            error("No server connection available to forward AD configure command")
        end
        return
    end

    -- SP / listen-server host / dedicated-server-side execution:
    -- resolveVehicle() uses netId (NetworkUtil) first, rootNode as fallback.
    local vehicle = FarmMonitor:resolveVehicle(cmd)
    if vehicle == nil or vehicle.ad == nil or vehicle.ad.stateModule == nil then
        error("Vehicle not found or has no AutoDrive: uniqueId=" .. tostring(cmd.uniqueId) .. " netId=" .. tostring(cmd.netId))
    end
    local sm = vehicle.ad.stateModule

    print("[FarmMonitor] AD configure: mode=" .. tostring(cmd.mode) .. " marker1=" .. tostring(cmd.marker1) .. " marker2=" .. tostring(cmd.marker2) .. " fillType=" .. tostring(cmd.fillType))

    if cmd.mode ~= "" then
        local modeNum = tonumber(cmd.mode)
        if modeNum then
            sm:setMode(modeNum)
            print("[FarmMonitor] AD setMode(" .. modeNum .. ") → getMode=" .. tostring(sm:getMode()))
        end
    end
    if cmd.marker1 ~= "" then
        local mid = tonumber(cmd.marker1)
        if mid then
            sm:setFirstMarker(mid)
            local m = sm.firstMarker
            print("[FarmMonitor] AD setFirstMarker(" .. mid .. ") → firstMarker=" .. tostring(m and m.name or "nil"))
        end
    end
    if cmd.marker2 ~= "" then
        local mid = tonumber(cmd.marker2)
        if mid then
            sm:setSecondMarker(mid)
            local m = sm.secondMarker
            print("[FarmMonitor] AD setSecondMarker(" .. mid .. ") → secondMarker=" .. tostring(m and m.name or "nil"))
        end
    end
    if cmd.fillType ~= "" then
        local ft = g_fillTypeManager:getFillTypeByName(cmd.fillType)
        if ft then
            sm:setFillType(ft.index)
            print("[FarmMonitor] AD setFillType(" .. cmd.fillType .. ")")
        end
    end
end

function FarmMonitor:cmdAutoDriveStartStop(cmd)
    if not (g_modIsLoaded and g_modIsLoaded["FS25_AutoDrive"]) then
        error("AutoDrive not loaded")
    end

    -- MP-Client: forward to server (same reason as cmdAutoDriveConfigure above)
    if g_server == nil and g_client ~= nil then
        local serverConn = g_client:getServerConnection()
        if serverConn ~= nil then
            serverConn:sendEvent(FarmMonitorADCommandEvent.new(cmd))
            print("[FarmMonitor] AD startStop forwarded to server via FarmMonitorADCommandEvent")
        else
            error("No server connection available to forward AD startStop command")
        end
        return
    end

    local vehicle = FarmMonitor:resolveVehicle(cmd)
    if vehicle == nil or vehicle.ad == nil or vehicle.ad.stateModule == nil then
        error("Vehicle not found or has no AutoDrive: uniqueId=" .. tostring(cmd.uniqueId) .. " netId=" .. tostring(cmd.netId))
    end
    local sm = vehicle.ad.stateModule
    print("[FarmMonitor] AD startStop: action=" .. tostring(cmd.mode) .. " isActive=" .. tostring(sm:isActive()) .. " isServer=" .. tostring(vehicle.isServer))
    if cmd.mode == "start" then
        local currentMode = sm:getCurrentMode()
        print("[FarmMonitor] AD start: isActive=" .. tostring(sm:isActive()) .. " mode=" .. tostring(sm:getMode()) .. " firstMarker=" .. tostring(sm.firstMarker and sm.firstMarker.name or "nil"))
        -- DriveToMode:start() ruft startAutoDrive() intern selbst auf — nicht vorher aufrufen
        if not sm:isActive() then
            currentMode:start()
            print("[FarmMonitor] AD mode:start() called")
        else
            print("[FarmMonitor] AD already active, stopping first then restarting")
            vehicle:stopAutoDrive()
            currentMode:start()
            print("[FarmMonitor] AD stopped and restarted")
        end
    else
        if sm:isActive() then
            vehicle:stopAutoDrive()
            print("[FarmMonitor] AD stopAutoDrive() called")
        end
    end
end

function FarmMonitor:cmdAutoDriveNextTarget(cmd)
    if not (g_modIsLoaded and g_modIsLoaded["FS25_AutoDrive"]) then
        error("AutoDrive not loaded")
    end

    if g_server == nil and g_client ~= nil then
        local serverConn = g_client:getServerConnection()
        if serverConn ~= nil then
            serverConn:sendEvent(FarmMonitorADCommandEvent.new(cmd))
            print("[FarmMonitor] AD nextTarget forwarded to server")
        else
            error("No server connection available")
        end
        return
    end

    local vehicle = FarmMonitor:resolveVehicle(cmd)
    if vehicle == nil or vehicle.ad == nil or vehicle.ad.stateModule == nil then
        error("Vehicle not found or has no AutoDrive: uniqueId=" .. tostring(cmd.uniqueId))
    end
    local sm = vehicle.ad.stateModule
    print("[FarmMonitor] AD nextTarget: isActive=" .. tostring(sm:isActive()) .. " mode=" .. tostring(sm:getMode()))

    local ok, err = pcall(function()
        sm:getCurrentMode():nextTarget()
    end)
    if not ok then
        print("[FarmMonitor] AD nextTarget mode:nextTarget() failed: " .. tostring(err))
        local ok2, err2 = pcall(function() vehicle:adNextTarget() end)
        if not ok2 then
            error("autodrive.nextTarget not supported: " .. tostring(err2))
        end
    end
end

-- Shared prologue for all AD commands.
-- - Raises if AutoDrive not loaded.
-- - On a pure MP-client (no g_server): forwards the command to the server via
--   FarmMonitorADCommandEvent and returns false — caller must return immediately.
-- - On SP / listen-server host / dedicated-server-side execution: returns true.
-- Note: dedicated server never reaches here via the dashboard (no g_localPlayer),
--       but CAN receive commands forwarded from connected clients.
function FarmMonitor:adBegin(cmd)
    if not (g_modIsLoaded and g_modIsLoaded["FS25_AutoDrive"]) then
        error("AutoDrive not loaded")
    end
    if g_server == nil and g_client ~= nil then
        local conn = g_client:getServerConnection()
        if conn == nil then error("No server connection available") end
        conn:sendEvent(FarmMonitorADCommandEvent.new(cmd))
        print("[FarmMonitor] AD command '" .. tostring(cmd.cmd) .. "' forwarded to server via FarmMonitorADCommandEvent")
        return false
    end
    return true
end

function FarmMonitor:cmdAutoDriveContinue(cmd)
    if not FarmMonitor:adBegin(cmd) then return end
    local vehicle = FarmMonitor:resolveVehicle(cmd)
    if vehicle == nil or vehicle.ad == nil or vehicle.ad.stateModule == nil then
        error("Vehicle not found or has no AutoDrive: " .. tostring(cmd.uniqueId))
    end
    local sm = vehicle.ad.stateModule
    local ok, err = pcall(function() sm:getCurrentMode():continue() end)
    if not ok then error("autodrive.continue failed: " .. tostring(err)) end
    print("[FarmMonitor] AD continue() called")
end

function FarmMonitor:cmdAutoDrivePark(cmd)
    if not FarmMonitor:adBegin(cmd) then return end
    local vehicle = FarmMonitor:resolveVehicle(cmd)
    if vehicle == nil or vehicle.ad == nil or vehicle.ad.stateModule == nil then
        error("Vehicle not found or has no AutoDrive: " .. tostring(cmd.uniqueId))
    end
    local sm = vehicle.ad.stateModule
    if sm.getParkDestinationAtJobFinished == nil then
        error("getParkDestinationAtJobFinished not available in this AD version")
    end
    local parkDest = sm:getParkDestinationAtJobFinished()
    if parkDest == nil or parkDest < 0 then
        error("No park destination configured for this vehicle")
    end
    sm:setFirstMarker(parkDest)
    sm:setMode(1)  -- DriveTO
    if sm:isActive() then vehicle:stopAutoDrive() end
    sm:getCurrentMode():start()
    print("[FarmMonitor] AD park: driving to marker " .. tostring(parkDest))
end

function FarmMonitor:cmdAutoDriveSwapTargets(cmd)
    if not FarmMonitor:adBegin(cmd) then return end
    local vehicle = FarmMonitor:resolveVehicle(cmd)
    if vehicle == nil or vehicle.ad == nil or vehicle.ad.stateModule == nil then
        error("Vehicle not found or has no AutoDrive: " .. tostring(cmd.uniqueId))
    end
    local sm = vehicle.ad.stateModule
    local m1 = sm.firstMarker
    local m2 = sm.secondMarker
    if m1 == nil or m2 == nil then
        error("Both markers must be set before swapping")
    end
    local id1 = m1.markerIndex
    local id2 = m2.markerIndex
    sm:setFirstMarker(id2)
    sm:setSecondMarker(id1)
    print("[FarmMonitor] AD swapTargets: " .. tostring(m1.name) .. " ↔ " .. tostring(m2.name))
end

function FarmMonitor:cmdAutoDriveLoopCounter(cmd)
    if not FarmMonitor:adBegin(cmd) then return end
    local vehicle = FarmMonitor:resolveVehicle(cmd)
    if vehicle == nil or vehicle.ad == nil or vehicle.ad.stateModule == nil then
        error("Vehicle not found or has no AutoDrive: " .. tostring(cmd.uniqueId))
    end
    local sm = vehicle.ad.stateModule
    if sm.getLoopCounter == nil or sm.changeLoopCounter == nil then
        error("Loop counter API not available in this AD version")
    end
    local target = tonumber(cmd.value)
    if target == nil then error("Invalid loop counter value: " .. tostring(cmd.value)) end
    target = math.max(0, math.min(99, math.floor(target)))
    local current = sm:getLoopCounter() or 0
    local delta = target - current
    if delta ~= 0 then
        local increment = delta > 0
        for i = 1, math.abs(delta) do
            sm:changeLoopCounter(increment, false)
        end
    end
    print("[FarmMonitor] AD loopCounter: " .. tostring(current) .. " → " .. tostring(target))
end

function FarmMonitor:cmdAutoDriveSpeedLimit(cmd)
    if not FarmMonitor:adBegin(cmd) then return end
    local vehicle = FarmMonitor:resolveVehicle(cmd)
    if vehicle == nil or vehicle.ad == nil or vehicle.ad.stateModule == nil then
        error("Vehicle not found or has no AutoDrive: " .. tostring(cmd.uniqueId))
    end
    local sm = vehicle.ad.stateModule
    if sm.getSpeedLimit == nil or sm.increaseSpeedLimit == nil then
        error("Speed limit API not available in this AD version")
    end
    local target = tonumber(cmd.value)
    if target == nil then error("Invalid speed limit: " .. tostring(cmd.value)) end
    target = math.max(2, math.floor(target))
    local maxIter = 200
    local i = 0
    while sm:getSpeedLimit() < target and i < maxIter do
        sm:increaseSpeedLimit(); i = i + 1
    end
    while sm:getSpeedLimit() > target and i < maxIter do
        sm:decreaseSpeedLimit(); i = i + 1
    end
    print("[FarmMonitor] AD speedLimit → " .. tostring(target) .. " km/h (iter=" .. i .. ")")
end

function FarmMonitor:cmdAutoDriveFieldSpeedLimit(cmd)
    if not FarmMonitor:adBegin(cmd) then return end
    local vehicle = FarmMonitor:resolveVehicle(cmd)
    if vehicle == nil or vehicle.ad == nil or vehicle.ad.stateModule == nil then
        error("Vehicle not found or has no AutoDrive: " .. tostring(cmd.uniqueId))
    end
    local sm = vehicle.ad.stateModule
    if sm.getFieldSpeedLimit == nil or sm.increaseFieldSpeedLimit == nil then
        error("Field speed limit API not available in this AD version")
    end
    local target = tonumber(cmd.value)
    if target == nil then error("Invalid field speed limit: " .. tostring(cmd.value)) end
    target = math.max(2, math.floor(target))
    local maxIter = 200
    local i = 0
    while sm:getFieldSpeedLimit() < target and i < maxIter do
        sm:increaseFieldSpeedLimit(); i = i + 1
    end
    while sm:getFieldSpeedLimit() > target and i < maxIter do
        sm:decreaseFieldSpeedLimit(); i = i + 1
    end
    print("[FarmMonitor] AD fieldSpeedLimit → " .. tostring(target) .. " km/h (iter=" .. i .. ")")
end

-- Handles all five toggle commands — cmd.cmd determines which toggle to apply.
function FarmMonitor:cmdAutoDriveToggle(cmd)
    if not FarmMonitor:adBegin(cmd) then return end
    local vehicle = FarmMonitor:resolveVehicle(cmd)
    if vehicle == nil or vehicle.ad == nil or vehicle.ad.stateModule == nil then
        error("Vehicle not found or has no AutoDrive: " .. tostring(cmd.uniqueId))
    end
    local sm = vehicle.ad.stateModule
    local toggles = {
        ["autodrive.toggleLoadByFill"]  = "toggleLoadByFillLevel",
        ["autodrive.toggleAutoUnload"]  = "toggleAutomaticUnloadTarget",
        ["autodrive.toggleAutoPickup"]  = "toggleAutomaticPickupTarget",
        ["autodrive.toggleStartHelper"] = "toggleStartHelper",
        ["autodrive.toggleUsedHelper"]  = "toggleUsedHelper",
    }
    local methodName = toggles[cmd.cmd]
    if methodName == nil then error("Unknown toggle command: " .. tostring(cmd.cmd)) end
    if sm[methodName] == nil then
        error("Toggle method '" .. methodName .. "' not available in this AD version")
    end
    local ok, err = pcall(sm[methodName], sm)
    if not ok then error("Toggle failed: " .. tostring(err)) end
    print("[FarmMonitor] AD toggle: " .. methodName .. "()")
end

function FarmMonitor:cmdAutoDriveSetting(cmd)
    if not (g_modIsLoaded and g_modIsLoaded["FS25_AutoDrive"]) then
        error("AutoDrive not loaded")
    end
    local settingName = cmd.setting
    if settingName == nil or settingName == "" then
        error("Missing setting name in autodrive.setting command")
    end
    local valueIndex = tonumber(cmd.value)
    if valueIndex == nil then
        error("Invalid value index for setting '" .. settingName .. "': " .. tostring(cmd.value))
    end

    -- Pure MP-client: follow exactly the same path AutoDrive itself uses.
    -- AutoDrive's own flow is: client sets value locally → sends AutoDriveUpdateSettingsEvent
    -- to server → server applies + broadcasts to all clients.
    -- We replicate this exactly so the DS processes and syncs the change correctly.
    if g_server == nil and g_client ~= nil then
        local vehicle = FarmMonitor:resolveVehicle(cmd)
        if vehicle == nil or vehicle.ad == nil or vehicle.ad.settings == nil then
            error("Vehicle not found or has no AutoDrive settings")
        end
        local s = vehicle.ad.settings[settingName]
        if s == nil then error("Unknown AD setting: " .. tostring(settingName)) end
        if s.values == nil or s.values[valueIndex] == nil then
            error("Value index " .. valueIndex .. " out of range for setting '" .. settingName .. "'")
        end
        -- 1. Apply locally on client (instant feedback, same as AD does)
        s.current = valueIndex
        s.new     = valueIndex
        -- 2. Send to server via AutoDrive's own event — server will apply + broadcast back to all clients
        local ok_ev, err_ev = pcall(function()
            AutoDriveUpdateSettingsEvent.sendEvent(vehicle)
        end)
        if ok_ev then
            print("[FarmMonitor] AD setting (client→AD-event→server): " .. settingName .. " = index " .. valueIndex)
        else
            -- Fallback: send via FarmMonitorADCommandEvent so server at least sets the value
            print("[FarmMonitor] AD setting AutoDriveUpdateSettingsEvent failed (" .. tostring(err_ev) .. "), using FarmMonitorADCommandEvent fallback")
            local conn = g_client:getServerConnection()
            if conn then conn:sendEvent(FarmMonitorADCommandEvent.new(cmd)) end
        end
        return
    end

    -- SP / listen-server host / DS-side execution (via FarmMonitorADCommandEvent fallback):
    local vehicle = FarmMonitor:resolveVehicle(cmd)
    if vehicle == nil or vehicle.ad == nil or vehicle.ad.settings == nil then
        error("Vehicle not found or has no AutoDrive settings: " .. tostring(cmd.uniqueId))
    end
    local s = vehicle.ad.settings[settingName]
    if s == nil then error("Unknown AD setting: " .. tostring(settingName)) end
    if s.values == nil or s.values[valueIndex] == nil then
        error("Value index " .. valueIndex .. " out of range for setting '" .. settingName .. "'")
    end
    s.current = valueIndex
    s.new     = valueIndex
    -- Broadcast to all clients (only reached in SP or as fallback)
    pcall(function()
        if AutoDriveUpdateSettingsEvent ~= nil then
            g_server:broadcastEvent(AutoDriveUpdateSettingsEvent.new(vehicle))
        end
    end)
    print("[FarmMonitor] AD setting: " .. settingName .. " = index " .. valueIndex)
end

function FarmMonitor:cmdAutoDrivePipeOffset(cmd)
    cmd.setting = "pipeOffset"
    FarmMonitor:cmdAutoDriveSetting(cmd)
end

function FarmMonitor:cmdAutoDriveFollowDistance(cmd)
    cmd.setting = "followDistance"
    FarmMonitor:cmdAutoDriveSetting(cmd)
end

function FarmMonitor:cmdAutoDriveUnloadFillLevel(cmd)
    cmd.setting = "unloadFillLevel"
    FarmMonitor:cmdAutoDriveSetting(cmd)
end

function FarmMonitor:cmdAutoDriveCornerSpeed(cmd)
    cmd.setting = "cornerSpeed"
    FarmMonitor:cmdAutoDriveSetting(cmd)
end

function FarmMonitor:cmdAutoDrivePreCallLevel(cmd)
    cmd.setting = "preCallLevel"
    FarmMonitor:cmdAutoDriveSetting(cmd)
end

function FarmMonitor:cmdAutoDriveChaseSide(cmd)
    cmd.setting = "chaseSide"
    FarmMonitor:cmdAutoDriveSetting(cmd)
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
    local n   = select('#', ...)   -- count ALL args including nils (Lua 5.1 safe)
    for i = 1, n, 2 do
        local k = select(i, ...)
        local v = select(i + 1, ...)
        t[k] = v
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
