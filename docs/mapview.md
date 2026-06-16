# Karten-View

Der Karten-View zeigt deine Farm in Echtzeit auf der Spielkarte — mit Live-Fahrzeugpositionen, Feldpolygonen und wichtigen Punkten auf der Karte.

---

## Übersicht

Klicke oben in der Navigation auf **Karte**, um den View zu öffnen. Die Karte zoomt automatisch auf den spielbaren Bereich und zeigt sofort alle aktiven Fahrzeuge, Felder und Hotspots.

---

## Navigation

| Aktion | Beschreibung |
|---|---|
| **Scrollen** (Mausrad) | Hinein- oder herauszoomen, zentriert auf den Mauszeiger |
| **Ziehen** (linke Maustaste) | Karte verschieben |
| **`+`** (Knopf unten rechts) | Hineinzoomen |
| **`−`** (Knopf unten rechts) | Herauszoomen |
| **⌖** (Knopf unten rechts) | Zurück zur Gesamtansicht des spielbaren Bereichs |

---

## Fahrzeuge

Fahrzeuge werden alle **2 Sekunden** aktualisiert und bewegen sich auf der Karte mit einer sanften Animation.

### Farben nach Fahrzeugtyp

| Farbe | Typ |
|---|---|
| Grün | Traktor |
| Orange | Mähdrescher |
| Blau | Spieler (zu Fuß) |
| Braun | LKW |
| Grau | Anhänger |
| Dunkelgrau | Werkzeug / Anbaugerät |

### Richtungspfeil

Traktoren, Mähdrescher, LKW und Spieler zeigen einen kleinen Pfeil in Fahrtrichtung. Anhänger und Werkzeuge haben keinen Pfeil.

### Tooltip

Fahre mit der Maus über ein Fahrzeug-Icon, um Name und (falls vorhanden) Füllstand in Prozent zu sehen.

---

## Hotspots

Farbige Punkte markieren wichtige Orte auf der Karte:

| Farbe | Typ |
|---|---|
| Grün | Verkaufsstation |
| Blau | Produktionspunkt |
| Braun | Kuhstall |
| Orange | Schweinestall |
| Hellgrau | Schafstall |
| Gelb | Hühnerstall |
| Dunkelbraun | Pferdestall |
| Grau-Blau | Gänsestall |
| Lila | Kaninchenstall |
| Gelb-Orange | Bienenstall |

Fahre mit der Maus über einen Hotspot, um Namen und Typ zu sehen.

---

## Felder

Eigene Felder werden als farbige Fläche auf der Karte eingezeichnet:

| Farbe | Bedeutung |
|---|---|
| **Amber / Gelb** | Erntereif |
| **Rot** | Vertrocknet (Erntezeitfenster verpasst) |
| **Grün** | Wächst noch |
| **Grau** | Leer / abgeerntet |

---

## Hinweise

- Die Karte wird beim Wechsel in einen anderen View pausiert und beim Zurückwechseln automatisch wieder gestartet — das spart Ressourcen.
- Das Kartenbild (Hintergrund) wird aus der `overview.dds` deiner installierten Karte geladen. Es steht bereit, sobald du das erste Mal den Karten-View öffnest.
- Fahrzeuge anderer Farmen (z. B. im Multiplayer) werden nicht angezeigt — nur Fahrzeuge der eigenen Farm.
