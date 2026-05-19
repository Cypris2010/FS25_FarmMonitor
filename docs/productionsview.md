# Produktionen-View — Dokumentation

## Übersicht

Der Produktionen-View zeigt alle Produktionsanlagen der aktuellen Farm. Pro Anlage werden Eingänge, Ausgänge und Produktionsketten angezeigt. Ausgänge zeigen zusätzlich den konfigurierten Ausgangsmodus.

---

## Datenquelle

Die Daten kommen aus `productions.json`, das vom Lua-Mod alle 10 Sekunden geschrieben wird. Jeder Eintrag enthält:

| Feld | Bedeutung |
|---|---|
| `uniqueId` | Eindeutiger Bezeichner des Placeables (identisch in allen JSON-Dateien) |
| `name` | Anzeigename der Produktionsanlage |
| `inputs` | Liste der Eingangswaren (Rohstoffe) |
| `outputs` | Liste der Ausgangswaren (Produkte) |
| `productions` | Liste der Produktionsketten mit Status |

### Input-Objekt

| Feld | Bedeutung |
|---|---|
| `fillType` | Interner Bezeichner (z.B. `WHEAT`) |
| `title` | Anzeigename |
| `level` | Aktueller Füllstand in Litern |
| `capacity` | Kapazität in Litern |

### Output-Objekt

| Feld | Bedeutung |
|---|---|
| `fillType` | Interner Bezeichner |
| `title` | Anzeigename |
| `level` | Aktueller Füllstand in Litern |
| `capacity` | Kapazität in Litern |
| `outputMode` | Konfigurierter Ausgangsmodus (siehe unten) |

### Produktionsketten-Objekt

| Feld | Bedeutung |
|---|---|
| `id` | Interner Ketten-Bezeichner |
| `name` | Anzeigename der Kette |
| `status` | `running` / `stopped` / `inactive` |
| `cyclesPerMonth` | Zyklen pro Spielmonat |

---

## Quicknav

Die linke Seitenleiste listet alle sichtbaren Anlagen alphabetisch. Klick scrollt zur Karte und hebt sie kurz per Flash-Highlight hervor.

### Dot-Farbe

Die Farbe des Punkts vor dem Anlagennamen spiegelt den Status der Produktionsketten:

| Farbe | Bedingung |
|---|---|
| **Grün** (climbing) | Alle aktiven Ketten laufen |
| **Gelb** (great-demand) | Mix aus laufenden und inaktiven Ketten |
| **Rot** (sell-now) | Mindestens eine Kette gestoppt |
| **Grau** (no-station) | Keine Ketten vorhanden oder alle inaktiv |

---

## Produktionskarte

Jede Karte zeigt drei Sektionen:

### Eingänge

Alle Eingangswaren als `metricRow` mit Füllstandsbalken. Barfarbe folgt dem Standard-Schema (grün → gelb → rot je nach Füllstand). Der Warenname ist ein klickbarer Link zum Waren-View, sofern die Ware dort gelistet ist.

### Ausgänge

Alle Ausgangswaren als `metricRow` mit Füllstandsbalken. Ausgabe-Balken nutzen eine invertierte Farblogik (voller Ausgang = rot). Der Warenname ist ein klickbarer Link zum Waren-View. Am Zeilenende erscheint ein farbiges Icon für den Ausgangsmodus (siehe unten).

### Ketten

Alle Produktionsketten mit Status-Badge und Zyklusrate:

| Status | Badge |
|---|---|
| `running` | Grünes Badge „Läuft" |
| `inactive` | Graues Badge „Inaktiv" |
| `stopped` | Rotes Badge „Gestoppt" |

Zyklusrate (`cyclesPerMonth`) erscheint als gedämmter Text vor dem Badge.

---

## Ausgangsmodus-Icons

Jeder Ausgang zeigt am Zeilenende ein Tabler-Icon, das den in-game konfigurierten Ausgangsmodus widerspiegelt. Hover zeigt einen Tooltip mit dem Modus-Namen.

| Modus | Icon | Farbe | Bedeutung |
|---|---|---|---|
| `keep` | `ti-arrow-bar-up` (↥) | Rot | Auslagern — Ware wird als Palette gespawnt |
| `sell` | `ti-currency-euro` (€) | Orange | Direktverkauf |
| `deliver` | `ti-arrow-right` (→) | Blau | Automatisch liefern |
| `store` | `ti-arrow-bar-to-down` (⤓) | Grün | Einlagern ins Silo (nur mit Mod FS25_ProductionStorageControl) |

Der `store`-Modus wird nur exportiert wenn `g_modIsLoaded["FS25_ProductionStorageControl"]` aktiv ist.

Icons: [Tabler Icons](https://tabler.io/icons) (MIT-Lizenz, eingebunden via CDN).

---

## Ausblenden / Edit-Mode

Anlagen können ausgeblendet werden — sie erscheinen dann weder im Grid noch im Quicknav.

- Im **Edit-Mode** werden alle Anlagen angezeigt; ausgeblendete mit reduzierter Deckkraft.
- Die Sichtbarkeit wird über die `uniqueId` gesteuert und server-seitig pro Savegame gespeichert.
- Das Auge-Icon auf jeder Karte schaltet die Sichtbarkeit um.

---

## Cross-View Navigation

### Produktionen → Waren

Input- und Output-Namen sind klickbare Links zum Waren-View, sofern der `fillType` in `goods.json` vorhanden ist. Klick wechselt den View und scrollt zur entsprechenden Warenkarte.

**Funktion:** `goToGood(fillType)`

### Waren → Produktionen

Im aufgeklappten Bereich einer Warenkarte erscheint eine „Verarbeitung"-Sektion wenn die Ware als Input in einer aktiven Produktionsanlage verwendet wird. Klick auf den Anlagennamen navigiert zurück in den Produktionen-View.

**Funktion:** `goToProduction(name)`

### Silos / Ställe → Produktionen

`goToStorageLocation(uniqueId)` durchsucht Produktionen nach der `uniqueId` und navigiert zum ersten Treffer.

---

## Hilfsfunktionen

| Funktion | Beschreibung |
|---|---|
| `renderProductions(data)` | Hauptfunktion — rendert Quicknav und Karten-Grid |
| `outputModeBadge(mode)` | Gibt HTML-Span mit Tabler-Icon für den Ausgangsmodus zurück |
| `goToProduction(name)` | Wechselt zum Produktionen-View und scrollt zur Anlage mit diesem Namen |
