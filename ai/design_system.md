# FarmMonitor Design System

Visuelle Regeln für alle UI-Elemente im Dashboard (`Server/dashboard.html`).

---

## Grundprinzip

Drei klar unterscheidbare visuelle Klassen:

| Klasse | Klickbar | Border | Hintergrund | Hover |
|---|---|---|---|---|
| **Button** | ✅ | `1px solid` | subtil | Background + Border heller |
| **Tag / Label** | ❌ | kein | farbige Fläche | keiner |
| **Infoblock** | ❌ | kein | `rgba(255,255,255,0.05)` | keiner |

---

## Buttons

### Text-Buttons (Filter, Navigation)
Klasse: `.filter-btn`

```css
border: 1px solid var(--line);          /* rgba(255,255,255,.12) */
background: rgba(255,255,255,.035);
border-radius: 10px;
padding: 8px 14px;
font-size: 13px; font-weight: 600;
cursor: pointer;
```

- Aktiver Zustand: grüne Border + grüner Text + grüner Hintergrund-Schimmer
- Hover: Border grünlich, Text grün

### Icon-Buttons (Einsteigen, Hinfahren, Teleport)
Klasse: `.tp-btn`

```css
border: 1px solid var(--line);
background: rgba(255,255,255,0.05);
border-radius: 8px;
width: 32px; height: 32px;
cursor: pointer;
```

- Hover: Background und Border heller, leichtes `scale(1.06)`

### Icon-Buttons mit semantischer Farbe (Ausgangsmodus)
Klasse: `button.output-mode-badge`

```css
border: 1px solid <farbige Border>;     /* passend zum Modus */
background: <farbiger Hintergrund>;
border-radius: 8px;
width: 30px; height: 30px;
cursor: pointer;
```

Farbvarianten: `.red` / `.green` / `.orange` / `.blue`  
- Hover: `filter: brightness(1.2)`, leichtes `scale(1.07)`

### Aktions-Button (Ansicht bearbeiten, Modals)
Klasse: `.fleet-settings-btn`, `.btn-edit` o.ä.

```css
border: 1px solid var(--line);
background: rgba(255,255,255,0.05);
border-radius: 8px;
padding: 6px 12px;
font-size: 12px; font-weight: 500;
cursor: pointer;
```

---

## Tags / Labels

Tags sind **nicht klickbar**, kein Border, kein Hover.

### Severity-Labels (Warnung, Kritisch, Vertrocknet)
Klasse: `.badge` + Farbklasse

```css
border: none;
border-radius: 5px;
padding: 2px 7px;
font-size: 11px; font-weight: 600;
text-transform: uppercase; letter-spacing: 0.04em;
background: <farbige Fläche>;           /* z.B. rgba(229,57,53,.13) für rot */
```

Farbvarianten: `.red` / `.orange` / `.green` / `.yellow` / `.blue` / `.gray`

### Typ-Tags auf Cards (Silo, Lager, Paletten, Extension)
Ebenfalls `.badge.gray` — gleiche flache Sprache.

### Status-Badges im Fahrzeug-View (Geparkt, In Betrieb, AutoDrive)
Klasse: `.fleet-badge` + Farbklasse

```css
border: 1px solid <farbige Border>;     /* weicher als Buttons */
border-radius: 20px;                    /* Pill-Form */
font-size: 10px;
```

> **Unterschied zu Buttons:** Pill-Form (sehr hoher `border-radius`) signalisiert Status, kein Button.

---

## Informationsblöcke

Nicht klickbar, kein Border, nur Hintergrund für Abgrenzung.

### Speed-Block (km/h Anzeige)
Klasse: `.fleet-speed-block`

```css
border: none;                           /* KEIN Border — kein Button */
background: rgba(255,255,255,0.05);
border-radius: 8px;
```

Fahrender Zustand (`.moving`): grüner Hintergrund ohne Border.

### Cards / Panels
Klasse: `.card`, `.panel`

```css
border: 1px solid var(--line);
background: linear-gradient(...);
border-radius: var(--radius);           /* 18px */
```

> Cards haben Border, sind aber keine Buttons — ihr Border ist strukturell (Abgrenzung), nicht interaktiv. Der Unterschied ist durch `cursor: pointer` und Hover-Verhalten erkennbar.

---

## Farbstreifen auf Fahrzeug-Cards

Kein SVG-Kreis. Stattdessen `::before`-Pseudo-Element am **rechten** Rand der Card.
Zwei Farben = diagonal geteilt (Haupt- und Sekundärfarbe des Fahrzeugs).

```css
.fleet-cell::before {
  content: '';
  position: absolute;
  right: 0; top: 0; bottom: 0; width: 8px;
  background: linear-gradient(to right, var(--vc1) 50%, var(--vc2) 50%);
}
```

CSS-Variablen `--vc1` und `--vc2` werden inline auf dem Card-Div gesetzt.  
Keine Farbe → `transparent` (Default), kein sichtbarer Streifen.

---

## Interaktive Zeilen (Chain-Rows, Inaktiv-Toggle)

Rows die klickbar sind aber kein Button-Element sind:

```css
cursor: pointer;
transition: background .12s;
```
```css
:hover { background: rgba(255,255,255,.05); }   /* chain-row */
:hover { background: rgba(255,255,255,.07); }   /* inactive-toggle */
```

Kein Border, kein Scale — nur Background-Highlight zeigt Klickbarkeit.

---

## Zusammenfassung: Woran erkenne ich was?

```
Border + Hintergrund + Hover-Background → Button (klickbar)
Pill-Form (border-radius ≥ 20px) + Border → Status-Badge (nicht klickbar)
Fläche ohne Border + Uppercase-Text → Tag / Label (nicht klickbar)
Hintergrund ohne Border, kein Hover → Infoblock (nicht klickbar)
Background-Highlight bei Hover, kein Border → Interaktive Zeile
```
