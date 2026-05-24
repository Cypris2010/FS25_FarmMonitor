# FarmMonitor Roadmap

## v0.2.2 — Bugfix: Produktionen mit Silo-Extension
- **Bug:** Warenbestände von Produktionen werden nicht angezeigt wenn eine Silo-Extension angeschlossen ist
- **Ursache:** `pp.storage:getCapacity(fillTypeId)` gibt 0 zurück wenn der Speicher durch eine Silo-Extension ersetzt wird — der `if capacity > 0` Check filtert dann alle Einträge heraus
- ✅ **Fix Lua:** `pp:getFillLevel/getCapacity` direkt auf ProductionPoint statt `pp.storage:`; Einträge mit `level > 0` auch bei `capacity == 0` exportieren
- ✅ **Fix Lua:** Produktions-Inputs aus globalem Siloverbund korrekt lesen — durch `pp:getFillLevel()` direkt auf ProductionPoint bereits korrekt gelöst (In-Game bestätigt)
- ✅ **Fix Dashboard:** Alert-Guard — Füllstand-Alerts nur wenn `capacity > 0` bekannt

## v0.2.3 — Bugfixes & QoL
- ✅ **Bug Lua:** Leere Arrays serialisieren als `{}` statt `[]`
- ✅ **Bug Lua:** Savegame-Wechsel ohne Server-Neustart — savegameDirectory-Vergleich in `update()` erkennt neues Savegame und setzt Cache zurück
- ✅ **Bug Lua:** Silo-Extension Kapazität im Silos-View — nicht reproduzierbar, `storage.capacity` korrekt in allen getesteten Extensions

## v0.2.4 — Smart Husbandry Alerts & konfigurierbare Warnstufen
- ✅ **Lua:** `animalFood.json` exportiert `consumptionType` (SERIAL/PARALLEL) und `eatWeight` pro Futtergruppe
- ✅ **Dashboard:** Alert-Schwellwerte für PARALLEL-Tiere (z.B. Schweine) werden mit `eatWeight` skaliert — eine Gruppe mit 5% Anteil löst erst bei `crit × 0.05` einen Alert aus
- ✅ **Dashboard:** Balkenfarben (grün/gelb/rot) folgen demselben gewichteten Schema
- ✅ **Dashboard:** Alle Alert-Schwellwerte (Eingänge, Ausgänge, Belegung) in den Settings konfigurierbar und persistent gespeichert

## v0.3.0 — Warenübersicht & Feldübersicht
- ✅ **Lua:** Alle Lagermengen aggregiert nach Fülltyp aus allen Quellen (Silos + Object Storages + Husbandry + Produktionen + Paletten + Ballen)
- ✅ **Lua:** Produktions-Inputs von Warenmengen-Aggregation ausgeschlossen
- ✅ **Lua:** UniqueId-Deduplizierung für Lagerorte mit gleichem Namen
- ✅ **Lua:** Verkaufspreise via `g_currentMission.storageSystem:getUnloadingStations()`:
  - Aktueller Preis pro Station: `station:getEffectiveFillTypePrice(fillType)`
  - Bester aktueller Preis & beste Station
  - Preistrend: FALLING / CLIMBING / GREAT_DEMAND (`station:getCurrentPricingTrend`)
  - Nachfrage-Highlight: `station.greatDemandFillType`
- ✅ **Lua:** Maximalpreis über alle 12 Jahresperioden inkl. Wirtschaftlichkeitsmultiplikator
- ✅ **Lua:** Bester Verkaufsmonat pro Ware
- ✅ **Dashboard:** View "Waren" — Tabelle mit Ware, Gesamtmenge, Aktueller/Maximaler Preis & Wert, Bester Monat, Preistrend-Indikator, farbliche Hervorhebung (Blau ≥100%, Dunkelgrün ≥95%, Gelb ≥90%)
- ✅ **Dashboard:** Produktions-Nutzungsanzeige auf Waren-Karten
- ✅ **Dashboard:** Klickbare Input-Links in Produktionen-View → Waren-View
- ✅ **Lua:** Felder exportieren via `g_farmlandManager.farmlands` + DensityMapModifier (3×3 Grid, 60s Intervall)
- ✅ **Lua:** Felddaten: Fläche, Fruchttyp & Wachstumsstufe, Erntebereit-Flag, Pflug-/Dünge-/Kalk-/Unkraut-/Mulch-/Steine-Zustand, Besitz
- ✅ **Lua:** Bodenzustand-Maximalwerte in `fieldMeta.json` exportiert
- ✅ **Dashboard:** View "Felder" — Grid mit Feldzustand (farbige Balken), Alerts für erntereife/ungepflegte Felder
- ✅ **Dashboard:** Projizierte Ernte auf Feldkarten
- ✅ **Dashboard:** Bedarfsrechner pro Feld — Saatgut, Kalk, Dünger, Herbizid
- ✅ **Dashboard:** Saatgut-Selektor Dropdown auf Feldkarten (Vorauswahl aktuelle Frucht)
- ✅ **Dashboard:** Quicknav + responsives Grid in Produktionen- und Tierhaltung-View
- ✅ **Dashboard:** Card-Flash-Highlight bei Quicknav- und View-übergreifender Navigation
- ✅ **Dashboard:** Safari CPU/GPU Performance-Fix (mix-blend-mode entfernt)
- ✅ **Lua/modDesc:** Multiplayer aktiviert (`multiplayer supported="true"`)
- ✅ **Lua:** `isServer`-Guard in `update()` — überspringt Ausführung auf Dedicated Servers

## v0.4.x — AutoDrive Integration
- ✅ **Lua:** `autoDriveMarkers.json` exportiert alle Marker (Name, Gruppe, markerIndex) via Iterator-Trick über `sm:setFirstMarker(id)` — da `ADGraphManager` aus FarmMonitor-Sandbox nicht zugänglich
- ✅ **Lua:** Inkrementeller Export alle 60s: Schnelltest mit `lastMaxId+1`, nur re-exportieren bei neuen Markern
- ✅ **Lua:** `vehicles.json` enthält AutoDrive-Status pro Fahrzeug: `adActive`, `adMode`, `adDriverName`, `adDestination`, `adDestination2`, `adRemainingTime`
- ✅ **Lua:** IPC-Commands `autodrive.configure` (Mode, Marker1, Marker2, FillType) und `autodrive.startStop`
- ✅ **Lua:** Fahrzeug-Lookup per `rootNode` (nicht `getVehicleByUniqueId`) da `vehicles.json` rootNode als ID exportiert
- ✅ **Lua:** Start-Sequenz: `sm:getCurrentMode():start()` direkt — der Mode ruft `startAutoDrive()` intern selbst auf; separate Vorbelegung bricht Initialisierungsreihenfolge
- ✅ **Dashboard:** AutoDrive-Tab im Fahrzeug-Detailpanel — schiebt sich von rechts ins Bild (max-width Animation)
- ✅ **Dashboard:** Mode-Dropdown (1–5), dynamische Marker-Dropdowns (gruppiert), FillType-Dropdown (Modi 2/3/4), Start/Stop-Buttons
- ✅ **Dashboard:** „Start" konfiguriert automatisch zuerst (configure + startStop in einem Click)
- ✅ **Dashboard:** Flottenkarte zeigt AutoDrive-Status (aktiv/Ziel)

## v0.4.0 — Object Storages (Paletten & Ballenlager)
- **Lua:** Alle Lagerquellen exportieren via `g_currentMission.placeableSystem.placeables`:
  - Giants Object Storage (`spec_objectStorage`) — Paletten, Ballen inkl. Fermentierungsstatus
  - Object Storage Mods (`spec_objectStorageMod`) — z.B. Ballenlager-Mods
  - Fahrsilo / Bunker Silo (`spec_bunkerSilo`) — inkl. Fermentierungsstatus & Kompaktierungsgrad
  - Mistlager (`spec_manureHeap`)
  - Bienenstock-Paletten (`spec_beehivePalletSpawner`)
- **Lua:** Loose Ballen aus `g_currentMission.itemSystem.itemsToSave` (Bale-Objekte)
- **Lua:** Loose Paletten & Shipping Container aus `g_currentMission.vehicleSystem.vehicles`
- **Lua:** uniqueId-Deduplizierung zwischen Object Storage und Ballen-Liste
- **Dashboard:** Neuer View "Lager" mit Karten pro Lagertyp + Kapazitätsbalken + Fermentierungsanzeige


## v0.6.0 — Feldübersicht Erweiterungen
- **Lua:** Optional mit PrecisionFarming DLC (`g_modIsLoaded["FS25_precisionFarming"]`):
  - Bodenfeuchtigkeit
  - N/P/K Werte (Stickstoff, Phosphor, Kalium)

## v0.7.0 — Mobile Web & Netzwerk
- **Server:** mDNS/Bonjour — meldet sich als `farmmonitor.local` im LAN
- **Server:** API-Versionierung (`/api/v1/...`)
- **Dashboard:** Responsive Layout für Smartphone/Tablet
- **Dashboard:** PWA-Manifest + Offline-Fähigkeit (als App auf Homescreen speicherbar)

## v0.8.0 — Historische Daten & Alert-Benachrichtigungen
- Zeitreihen für Silo-Füllstände, Preise, Produktionsleistung
- Charts im Dashboard
- Datenpersistenz auf dem Server (SQLite oder CSV)
- **Dashboard:** Notification-Banner oben im Dashboard bei neuen Alerts
  - Fingerprint-basiertes Delta-Tracking: jeder Alert erhält stabilen Key aus Typ + Name + Ressource + Level (z.B. `"husbandry:Hühner:water:crit"`)
  - `seenFingerprints` in localStorage (`farmmonitor_seen_alerts`) — kein Server-State nötig
  - Nach jedem SSE-Update: neue Fingerprints (nicht in seen) → Banner anzeigen; aufgelöste Fingerprints → aus seen entfernen (ermöglicht Re-Trigger)
  - Banner zeigt Anzahl neuer Alerts + schwersten Level; Klick navigiert zum Alerts-View; Dismiss fügt Fingerprints zu seen hinzu
  - Nur `dashboard.html` betroffen (~50–80 Zeilen JS + ~20 Zeilen CSS)

## v0.9.0 — Polish & QoL
- Mehrsprachigkeit (DE/EN)
- **QoL Dashboard:** Alert-Schwellwerte (z.B. Futter unter X%) konfigurierbar in Settings statt hardcoded
