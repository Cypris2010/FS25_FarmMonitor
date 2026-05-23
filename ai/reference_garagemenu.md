# FS25_GarageMenu — Referenz für Fahrzeug-Kategorisierung

Quelle: FS25_GarageMenu by Ozz  
Hauptdatei: `gui/MenuGarageMenu.lua`

## Fahrzeug-Kategorisierung via Shop-System

GarageMenu verwendet das FS25-Shop-System für die Kategorisierung, statt `mapHotspotType`.
Das ist der korrekte Ansatz — die Kategorien entsprechen exakt denen im Spiel-Shop.

### Kategorie-Name eines Fahrzeugs lesen

```lua
-- XML-Pfad des Fahrzeugs (bevorzugt vehicle.xmlFile.filename)
local xmlPath = (vehicle.xmlFile and vehicle.xmlFile.filename)
             or vehicle.configFileName
             or ""

-- Store-Item holen
local si = g_storeManager:getItemByXMLFilename(xmlPath)
if si then
    local categoryName = si.categoryName  -- z.B. "tractors", "harvesters", "trailers"
    local brandIndex   = si.brandIndex
end
```

### Alle verfügbaren Kategorien aus dem Shop lesen

```lua
local inGameMenu = g_gui.screenControllers[ShopMenu]

-- Sektionen (VEHICLES, EQUIPMENT, OBJECTS …)
for index, detail in pairs(inGameMenu.pageShopVehicles.categoryTypes) do
    detail.name   -- Sektions-ID
    detail.title  -- lokalisierter Titel (z.B. "Fahrzeuge")
end

-- Kategorien pro Sektion (tractors, combines, trailers …)
for sectionID, entries in pairs(inGameMenu.pageShopVehicles.categories) do
    for _, category in pairs(entries) do
        category.id         -- Kategorie-ID (z.B. "tractors")
        category.label      -- lokalisierter Name (z.B. "Traktoren")
        category.sortValue  -- Sortierreihenfolge innerhalb der Sektion
    end
end
```

### Verfügbarkeit

`g_gui.screenControllers[ShopMenu]` ist nach dem Spielstart verfügbar.
`pageShopVehicles.categoryTypes` und `.categories` sind nach Mission-Start befüllt.
→ In FarmMonitor: mit `pcall` und `vehicleCategoriesExported`-Flag exportieren.

### Wichtige Hinweise

- `vehicle.xmlFile.filename` ist zuverlässiger als `vehicle.configFileName`
- Fahrzeuge ohne Store-Eintrag (`si == nil`) oder ohne `categoryName` überspringen
- Kategorie `"OBJECTS"` in GarageMenu explizit ausgeblendet — enthält Platzierbare, keine Fahrzeuge
- `si.categoryName` ist der gleiche String, der in `vehicleCategories.json` und `vehicleMeta.json` verwendet wird
