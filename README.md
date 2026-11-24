# PixelPlayer voor Mac (ontwerpproef)

Een SwiftUI-prototype om een richting te kiezen voor PixelPlayer op de Mac (roadmap punt 28 van de Android-mod).
Alleen ontwerp: verzonnen muziek, getekende hoezen, niets speelt, niets wordt gescand of verbonden.

## Bouwen en draaien

```bash
./scripts/build-app.sh
open "dist/PixelPlayer Dev.app"
```

Minimaal macOS 26, bouwt met `swift build` en de Command Line Tools. In het menu **Richting** wissel je met
⌘1 en ⌘2 tussen de twee varianten. Instellingen zit onder ⌘, en het menubalkpaneel onder het muzieknootje.

## Ronde 2: native macOS

Alles met de onderdelen van het systeem: de zijbalk en het zoekveld van `NavigationSplitView`, de werkbalk, een `Table`
voor nummers, de wachtrij in de inspector rechts, Verbinden als popover, Instellingen als echt Mac-venster met tabbladen.
De speler staat onderin, op twee manieren:

- **A, Balk onderin:** een balk over de hele breedte van het venster, onder de zijbalk en de inhoud.
- **B, Zwevende speler:** een glazen capsule die onderin over de inhoud zweeft.

Ronde 1 (drie richtingen in PixelPlayer-stijl) staat in `design/ronde-1` en is afgekeurd: te veel Android nagedaan.

## Screenshots en beweging

`scripts/capture-all.sh` maakt echte screenshots van alleen het eigen venster (`screencapture -l`), licht en donker,
en zet ze per scherm naast elkaar in `design/ronde-2/`. Een popover is een eigen venster; dan wordt de rechthoek van het
venster vastgelegd en bijgesneden tot de vorm van het venster. `scripts/motion.sh` vertraagt de veren, legt het venster
beeld voor beeld vast en zet dat op echte snelheid in `design/ronde-2/beweging-*.mp4`. De debug-variabelen staan
bovenaan `Sources/PixelPlayerMac/App/Debug.swift`.
