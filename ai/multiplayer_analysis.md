# Multiplayer-Analyse FarmMonitor

## Grundprinzip
Jeder Spieler hat den Mod lokal installiert und führt ihn selbst aus. Daher:
- `io.open` schreibt ins lokale `getUserProfileAppPath()` des jeweiligen Clients
- `getFarmId()` gibt die eigene Farm-ID zurück
- Jeder Spieler sieht automatisch nur seine eigene Farm — ohne große Architekturänderungen nötig

## Offene Fragen
- `io.open` auf MP-Clients: wahrscheinlich erlaubt, aber noch nicht durch MP-Test bestätigt
- Dedicated Server: kein lokaler Spieler → `getFarmId()` gibt `SPECTATOR_FARM_ID` zurück → leere Listen

## Benötigte Code-Änderungen für MP (v0.8.0)
- `isServer`-Guard für Dedicated-Server-Fall in `update()` und `collectAndSave()`
- `getFarmId()` auf Dedicated Server konfigurierbar machen (z.B. über modSettings)
- Vor Implementierung: kurzen MP-Test machen (3 Zeilen Testcode in `loadMap`, Log prüfen)
