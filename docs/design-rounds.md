# Ontwerprondes van PixelPlayer voor Mac

Een SwiftUI-prototype om een richting te kiezen voor PixelPlayer op de Mac (roadmap punt 28 van de Android-mod).
Alleen ontwerp: verzonnen muziek, getekende hoezen, niets speelt, niets wordt gescand of verbonden.

## Bouwen en draaien

```bash
./scripts/build-app.sh
open "dist/PixelPlayer Dev.app"
```

Minimaal macOS 26, bouwt met `swift build` en de Command Line Tools. Instellingen zit onder ⌘, en het menubalkpaneel
onder het muzieknootje. De app is standaard Engels.

## Ronde 3 (nu)

Native macOS met een ruimere indeling zoals Spotify: de zijbalk is de bibliotheek (lijsten, albums en artiesten met hoes,
een keuzemenu om te filteren), Home met een brede Your Mix, snelkeuzetegels en rijen hoezen die altijd precies vol zijn,
afspeellijsten en albums met een grote kop in de kleur van de hoes en ruime rijen. Geen werkbalk: de bovenkant is vrij en
de kleur loopt door tot de rand. De speler is de zwevende glazen capsule onderin (Marks keuze uit ronde 2), de wachtrij een
kolom rechts. Wensen voor later staan in `docs/ROADMAP.md`.

Ronde 1 (PixelPlayer-stijl, te veel Android) en ronde 2 (native, maar te veel dichte lijsten) staan in `design/`.

## Screenshots en beweging

`scripts/capture-all.sh` maakt echte screenshots van alleen het eigen venster (`screencapture -l`), licht en donker,
en zet licht en donker per scherm naast elkaar in `design/ronde-3/`. Een popover is een eigen venster; dan wordt de rechthoek van het
venster vastgelegd en bijgesneden tot de vorm van het venster. `scripts/motion.sh` vertraagt de veren, legt het venster
beeld voor beeld vast en zet dat op echte snelheid in `design/ronde-3/beweging.mp4`. De debug-variabelen staan
bovenaan `Sources/PixelPlayerMac/App/Debug.swift`.
