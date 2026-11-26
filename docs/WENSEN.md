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

## Voor 0.2.8 (wordt gebundeld, nog niet uitbrengen)
- Shuffle opnieuw over Spotify gelegd: rechte diagonalen, onderbroken lijn loopt recht door onder de kruising.
- Getekende iconen in een laag: doorzichtig wit (mixkop) geeft geen lichte vlekjes meer bij de pijlpunten.
- Lijstkoppen zoals Spotify: kop in eigen kleur (donker), grotere witte titel, hoes groeit mee, 4 pt hoek, meta als "576 songs, 31 hr 21 min".
- Liked Songs-hoes in Spotify's verloop met hun hartje.
- App-icoon een tikje naar rechts.
- Wit bolletje bij hover op voortgangsbalk en volume, zoals Spotify.
- Grote titels in Figtree 850 (OFL), van 40 vrije lettertypes het dichtst bij Spotify's titelletter (78% gelijk), met gemeten spatiering.
- Wachtrij met tabs Queue en Recently played zoals Spotify (groen streepje), puntjes en kruisje rechts.
- Kop op Spotify-maat zoals Mark Spotify ziet (75% zoom), titel Figtree 800, Playlist en meta kleiner.
- Home-tegels zoals Spotify: 47 hoog, vet, lichter grijs, artiest vierkant, groene balkjes als hij speelt.
- Lijstpagina's: genre-chips uit de eigen tags (filteren), zoeken in de lijst, Sort by plus View as in een menu, download-icoon groen gevuld als alles lokaal staat.
- Wachtrij exact als Spotify: Now playing als gewone rij (titel groen), koppen vet wit, Next from:, hover met grijs, play op de hoes en drie puntjes, geen speelduur.
- Venster zoals Spotify: zwarte bovenbalk met pijltjes, Home en zoekbalk; drie afgeronde panelen; speler blijft zweven.
- Your Library zoals Spotify: inklapknop schuift in bij hover, plus, breder maken, chips, vergrootglas naar zoekpagina, Recents-menu (Sort by, View as in vier soorten), ingeklapt een strook met hoezen, sleepbaar.
- Zoeken ongevoelig voor accenten (stenstrom vindt Stenström), ook in lijsten.
- Recent searches op de zoekpagina (zoals SpotCopy), nummermenu in Marks volgorde met echte slaaptimer (maan in de speler), shuffle werkt echt en is op lijsten een schakelaar met bolletje.
- Wachtrij slepen: groen lijntje waar het landt, klein sleepbeeld, korte beweging bij neerzetten.
- Animaties op Spotify's maat (gemeten): knoppen en chips 0,15 s, play op kaarten 0,3 s omhoog, rijen direct, wachtrij direct open en dicht; bibliotheek sorteert niet meer bij elke hover.
- Inklappen gemeten op open.spotify.com: kop schuift 0,1 s, icoon volgt na 0,1 s (eruit andersom); in- en uitklappen zelf zonder animatie; strook 72 px met hoezen van 48.
- Plus slaat op in Liked Songs met een pop, het groene vinkje opent Saved in; "Made for" met je eigen naam.
- Standaard donker zoals Spotify, ook overdag; licht alleen via Instellingen › Appearance (heeft nu ook panelen).
- Bovenbalk op Spotify's maat: 48 pt, Home en zoekveld 36 pt met hun kleuren, hover en focusrand; verkeerslichtjes in het midden.
- Bibliotheek en wachtrij glijden weer in en uit (Spotify doet het direct, maar Mark vindt de animatie mooi).
- Genrechips zoals Spotify: één rij van hooguit 15, alleen wat past, geen pijltje; 32 hoog, tekst 14.
- Home-, zoek- en bibliotheekicoon heel (onderkant ontbrak), Browse-icoon in het zoekveld nagetekend.
- Zijbalk-hover zoals Spotify: geopende lijst grijs, hover op een andere eigen grijs, op de geopende lichter.
- Zijbalk: altijd maar één rij grijs; met de muis op een andere rij is alleen die grijs, de geopende pas weer als de muis van de lijst af is.
- Breedte van Your Library slepen volgt de muis soepel (werd gemeten op de sleeplijn zelf, die meeschoof).
- Zoekveld: klik opent de zoekpagina, witte rand meteen en blijft staan zolang die open is.
- Zoekveld zoals Spotify (gemeten): witte rand alleen tijdens typen, klik ergens anders haalt de cursor eruit, cursor wit.
- Sonos: na het opstarten skipte de speaker door de hele wachtrij (de wachtrij was geladen voor Navidrome antwoordde, dus zonder servercopie). Nu staat de serverlijst op schijf zoals op Android, krijgt de wachtrij de nieuwe nummers na elke update, en verbindt hij niet als het nummer echt alleen op de Mac staat (geen skipreeks, wachtrij blijft heel).
- Bibliotheek probeert Navidrome opnieuw als het netwerk vlak na het opstarten 'offline' meldt (dat liet hem de hele sessie zonder server).
- Titelletter: afstand per letter gemeten op Spotify's eigen titelletter, Figtree's kerning uit.
- Lettertype Mix (Spotify's eigen letter) via Instellingen › Appearance › Font: Import Font… slikt de zip, de map of losse bestanden, ook door te slepen; Get the Font en Use Default. Niet in de repo of de release; zonder import Figtree en de systeemletter. Vervangt de tabel per letter hierboven.
- Mix zoals Spotify het tekent: 0,967 zo breed (SpotifyMixUI), titels 0,015 em (800) en 0,019 em (700) krapper; per onderdeel Spotify's dikte (400, 700, 800) en maat, tracklijst en pagina's op Spotify's maat (titel 16, tweede regel 14, koppen 24).
- Songtekst eerst van LRCLIB zoals de Android-app, op duur gekozen; daarna het bestand en Navidrome.
- Home: Your Mix als kop zoals een playlist (variant A), kleur uit de hoezen, dezelfde hoezen als de tegel; collages met vier verschillende hoezen.
- Naam uit het Navidrome-account ("Made for ..."), geen naam in de code; profielknop rechtsboven met foto (Gravatar via Navidrome) of letter.
- View › Actual Size, Zoom In en Zoom Out (⌘0, ⌘+, ⌘−) zoals Spotify, met zijn stappen; alle maten zijn nu Spotify's maten op 100% (bovenbalk 64, Your Library en wachtrij met hoezen van 48, tekst 16 en 14).
- Tweede tekst en "Show all" in Spotify's grijs #B3B3B3 (was donkerder).
- Iconen hetzelfde als in de Android-app: shuffle, play (ook de groene knop), pauze, vorige, volgende, herhalen, wachtrij, Connect, toevoegen aan wachtrij, meer, sluiten, omlaag, plus, opslaan (groen vinkje), toevoegen (ring met plus), downloaden, zoeken, punaise, slaaptimer.
- Menu's zoals Spotify in plaats van de systeemmenu's: rechtsklik en drie puntjes overal (nummers, wachtrij, speler, Your Library, lijstkop, profiel, plus), donker paneel met Spotify's maten, elke regel een icoon uit de Android-app, Spotify's letters rechts (L, P, Q, A, ⌥A, S) die werken als het menu open is, submenu's ernaast, pijltjes en Esc; Sort by en View as met groene keuze en vinkje. Het zwarte icoontje is weg.
- Gedownload: groen gevulde cirkel met uitgesneden pijl, zoals Spotify.
- Vinkje in menu's zoals Spotify's (dunne lijn), gekozen icoon groen; tekst zo dun als Spotify's (zonder de verdikking van macOS, net als Spotify's antialiased).
- Standaard op 83%, dezelfde stap als Marks Spotify (zoom-level -100); zoomstappen zijn nu die van Spotify (telkens 1,2 keer).
- Wachtrij: dubbelklik op een nummer in de wachtrij speelt het weer (haalde het weg), Remove from queue staat weer in het menu.

## In 0.2.7 (uitgebracht)

- Accent Spotify-groen in plaats van blauw: play-knoppen massief groen met zwart teken, schuifjes, vinkjes.
- Mixes for You: klik op de hoes opent de mix als pagina; de groene knop op de hoes speelt en wordt pauze zolang die mix speelt. Zo ook op albums, artiesten, tegels op Home en de grote play-knop.
- Terug en vooruit zoals in een browser, naast de verkeerslichtjes; ook met ⌘[ en ⌘] en de zijknoppen van de muis.
- Artiestpagina: banner loopt over in de kleur van de hoes en daarna zwart, Liked Songs van die artiest, Discography met jaartallen, Appears On en meer uit hetzelfde genre.
- Voortgangsbalk zoals Spotify: dun, groen bij hover met de tijd erboven en grijs tot waar je klikt, bolletje alleen bij slepen. Klik op de rechtertijd wisselt tussen resterend en totaal.
- Songteksten: zijbalk gaat vanzelf weg (instelling in Algemeen, standaard aan), kolom in het midden.
- Volledig scherm: plusje of vinkje (groter, op hoogte van de artiest), songteksten aan en uit, alleen de hoes als een nummer geen tekst heeft, geen blauw zoekveldkader eroverheen; Esc sluit.
- Speler en menubalk: plusje of vinkje in plaats van hartje; Add to playlist opent zonder vertraging.
- Zijbalk: selectie grijs in plaats van blauw, hover en play-knop lopen gelijk, geen blijvende hover meer.
- Sonos: balk springt niet meer terug bij pauze of vooruit bij doorspelen; kleine correcties van de speaker glijden in. De leidende kamer kun je uitvinken, de andere kamer neemt het over.
- Zoekveld pakt geen focus meer bij het openen; ⌘L zet de cursor erin.
- Speler zoals Spotify: knoppen met de balk eronder, volume rechts, witte play-knop; shuffle, vorige, volgende, herhalen, microfoon, wachtrij en Add to Queue nagetekend over Marks Spotify-screenshots.
- Sorteren via de kolomtitels (Title, Artist, Album, Date added, lengte) met een groen pijltje; nog een klik draait om, # zet de eigen volgorde terug. View as: List of Compact in plaats van het sorteermenu.
- Songtekstkop met titel en artiest; grijze sorteer- en filtermenu's.

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
