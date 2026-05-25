---
name: vehicles_nearby
description: "Fahrzeug-Positionsanzeige (Nearby-System) — Felder als bevorzugte Ankerpunkte, Point-in-Polygon, Richtungsberechnung, Hotspot-Fallback"
metadata:
  node_type: memory
  type: reference
---

Vollständige Dokumentation: `ai/vehicles_nearby.md`

## Anzeigeformat

| Situation | Text |
|---|---|
| Auf Feld, Mitte | `Mitte Feld 7` |
| Auf Feld | `N auf Feld 7` |
| Außerhalb, Feld nah | `120 m NO v Feld 7` |
| Hotspot-Fallback | `80 m S · Getreidehof` |

## Entscheidungslogik

1. Point-in-Polygon → auf Feld?  
   - < 30 m vom Mittelpunkt → „Mitte Feld X"  
   - sonst → „[dir vom Mittelpunkt zum Fahrzeug] auf Feld X"

2. Außerhalb: nächstes Feld vs. nächsten Hotspot vergleichen  
   - `nearFieldDist < nearHotspotDist × 2` → Feld bevorzugt  
   - sonst → Hotspot-Fallback

## Ausgeschlossene Hotspot-Typen

`MISC` (inkl. Trainsystem-Ladestellen) und `BEE` — nie als Ankerpunkt.  
Erlaubt: `SELLING_STATION`, `PRODUCTION_POINT`, `SHOP`, `FUEL`, Tiertypen.

## Technisches

- Funktion: `nearestHotspot(vehicleId, vx, vz, speed, hotspots, fields)`
- Rückgabe: `{ text: "..." }` (vorformatierter String, kein dist/dir/name mehr)
- Caching: pro Fahrzeug-ID, nur Invalidierung wenn `speed > 0.5`
- Polygon-Daten aus `fields.json` → `field.polygon.x[]` / `field.polygon.z[]`
- Feldmittelpunkt: `field.cx`, `field.cz`

## Datenquellen

- `appData.fields.fields` — Felder mit cx/cz/polygon
- `appData.hotspots.hotspots` — Placeables, typisiert aus `exportHotspots()`
