# Fahrzeug-Positionsanzeige — Dokumentation

## Übersicht

Im Fleet-View (Footer jeder Karte) und im Detail-View wird angezeigt, wo sich ein Fahrzeug gerade befindet. Felder werden dabei bevorzugt als Orientierungspunkte verwendet.

---

## Anzeigeformat

| Situation | Beispieltext |
|---|---|
| Auf Feld, nahe Mitte | `Mitte Feld 7` |
| Auf Feld, nordöstlicher Teil | `NO auf Feld 7` |
| Außerhalb, nächstes Feld bevorzugt | `120 m NO v Feld 7` |
| Außerhalb, anderer Hotspot näher | `80 m S · Getreidehof` |

**„v"** steht für „von" — Richtung vom Fahrzeug zum Feld.  
**Himmelsrichtungen:** N, NO, O, SO, S, SW, W, NW

---

## Entscheidungslogik

### 1. Fahrzeug auf einem Feld?

Das System prüft per **Point-in-Polygon**, ob das Fahrzeug innerhalb eines der eigenen Felder steht.

- Abstand vom Feldmittelpunkt **< 30 m** → `Mitte Feld X`
- Abstand **≥ 30 m** → Himmelsrichtung vom Feldmittelpunkt zum Fahrzeug → `[dir] auf Feld X`

### 2. Außerhalb aller Felder

Das System sucht:
- das **nächste Feld** (Distanz zum Feldmittelpunkt)
- den **nächsten Hotspot** (aus der Hotspot-Datenbank, gefiltert)

**Entscheidungsregel:**

```
nearFieldDist < nearHotspotDist × 2  →  Feld bevorzugt
sonst                                 →  Hotspot-Fallback
```

Beispiel: Hotspot 100 m entfernt, Feld 190 m → Feld wird angezeigt.  
Beispiel: Hotspot 100 m entfernt, Feld 220 m → Hotspot wird angezeigt.

---

## Hotspot-Filter

Nicht alle Hotspots eignen sich als Orientierungspunkte.

| Typ | Verwendet | Grund |
|---|---|---|
| `SELLING_STATION` | ✅ | Getreidehöfe, Verkaufsstellen |
| `PRODUCTION_POINT` | ✅ | Produktionsanlagen |
| `SHOP` | ✅ | Händler |
| `FUEL` | ✅ | Tankstellen |
| Tiertypen (`COW`, `PIG`, …) | ✅ | Tiergehege |
| `MISC` | ❌ | Generisch — enthält u.a. Trainsystem-Ladestellen |
| `BEE` | ❌ | Bienenstöcke — zu klein als Orientierungspunkt |

Das **Trainsystem** erscheint durch diesen Filter automatisch nicht mehr als Ankerpunkt.

---

## Datenquellen

### Felder (`fields.json`)

Pro Feld werden benötigt:
- `id` — Feldnummer für die Anzeige
- `cx`, `cz` — Weltkoordinaten des Feldmittelpunkts
- `polygon.x[]`, `polygon.z[]` — Polygonpunkte für den Point-in-Polygon-Test

Nur eigene Felder (Besitz der Spielerfarm) sind in `fields.json` enthalten.

### Hotspots (`hotspots.json`)

Einmalig pro Session aus den Placeables exportiert. Enthält Name, Typ und Weltposition aller relevanten Gebäude.

---

## Performance

Das Ergebnis wird pro Fahrzeug gecacht. Eine Neuberechnung erfolgt nur, wenn das Fahrzeug fährt (`speed > 0,5 km/h`). Geparkte Fahrzeuge behalten ihren letzten Standort-Text ohne CPU-Aufwand.
