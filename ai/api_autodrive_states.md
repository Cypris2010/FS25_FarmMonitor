# FS25 AutoDrive — Vollständige State-Referenz

Quelle: https://github.com/Stephan-S/FS25_AutoDrive  
Relevante Verzeichnisse: `scripts/Modes/`, `scripts/Tasks/`, `scripts/Modules/`, `scripts/Specialization.lua`

Issues recherchierbar unter: https://github.com/Stephan-S/FS25_AutoDrive/issues

Siehe auch: `ai/api_autodrive.md` (Start-Sequenz, Marker-Export, IPC-Commands)

## Direkt lesbare Felder auf `vehicle.ad`

| Feld | Typ | Bedeutung |
|---|---|---|
| `stateModule:isActive()` | bool | AD aktiv und steuert Fahrzeug |
| `onRouteToRefuel` | bool | Fährt zur Tankstelle |
| `onRouteToPark` | bool | Fährt zum Parkplatz |
| `onRouteToRepair` | bool | Fährt zur Werkstatt |
| `isStoppingWithError` | bool | Gestoppt wegen Fehler |
| `specialDrivingModule.isBlocked` | bool | Durch Hindernis blockiert (nach 10–15 Sek. Stillstand) |
| `specialDrivingModule:isStoppingVehicle()` | bool | Fahrzeug wird aktiv angehalten |
| `specialDrivingModule:shouldStopMotor()` | bool | Motor darf ausgeschaltet werden |
| `trailerModule.isLoading` | bool | Wird gerade beladen |
| `trailerModule.isUnloading` | bool | Wird gerade entladen |
| `trailerModule.blocked` | bool | Entladung blockiert (z.B. Deckel zu) |
| `collisionDetectionModule.detectedObstable` | bool | Hindernis erkannt (Sensoren/Traffic/Reverse) |
| `collisionDetectionModule.detectedCollision` | bool | Fahrzeugkollision per Bounding Box |
| `collisionDetectionModule:detectAdTrafficOnRoute()` | bool | Anderes AD-Fahrzeug auf gleicher Route |
| `pathFinderModule.completelyBlocked` | bool | Pathfinding kann Ziel nicht erreichen |

## Modi (6 Betriebsmodi)

### Modus 1 — DriveTO
Einfache Punkt-zu-Punkt-Navigation. Keine internen States — Status über aktiven Task erkennbar.

### Modus 2 — UnloadAt (DeliverTo)
Nur entladen/liefern.

| State | Verhalten |
|---|---|
| STATE_TO_TARGET | Fährt zum Entladeziel |
| STATE_EXIT_FIELD | Verlässt Feld Richtung Straße |
| STATE_PARK | Parkt am Ziel |
| STATE_FINISHED | Auftrag abgeschlossen |

### Modus 3 — Load
Nur beladen.

| State | Verhalten |
|---|---|
| STATE_INIT | Initialisierung, erste Aktion bestimmen |
| STATE_TO_TARGET | Fährt zum Ladeort |
| STATE_LOAD | Am Ort, bereit zum Beladen |
| STATE_EXIT_FIELD | Verlässt Feld |
| STATE_FINISHED | Modus abgeschlossen |

### Modus 4 — PickupAndDeliver
Volles Abhol-/Lieferprogramm: laden → entladen → wiederholen.

| State | Verhalten |
|---|---|
| STATE_INIT | Initialisierung, Füllstand prüfen |
| STATE_PICKUP | Aktiv beladen am Abholort |
| STATE_DELIVER | Aktiv entladen am Lieferort |
| STATE_EXIT_FIELD | Verlässt Feld |
| STATE_DELIVER_TO_NEXT_TARGET | Fährt zum nächsten Lieferziel (Multi-Target) |
| STATE_PICKUP_FROM_NEXT_TARGET | Fährt zum nächsten Abholpunkt (Multi-Target) |
| STATE_RETURN_TO_START | Kehrt zur Startposition zurück (alle Schleifen done) |
| STATE_PARK | Parkt an Endposition |
| STATE_FINISHED | Modus abgeschlossen |

### Modus 5 — CombineUnloader (komplexester Modus)
Folgt Mähdrescher und entleert aktiv.

**Primäre States:**

| State | Verhalten |
|---|---|
| STATE_INIT | Füllstand prüfen, Aktion bestimmen |
| STATE_WAIT_TO_BE_CALLED | Geparkt, wartet auf Mähdrescher-Signal |
| STATE_DRIVE_TO_COMBINE | Fährt zum Mähdrescher |
| STATE_DRIVE_TO_PIPE | Positioniert sich unter Auswurfrohr |
| STATE_FOLLOW_COMBINE | Folgt Mähdrescher, Entladung läuft |
| STATE_ACTIVE_UNLOAD_COMBINE | Dynamisch positionieren zum Rohr |
| STATE_FOLLOW_CURRENT_UNLOADER | Folgt anderem Unloader (Konvoi-Modus) |
| STATE_DRIVE_TO_UNLOAD | Fährt zur Entladestation (voll) |
| STATE_DRIVE_TO_START | Kehrt zurück zum Feld nach Entladung |
| STATE_LEAVE_CROP | Räumt Erntegut vor Abfahrt |
| STATE_EXIT_FIELD | Verlässt Feld Richtung Entladestation |
| STATE_REVERSE_FROM_BAD_LOCATION | Rückwärts aus Blockierung |

**FollowCombineTask Sub-States** (wenn STATE_ACTIVE_UNLOAD_COMBINE):

| State | Verhalten |
|---|---|
| STATE_CHASING | Folgt Rohrposition für Entladung |
| STATE_WAIT_FOR_TURN | Wartet während Mähdrescher wendet |
| STATE_REVERSING | Rückwärts um Platz zu schaffen |
| STATE_REVERSING_FROM_CHOPPER | Spezialrückwärts für Häcksler |
| STATE_WAIT_FOR_PASS_BY | Wartet bis Mähdrescher vorbeifährt |
| STATE_GENERATE_UTURN_PATH | Plant U-Turn-Manöver |
| STATE_DRIVE_UTURN_PATH | Führt U-Turn aus |
| STATE_WAIT_BEFORE_FINISH | Kurzes Warten vor Task-Ende |

### Modus 6 — BGA
Spezialisiert für Biogasanlage. Keine internen States — führt UnloadBGATask aus.

## Aktive Tasks (via `taskModule:getActiveTask()`)

| Task | Infotext | Bedeutung |
|---|---|---|
| DriveToDestinationTask | "Driving to destination" | Navigiert zu Ziel |
| DriveToVehicleTask | "Driving to vehicle" | Fährt zu Fahrzeug |
| FollowVehicleTask | "Following vehicle" | Folgt Fahrzeug |
| LoadAtDestinationTask | "Loading at destination" | Lädt am Zielort |
| UnloadAtDestinationTask | "Unloading at destination" | Entlädt am Zielort |
| UnloadBGATask | "Unloading at biogas plant" | BGA-Entladung |
| FollowCombineTask | "Following combine" | Folgt Mähdrescher (mit Sub-States) |
| ExitFieldTask | "Exiting field" | Verlässt Feld (mit Fortschrittsanzeige) |
| ClearCropTask | "Clearing crop" | Räumt Erntegut |
| ParkTask | "Parking" | Parkt |
| WaitForCallTask | "Wait for call" | CombineUnloader wartet auf Ruf |
| ReverseFromBadLocationTask | "Reversing from collision" | Rückwärts aus Kollision |
| RefuelTask | "Driving to refuel / Refueling" | Tanken (inkl. Pfadfindungs-State X/Y) |
| RepairTask | "Driving to repair / Repairing" | Reparatur (inkl. Pfadfindungs-State X/Y) |
| CatchCombinePipeTask | "Catching combine pipe" | Rohr anfangen |
| EmptyHarvesterTask | "Emptying harvester" | Mähdrescher leeren |
| HandleHarvesterTurnTask | "Handling harvester turn" | Wendemanöver begleiten |
| StopAndDisableADTask | "Stopping / Disabling AutoDrive" | AD wird deaktiviert |

## Implementierung im Dashboard

### Lua-Export (`vehicles.json`)

Alle neuen Felder werden nur gesetzt wenn `true` (sonst `nil` → nicht im JSON):

```lua
adBlocked         -- specialDrivingModule.isBlocked == true
adError           -- vehicle.ad.isStoppingWithError == true
adOnRouteToRefuel -- vehicle.ad.onRouteToRefuel == true
adOnRouteToPark   -- vehicle.ad.onRouteToPark == true
adIsLoading       -- vehicle.ad.trailerModule.isLoading == true
adIsUnloading     -- vehicle.ad.trailerModule.isUnloading == true
adModeState       -- string, nur für Modus 5 (CombineUnloader), Werte:
                  --   "waitToBeCalled" | "driveToCombine" | "followCombine"
                  --   "driveToUnload" | "driveToStart" | "reverseFromBadLocation"
```

### Dashboard Badge-Funktion (`_adStatusBadge(state)`)

Priorität von oben nach unten — erster Match gewinnt:

| Priorität | Badge-Text | CSS-Klasse | Bedingung |
|---|---|---|---|
| 1 | AD Fehler | `badge-ad-alert` (coral) | `state.adError` |
| 2 | AD Rückwärts | `badge-ad-warn` (lime) | `adModeState === 'reverseFromBadLocation'` |
| 3 | AD Blockiert | `badge-ad-alert` (coral) | `state.adBlocked` |
| 4 | AD Tankt | `badge-ad-warn` (lime) | `state.adOnRouteToRefuel` |
| 5 | AD Parkt | `badge-ad-warn` (lime) | `state.adOnRouteToPark` |
| 6 | AD Lädt | `badge-ad-work` (teal) | `state.adIsLoading` |
| 7 | AD Entlädt | `badge-ad-work` (teal) | `state.adIsUnloading` |
| 8 | Wartet auf Mähdrescher | `badge-ad` (cyan) | `adModeState === 'waitToBeCalled'` |
| 9 | Fährt zum Mähdrescher | `badge-ad` (cyan) | `adModeState === 'driveToCombine'` |
| 10 | Folgt Mähdrescher | `badge-ad` (cyan) | `adModeState === 'followCombine'` |
| 11 | Fährt zum Entladen | `badge-ad` (cyan) | `adModeState === 'driveToUnload'` |
| 12 | Kehrt zurück | `badge-ad` (cyan) | `adModeState === 'driveToStart'` |
| 13 | AutoDrive | `badge-ad` (cyan) | Fallback |

### Badge-Farben (CSS)

Alle Farben bleiben in der Cyan/Teal-Familie — kein reines Rot oder Gelb:

```css
.badge-ad        { color: #4dd0e1; }  /* cyan  — Normalbetrieb */
.badge-ad-alert  { color: #f48fb1; }  /* coral — Fehler / Blockiert */
.badge-ad-warn   { color: #c6e64d; }  /* lime  — Rückwärts / Tankt / Parkt */
.badge-ad-work   { color: #4db6ac; }  /* teal  — Lädt / Entlädt */
```

### Speed-Block AD-Färbung

Wenn AD aktiv, bekommt der Geschwindigkeitsblock die Klasse `ad-active` → Zahl und Einheit in Cyan statt Grün. Gilt in Fleet-View (`.fleet-speed-block`) und Detail-View (`.vd-header-speed`).

```js
// Fleet-View
`<div class="fleet-speed-block ${speed > 0.5 ? 'moving' : ''}${state.adActive ? ' ad-active' : ''}">`
// Detail-View
`<div class="vd-header-speed ${isMoving ? 'moving' : ''}${rootState.adActive ? ' ad-active' : ''}">`
```

### Wichtige Besonderheiten

- `adActive` wird VOR `motorRunning` geprüft — AD kann bei stehendem Motor aktiv sein (z.B. `STATE_WAIT_TO_BE_CALLED`)
- `adModeState` wird nur für Modus 5 exportiert (CombineUnloader); andere Modi nutzen die direkt lesbaren Flags
- `reverseFromBadLocation` hat höhere Priorität als `adBlocked` — aktive Erholung > passives Feststecken
- Alle neuen Felder sind `nil` wenn nicht gesetzt → werden im JSON weggelassen → kein unnötiger Traffic
