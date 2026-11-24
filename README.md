# PixelPlayer voor Mac (ontwerpproef)

Een SwiftUI-prototype om een richting te kiezen voor PixelPlayer op de Mac (roadmap punt 28 van de Android-mod).
Alleen ontwerp: verzonnen muziek, getekende hoezen, niets speelt, niets wordt gescand of verbonden.

## Bouwen en draaien

```bash
./scripts/build-app.sh
open "dist/PixelPlayer Dev.app"
```

Minimaal macOS 26, bouwt met `swift build` en de Command Line Tools. In het menu **Richting** wissel je met
⌘1, ⌘2 en ⌘3 tussen de drie richtingen. Het menubalkpaneel zit onder het muzieknootje in de menubalk.

## De drie richtingen

- **A, Zijbalk:** een zwevende glazen zijbalk met de bibliotheek, de speler als glazen balk bovenin
  (hoes, titel en voortgang in één capsule), de wachtrij als kolom rechts, Verbinden groeit uit zijn knop.
- **B, Speler centraal:** de speler is het venster. Links altijd de grote hoes, rechts tekst-tabbladen
  (Hierna, Home, Bibliotheek, Zoeken). Verbinden schuift van onderen in, en de speler groeit uit tot het hele venster.
- **C, Tabbladen:** de Android-opbouw vertaald: tabbladen bovenin, inhoud over de hele breedte, een zwevende
  minispeler onderin die uitgroeit tot de volledige speler. Wachtrij en Verbinden komen als glazen panelen uit de minispeler.

## Screenshots en beweging

`scripts/capture-all.sh` maakt echte screenshots van alleen het eigen venster (`screencapture -l`, dus echt glas),
licht en donker, en zet ze per scherm naast elkaar in `design/ronde-1/`. `scripts/motion.sh` vertraagt alle veren,
legt het venster beeld voor beeld vast en zet dat op echte snelheid in `design/ronde-1/beweging-*.mp4`.
De debug-variabelen staan bovenaan `Sources/PixelPlayerMac/App/Debug.swift`.
