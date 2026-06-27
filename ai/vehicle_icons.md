# Fahrzeug-Icons (Karten-View) — Funktionsweise & Workflow

Top-Down-Icons für die Fahrzeug-Pins im Karten-View. Betrifft die Typen
`TRACTOR`, `TRUCK`, `TRAILER`. Alle anderen Typen (`HARVESTER`, `TOOL`,
`VEHICLE`, `PLAYER`) rendern den einfachen Punkt-Marker.

Quell-Refactor: Commit `eb4549c` (`refactor(map): load vehicle icons from
static/icons/*.svg`).

## Wo die Icons liegen

```
Server/static/icons/
  tractor.svg            ← TRACTOR
  truck_tractor.svg      ← TRUCK (Zugmaschine / Fallback)
  truck_rigid.svg        ← TRUCK truckKind="rigid"
  truck_hooklift.svg     ← TRUCK truckKind="hooklift" + "swapBody"
  trailer.svg            ← TRAILER (Deichselanhänger)
  semitrailer.svg        ← TRAILER trailerCoupling="auflieger"
  trailer_swapbody.svg   ← TRAILER trailerKind="wechselbruecke"
  trailer_container.svg  ← TRAILER trailerKind="container"
```

## Wie sie geladen werden

- `loadVehicleIcons()` in `dashboard.html` **fetcht** die Dateien **beim Boot**
  (`fetch('icons/x.svg')`), liest `viewBox` + Seitenverhältnis und nutzt das
  `svg.innerHTML` **verbatim** für die Registries `TRACTOR_ICON`,
  `TRUCK_ICON_TRACTOR`, `TRUCK_ICONS`, `TRAILER_ICONS`.
- Die Dateien sind via **`//go:embed static`** ins Go-Binary eingebettet.
  → **Eine SVG zu tauschen heißt: Datei ersetzen UND Binary neu bauen.**
  Ohne Rebuild bleibt die alte Version im Binary. (Das ist mit „nicht zur
  Laufzeit austauschbar" gemeint — der Browser fetcht zur Laufzeit, aber aus
  dem eingebetteten FS, nicht von der Festplatte.)

## ⚠️ Kritisch: Icons müssen Inline-`fill` nutzen — KEINE `<style>`/`class`

SVG-`<style>`-Regeln sind **dokumentweit global**, nicht aufs einzelne `<svg>`
begrenzt. Rohe Illustrator-Exporte nutzen `<defs><style>.cls-1{fill:#…}</style>`
+ `class="cls-1"`. Werden mehrere solcher Icons in die Seite injiziert, **kollidieren
die `.cls-1/.cls-2/…`-Klassennamen** über alle Icons hinweg (letzte Definition
gewinnt) → Farben brechen.

**Deshalb sind alle Projekt-Icons flachgelegt:** jedes Element trägt sein
`fill="#…"` direkt, es gibt keine `<style>`-Blöcke.

### Illustrator-Export flachlegen

Beim Übernehmen neuer SVGs (Illustrator-Default = klassenbasiert):

1. `<style>`-Block parsen → Map `.cls-N → #hex`
2. Jedes `class="cls-N"` durch `fill="#hex"` ersetzen
3. `<defs><style>…</style></defs>` entfernen

Ergebnis muss erfüllen: `0× <style>`, `0× class="cls`, `0× fill=""`,
`viewBox` unverändert. Die Anzahl der Inline-`fill` sollte der Anzahl der
vorher klassen-gestylten Elemente entsprechen.

(Ad-hoc-Skript: `/tmp/flatten_svg.py` im Bearbeitungs-Workflow vom 2026-06-27 —
parst Style-Block, substituiert Klassen, strippt defs.)

## Code-Anbindung (`dashboard.html`)

Drei Stellen, falls ein **neuer** Icon-Typ dazukommt:

1. **`VEHICLE_ICON_MANIFEST`** — `{ file: 'icons/x.svg', anchor?: {x,y} }`
2. **Registry-Variable** + Zuweisung in `loadVehicleIcons()`
   (`TRACTOR_ICON = loaded.tractor || null;`)
3. **Render-Auswahl** in `updateVehicles()`:
   ```js
   const ic = v.type === 'TRACTOR' ? TRACTOR_ICON
            : v.type === 'TRUCK'   ? (TRUCK_ICONS[v.truckKind] || TRUCK_ICON_TRACTOR)
            : v.type === 'TRAILER' ? trailerIconFor(v)
            : null;
   ```
   `ic == null` → Punkt-Fallback (Kreis + Pfeil).

### `anchor` (Kupplungspunkt)

Optionale Metadaten in viewBox-Koordinaten (nicht in der Datei). Trucks ankern
am Sattelpunkt (`truckTractor: {x:45.5, y:143}`), Sattelauflieger am Königszapfen
(`trailerSemi: {x:45.57, y:62.6}`), damit ein gekoppeltes Gespann fluchtet.
**Ohne `anchor` zentriert das Icon auf dem Pin** — korrekt für Traktoren
(keine durchgehende Kupplungslinie zum Pin).

## Größe

**Alle Icon-Fahrzeuge (TRACTOR/TRUCK/TRAILER) teilen sich EINE gemeinsame
Breite** `ICON_WIDTH_M` (Default 8). Da alle SVGs dieselbe viewBox-Breite
(91.13) haben, kommt das Größenverhältnis untereinander **allein aus dem
Seitenverhältnis der Zeichnung** — längere Fahrzeuge haben eine höhere viewBox.
Ein Traktor ist also nur dann schmaler als ein LKW, wenn er so gezeichnet ist;
**kein Per-Typ-Breitenfaktor.**

```js
W = ICON_WIDTH_M * (512 / terrainSize)   // gleiche Breite für jedes Icon
H = W * ratio                            // ratio = viewBoxH / viewBoxW
```

`MIN_VEHICLE_PX = 8` ist der Mindest-Bildschirmdurchmesser (Floor beim
Rauszoomen). Beim Reinzoomen wachsen die Icons maßstäblich mit der Karte.

`REAL_SIZE_M` gilt nur noch für **Punkt-Marker** (HARVESTER/TOOL/VEHICLE) und
als Fallback-Footprint, falls ein Icon nicht lädt. Der `PLAYER` ist von beidem
ausgenommen (fester 13px-Radius, bildschirm-konstant via `realPx=0`).

## Konvention der SVG-Dateien

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 91.13 189.56">
  <rect fill="#585857" .../>
  <path fill="#f7f6f6" d="…"/>
</svg>
```

- Breite immer `91.13`, Höhe variiert (längere Fahrzeuge = höhere viewBox)
- Icon zeigt nach **Norden** (oben) — rotiert zur Laufzeit mit dem Heading
- Nur Inline-`fill`, keine `id`/`data-name` nötig
