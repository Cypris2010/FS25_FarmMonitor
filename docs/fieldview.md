# Felder-View — Dokumentation

## Übersicht

Der Felder-View zeigt alle eigenen Felder der aktuellen Farm als Kacheln. Pro Feld werden Fruchttyp, Wachstumsstufe, projizierte Ernte, Bodenzustand und Bedarfsrechner angezeigt.

---

## Quickmenü

Das Quickmenü (linke Seitenleiste) zeigt eine kompakte Liste aller sichtbaren Felder. Jeder Eintrag besteht aus einem farbigen Punkt und der Feldnummer.

### Punktfarbe

Der Punkt zeigt den **schlechtesten Bodenzustand** des Feldes, basierend auf den konfigurierbaren Warnstufen:

| Farbe | Bedeutung |
|---|---|
| **Grün** | Alle Bodenwerte im grünen Bereich |
| **Gelb** | Mindestens ein Bodenwert im Warnbereich |
| **Rot** | Mindestens ein Bodenwert im kritischen Bereich |
| **Grau** | Feld leer (keine Frucht angebaut) |

Die Priorität ist: Rot > Gelb > Grün > Grau. Sobald ein einzelner Bodenwert den roten Schwellwert erreicht, wird der Punkt rot — unabhängig von allen anderen Werten.

---

## Bodenwerte & Farblogik

Jeder Bodenwert hat zwei konfigurierbare Schwellen. Zwischen den Schwellen wird der Balken gelb, unterhalb der unteren Schwelle rot (bzw. für invertierte Werte oberhalb).

### Normale Werte (höher = besser)

| Wert | Grün ab | Gelb ab | Rot unter |
|---|---|---|---|
| Pflug | ≥ Warn-Schwelle | zwischen Warn u. Krit | < Krit-Schwelle |
| Dünger | ≥ Warn-Schwelle | zwischen Warn u. Krit | < Krit-Schwelle |
| Kalk | ≥ Warn-Schwelle | zwischen Warn u. Krit | < Krit-Schwelle |
| Mulch | ≥ Warn-Schwelle | zwischen Warn u. Krit | < Krit-Schwelle |

### Invertierte Werte (niedriger = besser)

| Wert | Grün unter | Gelb ab | Rot ab |
|---|---|---|---|
| Unkraut | < Warn-Schwelle | ≥ Warn-Schwelle | ≥ Krit-Schwelle |
| Steine | < Warn-Schwelle | ≥ Warn-Schwelle | ≥ Krit-Schwelle |

### Walze

Die Walze hat keine konfigurierbaren Schwellen. Der Balken zeigt den Anteil der bereits gewalzten Fläche (100 − `needsRollingPct`):
- Grün ≥ 90 %, Gelb ≥ 50 %, Rot < 50 %

---

## Einstellungen (Settings → Warnstufen Felder)

Die Schwellwerte werden **global** gespeichert (unabhängig vom Savegame) und gelten für alle Karten und Felder gleichermaßen.

### Normale Werte — je zwei Schwellen

| Feld | Standard Gelb unter (%) | Standard Rot unter (%) |
|---|---|---|
| Pflug | 90 | 50 |
| Dünger | 100 | 50 |
| Kalk | 100 | 50 |
| Mulch | 90 | 50 |

- **Gelb unter (%)** — farbiger Punkt: gelb. Balken wird gelb.
- **Rot unter (%)** — farbiger Punkt: rot. Balken wird rot. Muss kleiner als Gelb-Schwelle sein.

### Invertierte Werte — je zwei Schwellen

| Feld | Standard Gelb ab (%) | Standard Rot ab (%) |
|---|---|---|
| Unkraut | 5 | 10 |
| Steine | 0,5 | 1 |

- **Gelb ab (%)** — ab diesem Prozentwert wird der Balken gelb.
- **Rot ab (%)** — ab diesem Prozentwert wird der Balken rot. Muss größer als Gelb-Schwelle sein.
- Steine unterstützen Dezimalwerte (Schrittweite 0,1).

### Validierung

Beim Speichern wird geprüft:
- Alle Werte müssen Zahlen ≥ 0 sein.
- Normale Werte: Rot-Schwelle muss kleiner als Gelb-Schwelle sein.
- Invertierte Werte: Gelb-Schwelle muss kleiner als Rot-Schwelle sein.
- Bei Fehler wird nicht gespeichert (kein Feedback — Eingabe prüfen).

---

## Bedarfsrechner

Der Bedarfsrechner auf jeder Feldkarte zeigt ausstehende Bodenbehandlungen, sobald ein Wert die **Gelb-Schwelle** unterschreitet (bzw. überschreitet):

| Anzeige | Bedingung |
|---|---|
| Kalk | `limePct < fieldLimeWarn` |
| Dünger | `fertPct < fieldFertWarn` |
| Herbizid | `weedPct >= fieldWeedWarn` |

---

## Filter

Oberhalb der Kacheln stehen vier Filter:

| Filter | Zeigt |
|---|---|
| Alle | Alle sichtbaren Felder |
| Erntereif | Felder mit `harvestReady` oder `needsPreparation` |
| Handlungsbedarf | Felder mit mindestens einem Bodenwert im Warnbereich (Gelb-Schwelle) |
| Leer | Felder ohne Frucht |

Filter berücksichtigen nur sichtbare Felder. Ausgeblendete Felder erscheinen in keinem Filter.

---

## Felder ausblenden (Ansicht bearbeiten)

Einzelne Felder können ausgeblendet werden, um die Ansicht auf relevante Felder zu reduzieren.

### Aktivierung

Der Button **"Ansicht bearbeiten"** (Stift-Icon) befindet sich rechts neben den Filterbuttons. Er ist identisch mit dem gleichnamigen Button in den anderen Views (Silos, Produktionen, Ställe) und aktiviert einen **globalen Edit-Mode** für alle Views gleichzeitig.

Im Edit-Mode:
- Alle Felder werden angezeigt — auch ausgeblendete (mit 38 % Deckkraft)
- Auf jeder Feldkarte erscheint oben rechts ein **Auge-Icon**
- Klick auf das Auge blendet das Feld aus oder wieder ein

### Speicherung

Die Sichtbarkeit wird **pro Savegame** gespeichert (Server-seitig unter der Savegame-ID). Basis ist die interne `farmlandId` des Spiels — nicht der angezeigte Feldname, der nicht eindeutig sein muss.

### Settings → Sichtbarkeit → Felder

Alternativ zum Edit-Mode können Felder auch direkt in den Einstellungen über Toggles ein- und ausgeblendet werden. Jeder Eintrag zeigt Feldnummer, aktuell angebaute Frucht und Fläche in ha.
