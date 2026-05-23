# FS25_QuickSelector — Referenz für Fahrzeugfarben

Quelle: FS25_QuickSelector  
Hauptdatei: `scripts/vim.lua`

## Fahrzeugfarbe auslesen

FS25 speichert Fahrzeugfarben als RGBA-Tabellen (Werte 0–1) in `vehicle.configurationData`.
Es gibt zwei Farbkonfigurationen: `designColor` (Hauptfarbe) und `baseColor` (Sekundärfarbe).

### Vollständige Logik (aus vim.lua)

```lua
local function getVehicleColor(vehicle, configName)
    if not vehicle.configurations or not vehicle.configurationData then return nil end
    local idx = vehicle.configurations[configName]
    if not idx then return nil end
    local configData = vehicle.configurationData[configName]
    if not configData then return nil end
    local entry = configData[idx]
    local c = entry and entry.color
    -- Fallback via ConfigurationUtil
    if not c then
        local ok, res = pcall(ConfigurationUtil.getColorByConfigId, vehicle, configName, idx)
        if ok and res then c = res end
    end
    if c and type(c) == "table" then
        -- c = {r, g, b, a} mit Werten 0–1
        return c
    end
    return nil
end

local color1 = getVehicleColor(vehicle, "designColor")  -- Hauptfarbe
local color2 = getVehicleColor(vehicle, "baseColor")    -- Sekundärfarbe
```

### In FarmMonitor: Export als Hex-String

```lua
local function colorToHex(c)
    local r = math.min(255, math.max(0, MathUtil.round((c[1] or 0) * 255)))
    local g = math.min(255, math.max(0, MathUtil.round((c[2] or 0) * 255)))
    local b = math.min(255, math.max(0, MathUtil.round((c[3] or 0) * 255)))
    return string.format("#%02x%02x%02x", r, g, b)
end
```

### Dashboard: Diagonal geteilter Farbkreis (SVG)

```html
<!-- Zwei Farben → diagonal geteilter Kreis -->
<svg width="20" height="20" viewBox="0 0 20 20">
  <defs><clipPath id="vc-{id}"><circle cx="10" cy="10" r="9"/></clipPath></defs>
  <circle cx="10" cy="10" r="9" fill="{color1}"/>
  <polygon points="20,0 20,20 0,20" fill="{color2}" clip-path="url(#vc-{id})"/>
  <circle cx="10" cy="10" r="9" fill="none" stroke="rgba(255,255,255,0.15)" stroke-width="1"/>
</svg>

<!-- Eine Farbe → Vollkreis -->
<svg width="20" height="20" viewBox="0 0 20 20">
  <circle cx="10" cy="10" r="9" fill="{color1}"/>
  <circle cx="10" cy="10" r="9" fill="none" stroke="rgba(255,255,255,0.15)" stroke-width="1"/>
</svg>
```

**Wichtig:** `clipPath`-IDs müssen pro Fahrzeug eindeutig sein (z.B. `vc-{vehicle.rootNode}`).

### Wichtige Hinweise

- `vehicle.configurations.designColor` — Index der gewählten Hauptfarbe (kann `nil` sein)
- `vehicle.configurations.baseColor` — Index der Sekundärfarbe (nicht immer vorhanden)
- `vehicle.configurationData` — enthält die Farbdefinitionen aller Konfigurationen
- `ConfigurationUtil.getColorByConfigId` — Fallback wenn `entry.color` nicht direkt verfügbar
- Fahrzeuge ohne Farbkonfiguration (z.B. manche Anhänger) haben `nil` für beide Farben
- `vehicle.isBrightDesignColor` (QuickSelector-intern berechnet via Helligkeitscheck) — nicht nativ auf vehicle
