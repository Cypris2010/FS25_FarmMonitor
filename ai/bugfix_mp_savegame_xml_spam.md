# Bug: careerSavegame.xml Spam auf MP-Client

## Symptom

Beim Joinen eines Multiplayer-Servers spamt der Client die Log-Datei mit dem Fehler:

```
Error: Failed to open xml file 'C:/Users/.../FarmingSimulator2025/savegame0/careerSavegame.xml'.
```

Ca. alle 40ms — also jeden Update-Tick. Der Mod läuft trotzdem, aber die Log-Datei wächst massiv.

## Ursache

`readSavegameInfo()` (`FarmMonitor.lua:621`) liest `careerSavegame.xml` um `savegameName` und `savegameId` für die JSON-Metadaten zu ermitteln. Die Datei existiert nur auf der Host-Maschine, nicht auf dem Client.

`XMLFile.load()` gibt `nil` zurück wenn die Datei fehlt — das Giants-Engine loggt dabei selbst den Fehler. Die Funktion gibt daraufhin `nil, nil` zurück.

In `update()` steht:

```lua
if FarmMonitor.savegameName == nil then
    FarmMonitor.savegameName, FarmMonitor.savegameId = FarmMonitor:readSavegameInfo()
end
```

Da `savegameName` nach dem fehlgeschlagenen Read weiterhin `nil` ist, wiederholt sich der Versuch jeden Tick.

## Abhängigkeiten

`savegameName` / `savegameId` sind reine Metadaten-Felder die in fast alle JSON-Exports eingebettet werden (`silos.json`, `productions.json`, `fields.json`, `vehicles.json` usw.). Sie werden vom Server und Dashboard nicht funktional ausgewertet, dienen nur zur Identifikation des aktiven Savegames.

Der Savegame-Wechsel-Mechanismus selbst (der `savegameDirectory`-Vergleich und die `*Exported`-Flags) funktioniert auf dem Client korrekt — nur der nachgelagerte `readSavegameInfo()`-Call ist das Problem.

## Fix (`FarmMonitor.lua:640-641`)

Nach dem `pcall` Fallback-Werte setzen wenn die XML nicht gelesen werden konnte:

```lua
-- On MP clients careerSavegame.xml only exists on the host — use fallbacks so we don't retry every tick
if name == nil then name = "unknown" end
if savegameId == nil then
    local slot = (missionInfo.savegameDirectory or ""):match("([^/\\]+)$") or "unknown"
    savegameId = (missionInfo.mapId or "unknown") .. "_" .. slot
end
```

- `name` — auf dem Client unbekannt, bleibt `"unknown"`
- `savegameId` — die echte ID ist `mapId .. "_" .. creationDate`; auf dem Client ist `creationDate` nicht verfügbar, daher Näherung aus `mapId` + letztem Verzeichnisteil aus `savegameDirectory` (z.B. `savegame0`). Ergibt z.B. `FS25_Haut-Beyleron_savegame0` — eindeutig genug für Metadaten-Zwecke.

Das Giants-Engine-Error tritt damit noch genau einmal auf (beim ersten Versuch), dann hört der Retry auf.

## Entstehungsgeschichte

Der Bug war latent seit **v0.2.3** (Einführung von `readSavegameInfo` für Savegame-Wechsel-Erkennung), trat aber erst durch das **v0.3.0** Multiplayer-Enable auf.
