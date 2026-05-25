# FarmMonitor — Fahrzeug-Tank-Logik

Dokumentiert die Klassifizierung, den Export und die Dashboard-Anzeige aller Fahrzeug-Tanks.

---

## Klassifizierung (Lua, `collectVehicles()`)

Jede `fillUnit` auf `vehicle.spec_fillUnit.fillUnits` wird in eine von drei Gruppen eingestuft:

| Gruppe | Kriterium | Verhalten |
|---|---|---|
| **Kraftstoff** | `ft.name` ∈ `{DIESEL, ELECTRICCHARGE, METHANE}` | Eigener `fuelPct`/`fuelLiter`-Export, nicht im `tanks`-Array |
| **Hilfsstoff** | `ft.name` ∈ `auxFillTypeNames` (s.u.) | Im `tanks`-Array, aber nie als `main` markiert |
| **Haupttank** | Alles andere mit `cap > 0` | Im `tanks`-Array; größter davon → `main: true` |

### `auxFillTypeNames` (nie Haupttank)

```lua
local auxFillTypeNames = {
    DEF=true, ADBLUE=true,
    COMPRESSEDAIR=true, AIR=true,
    OIL=true, HYDRAULIC_OIL=true,
}
```

**Wasser (`WATER`) ist bewusst nicht enthalten** — Tankwagen transportieren Wasser als Primärladung.

### Haupttank-Erkennung

Der Tank mit der **größten Kapazität** unter allen Nicht-Kraftstoff-, Nicht-Hilfsstoff-Tanks
bekommt `main: true`. Bei Gleichstand gewinnt der erste gefundene (Iterationsreihenfolge).

Typische Haupttanks:
- Getreidewagen → Getreidetank (WHEAT, BARLEY, …)
- Mähdrescher → Kornkorb
- Sprühgerät → Spritztank (FERTILIZER, HERBICIDE, …)
- Güllewagen → Gülletan (LIQUIDMANURE)

---

## JSON-Export (`vehicles.json`, `tanks`-Array)

```json
"tanks": [
  { "name": "WHEAT", "pct": 0, "liter": 0, "cap": 24000, "main": true },
  { "name": "DEF",   "pct": 85, "liter": 34, "cap": 40 }
]
```

| Feld | Typ | Bedeutung |
|---|---|---|
| `name` | string | Fülltyp-Name (leer wenn `UNKNOWN`) |
| `pct` | int | Füllstand in % |
| `liter` | int | Füllstand in Litern |
| `cap` | int | Kapazität in Litern |
| `main` | bool | Nur gesetzt wenn `true` — Haupttank |

- Tanks mit `cap >= 1e9` (unbegrenzt) werden übersprungen
- Tanks mit `cap == 0` werden übersprungen
- `main` fehlt im JSON wenn `false` → JSON kompakter

---

## Dashboard-Anzeige

### Fleet-Card (Balken-Zeile)

```
Haupttank (main: true)  → immer anzeigen, auch bei 0 %
                           0 % → Balken rot (.cargo.low)
Andere Tanks            → nur anzeigen wenn pct > 0
```

DEF und Druckluft werden zusätzlich durch die Settings `showDef` / `showAir` gesteuert.
Kraftstoff hat eine eigene Zeile (separat vom `tanks`-Array).

### Detail-View

Identische Logik — nicht-Haupttanks bei 0 % ausgeblendet, Haupttank immer sichtbar.
DEF und Druckluft landen in der `betriebRows`-Sektion (kleine Balken, 2-spaltig).
Alle anderen Tanks in `tankRows` (große Balken).

### CSS-Klassen

```css
/* Fleet-Card */
.fleet-bar-fill.cargo     { background: #5c8fd6; }   /* blau — gefüllt */
.fleet-bar-fill.cargo.low { background: #ef5350; }   /* rot  — Haupttank leer */

/* Detail-View */
.vd-tank-fill.cargo     { background: #5c8fd6; }
.vd-tank-fill.cargo.low { background: #ef5350; }
```

---

## Rationale

Ohne Haupttank-Erkennung würden DEF-Tanks (AdBlue), Hydrauliköl und Druckluft-Reservoire
als leere Balken erscheinen, obwohl das für den Farmerbetrieb irrelevant ist. Die Logik
„größter nicht-auxiliärer Tank = Haupt-Ladeluke" trifft in der Praxis zuverlässig:
Getreideanhänger, Mähdrescher, Sprühgeräte und Güllefässer haben alle einen dominanten Tank.
