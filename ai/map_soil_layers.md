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

## Vorteile gegenüber dem vorherigen Ansatz (Pixel-PNG)

| | Vorher (Pixel) | Jetzt (Marching Squares) |
|---|---|---|
| Rendering | Web Worker + Canvas + DataURL | Direktes SVG |
| Skalierung | Pixelig beim Zoomen | Vektoren, perfekt scharf |
| CPU | Worker-Thread + PNG-Encoding | Einmaliger JS-Durchlauf |
| Transfer | ~60–80 KB JSON | Gleich (JSON unverändert) |
| Blur | Nötig für weiche Kanten, sah ungenau aus | Entfällt |
