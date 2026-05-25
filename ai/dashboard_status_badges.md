# Dashboard — Status-Badges Referenz

Vollständige Liste aller Status-Texte im Fleet-View und Detail-View.
Beide Views zeigen identische Texte und Farben.

## Prioritätskette

```
adActive → cpActive → motorRunning (isAIActive / isEntered) → Geparkt
```

AD hat immer Vorrang vor CP. Nur ein Badge wird gleichzeitig angezeigt.

---

## AutoDrive (Cyan-Familie)

| Text | CSS-Klasse | Farbe | Bedingung |
|---|---|---|---|
| **AD Fehler** | `badge-ad-alert` | coral `#f48fb1` | `adError` |
| **AD Blockiert** | `badge-ad-alert` | coral `#f48fb1` | `adBlocked` |
| **AD Rückwärts** | `badge-ad-warn` | lime `#c6e64d` | `adModeState = reverseFromBadLocation` |
| **AD Tankt** | `badge-ad-warn` | lime `#c6e64d` | `adOnRouteToRefuel` |
| **AD Parkt** | `badge-ad-warn` | lime `#c6e64d` | `adOnRouteToPark` |
| **AD Lädt** | `badge-ad-work` | teal `#4db6ac` | `adIsLoading` |
| **AD Entlädt** | `badge-ad-work` | teal `#4db6ac` | `adIsUnloading` |
| **AD Wartet auf Ernter** | `badge-ad` | cyan `#4dd0e1` | `adModeState = waitToBeCalled` |
| **AD Fährt zum Ernter** | `badge-ad` | cyan `#4dd0e1` | `adModeState = driveToCombine` |
| **AD Folgt Ernter** | `badge-ad` | cyan `#4dd0e1` | `adModeState = followCombine` |
| **AD Fährt zum Entladen** | `badge-ad` | cyan `#4dd0e1` | `adModeState = driveToUnload` |
| **AD Fährt zu Start** | `badge-ad` | cyan `#4dd0e1` | `adModeState = driveToStart` |
| **AD** | `badge-ad` | cyan `#4dd0e1` | Fallback |

---

## Courseplay (Amber-Familie)

| Text | CSS-Klasse | Farbe | Bedingung |
|---|---|---|---|
| **CP Feststeckend** | `badge-cp-alert` | coral `#f48fb1` | `cpInfoText = IS_STUCK` |
| **CP Kein Pfad** | `badge-cp-alert` | coral `#f48fb1` | `cpInfoText = ERROR_NO_PATH_FOUND` |
| **CP Tank leer** | `badge-cp-alert` | coral `#f48fb1` | `cpInfoText = FUEL_IS_EMPTY` |
| **CP Reparatur** | `badge-cp-alert` | coral `#f48fb1` | `cpInfoText = IS_COMPLETELY_BROKEN` |
| **CP Fehler** | `badge-cp-alert` | coral `#f48fb1` | sonstiger Fehler-InfoText |
| **CP Voll** | `badge-cp-warn` | gelb `#ffe082` | `cpInfoText = NEEDS_UNLOADING` |
| **CP Tankt** | `badge-cp-warn` | gelb `#ffe082` | `cpInfoText = FUEL_IS_LOW` |
| **CP Blockiert** | `badge-cp-warn` | gelb `#ffe082` | `cpInfoText = BLOCKED_BY_OBJECT` |
| **CP Wetter** | `badge-cp-warn` | gelb `#ffe082` | `cpInfoText = WAITING_FOR_RAIN/SNOW_*` |
| **CP Wartet** | `badge-cp-warn` | gelb `#ffe082` | sonstiger Warn-InfoText |
| **CP Wartet auf Entlader** | `badge-cp-warn` | gelb `#ffe082` | `cpWaitingForUnload` |
| **CP Feldarbeit** | `badge-cp` | amber `#ffb74d` | `cpJobType = fieldWork` |
| **CP Entlader** | `badge-cp` | amber `#ffb74d` | `cpJobType = combineUnloader` |
| **CP Ballen** | `badge-cp` | amber `#ffb74d` | `cpJobType = baleFinder` |
| **CP Silo** | `badge-cp` | amber `#ffb74d` | `cpJobType = bunkerSilo` |
| **CP Laden** | `badge-cp` | amber `#ffb74d` | `cpJobType = siloLoader` |
| **CP** | `badge-cp` | amber `#ffb74d` | Fallback |

---

## Allgemein (kein Mod aktiv)

| Text | CSS-Klasse | Bedingung |
|---|---|---|
| **KI aktiv** | `badge-ai` | Vanilla-KI helper aktiv |
| **In Betrieb** | `badge-active` | Fahrer sitzt drin, Motor läuft |
| **Motor läuft** | `badge-active` | Motor an, niemand drin |
| **Geparkt** | `badge-idle` | Motor aus |

---

## CSS-Definitionen

```css
/* AutoDrive */
.fleet-badge.badge-ad       { background: rgba(0,188,212,.15);  border-color: rgba(0,188,212,.4);  color: #4dd0e1; }
.fleet-badge.badge-ad-alert { background: rgba(244,143,177,.15); border-color: rgba(244,143,177,.4); color: #f48fb1; }
.fleet-badge.badge-ad-warn  { background: rgba(198,230,77,.13);  border-color: rgba(198,230,77,.35); color: #c6e64d; }
.fleet-badge.badge-ad-work  { background: rgba(77,182,172,.15);  border-color: rgba(77,182,172,.4);  color: #4db6ac; }

/* Courseplay */
.fleet-badge.badge-cp       { background: rgba(255,183,77,.15);  border-color: rgba(255,183,77,.4);  color: #ffb74d; }
.fleet-badge.badge-cp-alert { background: rgba(244,143,177,.15); border-color: rgba(244,143,177,.4); color: #f48fb1; }
.fleet-badge.badge-cp-warn  { background: rgba(255,224,130,.15); border-color: rgba(255,224,130,.4); color: #ffe082; }
```

---

## Speed-Block-Färbung (wenn Mod aktiv)

```css
/* AD → Cyan */
.fleet-speed-block.ad-active .fleet-speed-val  { color: #4dd0e1; }
/* CP → Amber */
.fleet-speed-block.cp-active .fleet-speed-val  { color: #ffb74d; }
```

AD hat Vorrang: wenn `adActive`, wird `ad-active` gesetzt, nicht `cp-active`.

## AutoDrive Modus-Namen (Detail-View, vd-ad-banner)

| ID | Label |
|---|---|
| 1 | Fahrt zu Ziel |
| 2 | Abholen & Liefern |
| 3 | Liefern |
| 4 | Laden |
| 5 | Ernter-Begleiter |
