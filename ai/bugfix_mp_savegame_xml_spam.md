# Bug: careerSavegame.xml Spam auf MP-Client

## Symptom

Beim Joinen eines Multiplayer-Servers spamt der Client die Log-Datei mit dem Fehler:

```
Error: Failed to open xml file 'C:/Users/.../FarmingSimulator2025/savegame0/careerSavegame.xml'.
```

Ca. alle 40ms — also jeden Update-Tick. Der Mod läuft trotzdem, aber die Log-Datei wächst massiv.

## Ursache

`readSavegameInfo()` liest `careerSavegame.xml` um `savegameName` und `savegameId` für die JSON-Metadaten zu ermitteln. Die Datei existiert nur auf der Host-Maschine, nicht auf dem Client.

`XMLFile.load()` gibt `nil` zurück wenn die Datei fehlt — das Giants-Engine loggt dabei selbst den Fehler. Die Funktion gab `nil, nil` zurück, `savegameName` blieb `nil`, und `update()` wiederholte den Versuch jeden Tick.

## Abhängigkeiten

`savegameName` / `savegameId` sind Metadaten-Felder in fast allen JSON-Exports (`silos.json`, `productions.json`, `fields.json`, `vehicles.json` usw.). Sie werden vom Dashboard nicht funktional ausgewertet — dienen nur zur Identifikation des aktiven Savegames.

Der Savegame-Wechsel-Mechanismus (der `savegameDirectory`-Vergleich + `*Exported`-Flags) funktioniert auch ohne diese Werte korrekt.

## Lösung (implementiert in v0.4.4)

### Schritt 1: Fallbacks statt Retry-Loop

`readSavegameInfo()` wird auf dem Client nicht mehr aufgerufen. Stattdessen setzt `update()` direkt Fallback-Werte wenn `isServer == false`:

```lua
FarmMonitor.savegameName = "unknown"
local slot = missionInfo.savegameDirectory:match("([^/\\]+)$") or "unknown"
FarmMonitor.savegameId   = (missionInfo.mapId or "unknown") .. "_" .. slot
-- z.B. "FS25_Haut-Beyleron_savegame0"
```

### Schritt 2: Echter Wert via Network Event

Der Server überträgt `savegameName` und `savegameId` beim Client-Join via `FarmMonitorSavegameEvent`:

```lua
-- Server → onClientJoined:
connection:sendEvent(FarmMonitorSavegameEvent.new(FarmMonitor.savegameName, FarmMonitor.savegameId))

-- Client → Event:run():
FarmMonitor.savegameName      = self.savegameName
FarmMonitor.savegameId        = self.savegameId
FarmMonitor.savegameInfoReady = true
```

### Schritt 3: Exports blockieren bis Info bereit

Client-seitige Exports starten erst wenn `savegameInfoReady == true`. Timeout nach 10s mit Fallback-Werten, damit nichts dauerhaft blockiert:

```lua
if not FarmMonitor.savegameInfoReady then
    if g_currentMission.isServer then
        FarmMonitor.savegameName, FarmMonitor.savegameId = FarmMonitor:readSavegameInfo()
        FarmMonitor.savegameInfoReady = true
    else
        FarmMonitor.savegameInfoTimeout = FarmMonitor.savegameInfoTimeout - dt
        if FarmMonitor.savegameInfoTimeout <= 0 then
            -- Fallbacks setzen, exports freigeben
            FarmMonitor.savegameInfoReady = true
        end
        return  -- noch nicht exportieren
    end
end
```

## Entstehungsgeschichte

- **v0.2.3**: `readSavegameInfo()` eingeführt für Savegame-Wechsel-Erkennung
- **v0.3.0**: Multiplayer aktiviert — Bug wird sichtbar
- **v0.4.4**: Vollständige Lösung via Network Event + savegameInfoReady-Flag
