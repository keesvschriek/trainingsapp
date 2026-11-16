# Trainingsapp

Persoonlijke app voor mijn trainingsschema. Doelen: 3000 m op de Cooper-test, 10 km onder 43 minuten en een fitte bouw.
Android-app (APK) en webversie, werkt offline, haalt Garmin-activiteiten op via intervals.icu en synchroniseert optioneel via Supabase.

App: https://keesvschriek.github.io/trainingsapp/

## Wat zit erin

- **Vandaag**: training van de dag met uitgeschreven oefeningen, afvinken, lopen en kracht loggen, testresultaten invullen, teller voor pull-ups tussendoor.
- **Schema**: blokken van 8 weken (blok 1: 9 weken), elk met een testweek. Loopt door zonder einddatum. Defensie, wedstrijden, vakantie of ziekte passen het schema automatisch aan.
- **Logboek**: alle trainingen per week, ophalen uit Garmin, zelf toevoegen en bewerken.
- **Voortgang**: looptijd en langste loop per week tegen het plan, doelen, metingen (Cooper, 10 km, buikomtrek, gewicht, pull-ups, press).
- **Instellingen**: intervals.icu, synchronisatie, back-up als JSON.

## 1. Publiceren (eenmalig)

1. Ga in deze repository naar **Settings > Pages**.
2. Kies bij **Source**: **GitHub Actions**.
3. Ga naar **Actions** en start de workflow **Publiceren op GitHub Pages** opnieuw als hij al was mislukt.

Na 1 tot 2 minuten staat de app op https://keesvschriek.github.io/trainingsapp/. Elke push naar `main` publiceert automatisch een nieuwe versie.

## 2. Android-app installeren

Bij elke push bouwt GitHub automatisch een nieuwe APK (workflow **Android-app bouwen**, duurt ongeveer 5 minuten).

1. Open op je telefoon: https://github.com/keesvschriek/trainingsapp/releases/latest/download/trainingsapp.apk
2. Open het gedownloade bestand. Android vraagt eenmalig of Chrome apps mag installeren: zet dat aan.
3. Kies **Installeren**. Krijg je een melding van Play Protect, kies dan **Toch installeren**: de app komt niet uit de Play Store, daarom die waarschuwing.

**Updates**: de app meldt bovenaan als er een nieuwe versie is. Tik erop, download en installeer over de oude heen. Je gegevens blijven staan, omdat elke versie met dezelfde sleutel is ondertekend (`android-assets/debug.keystore`).

De webversie op GitHub Pages blijft bestaan, handig op je laptop.

## 3. Garmin koppelen via intervals.icu

1. Maak een gratis account op intervals.icu en koppel Garmin Connect (Settings > Connections).
2. Settings > helemaal onderaan **Developer Settings** > maak een API-sleutel.
3. In de app: **Instellingen > Garmin via intervals.icu**, plak de sleutel, laat Athlete-ID op `0` staan, tik op **Testen en ophalen**.

De app haalt bij openen automatisch nieuwe activiteiten op (hooguit eens per uur).

In de Android-app werkt dit direct. **Alleen in de webversie** kan een CORS-fout komen, omdat intervals.icu geen verzoeken vanuit de browser toestaat. Oplossing (gratis, 5 minuten):

1. Maak een account op dash.cloudflare.com > **Workers & Pages** > **Create** > **Worker**.
2. Plak de code uit `worker/intervals-proxy.js`, pas `ALLOWED_ORIGIN` aan naar `https://keesvschriek.github.io` en klik **Deploy**.
3. Vul de Worker-URL in bij **Proxy-URL** in de app.

## 4. Synchroniseren via Supabase (optioneel)

1. Open je Supabase-project > **SQL Editor** > **New query**, plak de inhoud van `supabase/schema.sql` en klik **Run**.
2. **Authentication > URL Configuration**: zet **Site URL** op `https://keesvschriek.github.io/trainingsapp/`.
3. **Project Settings > API** (of **Data API**): kopieer de **Project URL** en de **anon** of **publishable** key.
4. In de app: **Instellingen > Synchroniseren**, vul beide in, kies **Account aanmaken**, bevestig de mail en log in.
5. Op je laptop: open dezelfde link, vul dezelfde gegevens in en log in. Alles komt binnen.

Makkelijker: zet de Project URL en de anon key als repository-secrets `SUPABASE_URL` en `SUPABASE_ANON_KEY` (Settings > Secrets and variables > Actions). De builds nemen ze dan mee en de app vraagt alleen nog je e-mail en wachtwoord. Maak je account dan in Supabase bij Authentication > Users > Add user (met Auto confirm) en zet daarna Allow new users to sign up uit.

De anon/publishable key mag in de app staan: de tabel is afgeschermd met Row Level Security, dus alleen jij ziet je eigen gegevens.

Let op: een gratis Supabase-project wordt gepauzeerd na een week zonder gebruik. Je gegevens blijven bewaard en je zet het project terug met **Resume project** in het dashboard. De app werkt intussen gewoon door op je telefoon.

## Ontwikkelen

```bash
npm install
npm run dev      # lokaal op http://localhost:5173
npm test         # tests van de schema-logica
npm run build    # productie-build in dist/
```

Techniek: React, TypeScript, Vite, Capacitor (Android), vite-plugin-pwa, Dexie (IndexedDB), Recharts, Supabase.

Het schema zelf staat in `src/plan.ts`. Weken, minuten en krachtoefeningen pas je daar aan.
