# AutoDrive Marker-Suche — Konzept

## Ziel

Das bestehende statische Dropdown für Marker 1 und Marker 2 im AD-Detail-Panel wird durch ein **durchsuchbares Kombifeld** ersetzt. Es unterstützt Freitext-Suche auf Marker-Namen und Gruppen-Namen, zeigt gemischte Ergebnisse (Gruppen + Einzelmarker) und ist vollständig per Tastatur bedienbar.

---

## Datenbasis

`autoDriveMarkers.json` liefert alles was gebraucht wird:

```json
{
  "markers": [
    { "id": 1,  "name": "Hof Einfahrt",  "group": "Höfe"    },
    { "id": 2,  "name": "Hof Ausfahrt",  "group": "Höfe"    },
    { "id": 22, "name": "Wald 107",      "group": "Wälder"  },
    { "id": 23, "name": "Wald 203",      "group": "Wälder"  },
    { "id": 30, "name": "Getreide Silo", "group": null       }
  ],
  "groups": ["Höfe", "Wälder"]
}
```

- `id` = `markerIndex` → wird direkt an `autodrive.configure marker1=id` übergeben
- `group` = Ordnername (`null` = kein Ordner)

---

## Such-Logik

Die Suche läuft **client-seitig in JS** gegen das gecachte `autoDriveMarkers`-Objekt.

### Suchanfrage normalisieren
```
query = eingabe.trim().toLowerCase()
```

### Treffer-Kategorien (in dieser Reihenfolge)

**1. Gruppen-Treffer** — Ordnername enthält den Suchbegriff:
```
"höfe".includes(query)  →  Gruppe "Höfe" als Eintrag + alle Marker der Gruppe darunter
```

**2. Direkte Marker-Treffer** — Marker-Name enthält den Suchbegriff, Gruppe hat NICHT schon gematcht:
```
"hof einfahrt".includes(query)  →  einzelner Marker-Eintrag
```

### Beispiel: Eingabe „hof"

```
📁 Höfe                   ← Gruppe matcht → als Gruppen-Eintrag
   📍 Hof Einfahrt        ← Marker der Gruppe (eingerückt, nicht separat)
   📍 Hof Ausfahrt

📍 Getreide Silo          ← Name matcht direkt (kein Gruppen-Treffer)
```

### Beispiel: Eingabe „wald"

```
📁 Wälder                 ← Gruppe matcht
   📍 Wald 107
   📍 Wald 203
```

(Keine separaten Marker-Treffer, weil alle schon über die Gruppe erscheinen)

### Beispiel: Eingabe „107"

```
📍 Wald 107               ← nur Marker-Treffer, kein Gruppen-Treffer
```

### Leere Eingabe / Fokus ohne Text

Zeigt alle Gruppen mit ihren Markern — als vollständige strukturierte Liste.

---

## UI-Struktur

### Komponente: `ADMarkerSearch`

```
┌─────────────────────────────────────┐
│ 🔍  Wald___________________   [✕]  │  ← Input-Feld
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ 📁 Wälder                          │  ← Gruppen-Eintrag (navigierbar)
│    📍 Wald 107                     │  ← Marker unter Gruppe (navigierbar)
│    📍 Wald 203                     │
│    📍 Waldhof Nord                 │
├─────────────────────────────────────┤
│ 📍 Waldsee Kreuzung                │  ← direkter Marker-Treffer
└─────────────────────────────────────┘
```

### Visuelles Styling

| Element | Styling |
|---|---|
| Gruppen-Eintrag | `📁` Icon, leicht hellerer Hintergrund, fett |
| Marker unter Gruppe | `📍` Icon, 16px Einrückung, normale Schrift |
| Einzelner Marker-Treffer | `📍` Icon, keine Einrückung |
| Fokus/Hover | `background: rgba(255,255,255,0.12)`, linker Akzentstreifen `2px solid #4dd0e1` |
| Aktuell gesetzter Marker | Checkmark `✓` rechts, Cyan-Text |

---

## Tastatur-Navigation

### Flaches Navigationsmodell

Alle Einträge (Gruppen UND Marker) sind in einer **flachen navigierbaren Liste** organisiert — `↑`/`↓` springt sequenziell durch alle sichtbaren Einträge, unabhängig ob Gruppe oder Marker.

```
Index 0:  📁 Wälder            ← navigierbar
Index 1:     📍 Wald 107       ← navigierbar
Index 2:     📍 Wald 203       ← navigierbar
Index 3:  📍 Waldsee Kreuzung  ← navigierbar
```

### Tasten

| Taste | Aktion |
|---|---|
| `↓` | Nächsten Eintrag fokussieren (am Ende: zurück zum Anfang) |
| `↑` | Vorherigen Eintrag fokussieren (am Anfang: zum Ende springen) |
| `Enter` | Fokussierten Eintrag auswählen |
| `Escape` | Dropdown schließen, Input-Feld leeren, Fokus bleibt auf Input |
| `Tab` | Auswählen + Fokus zum nächsten Feld (Marker 2 oder Start-Button) |
| Tippen | Suche aktualisieren, Fokus zurück auf Index 0 |

### Maus

- Hover → visuell highlighten (wie Tastatur-Fokus)
- Click → auswählen

---

## Auswahl-Verhalten

### Einzelnen Marker auswählen

```
IPC-Command: autodrive.configure uniqueId=... marker1=22
```

Input-Feld zeigt: `Wald 107`
Dropdown schließt sich.

### Gruppe auswählen

Wenn eine **Gruppe** gewählt wird, setzt das Dashboard:
1. `marker1` = ersten Marker der Gruppe (niedrigste `id`)
2. `autodrive.setting setting=rotateTargets value=2` (ONLYPICKUP — oder je nach Kontext)

Input-Feld zeigt: `📁 Wälder (4 Ziele)`
Dropdown schließt sich.

> **Anmerkung:** Der genaue `rotateTargets`-Wert hängt davon ab ob es Marker 1 (Ladeort) oder Marker 2 (Entladeort) ist. Das kann im Panel konfigurierbar sein oder auf einen sinnvollen Default gesetzt werden.

---

## Komponenten-Zustand (JS)

```js
const markerSearchState = {
    query: "",               // aktueller Suchtext
    results: [],             // gefilterte Einträge (flache Liste, gemischt Gruppen+Marker)
    focusIndex: -1,          // -1 = nichts fokussiert, 0+ = Index in results
    isOpen: false,           // Dropdown sichtbar?
    selectedId: null,        // aktuell gesetzter markerIndex
    selectedName: "",        // Anzeigename des gesetzten Markers
    forMarker: 1,            // 1 = Marker 1, 2 = Marker 2
}
```

### Ergebnis-Einträge

```js
// Gruppen-Eintrag:
{ type: "group",  name: "Wälder",   markers: [{id, name}, ...] }

// Marker-Eintrag (direkt oder unter Gruppe):
{ type: "marker", name: "Wald 107", id: 22, group: "Wälder", indented: true }
{ type: "marker", name: "Waldsee",  id: 30, group: null,     indented: false }
```

---

## Integration ins AD-Panel

Das Such-Feld ersetzt die bisherigen `<select>`-Elemente für Marker 1 und Marker 2 im Fahrzeug-Detailpanel.

### Vorher (aktuell)

```html
<select id="ad-marker1">
  <option value="22">Wald 107</option>
  ...
</select>
```

### Nachher

```html
<div class="ad-marker-search" data-marker="1">
  <input type="text" placeholder="Ziel suchen…" autocomplete="off"/>
  <button class="clear-btn">✕</button>
  <div class="ad-marker-dropdown" hidden>
    <!-- dynamisch befüllt -->
  </div>
</div>
```

---

## Technische Umsetzung (dashboard.html)

Da das Dashboard eine Single-File-SPA ist, wird die Komponente als pure JS-Funktion implementiert — kein Framework, kein Build-Schritt.

### Kern-Funktionen

```js
function _adMarkerSearch_filter(query, markers, groups) { ... }
// → gibt flache Ergebnis-Liste zurück

function _adMarkerSearch_render(containerId, results, focusIndex) { ... }
// → rendert Dropdown-Inhalt per innerHTML

function _adMarkerSearch_select(entry, markerSlot, vehicleId) { ... }
// → sendet IPC-Command, aktualisiert Input-Feld, schließt Dropdown

function _adMarkerSearch_onKey(e, state) { ... }
// → behandelt ↑ ↓ Enter Escape Tab
```

### Lifecycle

1. Panel öffnet sich → Input mit aktuellem Marker-Namen befüllen, `selectedId` setzen
2. Input fokussiert → Dropdown öffnen, leere Suche = vollständige Liste
3. Tippen → `filter()` aufrufen, `render()`, `focusIndex = -1`
4. `↓` → `focusIndex++`, `render()` mit neuem Fokus
5. `Enter` → `select()` aufrufen
6. Außerhalb klicken → Dropdown schließen (`blur`-Event mit kurzer Verzögerung für Click-Handling)

---

## Offene Fragen / Entscheidungen

| Frage | Optionen |
|---|---|
| Gruppe auswählen → welcher `rotateTargets`-Wert? | Default ONLYPICKUP für Marker 1, ONLYDELIVER für Marker 2 — oder konfigurierbar lassen |
| Leere Suche → Liste sofort anzeigen oder erst ab 1 Zeichen? | Sofort anzeigen (bessere UX bei Touch) |
| Max. Ergebnisse im Dropdown | Keine harte Grenze, aber virtuelles Scrollen wenn >50 Einträge |
| Marker ohne Gruppe | Werden am Ende der Liste unter eigenem Abschnitt „Ohne Gruppe" gezeigt |
