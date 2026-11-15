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

- Sport: schema van twee weken en per dag bladeren; kracht en tests als notitie via de telefoon-app
- Toolbox: rekenmachine, stopwatch, tempo berekenen, omrekenen, wereldklok, intervaltimer
- Automatisch volledig verversen om de zoveel schermen (instelbaar)

## Volgende ronde: telefoon en Kobo gelijktrekken (bewaard op 15 nov, nog niet gestart)
Eén centrale plek: de Supabase-tabel `records` die de telefoon-app al gebruikt (per gebruiker
afgeschermd, offline eerst, nieuwste wijziging wint). De Kobo krijgt dezelfde synchronisatie in Lua:
eenmalig inloggen met e-mail en wachtwoord, daarna alleen een sleutel om ingelogd te blijven.

1. Sport: op de Kobo een training afvinken met zwaarte (1-10) en een notitie, plus de ochtend-check-in
   (slaap, benen, energie, rust). Dat zijn bestaande gegevens van de telefoon-app.
2. Notities in beide apps. Typen op de telefoon, lezen en aanvullen op de Kobo (Kobo voegt alleen toe).
3. Gedeelde ontwerpregels (Inter, Material Design-iconen, kaarten, zelfde opbouw en namen);
   de telefoon-app in de nieuwe stijl.
4. Gewoontes, quizvoortgang en dagteksten gedeeld.

Open vragen voor Kees:
- Staat synchroniseren op de telefoon aan (Instellingen, Synchroniseren, Laatste synchronisatie)?
- Telefoon helemaal zwart-wit, of met één rustige accentkleur?
- Nieuws en dagtekst ook op de telefoon, of alleen op de Kobo?
- In Supabase het aanmaken van nieuwe accounts uitzetten voordat het adres en de openbare sleutel in de app komen.

## Daarna
- Leesstatistieken uit de Kobo-database (leestijd, voortgang, markeringen als citaten)
- Focustimer (pomodoro, historie) en dagplanner (taken, prioriteit, weekoverzicht, reflectie)

## Later
- Leren: gespreid herhalen, tips, vandaag in de geschiedenis
- Notities (schermtoetsenbord van KOReader; handschrift kan beter in de notitieboeken van Kobo zelf)

## Bewust niet
- Liggend scherm: alle schermen zijn voor staand ontworpen
- Kleuren en animaties
