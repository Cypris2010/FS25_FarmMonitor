# FS25 Fahrzeug-API — Vollständige Referenz

Quellen: FS25_VehicleInspector, FS25_VehicleManager, FS25_EnhancedVehicle, GIANTS LuaDoc

## Iteration über alle Fahrzeuge

```lua
local farmId = g_currentMission:getFarmId()
for v = 1, #g_currentMission.vehicleSystem.vehicles do
    local vehicle = g_currentMission.vehicleSystem.vehicles[v]
    if vehicle ~= nil and vehicle.finishedLoading == true then
        if vehicle.ownerFarmId == farmId then
            -- Fahrzeug verarbeiten
        end
    end
end

-- Nur begehbare Fahrzeuge (schneller für UI-Listen):
g_currentMission.vehicleSystem.enterables[v]

-- Lookup per Node:
local vehicle = g_currentMission.nodeToObject[vehicleNode]
-- Lookup per uniqueId:
g_currentMission.vehicleSystem:getVehicleByUniqueId(uniqueId)
```

## Basis-Eigenschaften (immer vorhanden)

```lua
vehicle.rootNode              -- Szenen-Node
vehicle.typeName              -- Typ-String ("locomotive", "crane", ...)
vehicle.typeDesc              -- Typ-Beschreibung
vehicle.configFileName        -- Pfad zur XML-Konfigurationsdatei
vehicle.ownerFarmId           -- Besitzer-Farm-ID (auch via :getOwnerFarmId())
vehicle.propertyState         -- 1=owned, 3=leased, 4=mission leased
vehicle.finishedLoading       -- true wenn fertig geladen
vehicle.age                   -- Alter in Monaten
vehicle.price                 -- aktueller Fahrzeugwert
vehicle.operatingTime         -- Betriebsstunden
vehicle.lastSpeed             -- Geschwindigkeit (m/s)
vehicle.lastSpeedReal         -- reale Geschwindigkeit
vehicle.speedLimit            -- Geschwindigkeitsbegrenzer
vehicle.lastMovedDistance     -- Distanz im letzten Update-Zyklus
vehicle.isBroken              -- Schadenstatus
vehicle.isPallet              -- Palette?
vehicle.isInWater             -- Im Wasser?
vehicle.isBlocked             -- Blockiert?
vehicle.isServer / .isClient  -- Netzwerk-Rolle
vehicle.schemaOverlay.schemaName  -- Schema-Kategorie (siehe unten)
vehicle.configurations        -- aktive Konfigurationen (z.B. .motor, .frontloader)
vehicle.components            -- Komponenten-Nodes
vehicle.steeringAxleNode      -- Lenkachsen-Node
vehicle.trainSystem           -- Train-System (nil wenn kein Zug)
vehicle.rootVehicle           -- Parent-Vehicle (für Child-Vehicles)

-- Methoden:
vehicle:getName()             -- Fahrzeugname
vehicle:getFullName()         -- vollständiger Name
vehicle:getImageFilename()    -- Thumbnail-Pfad
vehicle:getIsActive()
vehicle:getIsControlled()
vehicle:getIsEntered()
vehicle:getIsAIActive()       -- KI/Helper aktiv?
vehicle:getIsDrivingBackward()
vehicle:getLastSpeed()
vehicle:getSpeedLimit()
vehicle:getTotalMass(withImplements)  -- Gesamtgewicht
vehicle:getMaxComponentMassReached()  -- Überlast?
vehicle:getAvailableComponentMass()
vehicle:getShowInVehiclesOverview()
vehicle:getDailyUpkeep()
```

## Name & Marke (via Store)

```lua
local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
if storeItem then
    storeItem.name          -- vollständiger Modellname
    storeItem.price         -- Kaufpreis
    storeItem.brandIndex    -- Index für g_brandManager
    local brand = g_brandManager:getBrandByIndex(storeItem.brandIndex)
    brand.title             -- Markenname (z.B. "FENDT", "JOHN DEERE")
end
```

## Schema-Kategorien (vehicle.schemaOverlay.schemaName)

```lua
"DEFAULT_VEHICLE"     -- normales Fahrzeug
"DEFAULT_IMPLEMENT"   -- Anbaugerät
"HARVESTER"           -- Mähdrescher
"MOTORBIKE"           -- Motorrad/Quad
-- typeName-Vergleiche (vehicle.typeName:lower()):
"combinecutterfruitpreparer"
"combinedrivable"
"locomotive"
"crane"
```

## Position & Rotation

```lua
local x, y, z    = getWorldTranslation(vehicle.rootNode)
local rx, ry, rz = getWorldRotation(vehicle.rootNode)
-- Lokale → Weltkoordinaten:
local wx, wy, wz = localToWorld(vehicle.rootNode, lx, ly, lz)
-- Richtungsvektor:
local dx, dy, dz = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
-- Fahrtrichtung in Grad:
-- MathUtil.getYRotationFromDirection(dx, dz) → Winkel
```

## spec_motorized — Motor & Antrieb

```lua
if vehicle.spec_motorized ~= nil then
    vehicle.spec_motorized.motorizedNode         -- Motor-Node
    vehicle.spec_motorized.motor                 -- Motor-Objekt
    vehicle.spec_motorized.currentRPM            -- aktuelle Drehzahl
    vehicle.spec_motorized.minRpm                -- Min-Drehzahl
    vehicle.spec_motorized.maxRpm                -- Max-Drehzahl
    vehicle.spec_motorized.smoothedLoadPercentage  -- Motorauslastung %
    vehicle.spec_motorized.peakMotorTorque       -- Max-Drehmoment (Nm)
    vehicle.spec_motorized.peakMotorPower        -- Max-Leistung (kW)
    vehicle.spec_motorized.motorAppliedTorque    -- aktuelles Drehmoment
    vehicle.spec_motorized.lastFuelUsage         -- Verbrauch (l/h oder kW/h)
    vehicle.spec_motorized.motorTemperature.value  -- Motortemperatur
    vehicle.spec_motorized:getMotorRpmReal()     -- reale RPM
    vehicle.spec_motorized:getIsOperating()      -- betrieb?
    vehicle:getIsMotorStarted()                  -- Motor läuft?
    vehicle:getIsMotorInNeutral()                -- Neutral?
    -- Differenziale:
    vehicle.spec_motorized.differentials[i]
        .diffIndex1             -- 0=vorne-hinten, 1=vorne, 3=hinten
        .diffIndex1IsWheel      -- Rad-Sperre?
        .torqueRatio            -- Drehmomentverhältnis (1.0 = gesperrt)
        .maxSpeedRatio          -- Geschwindigkeitsverhältnis (hoch = offen)
    -- Differenzial steuern:
    updateDifferential(rootNode, diffIdx, torqueRatio, maxSpeedRatio)
end
```

## spec_drivable — Fahrverhalten & Getriebe

```lua
if vehicle.spec_drivable ~= nil then
    vehicle.spec_drivable.currentGear           -- aktueller Gang
    vehicle.spec_drivable.targetGear            -- Zielgang
    vehicle.spec_drivable.gearShiftMode         -- Auto/Manuell/Kupplung
    vehicle.spec_drivable.reverserDirection     -- Fahrtrichtung (-1/1)
    vehicle.spec_drivable.maxForwardSpeed       -- Max vorwärts (m/s)
    vehicle.spec_drivable.maxBackwardSpeed      -- Max rückwärts (m/s)
    vehicle.spec_drivable.clutchPedal           -- Kupplungsposition
    vehicle.spec_drivable.pto                   -- Zapfwellendrehmoment
    -- Cruise Control:
    vehicle.spec_drivable.cruiseControl.state   -- 0=off, 1=aktiv
    vehicle.spec_drivable.cruiseControl.speed   -- Zielgeschwindigkeit
    vehicle.spec_drivable.cruiseControl.speedReverse
    vehicle.spec_drivable.cruiseControl.maxSpeedReverse
    vehicle:setCruiseControlState(Drivable.CRUISECONTROL_STATE_OFF)
    -- Bewegungsrichtung:
    vehicle.movingDirection      -- aktuell (vorwärts/rückwärts)
    vehicle.nextMovingDirection  -- geplant
end
```

## spec_fillUnit — Tanks & Füllmengen

```lua
if vehicle.spec_fillUnit ~= nil then
    for i, fu in ipairs(vehicle.spec_fillUnit.fillUnits) do
        fu.fillType            -- fillTypeIndex
        fu.fillLevel           -- aktuelle Menge (Liter)
        fu.fillLevelToDisplay  -- Anzeigewert
        fu.capacity            -- Tankgröße
        fu.supportedFillTypes  -- {fillTypeIndex → true}
        fu.showOnHud           -- auf HUD anzeigen?
        fu.showOnInfoHud       -- auf Info-HUD?
        fu.uiPrecision         -- UI-Nachkommastellen
        fu.ignoreFillLimit     -- Limit ignorieren?
        fu.parentUnitOnHud     -- Parent-Unit-Ref
    end
    -- Methoden:
    vehicle:getFillUnitFillLevel(fillUnitIndex)
    vehicle:getFillUnitCapacity(fillUnitIndex)
    vehicle:getConsumerFillUnitIndex()
end
-- Erkannte Fülltypen:
-- FillType.DIESEL, FillType.DEF (AdBlue), FillType.ELECTRICCHARGE, FillType.METHANE
```

## spec_attacherJoints — Anbaugeräte & Hydraulik

```lua
if vehicle.spec_attacherJoints ~= nil then
    for i, joint in ipairs(vehicle.spec_attacherJoints.attacherJoints) do
        joint.allowsLowering    -- Hydraulik auf/ab erlaubt?
        joint.moveDown          -- aktuell abgesenkt?
        joint.jointTransform    -- Transform-Node
    end
    vehicle.spec_attacherJoints:setJointMoveDown(vehicle, jointIndex, moveDown)
    vehicle.spec_attacherJoints:getImplementByJointDescIndex(index)
    -- alle angehängten Geräte:
    local implements = vehicle:getAttachedImplements()
    for _, impl in pairs(implements) do
        impl.object                   -- Gerät als Vehicle-Objekt
        impl.jointDescIndex           -- Joint-Index am Traktor
        impl.inputAttacherJointDescIndex  -- Anschlusspunkt am Gerät
        impl.object.rootNode          -- Gerät rootNode
    end
end
```

## spec_attachable — Anbaugerät (wird angebaut)

```lua
if vehicle.spec_attachable ~= nil then
    vehicle.spec_attachable:setLoweredAll(isLowered)  -- heben/senken
end
```

## spec_workArea — Arbeitsbreite & -typ

```lua
if vehicle.spec_workArea ~= nil then
    for _, area in ipairs(vehicle.spec_workArea.workAreas) do
        area.functionName  -- Arbeitstyp (CULTIVATOR, SOWER, SPRAYER, ...)
        area.start         -- Start-Node
        area.width         -- Breiten-Node
        area.height        -- Höhen-Node
        area.workWidth     -- effektive Arbeitsbreite (Meter)
        area.type          -- Typ-Konstante
    end
end
-- Sprayer-Sonderfall:
if vehicle.spec_sprayer ~= nil then
    vehicle.spec_sprayer.usageScale.workingWidth  -- aktuelle Spritzbreite
end
-- AI-Marker für Arbeitsbreite:
local leftMarker, rightMarker = object:getAIMarkers()
```

## spec_wearable — Schaden & Verschleiß

```lua
if vehicle.spec_wearable ~= nil then
    vehicle.spec_wearable:getDamageAmount()   -- Schaden 0.0–1.0
    vehicle.spec_wearable:getWearTotalAmount() -- Verschleiß 0.0–1.0
end
-- Auch für angehängte Geräte iterieren:
-- implement.object.spec_wearable:getDamageAmount()
```

## spec_foldable — Klappzustand

```lua
if vehicle.spec_foldable ~= nil then
    vehicle.spec_foldable.isFoldAllowed       -- Klappen erlaubt?
    vehicle.spec_foldable.foldMoveDirection   -- 0=stop, +1=klappt, -1=klappt aus
    vehicle.spec_foldable:getIsUnfolded()     -- ausgeklappt?
    vehicle.spec_foldable:setFoldState(direction, moveToFoldWhenLowered)
    -- direction: 1=einklappen, -1=ausklappen
end
```

## spec_turnOnVehicle — Ein/Aus-Status

```lua
if vehicle.spec_turnOnVehicle ~= nil then
    vehicle.spec_turnOnVehicle.isTurnedOn           -- läuft?
    vehicle.spec_turnOnVehicle.requiresMotorTurnOn  -- braucht Motor?
    vehicle.spec_turnOnVehicle:setIsTurnedOn(state)
end
```

## spec_lights — Beleuchtung

```lua
if vehicle.spec_lights ~= nil then
    vehicle.spec_lights.currentLightState  -- 0=aus, >0=an
    vehicle.spec_lights.numLightTypes      -- Anzahl Lichttypen
    vehicle:setNextLightsState(numLightTypes)
    vehicle:deactivateLights(state)
end
```

## spec_globalPositioningSystem — GPS

```lua
if vehicle.spec_globalPositioningSystem ~= nil then
    vehicle.spec_globalPositioningSystem.hasGuidanceSystem  -- GPS vorhanden?
    vehicle.spec_globalPositioningSystem.lastInputValues.guidanceIsActive  -- aktiv?
end
```

## spec_enterable — Begehbar

```lua
if vehicle.spec_enterable ~= nil then
    vehicle.spec_enterable.controllerUserId  -- UserID des Fahrers
    vehicle.spec_enterable.isEntered         -- besetzt?
    vehicle:getActiveCamera()                -- aktive Kamera (hat .cameraNode)
end
```

## spec_trailer — Anhänger

```lua
if vehicle.spec_trailer ~= nil then
    vehicle.spec_trailer.tipSideCount         -- Anzahl Entladeseiten
    vehicle.spec_trailer.tipSides[i].name     -- Seitenname
    vehicle.spec_trailer.preferedTipSideIndex -- aktive Seite
    vehicle.spec_trailer.infoText             -- Info-Text-Template
end
```

## spec_rideable — Reittier (Pferd)

```lua
if vehicle.spec_rideable ~= nil then
    -- Fahrzeug ist ein Pferd/Reittier
end
```

## spec_plow — Pflug

```lua
if vehicle.spec_plow ~= nil then
    vehicle.spec_plow.rotationMax  -- Max-Schwenkwinkel
end
```

## spec_combine — Mähdrescher

```lua
if vehicle.spec_combine ~= nil then
    vehicle.spec_combine:getFillLevelInformation()  -- Ernte-Füllstandsdaten
end
```

## spec_woodContainer — Holzcontainer / Shipping Container

```lua
if vehicle.spec_woodContainer ~= nil then
    -- Fahrzeug ist ein Shipping Container (kein Pallet)
end
```

## Drittanbieter-Mod Integration (falls geladen)

```lua
-- AutoDrive:
if vehicle.ad ~= nil then
    vehicle.ad.stateModule:getName()          -- Fahrername
    vehicle.ad.stateModule:getFirstMarker()   -- erster Wegpunkt
    vehicle.ad.drivePathModule                -- Routenmodul
    vehicle.ad.collisionDetectionModule       -- Kollisionserkennung
end
-- CoursePlay:
if vehicle.cp ~= nil then
    vehicle:getCpStatus()
    vehicle:getIsCourseplayDriving()
end
-- VehicleManager-Integration:
if vehicle.vmControl ~= nil then
    vehicle.vmControl.typId        -- zugewiesene Typ-ID
    vehicle.vmControl.driverName   -- manuell gesetzter Fahrername
end
```

## Wichtige Patterns

```lua
-- Fahrzeugtyp-Erkennung:
vehicle.spec_motorized ~= nil    → motorisiert
vehicle.spec_combine ~= nil      → Mähdrescher
vehicle.spec_attachable ~= nil   → Anbaugerät/Anhänger
vehicle.spec_drivable ~= nil     → fahrbar
vehicle.isPallet                 → Palette
vehicle.spec_woodContainer ~= nil → Shipping Container
vehicle.spec_rideable ~= nil     → Reittier
vehicle.trainSystem ~= nil       → Zug

-- Besitz prüfen:
vehicle.ownerFarmId == g_currentMission:getFarmId()
-- oder Pächter:
farm:getIsContractingFor(vehicle.ownerFarmId)

-- Schäden aller Fahrzeuge inkl. Anbaugeräte auslesen:
local function getDamage(v)
    local dmg = v.spec_wearable and v.spec_wearable:getDamageAmount() or 0
    if v.spec_attacherJoints then
        for _, impl in pairs(v:getAttachedImplements()) do
            if impl.object.spec_wearable then
                dmg = math.max(dmg, impl.object.spec_wearable:getDamageAmount())
            end
        end
    end
    return dmg
end
```
