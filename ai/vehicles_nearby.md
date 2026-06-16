# FarmMonitor — Fahrzeug-Positionsanzeige (Nearby-System)

Zeigt im Fleet-View (Footer) und Detail-View wo sich ein Fahrzeug befindet,
bevorzugt immer Felder als Ankerpunkte gegenüber anderen Hotspots.

---

## Anzeigeformat

| Situation | Beispieltext |
|---|---|
| Auf Feld, nahe Mitte (< 30 m vom Feldmittelpunkt) | `Mitte Feld 7` |
| Auf Feld, nordseitiger Teil | `N auf Feld 7` |
| Außerhalb, Feld bevorzugt | `120 m NO v Feld 7` |
| Außerhalb, Hotspot deutlich näher | `80 m S · Getreidehof` |

---

## Entscheidungslogik (`nearestHotspot()` in `dashboard.html`)

```
1. Fahrzeug auf einem Feld? (Point-in-Polygon)
   → JA:  dist(Fzg, Feldmitte) < 30 m  → "Mitte Feld X"
          sonst                          → "[dir] auf Feld X"
          dir = Himmelsrichtung vom Feldmittelpunkt zum Fahrzeug

2. NEIN:
   a. Nächstes Feld (über Feldmittelpunkt, alle eigenen Felder)
   b. Nächster Hotspot (aus hotspots.json, MISC+BEE ausgeschlossen)

   if nearFieldDist < nearHotspotDist × 2:
     → "[dist] m [dir] v Feld X"     (Feld bevorzugt)
   else:
     → "[dist] m [dir] · [Name]"     (Hotspot-Fallback)
```

**Schwellenwert 2×**: Feld bis doppelte Hotspot-Distanz noch bevorzugt.
Beispiel: Hotspot 100 m, Feld 190 m → Feld; Feld 210 m → Hotspot.

---

## Datenquellen

### Felder (`appData.fields.fields`)
Aus `fields.json`. Benötigte Felder pro Feld:

| Feld | Typ | Verwendung |
|---|---|---|
| `id` | string | Feldnummer für Anzeige |
| `cx`, `cz` | float | Feldmittelpunkt für Distanz + Richtungsberechnung |
| `polygon.x[]`, `polygon.z[]` | float[] | Point-in-Polygon-Test |

Felder ohne `cx`/`cz` werden übersprungen.

### Hotspots (`appData.hotspots.hotspots`)
Aus `hotspots.json`. Exportiert von `FarmMonitor:exportHotspots()` aus Placeables.

Verwendete Typen (als Fallback-Ankerpunkte):

| Typ | Bedeutung |
|---|---|
| `SELLING_STATION` | Verkaufsstelle, Getreidehof |
| `PRODUCTION_POINT` | Produktionsanlage |
| `SHOP` | Händler |
| `FUEL` | Tankstelle |
| Tiernamen (`PIG`, `COW`, …) | Tiergehege |

**Explizit ausgeschlossen:**

| Typ | Grund |
|---|---|
| `MISC` | Generischer Typ — enthält u.a. Trainsystem-Ladestellen |
| `BEE` | Bienenstöcke — zu klein/irrelevant als Orientierungspunkt |

---

## Richtungsberechnung

Einheitliche Formel in allen drei Situationen:

```js
function _cardinal(dx, dz) {
  const deg = ((Math.atan2(dx, -dz) * 180 / Math.PI) + 360) % 360;
  return ['N','NO','O','SO','S','SW','W','NW'][Math.round(deg / 45) % 8];
}
```

- **Auf Feld**: `dx = vx - f.cx`, `dz = vz - f.cz` (Fahrzeug relativ zum Feldmittelpunkt)
- **v Feld**: `dx = f.cx - vx`, `dz = f.cz - vz` (Feldmittelpunkt relativ zum Fahrzeug)
- **Hotspot**: `dx = h.x - vx`, `dz = h.z - vz` (Hotspot relativ zum Fahrzeug)

---

## Point-in-Polygon

Ray-Casting-Algorithmus (Standard):

```js
function _pointInPoly(px, pz, xs, zs) {
  let inside = false;
  for (let i = 0, j = xs.length - 1; i < xs.length; j = i++) {
    const xi = xs[i], zi = zs[i], xj = xs[j], zj = zs[j];
    if (((zi > pz) !== (zj > pz)) && (px < (xj - xi) * (pz - zi) / (zj - zi) + xi))
      inside = !inside;
  }
  return inside;
}
```

Eingabe: Weltkoordinaten X/Z, Polygon-Arrays aus `field.polygon.x` / `field.polygon.z`.

---

## Caching

Ergebnis wird pro Fahrzeug-ID gecacht (`_nearestHotspotCache: Map`).
Cache wird nur invalidiert wenn das Fahrzeug fährt (`speed > 0.5 km/h`).
Geparkte Fahrzeuge behalten ihr letztes Ergebnis ohne Neuberechnung.

---

## Rückgabeformat

```js
// Früher: { name, dist, dir }  ← nicht mehr verwendet
// Jetzt:  { text }             ← vorformatierter String

{ text: "N auf Feld 7" }
{ text: "120 m NO v Feld 7" }
{ text: "80 m S · Getreidehof" }
```

Rendering in Fleet-Card (`footerParts`) und Detail-View (`vd-loc-tag`):
```js
footerParts.push(near.text);          // Fleet-Card
`<span class="vd-loc-tag">...${near.text}</span>`  // Detail-View
```

---

## Aufruf

```js
nearestHotspot(vehicleId, vx, vz, speed,
  appData?.hotspots?.hotspots,
  appData?.fields?.fields)
```

Beide Datenquellen müssen übergeben werden. Felder können `null`/`undefined` sein —
dann nur Hotspot-Fallback.
