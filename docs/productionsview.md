# Produktionen-View — Dokumentation

## Übersicht

Der Produktionen-View zeigt alle Produktionsanlagen der aktuellen Farm. Pro Anlage werden Eingänge, Ausgänge und Produktionsketten angezeigt. Ausgänge zeigen zusätzlich den konfigurierten Ausgangsmodus. Inaktive Einträge werden standardmäßig ausgeblendet und können pro Karte aufgeklappt werden.

---

## Datenquelle

Die Daten kommen aus `productions.json`, das vom Lua-Mod alle 10 Sekunden geschrieben wird. Jeder Eintrag enthält:

| Feld | Bedeutung |
|---|---|
| `uniqueId` | Eindeutiger Bezeichner des Placeables (identisch in allen JSON-Dateien) |
| `name` | Anzeigename der Produktionsanlage |
| `inputs` | Liste der Eingangswaren (Rohstoffe) |
| `outputs` | Liste der Ausgangswaren (Produkte) |
| `productions` | Liste der Produktionsketten mit Status und Rezept |

### Input-Objekt

| Feld | Bedeutung |
|---|---|
| `fillType` | Interner Bezeichner (z.B. `WHEAT`) |
| `title` | Anzeigename |
| `level` | Aktueller Füllstand in Litern |
| `capacity` | Kapazität in Litern |
| `needed` | `true` wenn mind. eine aktive/gestoppte Kette diesen Input benötigt |

### Output-Objekt

| Feld | Bedeutung |
|---|---|
| `fillType` | Interner Bezeichner |
| `title` | Anzeigename |
| `level` | Aktueller Füllstand in Litern |
| `capacity` | Kapazität in Litern |
| `outputMode` | Konfigurierter Ausgangsmodus (siehe unten) |
| `needed` | `true` wenn mind. eine aktive/gestoppte Kette diesen Output produziert |

### Produktionsketten-Objekt

| Feld | Bedeutung |
|---|---|
| `id` | Interner Ketten-Bezeichner |
| `name` | Anzeigename der Kette |
| `status` | `running` / `stopped` / `inactive` |
| `cyclesPerMonth` | Zyklen pro Spielmonat |
| `inputs` | Rezept-Inputs: `[{fillType, title, amountPerCycle}]` — via `prod.inputs[n].type/.amount` |
| `outputs` | Rezept-Outputs: `[{fillType, title, amountPerCycle}]` — via `prod.outputs[n].type/.amount` |

---

## Quicknav

Die linke Seitenleiste listet alle sichtbaren Anlagen alphabetisch. Klick scrollt zur Karte und hebt sie kurz per Flash-Highlight hervor.

### Dot-Farbe

| Farbe | Bedingung |
|---|---|
| **Grün** (climbing) | Alle aktiven Ketten laufen |
| **Gelb** (great-demand) | Mix aus laufenden und inaktiven Ketten |
| **Rot** (sell-now) | Mindestens eine Kette gestoppt |
| **Grau** (no-station) | Keine Ketten vorhanden oder alle inaktiv |

---

## Produktionskarte

### Eingänge

Nur Inputs mit `level > 0` oder `needed === true` werden angezeigt. Barfarbe:
- Normal: grün → gelb → rot je nach Füllstand
- `level === 0` + `needed`: gedämpfter roter Balken (`.bar.empty-needed`) als Warnung

Der Warenname ist ein klickbarer Link zum Waren-View, sofern der `fillType` dort gelistet ist.

### Ausgänge

Nur Outputs mit `level > 0` oder `needed === true` werden angezeigt. Balken nutzen invertierte Farblogik (voller Ausgang = rot). Der Warenname ist ein klickbarer Link zum Waren-View. Am Zeilenende erscheint ein farbiges Icon für den Ausgangsmodus.

### Ketten

Nur aktive (`running`) und gestoppte (`stopped`) Ketten werden angezeigt. Jede Ketten-Zeile ist klickbar und klappt eine Rezept-Zeile auf:

```
▼ Mehl                          48×/Mo  [Läuft]
    Weizen 1.000L + Wasser 500L  →  Mehl 800L + Schweinefutter 50L
```

| Status | Badge |
|---|---|
| `running` | Grünes Badge „Läuft" |
| `stopped` | Rotes Badge „Gestoppt" |

Zyklusrate (`cyclesPerMonth`) erscheint als gedämmter Text vor dem Badge.

### Inaktiv-Sektion

Am Ende jeder Karte erscheint `▶ Inaktiv (N)` wenn es ausgeblendete Einträge gibt. Klick klappt auf:
- Inputs mit `level === 0` und `needed === false`
- Outputs mit `level === 0` und `needed === false`
- Ketten mit `status === 'inactive'` (ebenfalls mit aufklappbarer Rezept-Zeile)

Alle inaktiven Einträge werden in gedämpftem Grau dargestellt.

---

## Ausgangsmodus-Icons

Jeder Ausgang zeigt am Zeilenende ein Tabler-Icon. Hover zeigt einen Tooltip mit dem Modus-Namen.

| Modus | Icon | Farbe | Bedeutung |
|---|---|---|---|
| `keep` | `ti-arrow-bar-up` | Rot | Auslagern — Ware wird als Palette gespawnt |
| `sell` | `ti-currency-euro` | Orange | Direktverkauf |
| `deliver` | `ti-arrows-move` | Blau | Automatisch liefern |
| `store` | `ti-arrow-bar-to-down` | Grün | Einlagern ins Silo (nur mit Mod FS25_ProductionStorageControl) |

Der `store`-Modus wird nur exportiert wenn `g_modIsLoaded["FS25_ProductionStorageControl"]` aktiv ist.

Die globalen Konstanten `OUTPUT_MODE_ICON`, `OUTPUT_MODE_LABEL`, `OUTPUT_MODE_COLOR` und `OUTPUT_MODE_ALL` sind im Dashboard geteilt und werden auch vom Waren-View und dem Ausgangsmodus-Modal verwendet.

### outputModeBadge-Funktion

```js
outputModeBadge(mode, ppUniqueId, fillType)
```

- Mit `ppUniqueId` + `fillType`: rendert einen klickbaren `<button>` mit Kreis-Border, öffnet den Modus-Popover
- Ohne diese Parameter: rendert einen nicht-klickbaren `<span>` ohne Kreis — wird im Waren-View für Lagerort-Zeilen verwendet

### Pending-Animation

Nach einer Modus-Änderung erhält das Badge-Element die Klasse `pending`:

- `button.output-mode-badge.pending`: Hintergrund pulsiert (`mode-pending`-Keyframe)
- `span.output-mode-badge.pending`: Icon blendet zwischen Vollhelligkeit und `opacity: 0.2` (`mode-pending-icon`-Keyframe)

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

Input- und Output-Namen sind klickbare Links zum Waren-View, sofern der `fillType` in `goods.json` vorhanden ist.

**Funktion:** `goToGood(fillType)`

### Waren → Produktionen

Im aufgeklappten Bereich einer Warenkarte erscheint eine „Verarbeitung"-Sektion wenn die Ware als Input in einer aktiven Produktionsanlage verwendet wird. Klick navigiert zurück in den Produktionen-View.

**Funktion:** `goToProduction(name)`

### Silos / Ställe → Produktionen

`goToStorageLocation(uniqueId)` durchsucht Produktionen nach der `uniqueId` und navigiert zum ersten Treffer.

---

## Hilfsfunktionen

| Funktion | Beschreibung |
|---|---|
| `renderProductions(data)` | Hauptfunktion — rendert Quicknav und Karten-Grid |
| `chainRowHtml(c, key)` | Rendert eine Ketten-Zeile mit Toggle-Pfeil und Status-Badge |
| `chainRecipeHtml(c)` | Rendert die aufgeklappte Rezept-Zeile (Inputs → Outputs) |
| `outputModeBadge(mode)` | Gibt HTML-Span mit Tabler-Icon für den Ausgangsmodus zurück |
| `toggleProdChain(key)` | Klappt die Rezept-Zeile einer Kette auf/zu |
| `toggleProdInactive(uniqueId)` | Klappt die Inaktiv-Sektion einer Karte auf/zu |
| `goToProduction(name)` | Wechselt zum Produktionen-View und scrollt zur Anlage mit diesem Namen |

## Zustandsvariablen

| Variable | Typ | Bedeutung |
|---|---|---|
| `prodChainExpanded` | Set | Keys (`uniqueId:chainId`) aufgeklappter Ketten-Rezepte |
| `prodInactiveExpanded` | Set | `uniqueId`-Werte von Karten mit aufgeklappter Inaktiv-Sektion |
