# Wensenlijst PixelPlayer voor Mac

Alles wat Mark vroeg, met wat klaar is en wat nog moet. Bijgewerkt bij elke ronde. Grote plannen voor later staan in
`ROADMAP.md`.

## Nog te doen

- **Sonos wisselt snel door veel nummers bij verbinden.** Serverbibliotheek laadt goed (970 nummers); hi-res wordt nu omgezet voor Sonos (waarschijnlijke oorzaak); logboek in 0.2.3 om het zeker te weten.
- **Apps laten samenwerken.** Mac en Android zien wat er op een Sonos-speaker speelt en kunnen het pauzeren; overnemen met een vraag; meerdere mensen in huis (eigen Navidrome-account). Voorstel, nog niet gebouwd.
- **Your Mix op Android** dezelfde laten zijn: Android moet de afspeellijst Your Mix van vandaag overnemen of zelf maken (Android-kant).
- **Sonos overnemen zonder wachtrij te verliezen.** Speelt de telefoon op een speaker en start je vanaf de Mac, dan eerst
  vragen (achter dit nummer, nu spelen, of vervangen), de wachtrij van de speaker overnemen en de telefoon netjes laten
  loslaten. Andersom laat de Mac los. Voorstel staat klaar, nog niet gebouwd.
- **Sonos met nummers die alleen op de Mac staan.** De Mac zou ze zelf aan de speaker kunnen aanbieden. Idee.
- **Spotify.** Grijs in de welkom en in Instellingen tot het er is.
- **Nederlandse vertaling** (zie ROADMAP).

## In 0.2.6

- De app gebruikte soms de halve processor (het menubalk-item liet de hele app steeds opnieuw opbouwen); nu rustig.
- Geen vraag om het sleutelhangerwachtwoord meer na elke update: de app bewaart een inlogtoken in plaats van het wachtwoord (na de update nog een laatste keer).

## In 0.2.5 (0.2.3 en 0.2.4 kwamen nooit uit)

- Genres in Browse openen een genrepagina; albums in zoekresultaten en het topresultaat openen.
- Dubbelklik in de zijbalk speelt af. Vastzetten met de rechtermuisknop, met groen speldje.
- Your Library toont alle albums en artiesten (recente eerst), zonder dat de zijbalk traag wordt.
- Artiestpagina zoals Spotify: banner, Popular (meest gespeeld via Navidrome), Albums.
- Albumkop: artiest aanklikbaar; "1 song" in plaats van "1 songs".
- Nummerrij zoals Spotify: groen vinkje als bewaard, plus en drie puntjes bij hover, menu om in afspeellijsten te zetten; afspeellijsten gaan naar Navidrome.
- Play rond, shuffle en meer als losse iconen; Home als simpel huisje.
- Wachtrij: eigen schakelaar Up Next/History met hover, drie puntjes met hover, geen blauw kader bij rechtermuisklik.
- Instellingen: Open at login, Player in the menu bar, Add new songs automatically en licht/donker werken; crossfade, equalizer en accentkleur grijs met reden.
- Your Mix slimmer (likes, vaak gespeeld, ontdekkingen, herontdekken, nieuw) en elke dag gedeeld als afspeellijst Your Mix op Navidrome.
- Sonos: hi-res (boven 48 kHz) komt als FLAC 16-bit 48 kHz van Navidrome (eenmalig een transcoding flac toevoegen in Navidrome), of als MP3 320 via Instellingen; songtekst loopt preciezer gelijk.
- Plusje bij een nummer: meteen in Liked Songs (groen in het menu), vinkje blijft zichtbaar zolang het menu open is.
- Songtekstachtergrond loopt door tot onder de speler; klokje gecentreerd boven de tijden.
- Updatemelding met gelijke ruimte boven en rechts; titel opent juiste album; een gehoverde rij in de zijbalk.

## In 0.2.2

- Bij het openen staat het laatst gespeelde nummer klaar, op de plek waar je was, met de wachtrij; de eerste keer Your Mix.
- Individual volume klapt weer uit.
- Meer ruimte rond Your Library.
- Speakerknop blauw zolang Connect open is.

## In 0.2.1

- Wachtrij helemaal opnieuw: Up Next en History, Now playing als kaart, Next in queue met Clear, Next from de lijst,
  afspelen, weghalen en slepen met animaties, zelfde kleur als de zijbalk.
- Updatemelding als kleine popup rechtsboven met een download-pijl, niet meer als groot blok.
- Spotify-sneltoetsen in het menu Controls.
- Speler wordt soepel breder of smaller met de titel; play en pauze wisselen snel.
- Volgend nummer schuift soepel in de speler.
- Tegels op Home openen bij een klik; de play-knop speelt.
- Songtekst loopt preciezer gelijk; klik op een regel springt er netjes heen; voor de eerste regel staat de tekst op de
  plek van de gezongen regel.
- Hover in de zijbalk even groot als de selectie, geen dubbel vak op het open item.
- Home en Browse wit in de donkere modus.
- Sonos sloeg nummers over ("not on the server"): de serverbibliotheek wordt nu per album geladen, zoals op Android.
- Instellingen › Sources laat zien hoeveel nummers de server gaf.

## Klaar

- Native Mac-ontwerp: zwevende glazen speler, ruim zoals Spotify, Engels, geen werkbalk, gelijke ronde knoppen.
- Songtekst over de hele breedte, speler op volledig scherm, wachtrij met kruisje, rechtermuisknop-menu's, Song Info,
  groen hartje, app-icoon (eigen noot, rondje iets hoger), geen blauwe focusranden.
- Navidrome-bibliotheek, lokaal eerst, likes en luisterbeurten gelijk met Navidrome, afspeellijsten ophalen.
- Sonos: kamers, groeperen, volume per kamer, terug naar de Mac. Telefoon bedienen via Bluetooth.
- Artiest en album aanklikbaar met onderstreping.
- GitHub-repo met automatisch bijwerken zoals Tandem (0.1.0, 0.1.1, 0.2.0).
- Songtekstknop is een microfoon.
- Welkom bij de eerste start: muziekmap, Navidrome, Sonos, telefoon, Spotify (later).
- Zijbalk 280 breed en verder van de rand; donkere modus bijna zwart zoals Spotify, zijbalk nog donkerder.
- Hover zoals Spotify: grijze achtergrond en afspeelknop op de hoes, geen zoom.
- Knoppen die niets deden werken; hoezen uit de albummap; genres uit FLAC; echte songteksten die meelopen; sorteren;
  Show all.
- Afspeelteken in een rij speelt af; spatiebalk speelt en pauzeert.
- Songtekst: geen flits of kleur in de zijbalk bij openen, geen sprong, klik op een regel, regels lichten op bij hover.
- Dubbele PixelPlayer Dev-apps opgeruimd: alleen PixelPlayer in Programma's.
