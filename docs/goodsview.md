# Waren-View — Dokumentation

## Übersicht

Der Waren-View zeigt alle Waren der aktuellen Farm aggregiert über alle Lagerquellen. Pro Ware werden Gesamtmenge, aktuelle und maximale Verkaufspreise, Preistrend, bester Verkaufsmonat und Lagerorte angezeigt.

---

## Datenquelle

Die Warendaten kommen aus `goods.json`, das vom Lua-Mod alle 10 Sekunden geschrieben wird. Jeder Eintrag enthält:

| Feld | Bedeutung |
|---|---|
| `fillType` | Interner Bezeichner (z.B. `WHEAT`) |
| `title` | Anzeigename (z.B. `Weizen`) |
| `totalLiters` | Summe über alle Lagerquellen |
| `maxPrice` | Höchstpreis über alle 12 Jahresperioden |
| `maxValue` | `totalLiters × maxPrice` |
| `bestPeriod` | Periode mit höchstem Preis (0–11) |
| `sellingStations` | Verkaufsstationen, sortiert nach aktuellem Wert |
| `storageLocations` | Lagerorte mit Name, uniqueId und Litern (Produktions-Ausgänge enthalten zusätzliche Felder, siehe unten) |
| `hasPSC` | `true` wenn der Mod `FS25_ProductionStorageControl` aktiv ist (Root-Feld, nicht pro Ware) |

Wasser (`WATER`) wird standardmäßig aus der Anzeige herausgefiltert (konfigurierbar über den Toggle in der Toolbar).

---

## KPI-Leiste

Oberhalb des Grids werden fünf Kennzahlen angezeigt:

| Kachel | Inhalt |
|---|---|
| **Waren** | Anzahl verschiedener Waren, Hinweis auf Waren ohne Verkaufsstelle |
| **Gesamtwert aktuell** | Summe aller Waren × bester aktueller Stationspreis |
| **Wertvollste Ware** | Ware mit dem höchsten aktuellen Gesamtwert |
| **Preistrend** | Anzahl steigender / stabiler / fallender Waren |
| **Max-Gesamtwert** | Summe aller Waren × Jahreshöchstpreis |

---

## Filter & Sortierung

Die Toolbar über dem Grid bietet folgende Steuerungsmöglichkeiten:

### Suche
Freitext-Suche über `title` und `fillType`. Filtert live beim Tippen.

### Trendfilter
| Option | Zeigt |
|---|---|
| Alle | Alle Waren |
| Steigend | `CLIMBING` + `GREAT_DEMAND` |
| Fallend | `FALLING` |
| Stabil | `STABLE` |
| Keine Station | Waren ohne Verkaufsstelle |

### Monatsfilter
Filtert auf Waren, deren `bestPeriod` dem gewählten Monat entspricht.

### Sortierung
| Option | Reihenfolge |
|---|---|
| Name | Alphabetisch (de) |
| Wert | Bester aktueller Stationswert absteigend |
| Menge | `totalLiters` absteigend |
| Bester Monat | `bestPeriod` aufsteigend |

### Wasser ausblenden
Toggle — blendet `WATER` aus KPIs und Grid aus. Standard: aktiviert.

---

## Quicknav

Die linke Seitenleiste zeigt alle gefilterten Waren als kompakte Buttons. Klick scrollt direkt zur entsprechenden Karte und hebt sie kurz hervor.

### Dot-Farbe

Der Punkt kombiniert **Preistrend** und **aktuellen Preis relativ zum Jahreshöchstpreis**:

| Farbe | Bedingung |
|---|---|
| **Gelb** (great-demand) | Sondernachfrage aktiv |
| **Rot** (sell-now) | Preis ≥ 95 % des Maximums AND Trend fallend |
| **Grün** (climbing) | Preis ≥ 95 % des Maximums |
| **Orange** (falling) | Trend fallend |
| **Blau** (stable) | Trend stabil |
| **Grau** (no-station) | Keine Verkaufsstelle |

---

## Warenkarte (`renderGoodCard`)

Jede Karte zeigt:

- **Name** und bester Verkaufsmonat
- **Gesamtmenge** in Litern
- **Beste Verkaufsstation** mit aktuellem Preis, Preistrend-Icon und Gesamtwert
- **Preisbalken** — aktueller Preis als Prozent des Jahreshöchstpreises
- **Empfehlungs-Badge** (siehe unten)
- **Aufgeklappter Bereich:** Top-5-Stationen, Verarbeitungsbedarf, Lagerorte

### Empfehlungs-Badge (`goodRecommendation`)

Leitet aus Trend-Klasse und Preisprozent eine Handlungsempfehlung ab:

| Klasse | Preis% | Badge |
|---|---|---|
| no-station | — | Keine Verkaufsstelle (grau) |
| great-demand | — | ⚡ Sondernachfrage! (gelb) |
| falling | ≥ 95 % | 🔥 Jetzt verkaufen! (rot) |
| climbing/stable | ≥ 95 % | ↑ Warten möglich (grün) |
| falling | ≥ 70 % | ↓ Verkaufen prüfen (orange) |
| climbing/stable | ≥ 70 % | → Beobachten (blau) |
| alle | < 70 % | ⏳ Warten (blau) |

---

## Lagerorte — Ausgangsmodus-Anzeige & Bulk-Änderung

### Erweiterte storageLocation-Felder (nur für Produktions-Ausgänge)

Wenn ein Lagerort der Ausgang einer Produktionsanlage ist, enthält der Eintrag zusätzliche Felder:

| Feld | Bedeutung |
|---|---|
| `sourceType` | `"production"` — kennzeichnet den Eintrag als Produktionsausgang |
| `ppUniqueId` | `uniqueId` des Placeables (identisch mit `uniqueId` des Lagerorts) |
| `fillType` | Interner Fülltyp-Name (z.B. `"BUTTER"`) — wird für den IPC-Command benötigt |
| `outputMode` | Aktueller Modus: `"keep"` / `"sell"` / `"deliver"` / `"store"` |

Nicht-Produktions-Lagerorte (Silos, Ställe, Paletten, …) haben diese Felder nicht.

### Modus-Icon in der Lagerort-Zeile

Hat ein Lagerort `sourceType === 'production'`, erscheint am Zeilenende ein kleines, farbiges Tabler-Icon, das den aktuellen Ausgangsmodus anzeigt:

- Kein Kreis, nicht klickbar (`<span>` statt `<button>`)
- Gleiche Icons und Farben wie im Produktionen-View (siehe `OUTPUT_MODE_ICON`, `OUTPUT_MODE_COLOR`)
- Identifizierbar über `data-loc-uid` und `data-loc-ft`-Attribute (für optimistischen Update)

### „Ausgangsmodus wählen"-Button

Unterhalb der Lagerort-Liste erscheint ein Button, wenn mindestens ein Lagerort `sourceType === 'production'` hat.

Klick öffnet das **Ausgangsmodus-Modal** (`openOutputModeModal(fillType, title)`).

### Ausgangsmodus-Modal

Ein zentriertes Modal (eigener Backdrop `#omm-backdrop`, Container `#omm-modal`), unabhängig vom Popover des Produktionen-Views.

**Aufbau:**
- **Produktionen** — Checkbox-Liste aller Produktions-Lagerorte dieser Ware mit aktuellem Modus-Icon
- **Neuer Modus für Auswahl** — 2×2-Grid mit Radio-Buttons (STORE nur wenn `hasPSC === true`)
- **Footer** — Abbrechen / Bestätigen

**Bestätigen-Logik:**
1. Modal schließt sofort
2. Optimistischer Update: Icon jeder bestätigten Zeile wechselt auf neuen Modus + Abdunkel-Animation (`pending`-Klasse, `mode-pending-icon`-Keyframe)
3. Für jede gecheckte Produktion: `POST /api/command { cmd: "production.setOutputMode", uniqueId, fillType, mode }`
4. Befehle werden akkumuliert in `commands.xml` (nicht überschrieben) — der Go-Server nutzt atomares Rename via tmp-Datei
5. ~10s-SSE-Update re-rendert die Karten mit den echten Daten — Abdunkel-Animation stoppt

---

## Lagerorte — Navigation

Jeder Lagerort in der Detailansicht einer Warenkarte ist ein klickbarer Link. Ein Klick navigiert automatisch zur entsprechenden Karte im richtigen View:

| Quelle | Ziel |
|---|---|
| Silo / Silo-Extension | Silos-View |
| Produktionsanlage | Produktionen-View |
| Tierstall | Ställe-View |
| Bunkersilos, Mistlager, Paletten u.a. | kein Link (noch kein View) |

Die Zuordnung läuft über die `uniqueId` des Placeables — sie ist in allen Datendateien identisch. Beim Klick wird der passende View geöffnet, zur Karte gescrollt und diese kurz mit einem Flash-Highlight hervorgehoben.

**Funktion:** `goToStorageLocation(uniqueId)` — durchsucht Silos, Produktionen und Ställe der Reihe nach und navigiert beim ersten Treffer.

---

## Verarbeitungsanzeige (`goodProductionUsages`)

Im aufgeklappten Bereich einer Warenkarte erscheint ein Abschnitt **"Verarbeitung"**, wenn die Ware als Input in einer aktiven Produktionsanlage verwendet wird.

Bedingung für Anzeige:
1. Die Ware taucht als `fillType` in `pp.inputs` einer Produktionsanlage auf
2. Mindestens eine Produktionskette der Anlage hat Status `running` oder `stopped` (nicht `inactive`)

Jede Zeile zeigt Name der Anlage, aktuellen Füllstand des Inputs als Balken und Prozentwert. Klick auf den Namen navigiert zur Produktionsanlage (analog zu Lagerorte-Links).

---

## Zustandsvariablen

| Variable | Typ | Bedeutung |
|---|---|---|
| `goodsSearch` | string | Aktueller Suchtext |
| `goodsTrendFilter` | string | Aktiver Trendfilter (`'all'` / `'climbing'` / `'falling'` / `'stable'` / `'no-station'`) |
| `goodsMonthFilter` | string | Aktiver Monatsfilter (`'all'` oder Periode 0–11 als String) |
| `goodsHideWater` | bool | Wasser ausblenden (Standard: `true`) |
| `goodsSort` | string | Aktive Sortierung (`'name'` / `'value'` / `'liters'` / `'month'`) |
| `goodsExpandedSet` | Set | Set der `fillType`-Werte aktuell aufgeklappter Karten |

---

## Hilfsfunktionen

| Funktion | Beschreibung |
|---|---|
| `goodTrendClass(g)` | Gibt Trend-Klasse des besten Stations-Trends zurück: `great-demand`, `climbing`, `falling`, `stable`, `no-station` |
| `goodVisualClass(tCls, pricePct)` | Kombiniert Trend und Preisniveau zu einer visuellen CSS-Klasse für Kartenstreifen und Quicknav-Dot |
| `goodRecommendation(cls, pricePct)` | Gibt `{ label, badgeCls }` für den Empfehlungs-Badge zurück |
| `goodProductionUsages(fillType)` | Gibt alle aktiven Produktionsanlagen zurück, die diese Ware als Input verwenden |
| `toggleGoodExpanded(fillType, e)` | Klappt Detailbereich einer Karte auf/zu (Toggle in `goodsExpandedSet`) |
| `renderGoodCard(g)` | Rendert eine einzelne Warenkarte als HTML-String |
| `renderGoods(data)` | Hauptfunktion — rendert KPI-Leiste, Grid und Quicknav |
| `scrollToGood(fillType)` | Scrollt zur Karte einer Ware und setzt aktiven Quicknav-Button |
| `goToGood(fillType)` | Wechselt zum Waren-View und scrollt zur Ware (für externe Navigation) |
| `goToStorageLocation(uniqueId)` | Navigiert von Lagerort-Links zum passenden View (Silos / Produktionen / Ställe) |
| `openOutputModeModal(fillType, title)` | Öffnet das Ausgangsmodus-Modal für eine Ware |
| `closeOutputModeModal()` | Schließt das Modal und gibt `body.overflow` frei |
| `confirmOutputModes()` | Liest Auswahl, führt optimistischen Update durch, sendet IPC-Commands |
| `fmtLiters(n)` | Formatiert Liter-Wert als lokalisierte Zahl mit `l`-Suffix |
| `fmtEur(n)` | Formatiert Geldbetrag in `€` mit deutschem Format |
| `fmtPrice(n)` | Formatiert Preis pro Liter auf 4 Nachkommastellen |
| `trendIcon(trend)` | Gibt HTML-Span mit Pfeil/Icon für Preistrend zurück |

---

## Perioden-Namen (`PERIOD_NAMES`)

```
0  → Jan/Feb    4  → Mai/Jun    8  → Sep/Okt
1  → Feb/Mär    5  → Jun/Jul    9  → Okt/Nov
2  → Mär/Apr    6  → Jul/Aug   10  → Nov/Dez
3  → Apr/Mai    7  → Aug/Sep   11  → Dez/Jan
```
