# Karten-Bodenlayer — Implementierung

## Überblick

Die Bodenlayer (Kalk, Dünger, Pflug, Mulch, Walze, Unkraut, Steine) werden als vektorielle SVG-Flächen über die Karte gelegt. Grundlage ist der **Marching-Squares-Algorithmus**.

## Datenpipeline

```
Lua (FS25) → layer_*.json → Go /api/map/layer/{name} → JS _marchingSquares() → SVG <path>
```

### Lua: Grid-Scan (`FarmMonitor.lua`, `stepSoilExport`)
- Rasterisiert die Density Maps über die gesamte Spielfläche in ein `res×res` Grid (Standard: 128×128)
- Pro Zelle: höchster vorhandener Density-Wert wird auf 0–255 normiert (`math.floor(lv / maxVal * 255)`)
- Weed/Stone: binär 0 oder 255 (irgendein penalisierender Wert vorhanden → 255)
- Läuft inkrementell über `rowsPerTick` Zeilen pro Spieltick (Round-Robin über alle Layer)
- Schreibt `layer_lime.json`, `layer_spray.json`, `layer_plow.json`, `layer_mulch.json`, `layer_roller.json`, `layer_weed.json`, `layer_stone.json`

### JSON-Format
```json
{ "layer": "lime", "res": 128, "data": [0, 255, 85, ...] }
```
`data` ist ein flaches Array mit `res×res` Werten (zeilenweise, von oben-links nach unten-rechts).

### Go: Endpoint (`server.go`)
- `GET /api/map/layer/{name}` — liest `layer_{name}.json` direkt aus dem Datenverzeichnis
- Cache-Control: 55 Sekunden
- Keine Transformation, kein Rendering

## Dashboard: Marching Squares (`dashboard.html`)

### Koordinatensystem
- SVG-Gesamtgröße: `MAP_PX = 1024`
- Spielfläche: Mitte 50% → x/y jeweils 256–768 (= `MAP_PX * 0.25` bis `MAP_PX * 0.75`)
- Zellgröße: `cellSize = MAP_PX * 0.5 / res` (bei res=128 → 4px pro Zelle)
- Grid-Ecke (r, c) → SVG: `x = 256 + c * cellSize`, `y = 256 + r * cellSize`

### Schwellwert-Logik

| Layer | `above` | Bedeutung |
|---|---|---|
| `lime`, `spray`, `plow`, `mulch` | `false` | Hoher Wert = gut → Fläche wo Wert **< 127** (Problem) |
| `weed`, `stone`, `roller` | `true` | Hoher Wert = schlecht → Fläche wo Wert **> 127** (Problem) |

Threshold: **127** (fest). Interpolation zwischen Gitterpunkten ist linear.

### Marching Squares Algorithmus (`_marchingSquares`)

**Lookup-Tabelle** (Bitmask: TL=8, TR=4, BR=2, BL=1):

| Mask | Segment(e) |
|---|---|
| 1 | [L, B] |
| 2 | [B, R] |
| 3 | [L, R] |
| 4 | [T, R] |
| 5 *(Sattel)* | [T, R], [B, L] |
| 6 | [T, B] |
| 7 | [T, L] |
| 8 | [T, L] |
| 9 | [T, B] |
| 10 *(Sattel)* | [T, L], [B, R] |
| 11 | [T, R] |
| 12 | [L, R] |
| 13 | [B, R] |
| 14 | [L, B] |
| 0, 15 | — |

**Kanteninterpolation:** Für jede Kante wird der Übergangsort linear zwischen den beiden Eckwerten berechnet:
```js
t = (threshold - v0) / (v1 - v0)  // geklemmt auf [0, 1]
```

**Randbehandlung:** `val(r, c)` gibt für Koordinaten außerhalb des Grids den "außen"-Wert zurück (0 wenn `above=true`, 255 wenn `above=false`). Die Iteration geht bis `r < res` und `c < res` (eine virtuelle Außenreihe), damit Konturen am Kartenrand korrekt geschlossen werden.

**Loop-Assembly:**
1. Alle Segmente in Adjazenzgraph eintragen (Schlüssel = Kantenbezeichner z.B. `h12_5`)
2. Von jedem unbesuchten Startknoten aus dem Nachfolger folgen (nicht vom Vorgänger)
3. Abbruch wenn Loop geschlossen oder Sackgasse (Randkonturen)
4. Loops mit ≥ 3 Punkten werden übernommen

**SVG-Ausgabe:**
- Pro Layer ein `<path>` Element mit `fill-rule="evenodd"` (Löcher werden korrekt ausgestanzt)
- `d`-Attribut: `M x,y L x,y ... Z` pro Loop, alle Loops aneinandergehängt
- Kein Web Worker, kein Canvas, kein PNG-Encoding

### Farben

```js
weed:   rgba(239, 68, 68,  0.55)  // rot
stone:  rgba(156,163,175,  0.55)  // grau
plow:   rgba(167,139,250,  0.55)  // lila
spray:  rgba( 52,211,153,  0.55)  // grün
lime:   rgba( 29, 78,216,  0.55)  // blau
mulch:  rgba(146, 64, 14,  0.55)  // braun
roller: rgba( 96,165,250,  0.55)  // hellblau
```

### Refresh
- Alle 30 Sekunden werden aktive Layer neu vom Server geholt und neu gerendert
- Beim Aktivieren eines Layers wird er sofort geladen

## Mehrschichtige Darstellung (Stacking)

### Gedanke dahinter

Der erste Ansatz verwendete einen einzelnen Schwellwert (127) pro Layer → binäres Ergebnis: Problem oder kein Problem. Das verschenkt Information bei Layern mit mehreren Stufen.

**Erkenntnis:** Kalk hat 4 Stufen (kein/wenig/mittel/voll), Unkraut hat 10 Stufen (0–9 mit unterschiedlicher Schwere). Diese Abstufung soll sichtbar sein.

**Lösung:** Marching Squares läuft pro Layer mehrfach mit verschiedenen Schwellwerten. Jeder Durchlauf erzeugt einen SVG-Pfad mit fester Farbe aber geringer Deckkraft. Schlechtere Zonen werden von mehr Pfaden überdeckt und wirken dadurch automatisch dunkler — ohne explizite Farbberechnung.

### Stacking-Logik

Beispiel Kalk (3 Bänder, je 0.25 Opacity):

| Zone | Abgedeckt von | Effektive Deckkraft |
|---|---|---|
| Level 3 (voll gekalkt) | 0 Bänder | 0% — unsichtbar |
| Level 2 | Band 1 | ~25% — hellblau |
| Level 1 | Band 1 + 2 | ~44% — mittelblau |
| Level 0 (kein Kalk) | Band 1 + 2 + 3 | ~58% — dunkelblau |

Beispiel Unkraut (3 Bänder):

| Zone | Abgedeckt von | Effektive Deckkraft |
|---|---|---|
| Kein Unkraut | 0 Bänder | 0% |
| Junges Unkraut (Level 1–2) | Band 1 | ~20% |
| Penalisierendes Unkraut (Level 3–5) | Band 1 + 2 | ~40% |
| Starkes Unkraut (Level 6–9) | Band 1 + 2 + 3 | ~58% |

### Schwellwerte im Detail

```javascript
const SOIL_LAYER_BANDS = {
  // lime: Exportwerte 0/85/170/255 (Level 0–3)
  lime: [
    { t: 240, above: false, opacity: 0.25 },  // < 240 → Level 0–2 sichtbar
    { t: 128, above: false, opacity: 0.25 },  // < 128 → Level 0–1 sichtbar
    { t:  64, above: false, opacity: 0.25 },  // <  64 → nur Level 0 sichtbar
  ],
  // spray: Exportwerte 0/127/255 (Level 0–2)
  spray: [
    { t: 200, above: false, opacity: 0.30 },  // Level 0–1
    { t:  64, above: false, opacity: 0.30 },  // Level 0 only
  ],
  plow:   [{ t: 127, above: false, opacity: 0.55 }],  // binär
  mulch:  [{ t: 127, above: false, opacity: 0.55 }],  // binär
  roller: [{ t: 127, above: true,  opacity: 0.55 }],  // binär
  // weed: Exportwerte 0/28/56/85/.../255 (Level 0–9)
  //   Level 1–2 = junges Unkraut, 3–5 = penalisierend, 6–9 = stark
  weed: [
    { t:   0, above: true, opacity: 0.20 },  // > 0   → Level 1–9
    { t:  56, above: true, opacity: 0.25 },  // > 56  → Level 3–9
    { t: 141, above: true, opacity: 0.25 },  // > 141 → Level 6–9
  ],
  // stone: Exportwerte 0/64/127/191/255 (Level 0–4)
  stone: [
    { t:   0, above: true, opacity: 0.20 },  // Level 1–4
    { t: 126, above: true, opacity: 0.25 },  // Level 2–4
    { t: 190, above: true, opacity: 0.25 },  // Level 3–4
  ],
};
```

### Warum Weed und Stone ursprünglich falsch exportiert wurden

Der ursprüngliche Export-Code hatte zwei Pfade:
- **Mit `maxVal`**: `v = lv / maxVal * 255` → abgestufte Werte (für Lime, Spray)
- **Ohne `maxVal`** (else-Pfad): `v = 255` sobald irgendein Wert ≥ minVal gefunden → **binär**

Weed und Stone hatten kein `maxVal` gesetzt → wurden binär exportiert (0 oder 255), obwohl beide mehrere Stufen haben.

**Fix:** `maxVal = 9` für Weed, `maxVal = 4` für Stone. Damit greift der erste Pfad und exportiert echte Abstufungen.

## Vorteile gegenüber dem vorherigen Ansatz (Pixel-PNG)

| | Vorher (Pixel) | Jetzt (Marching Squares) |
|---|---|---|
| Rendering | Web Worker + Canvas + DataURL | Direktes SVG |
| Skalierung | Pixelig beim Zoomen | Vektoren, perfekt scharf |
| CPU | Worker-Thread + PNG-Encoding | Einmaliger JS-Durchlauf |
| Transfer | ~60–80 KB JSON | Gleich (JSON unverändert) |
| Blur | Nötig für weiche Kanten, sah ungenau aus | Entfällt |
| Abstufungen | Keine (alpha-codiert, schwer lesbar) | Stacking ergibt natürlichen Gradienten |
