# Logistik-Planer

## 1. Ziel & Abgrenzung

Der Logistik-Planer hilft dem Spieler, auf Knopfdruck einen Transportvorschlag für einen konkreten Produktions-Eingang zu bekommen. Er **generiert keine automatischen Touren**, startet keine Fahrzeuge und trifft keine Entscheidungen — er zeigt einen Vorschlag an, den der Spieler selbst ausführt.

**Auslöser:** Button `[Transport planen]` neben jedem Produktions-Eingang, dessen Füllstand unter einem Schwellwert liegt.

---

## 2. Zwei Transportarten

| | Schüttgut-Transport | Paletten-Transport |
|---|---|---|
| **Quelle** | Silo, Tank, Bunker | Lose Paletten in der Welt |
| **Fahrzeug** | Kipper, Tanker, Auflieger (bulk) | Palettenauflieger, Flachwagen |
| **Erkennung Fahrzeug** | `cargoFillTypes` enthält den Fill-Typ | `hasTensionBelts = true` |
| **Laden** | Automatisch an Entnahmestation | Manuell mit Teleskoplader/Stapler |
| **Positionsdaten** | `goods.json` → Lagerortname | `silos.json` → `loosePallets` mit `posX/posZ` |

Beide Transportarten werden **parallel** im Modal angeboten, wenn jeweils Quellen und Fahrzeuge vorhanden sind.

---

## 3. Datengrundlage

### Was wir bereits haben

| Daten | Datei | Felder |
|---|---|---|
| Produktions-Eingänge | `productions.json` | `inputs[].fillType`, `.fillLevel`, `.capacity` |
| Schüttgut-Quellen | `goods.json` | `fillType`, `totalLiters`, Lagerorte |
| Lose Paletten (mit Position) | `silos.json` → `type:"loosePallets"` | `posX`, `posZ`, `contents[].fillType`, `.count`, `.level` |
| Paletten auf Fahrzeugen | `vehicles.json` → `pallets[]` | `name`, `count`, `totalLiters` |
| Fahrzeugstatus | `vehicles.json` | `id`, `rootId`, `speed`, `adActive`, `cpActive`, `driver`, `tanks[]` |
| Fahrzeugkategorie | `vehicleMeta.json` | `id`, `category`, `brand`, `name` |

### Was neu exportiert werden muss

**In `vehicleMeta.json`** (statisch, einmalig beim Laden):

| Neues Feld | Lua-Quelle | Bedeutung |
|---|---|---|
| `inputJointTypes` | `spec_attachable.inputAttacherJoints[i].jointType` | Welchen Kupplungstyp braucht dieser Anhänger |
| `outputJointTypes` | `spec_attacherJoints.attacherJoints[i].jointType` | Welche Kupplungstypen bietet diese Zugmaschine |
| `cargoFillTypes` | `spec_fillUnit.fillUnits[i].supportedFillTypes` (nur non-fuel, showOnHud) | Welche Bulk-Waren kann der Tank aufnehmen |
| `cargoCapacity` | Summe aller Cargo-Tank-Kapazitäten | Gesamtladevolumen in Litern |
| `hasTensionBelts` | `spec_tensionBelts ~= nil` | Fahrzeug ist ein Palettenauflieger/Flachwagen |

**In `vehicles.json`** (dynamisch, alle 2 s):

| Neues Feld | Lua-Quelle | Bedeutung |
|---|---|---|
| `attachedToId` | `rootId` wenn `rootId ~= tostring(vehicle.rootNode)` | An welche Zugmaschine ist dieser Anhänger gekuppelt (`nil` = entkuppelt) |
| `cargoFillPct` | Summe Cargo-Tanks Level/Capacity | Wie voll ist der Laderaum (0–100) |

> **Hinweis:** `rootId` in `vehicles.json` existiert bereits und entspricht `attachedToId` — kann direkt genutzt werden, muss nur klar im Dashboard ausgewertet werden.

---

## 4. Kupplungstypen

| Konstante | Bedeutung | Typisches Gespann |
|---|---|---|
| `JOINTTYPE_TRAILER` | Standard-Anhängerkupplung | Traktor + Kipper/Tanker |
| `JOINTTYPE_TRAILER_LOW` | Tiefer Anhängerpunkt | Traktor + Tieflader |
| `JOINTTYPE_SEMITRAILER` | Sattelkupplung (5th wheel) | LKW + Sattelauflieger |
| `JOINTTYPE_IMPLEMENT` | Anbaugerät | → ignorieren für Logistik |

Anhänger und Zugmaschine passen zusammen wenn mindestens ein `inputJointType` des Anhängers in den `outputJointTypes` der Zugmaschine vorkommt.

---

## 5. "Frei"-Definition für Fahrzeuge

| Bedingung | Datenfeld |
|---|---|
| Kein Fahrer | `driver == null` |
| Kein AutoDrive aktiv | `adActive == false` |
| Kein Courseplay aktiv | `cpActive == false` |
| Steht still | `speed < 0.5` |

Für **Zugmaschinen** zusätzlich:
- Kein anderes Fahrzeug mit `rootId === zugmaschineId` (kein Anhänger dran)

Für **Anhänger/Auflieger**:
- `rootId === eigene id` → entkuppelt, frei
- `rootId === fremde id` → angekuppelt; Gespann gilt als frei wenn Zugmaschine selbst frei ist

---

## 6. Algorithmus (Frontend, Browser)

Eingabe: `fillTypeName` (z.B. `"WHEAT"`), `productionId`

```
1. QUELLEN FINDEN

   Schüttgut:
   → goods[fillType].sources, sortiert nach totalLiters (absteigend)
   → Beste Quelle: meiste Liter, nicht eine Produktions-Output-Quelle der eigenen Farm

   Paletten:
   → silos[].type == "loosePallets" && contents[].fillType == fillType
   → Sortiert nach Palettenanzahl (absteigend)

2. FAHRZEUGE KLASSIFIZIEREN

   Schüttgut-Anhänger:
   → vehicleMeta[id].cargoFillTypes ∋ fillType
   → vehicleMeta[id].hasTensionBelts == false (kein Palettenfahrzeug)

   Paletten-Anhänger:
   → vehicleMeta[id].hasTensionBelts == true

   Zugmaschinen:
   → vehicleMeta[id].outputJointTypes ist nicht leer
   → vehicleMeta[id].hasTensionBelts == false (kein Anhänger selbst)

3. GESPANNE ERKENNEN

   Für jeden Anhänger mit rootId != eigene ID:
   → Zugmaschine = vehicles[rootId]
   → Wenn Anhänger frei UND Zugmaschine frei → "Gespann sofort einsatzbereit"
   → Wenn Zugmaschine belegt → "Gespann belegt"

   Für freie Einzelanhänger (rootId == eigene ID):
   → Passende freie Zugmaschine suchen (Joint-Type-Match)
   → Wenn gefunden → "Trailer verfügbar, Zugmaschine nötig"
   → Wenn keine Zugmaschine frei → "Eingeschränkt"

4. OPTIONEN ZUSAMMENSTELLEN

   Schüttgut-Optionen (Kategorie A–C):
     A: Gespann sofort einsatzbereit, cargoFillPct < 20%
     B: Freier Trailer + freie passende Zugmaschine
     C: Trailer vorhanden, keine Zugmaschine frei (ausgegraut)

   Paletten-Optionen (Kategorie P):
     P: hasTensionBelts-Fahrzeug frei + lose Paletten der Ware vorhanden
        → immer mit Hinweis "Beladen erfordert Teleskoplader"
        → ausgegraut wenn kein Palettenfahrzeug frei

5. AUSGABE: Optionsliste ans Modal
```

---

## 7. UI-Design

### Einstiegspunkt: Produktionen-View

Neben jedem Input unter Schwellwert (z.B. < 30%):

```
Weizen    ████░░░░░░  18%    [Transport planen]
```

### Modal: Logistik-Vorschlag

```
╔═══════════════════════════════════════════════════════════════╗
║  Transport planen                                             ║
║  Weizen → Mehlmühle  (benötigt ~14.000 l)                    ║
╠═══════════════════════════════════════════════════════════════╣
║  SCHÜTTGUT                                                    ║
║  Quelle: Silo Nord — 22.400 l verfügbar                      ║
║                                                               ║
║  ● Sofort einsatzbereit                                       ║
║  ┌─────────────────────────────────────────────────────────┐  ║
║  │ Fendt 942 + Fliegl 3-Achs    32.000 l  leer  380 m    │  ║
║  │ Anhängerkupplung                                        │  ║
║  ├─────────────────────────────────────────────────────────┤  ║
║  │ Volvo FH + Schwarzmüller     25.000 l  4%   1.200 m   │  ║
║  │ Sattelkupplung                                          │  ║
║  └─────────────────────────────────────────────────────────┘  ║
║                                                               ║
║  ○ Zugmaschine nötig                                          ║
║  ┌─────────────────────────────────────────────────────────┐  ║
║  │ Joskin Volumetra (leer) + Deutz 8280 TTV (840 m)       │  ║
║  └─────────────────────────────────────────────────────────┘  ║
║                                                               ║
║  ░ Krampe Big Body — Zugmaschine belegt (John Deere 8R)      ║
║                                                               ║
╠═══════════════════════════════════════════════════════════════╣
║  PALETTEN                                                     ║
║  Quelle: 6 Paletten bei Lagerhalle Süd                       ║
║  ⚠ Beladen erfordert Teleskoplader                           ║
║                                                               ║
║  ● Verfügbar                                                  ║
║  ┌─────────────────────────────────────────────────────────┐  ║
║  │ Fliegl Flatbed (frei)  Anhängerkupplung  620 m         │  ║
║  │ Zugmaschine: Fendt 516 (frei, 240 m)                   │  ║
║  └─────────────────────────────────────────────────────────┘  ║
║                                                               ║
║  ░ Keine Palettenfahrzeuge verfügbar                         ║
╚═══════════════════════════════════════════════════════════════╝
```

**Klick auf eine Option:** zentriert die Kartenansicht auf das Fahrzeug.

**Wenn keine Quellen vorhanden:** jeweiliger Block wird ausgeblendet oder zeigt "Keine [Schüttgut/Paletten] verfügbar."

---

## 8. Was explizit nicht Teil dieses Features ist

- Automatisches Starten von AutoDrive-Touren
- Berechnung von Fahrzeit oder Route
- Benachrichtigungen nach abgeschlossenem Transport
- Mehrere gleichzeitige Transporte planen
- Unterscheidung welche Paletten einzeln aufladbar sind (z.B. BigBag vs. Europalette)

---

## 9. Implementierungsreihenfolge

| Schritt | Was | Wo | Aufwand |
|---|---|---|---|
| 1 | `inputJointTypes`, `outputJointTypes`, `cargoFillTypes`, `cargoCapacity`, `hasTensionBelts` exportieren | Lua `vehicleMeta` | ~1,5h |
| 2 | `attachedToId`, `cargoFillPct` ableiten (aus bestehendem `rootId`) | Dashboard JS | ~30 min |
| 3 | Matching-Algorithmus (Bulk + Paletten) | Dashboard JS | ~2,5h |
| 4 | `[Transport planen]`-Button in Produktionen-View | Dashboard HTML/JS | ~30 min |
| 5 | Modal mit beiden Transporttypen | Dashboard HTML/CSS/JS | ~2,5h |
| 6 | Klick → Karte zentrieren auf Fahrzeug | Dashboard JS | ~30 min |

**Gesamtaufwand ca. 8 Stunden.**
