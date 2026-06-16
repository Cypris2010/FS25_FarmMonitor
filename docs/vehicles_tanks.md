# Fahrzeug-Tanks — Dokumentation

## Übersicht

Jedes Fahrzeug kann mehrere Fülleinheiten (`fillUnit`) haben: Kraftstofftank, Hauptladeluke, AdBlue-Tank, Hydrauliköl usw. FarmMonitor klassifiziert diese automatisch und zeigt im Fleet-View und Detail-View nur relevante Tanks an.

---

## Klassifizierung

| Gruppe | Erkennungsmerkmal | Anzeige |
|---|---|---|
| **Kraftstoff** | Fülltyp `DIESEL`, `ELECTRICCHARGE` oder `METHANE` | Eigene Kraftstoffzeile (grüner Balken) |
| **Haupttank** | `showOnHud == true` im Spiel-HUD, kein Kraftstofftyp | Immer sichtbar, leer → roter Balken |
| **Sonstige Tanks** | Alle anderen Tanks mit Kapazität > 0 | Nur wenn Füllstand > 0 % |

Der **Haupttank** wird direkt vom Spiel bestimmt: FS25 markiert genau die Fülleinheit(en) als `showOnHud`, die es selbst im HUD anzeigt — also die primäre Ladeluke. Typische Beispiele:

- Getreidewagen → Getreidetank
- Mähdrescher → Kornkorb
- Sprühgerät → Spritztank
- Güllewagen → Gülletank
- Tankwagen → Wassertank

---

## Anzeigelogik

### Fleet-View (Balkenzeile unter dem Fahrzeugnamen)

| Tank | Sichtbar wenn |
|---|---|
| Kraftstoff | Immer (eigene Zeile, separate Einstellung) |
| **Haupttank** | **Immer** — auch bei 0 % (roter Balken) |
| Andere Tanks | Nur wenn Füllstand > 0 % |

### Detail-View (Tankbereich im Fahrzeugpanel)

Identische Logik. DEF und Druckluft erscheinen in einem schmaleren 2-spaltigen Hilfsbereich, alle anderen Tanks in der Hauptspalte.

---

## Farbcodes

| Zustand | Farbe | CSS-Klasse |
|---|---|---|
| Gefüllt (Cargo) | Blau `#5c8fd6` | `.cargo` |
| Haupttank leer | Rot `#ef5350` | `.cargo.low` |
| Kraftstoff normal | Grün | `.fuel` |
| Kraftstoff niedrig | Orange `#ffa726` | `.fuel.warn` |
| Kraftstoff kritisch | Rot `#ef5350` | `.fuel.low` |

---

## JSON-Felder (`vehicles.json`, pro Tank)

| Feld | Typ | Bedeutung |
|---|---|---|
| `name` | string | Fülltyp-Name (z.B. `WHEAT`, leer wenn `UNKNOWN`) |
| `pct` | int | Füllstand in % (0–100) |
| `liter` | int | Füllstand in Litern |
| `cap` | int | Kapazität in Litern |
| `main` | bool | Nur vorhanden wenn `true` — kennzeichnet den Haupttank |

---

## Rationale

Ohne diese Klassifizierung würden Fahrzeuge mit AdBlue-Tank, Hydrauliköl oder Druckluftreservoir ständig leere Balken anzeigen, die im landwirtschaftlichen Betrieb irrelevant sind. Die Nutzung des `showOnHud`-Flags aus dem Spiel ist präziser als eine Kapazitätsheuristik — das Spiel selbst entscheidet, welcher Tank die primäre Ladeluke ist.
