# Karten-View — Technische Referenz

Implementiert in v0.4.x. Zeigt die Spielkarte mit Live-Fahrzeugpositionen, Feldpolygonen und Hotspots.

---

## overview.dds Konvention

**Die wichtigste Grundlage der gesamten Koordinatenumrechnung.**

FS25-Karten liefern eine `overview.dds`, die **doppelt so groß** ist wie das spielbare Terrain:

```
overview.dds:      4096 × 4096 px  (typische Standardkarte)
Spielbares Terrain: 2048 × 2048 px
Rand (je Seite):   1024 px links/rechts/oben/unten
```

Die spielbare Fläche liegt **zentriert** im Bild — d.h. bei Pixeln 1024–3072 auf jeder Achse.

**Quelle bestätigt durch:**
- GIANTS Developer Network Forum (thread 10177)
- Maps4FS Dokumentation
- FS25_LiveMap_Companion v2: `const baseSrcW = imgW * 0.50` in `drawOverlay()`
- User-Recherche: `fs25_mapview_overview_rand_quellen.md`

---

## Koordinatenumrechnung (worldToMap)

FS25-Weltkoordinaten liegen im Bereich `[-terrainSize/2 … +terrainSize/2]` auf X und Z.

Die Funktion bildet Weltkoordinaten auf SVG-Pixel-Koordinaten ab:

```js
const MAP_PX = 1024; // SVG-Viewport in Pixeln

function worldToMap(wx, wz, terrainSize) {
  // overview.dds deckt 2× terrainSize ab (Terrain + dekorativer Rand)
  const s = terrainSize * 2;
  return {
    x: (wx / s + 0.5) * MAP_PX,
    y: (wz / s + 0.5) * MAP_PX,
  };
}
```

Beispiel für terrainSize=4096:
- Weltpunkt (0, 0) → SVG (512, 512) — Bildmitte
- Weltpunkt (-2048, -2048) → SVG (256, 256) — linke obere Ecke des spielbaren Bereichs
- Weltpunkt (+2048, +2048) → SVG (768, 768) — rechte untere Ecke des spielbaren Bereichs

Der spielbare Bereich liegt damit immer bei SVG-Pixeln `MAP_PX*0.25` bis `MAP_PX*0.75` (256–768 bei 1024px SVG).

**Kritischer Fehler den es zu vermeiden gilt:** Division durch `terrainSize` statt `terrainSize * 2` — dann erscheinen alle Punkte doppelt so weit vom Zentrum entfernt wie sie sein sollten.

---

## Auto-Zoom auf spielbaren Bereich (centerMap)

Beim Öffnen des Karten-Views wird automatisch auf den spielbaren Bereich gezoomt:

```js
function centerMap() {
  const c = document.getElementById('map-container');
  // Spielbarer Bereich = center 50% des SVG (256–768 von 1024px)
  const PLAY_PX  = MAP_PX * 0.5;   // 512px
  const PLAY_OFF = MAP_PX * 0.25;  // 256px Offset zur linken/oberen Ecke

  mapZoom = Math.min(c.clientWidth, c.clientHeight) / PLAY_PX * 0.92;
  mapPanX = (c.clientWidth  - PLAY_PX * mapZoom) / 2 - PLAY_OFF * mapZoom;
  mapPanY = (c.clientHeight - PLAY_PX * mapZoom) / 2 - PLAY_OFF * mapZoom;
  applyMapTransform();
}
```

`centerMap()` wird **synchron** (nicht via `requestAnimationFrame`) aufgerufen, damit das Container-Layout bereits berechnet ist und `clientWidth/Height` korrekte Werte liefern.

---

## SVG-Overlay Struktur

```
#map-container          position:relative, overflow:hidden
  #map-inner            transform: translate(panX,panY) scale(zoom), origin: top-left
    #map-overview       <img> 1024×1024px, background (overview.dds als PNG)
    #map-svg            <svg> viewBox="0 0 1024 1024", position:absolute, top/left:0
      #layer-fields     <polygon> je Feld
      #layer-hotspots   <g class="hotspot-pin"> je Hotspot
      #layer-vehicles   <g id="vm-{id}" class="vehicle-pos"> je Fahrzeug
```

Zoom/Pan wird **ausschließlich auf `#map-inner`** angewendet — damit skalieren Bild und SVG immer synchron.

---

## Icon Counter-Scaling

**Problem:** Wenn `#map-inner` mit `scale(mapZoom)` skaliert wird, wachsen die Icons mit der Karte mit — bei hohem Zoom werden sie sehr groß.

**Lösung:** Jedes Icon wird intern mit `scale(1/mapZoom)` gegenskaliert, sodass es auf dem Bildschirm konstant groß bleibt.

### Fahrzeug-Icons: Outer/Inner-Split

Um Bewegungs-Transition und Zoom-Scale zu entkoppeln:

```
<g id="vm-{id}" class="vehicle-pos">      ← translate(x,y), transition: transform 2s linear
  <g class="vehicle-rot-scale" data-deg>  ← rotate(deg) scale(1/zoom), KEIN transition
    <circle r=8>
    <polygon> (Richtungspfeil)
    <title>
```

- **Outer** (`vehicle-pos`): nur `translate(x,y)` + CSS `transition: transform 2s linear` → smooth movement
- **Inner** (`vehicle-rot-scale`): `rotate(deg) scale(S)` ohne transition → Zoom-Updates passieren sofort

`data-deg` auf dem inneren Element speichert den aktuellen Rotationswinkel für `applyMapTransform()`.

### Hotspot-Pins

```
<g class="hotspot-pin" data-x data-y>    ← transform: translate(x,y) scale(1/zoom)
  <circle cx=0 cy=0 r=7>
  <title>
```

Hotspot-Kreise liegen bei `cx=0 cy=0`, Positionierung ausschließlich über den äußeren `<g>`-Transform.

### applyMapTransform

```js
function applyMapTransform() {
  document.getElementById('map-inner').style.transform =
    `translate(${mapPanX}px,${mapPanY}px) scale(${mapZoom})`;
  const iconS = (1 / mapZoom).toFixed(4);
  document.querySelectorAll('.vehicle-rot-scale').forEach(el => {
    el.style.transform = `rotate(${el.dataset.deg}deg) scale(${iconS})`;
  });
  document.querySelectorAll('.hotspot-pin').forEach(el => {
    el.style.transform = `translate(${el.dataset.x}px,${el.dataset.y}px) scale(${iconS})`;
  });
}
```

---

## Fahrzeug-Live-Tracking

### Datenfluss

```
FarmMonitor.lua → vehicles.json (alle 2 s) → Go file watcher → VehicleBroker (SSE) → Browser
```

### Server-Seite

- **`/api/vehicles`** — JSON-Snapshot aus `vehicles.json`; wird initial geladen und nach jedem SSE-Signal abgefragt
- **`/api/vehicle-events`** — SSE-Stream; sendet `data: update\n\n` wenn `vehicles.json` sich ändert
- Ein separater `broker` (`VehicleBroker`) überwacht nur `vehicles.json` — unabhängig vom Haupt-SSE-Broker für Silos/Produktionen

### Browser-Seite

```js
function startVehicleTracking() {
  vehicleEventSource = new EventSource('/api/vehicle-events');
  vehicleEventSource.onmessage = async (e) => {
    if (e.data === 'connected') return;
    // Fetch aktuellen Snapshot und render
    const data = await fetch('/api/vehicles').then(r => r.json());
    updateVehicles(data, appData.mapMeta.terrainSize);
  };
}
function stopVehicleTracking() {
  vehicleEventSource?.close();
  vehicleEventSource = null;
}
```

`startVehicleTracking()` / `stopVehicleTracking()` werden in `showView()` an den Map-View gebunden.

---

## Server-Endpoints (Überblick)

| Endpoint | Methode | Beschreibung |
|---|---|---|
| `/api/map/overview` | GET | `overview.dds` konvertiert zu PNG, 5 min gecacht |
| `/api/vehicles` | GET | Aktueller Fahrzeug-Snapshot aus `vehicles.json` |
| `/api/vehicle-events` | GET (SSE) | Signal bei jeder Änderung von `vehicles.json` |

### overview.dds → PNG Konvertierung (server.go)

Der Go-Server liest den Pfad zur `overview.dds` aus `mapMeta.json`, konvertiert die DDS-Datei einmalig zu PNG (via `bc7.go` / DDS-Decoder) und cached das Ergebnis im RAM. Bei Savegame-Wechsel (neuer Pfad in `mapMeta.json`) wird neu geladen.

---

## Lua Datenexport

### vehicles.json

```json
{
  "savegameId": "...",
  "vehicles": [
    { "id": 42, "name": "Fendt 942", "type": "TRACTOR",
      "x": 123.4, "z": -456.7, "rot": 1.23,
      "fillPct": 45 }
  ]
}
```

Export alle 2 s (eigener Timer `vehicleTimer`). Typen: `TRACTOR`, `HARVESTER`, `TRAILER`, `TOOL`, `TRUCK`, `PLAYER`, `VEHICLE`.

### mapMeta.json

```json
{
  "savegameId": "...",
  "terrainSize": 4096,
  "mapName": "LS25 Thüringen 2.0",
  "overviewDdsPath": "/absolute/path/to/overview.dds",
  "savegameDir": "/path/to/savegame"
}
```

Einmalig exportiert wenn sich Savegame ändert.

### hotspots.json

```json
{
  "savegameId": "...",
  "hotspots": [
    { "name": "Bauernhof", "type": "SELLING_STATION", "x": 0.0, "z": 0.0 }
  ]
}
```

Typen: `SELLING_STATION`, `PRODUCTION_POINT`, `COW`, `PIG`, `SHEEP`, `CHICKEN`, `HORSE`, `GOOSE`, `RABBIT`, `BEE`, `MISC`. `MISC` wird im Dashboard gefiltert (zu viele Punkte).

---

## Feldpolygone

Feldpolygone kommen aus `fields.json` (selbe Datei wie der Felder-View). Jedes Feld enthält `polygon.x[]` und `polygon.z[]` — Arrays von Weltkoordinaten, die mit `worldToMap()` in SVG-Koordinaten umgerechnet werden.

Füllfarben im SVG:

| Zustand | Farbe |
|---|---|
| `harvestReady` | amber `rgba(251,191,36,0.45)` |
| `withered` | rot `rgba(239,68,68,0.45)` |
| `growing` | grün `rgba(34,197,94,0.22)` |
| empty/cut | grau `rgba(100,116,139,0.15)` |

---

## Referenz-Mods

| Mod | Relevanz |
|---|---|
| [FS25_LiveMap_Companion v2](https://www.farming-simulator.com/mod.php?mod_id=...) | Bestätigung der 50%-Konvention (`imgW * 0.50`), Fahrzeugtyp-Export-Muster |
| [FS25_VG_Livemap](https://www.modhub.us/farming-simulator-2025-mods/...) | Hotspot-Export-Struktur, Kartenansicht-Architektur |
