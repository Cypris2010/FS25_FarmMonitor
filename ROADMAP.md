# FarmMonitor Roadmap

## v0.2.1 — Bugfix: Produktionen mit Silo-Extension
- **Bug:** Warenbestände von Produktionen werden nicht angezeigt wenn eine Silo-Extension angeschlossen ist
- **Ursache:** `pp.storage:getCapacity(fillTypeId)` gibt 0 zurück wenn der Speicher durch eine Silo-Extension ersetzt wird — der `if capacity > 0` Check filtert dann alle Einträge heraus
- **Fix Lua:** Kapazität aus der verknüpften Silo-Extension lesen wenn `pp.storage` sie nicht kennt; Einträge mit `level > 0` auch bei `capacity == 0` exportieren
- **Fix Lua:** Produktions-Inputs aus globalem Siloverbund korrekt lesen — wenn Inputs über Siloverbund fließen zeigt `pp.storage:getFillLevel()` 0 obwohl Material vorhanden ist
- **Fix Dashboard:** Füllstandsanzeige ohne Kapazität graceful behandeln

## v0.2.2 — Bugfixes & QoL
- **Bug Lua:** Leere Arrays serialisieren als `{}` statt `[]` — kann im Dashboard zu Fehlern führen wenn z.B. eine Produktion keine Inputs hat
- **Bug Lua:** Savegame-Wechsel ohne Server-Neustart — `savegameName` und `savegameId` werden einmalig gecacht; bei neuem Savegame stimmen die Daten nicht mehr
- **Bug Lua:** Silo-Extension Kapazität im Silos-View — `storage.capacity` kann 0 sein bei Extensions
- **QoL Server:** Beim Start vorhandene JSON-Dateien sofort laden statt auf ersten Schreibvorgang warten
- **QoL Dashboard:** Alert-Schwellwerte (z.B. Futter unter X%) konfigurierbar in Settings statt hardcoded

## v0.3.0 — Object Storages (Paletten & Ballenlager)
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

## v0.4.0 — Warenübersicht
- **Server:** DDS-Icons der Fülltypen server-seitig zu PNG konvertieren — Go-Server liest `fillTypes.json`, konvertiert alle `hudOverlayFilename`-Pfade (`.dds`) zu PNG und serviert sie unter `/icons/<filltype>.png`
- **Dashboard:** Fülltyp-Icons aus `/icons/<filltype>.png` laden und in der Warenübersicht anzeigen
- **Lua:** Alle Lagermengen aggregiert nach Fülltyp aus allen Quellen (Silos + Object Storages + Husbandry + Produktionen + Paletten + Ballen)
- **Lua:** Verkaufspreise via `g_currentMission.storageSystem:getUnloadingStations()`:
  - Aktueller Preis pro Station: `station:getEffectiveFillTypePrice(fillType)`
  - Bester aktueller Preis & beste Station
  - Preistrend: FALLING / CLIMBING / GREAT_DEMAND (`station:getCurrentPricingTrend`)
  - Nachfrage-Highlight: `station.greatDemandFillType`
- **Lua:** Maximalpreis über alle 12 Jahresperioden: `fillType.economy.factors[period]`
- **Lua:** Bester Verkaufsmonat pro Ware
- **Dashboard:** Neuer View "Waren" — Tabelle mit:
  - Ware, Gesamtmenge, Aktueller Preis, Aktueller Wert, Maximalpreis, Maximaler Wert, Bester Monat
  - Farbliche Hervorhebung: Blau ≥100%, Dunkelgrün ≥95%, Gelb ≥90%, Weiß <90%
  - Preistrend-Indikator (Pfeil hoch/runter/Sondernachfrage)

## v0.5.0 — Feldübersicht
- **Lua:** Felder exportieren via `g_farmlandManager.farmlands` + `field:getFieldState()`
- **Lua:** Basis-Felddaten (immer verfügbar):
  - Fläche (`farmland.field.areaHa`)
  - Fruchttyp & Wachstumsstufe (`data.lastFruitTypeIndex`, `data.lastGrowthState / fruitType.numGrowthStates`)
  - Erntebereit-Flag (`fruitType.growthStateToName[stage] == "harvestReady"`)
  - Potenzielle Ernte in Litern/Tonnen (`fruitType.literPerSqm * areaHa * harvestMultiplier`)
  - Pflugzustand (`field:getFieldState().plowLevel`)
  - Düngezustand allgemein (`field:getFieldState().sprayLevel`)
  - Kalkzustand (`field:getFieldState().limeLevel`)
  - Unkrautzustand (`field:getFieldState().weedState`)
  - Mulchzustand (`field:getFieldState().stubbleShredLevel`)
  - Steine (`field:getFieldState().stoneLevel`)
  - Besitz (`farmland.isOwned`)
- **Lua:** Optional mit PrecisionFarming DLC (`g_modIsLoaded["FS25_precisionFarming"]`):
  - Bodenfeuchtigkeit
  - N/P/K Werte (Stickstoff, Phosphor, Kalium)
- **Dashboard:** Neuer View "Felder" — Grid mit Feldzustand + Alerts für erntereife/ungepflegte Felder

## v0.6.0 — Mobile Web & Netzwerk
- **Server:** mDNS/Bonjour — meldet sich als `farmmonitor.local` im LAN
- **Server:** API-Versionierung (`/api/v1/...`)
- **Dashboard:** Responsive Layout für Smartphone/Tablet
- **Dashboard:** PWA-Manifest + Offline-Fähigkeit (als App auf Homescreen speicherbar)

## v0.7.0 — Historische Daten
- Zeitreihen für Silo-Füllstände, Preise, Produktionsleistung
- Charts im Dashboard
- Datenpersistenz auf dem Server (SQLite oder CSV)

## v0.8.0 — Polish & QoL
- Mehrsprachigkeit (DE/EN)
- Multiplayer-Unterstützung
