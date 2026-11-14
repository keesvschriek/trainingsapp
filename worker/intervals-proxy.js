// Kleine gratis proxy voor intervals.icu, alleen nodig als de app "CORS" meldt.
// Zet dit in een Cloudflare Worker (gratis): dash.cloudflare.com > Workers > Create > plak deze code > Deploy.
// Vul daarna de Worker-URL in bij Instellingen > intervals.icu > Proxy-URL.
//
// De proxy bewaart niets. Hij stuurt je verzoek door en zet de juiste headers terug.
// ALLOWED_ORIGIN: het adres van je app, zodat andere sites je proxy niet kunnen gebruiken.

const ALLOWED_ORIGIN = 'https://JOUW-GITHUB-NAAM.github.io';

export default {
  async fetch(request) {
    const origin = request.headers.get('Origin') || '';
    const cors = {
      'Access-Control-Allow-Origin': origin === ALLOWED_ORIGIN || origin.startsWith('http://localhost') ? origin : ALLOWED_ORIGIN,
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Accept',
      'Access-Control-Max-Age': '86400',
    };
    if (request.method === 'OPTIONS') return new Response(null, { headers: cors });

    const url = new URL(request.url);
    if (!url.pathname.startsWith('/api/v1/')) return new Response('Niet gevonden', { status: 404, headers: cors });

    const upstream = await fetch('https://intervals.icu' + url.pathname + url.search, {
      headers: {
        Authorization: request.headers.get('Authorization') || '',
        Accept: 'application/json',
        'User-Agent': 'Mozilla/5.0 (trainingsapp)',
      },
    });
    const body = await upstream.text();
    return new Response(body, {
      status: upstream.status,
      headers: { ...cors, 'Content-Type': upstream.headers.get('Content-Type') || 'application/json' },
    });
  },
};
