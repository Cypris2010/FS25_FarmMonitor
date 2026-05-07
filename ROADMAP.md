# FarmMonitor Roadmap

## v0.3.0 — Object Storages (Paletten & Ballenlager)
- **Lua:** Object Storages exportieren — Typ, Inhalt, Kapazität, Standort
- **Lua:** Unterscheidung Paletten vs. Ballen
- **Dashboard:** Neuer View "Lager" mit Karten + Kapazitätsbalken

## v0.4.0 — Warenübersicht
- **Lua:** Verkaufspreise exportieren (aktueller Preis + Maximalpreis pro Ware)
- **Lua:** Alle Lagermengen aggregiert nach Fülltyp (Silos + Object Storages)
- **Dashboard:** Neuer View "Waren" — Tabelle mit Menge, Akt. Preis, Max. Preis, % vom Maximum
- **Dashboard:** Farbliche Hervorhebung bei Verkaufsempfehlung

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
