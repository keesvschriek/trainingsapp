# Kees Personal: plan

Richtlijn: de projectopdracht "Kobo Elipsa 2E Personal Edition" (nov 2026), aangepast aan wat Kees zelf koos.
Vaste regels: niets bestaands weghalen, nooit gebruikersgegevens overschrijven, alles offline bruikbaar,
rustig zwart-wit ontwerp met grote tikvlakken, alleen gedeeltelijke verversing, elke module los zodat een fout de rest niet raakt,
en alleen echte testresultaten melden.

## Architectuur
- Motor: KOReader (Lua), gestart via NickelMenu met KEES_STUDY=1; de patch `2-kees-study.lua` neemt het scherm over.
- Eén module per onderdeel in `kobo/app/ks_*.lua`. Het beginscherm laadt onderdelen via `pcall`.
- Opslag: `settings/keesstudy.lua` (LuaSettings, met `.old`) plus een dagelijkse kopie in `settings/keesstudy-backup/` (7 dagen).
- Bijwerken via wifi: `manifest.json` op GitHub Pages met versie, wijzigingen en md5 per bestand; vorige versie in `app/.backup`.

## Klaar
- Kees Study (map): schaken leren, tegen de computer, quiz, topografie
- Beginscherm met mappen, statusbalk (tijd, batterij, wifi, schermtijd)
- Dagtekst (ochtend/avond), gewoontes (reeksen, 7 en 30 dagen)
- Instellingen: lettergrootte (vier stappen, schermen die niet passen worden automatisch iets compacter), automatisch slapen, schermtijd, back-ups
- Bijwerken: wijzigingen tonen, voortgang per bestand, vorige versie terugzetten

- Nieuw ontwerp (Inter, iconen, kaarten), verversknop en home-knop
- Sport: intervals.icu (vandaag, komende dagen, week, vorm) en intervaltimer
- Krant: NOS-feeds, ochtend- en avondeditie automatisch, offline lezen

## Volgende ronde (gekozen door Kees)
1. Synchronisatie twee kanten op voor sport en notities (privé, niet via de openbare repo)
2. Leesstatistieken uit de Kobo-database (leestijd, voortgang, markeringen als citaten)
3. Focustimer (pomodoro, historie) en dagplanner (taken, prioriteit, weekoverzicht, reflectie)
4. Toolbox (rekenmachine, stopwatch, eenheden, wereldklok)

## Later
- Leren: gespreid herhalen, tips, vandaag in de geschiedenis
- Notities (schermtoetsenbord van KOReader; handschrift kan beter in de notitieboeken van Kobo zelf)

## Bewust niet
- Liggend scherm: alle schermen zijn voor staand ontworpen
- Kleuren en animaties
