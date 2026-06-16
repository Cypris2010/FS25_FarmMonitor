---
name: vehicles_tanks
description: "Fahrzeug-Tank-Klassifizierung — Kraftstoff/Hilfsstoff/Haupttank, main:true Flag, Leer-Anzeige nur für Haupttank"
metadata:
  node_type: memory
  type: reference
---

Vollständige Dokumentation: `ai/vehicles_tanks.md`

## Drei Tank-Gruppen (Lua)

| Gruppe | Fülltypen | Export |
|---|---|---|
| Kraftstoff | DIESEL, ELECTRICCHARGE, METHANE | `fuelPct` / `fuelLiter` (separat) |
| Hilfsstoff | DEF, ADBLUE, COMPRESSEDAIR, AIR, OIL, HYDRAULIC_OIL | `tanks`-Array, nie `main` |
| Haupttank | alles andere mit cap > 0 | `tanks`-Array, größter → `main: true` |

WATER ist kein Hilfsstoff (Tankwagen-Hauptladung).

## JSON-Format

```json
{ "name": "WHEAT", "pct": 0, "liter": 0, "cap": 24000, "main": true }
```

`main` fehlt im JSON wenn nicht gesetzt (nur bei `true` exportiert).

## Dashboard-Logik (Fleet-Card + Detail-View identisch)

- **Haupttank**: immer anzeigen, 0 % → Balken rot (`.cargo.low`)
- **Andere Tanks**: nur anzeigen wenn `pct > 0`

## CSS

```css
.fleet-bar-fill.cargo.low { background: #ef5350; }
.vd-tank-fill.cargo.low   { background: #ef5350; }
```
