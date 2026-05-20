# Dashboard Notification-System — Konzept

Geplant für v0.8.0. Zeigt einen Banner oben im Dashboard wenn neue Alerts entstehen.

## Problem

`collectAllAlerts()` wird bei jedem SSE-Update neu berechnet (event-driven, mehrmals pro Minute).
Ohne Tracking würden alle aktiven Alerts endlos aufpoppen — auch wenn der User sie bereits gesehen hat.

## Lösung: Fingerprint-basiertes Delta-Tracking

### Fingerprint-Funktion

Jeder Alert bekommt einen stabilen String-Key aus Typ + Name + Ressource + Level:

```js
function alertFingerprint(alert) {
  // Beispiele:
  // "husbandry:Hühner:water:crit"
  // "silo:Weizen:outCrit"
  // "production:Bäckerei:input:Mehl:warn"
  // "field:12:harvestReady"
  return `${alert.src}:${alert.key}:${alert.level}`;
}
```

### State

```js
// Fingerprints der aktuell aktiven Alerts (jedes Update neu berechnet)
let activeFingerprints = new Set();

// Fingerprints die der User bereits gesehen/quittiert hat (localStorage)
// Key: 'farmmonitor_seen_alerts'
let seenFingerprints = new Set(JSON.parse(localStorage.getItem('farmmonitor_seen_alerts') || '[]'));
```

### Delta-Logik nach jedem `loadData()`

```js
// Nach collectAllAlerts(data):
const currentFingerprints = new Set(alerts.map(alertFingerprint));

// Neue Alerts: aktiv aber noch nicht gesehen
const newAlerts = alerts.filter(a => !seenFingerprints.has(alertFingerprint(a)));

// Aufgelöste Alerts aus seen entfernen → ermöglicht Re-Trigger wenn Alert wiederkommt
for (const fp of seenFingerprints) {
  if (!currentFingerprints.has(fp)) seenFingerprints.delete(fp);
}

if (newAlerts.length > 0) showNotificationBanner(newAlerts);
```

### Notification-Banner

- Erscheint **über** der Navigation (kein Overlay, schiebt Content nach unten)
- Zeigt: Anzahl neuer Alerts + schwersten Level
  - Beispiel: `"3 neue Alerts — 1 kritisch"` mit rotem Dot
- **Klick** auf Banner → navigiert zum Alerts-View
- **Dismiss-Button (×)** → fügt alle neuen Fingerprints zu `seenFingerprints` hinzu, speichert in localStorage, Banner verschwindet
- Kein Auto-Dismiss — User quittiert aktiv

### Verhalten

| Situation | Verhalten |
|---|---|
| Neuer Alert entsteht | Banner erscheint |
| User dismissed, Alert bleibt aktiv | Kein erneuter Banner |
| Alert verschwindet (z.B. Wasser aufgefüllt) | Fingerprint aus seen entfernt |
| Alert kommt später wieder | Banner erscheint erneut |
| Mehrere neue Alerts gleichzeitig | Ein Banner, schwerster Level bestimmt Farbe |

## Implementierung

Nur `Server/dashboard.html` betroffen — kein Server-Code, kein Lua.

- ~50–80 Zeilen JS (Delta-Logik + Banner-Rendering)
- ~20 Zeilen CSS (Banner-Styling)
- Einstiegspunkt: nach `collectAllAlerts()` in `loadData()` (ca. Zeile 2338 ff.)
- localStorage-Key: `farmmonitor_seen_alerts`
