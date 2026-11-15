import { COUNTRIES, byC3, capitalAnswers, countryAnswers, type Region } from './geo/countries';

// Lijstjes à la JetPunk: zo veel mogelijk noemen binnen de tijd.

export interface ListItem { answers: string[]; hint?: string; show: string }
export interface ListQuiz { key: string; title: string; group: string; seconds: number; items: ListItem[]; note?: string }

const simple = (words: string[], extra: Record<string, string[]> = {}): ListItem[] => words.map(w => ({ answers: [w, ...(extra[w] ?? [])], show: w }));
const pairs = (list: [string, string, string[]?][]): ListItem[] => list.map(([hint, ans, alt]) => ({ hint, answers: [ans, ...(alt ?? [])], show: ans }));

const regionList = (r: Region): ListItem[] => COUNTRIES.filter(c => c.region === r).map(c => ({ answers: countryAnswers(c), show: c.name }));
const borderList = (c3: string): ListItem[] => (byC3.get(c3)?.borders ?? []).map(b => byC3.get(b)).filter(Boolean).map(c => ({ answers: countryAnswers(c!), show: c!.name }));
const capitalsOf = (r: Region): ListItem[] => COUNTRIES.filter(c => c.region === r).map(c => ({ hint: c.name, answers: capitalAnswers(c), show: c.cap[0] }));

export const LISTS: ListQuiz[] = [
  { key: 'provincies', title: 'De 12 provincies van Nederland', group: 'Nederland', seconds: 120, items: simple(['Groningen', 'Friesland', 'Drenthe', 'Overijssel', 'Flevoland', 'Gelderland', 'Utrecht', 'Noord-Holland', 'Zuid-Holland', 'Zeeland', 'Noord-Brabant', 'Limburg'], { Friesland: ['Fryslân', 'Fryslan'], 'Noord-Brabant': ['Brabant'] }) },
  { key: 'provhoofdsteden', title: 'Hoofdsteden van de provincies', group: 'Nederland', seconds: 150, items: pairs([['Groningen', 'Groningen'], ['Friesland', 'Leeuwarden'], ['Drenthe', 'Assen'], ['Overijssel', 'Zwolle'], ['Flevoland', 'Lelystad'], ['Gelderland', 'Arnhem'], ['Utrecht', 'Utrecht'], ['Noord-Holland', 'Haarlem'], ['Zuid-Holland', 'Den Haag', ["'s-Gravenhage", 's-Gravenhage']], ['Zeeland', 'Middelburg'], ['Noord-Brabant', "'s-Hertogenbosch", ['Den Bosch', 's-Hertogenbosch']], ['Limburg', 'Maastricht']]) },
  { key: 'waddeneilanden', title: 'De vijf bewoonde Nederlandse Waddeneilanden', group: 'Nederland', seconds: 60, items: simple(['Texel', 'Vlieland', 'Terschelling', 'Ameland', 'Schiermonnikoog']) },
  { key: 'premiers', title: 'Nederlandse premiers sinds 1945 (achternaam)', group: 'Nederland', seconds: 240, items: simple(['Schermerhorn', 'Beel', 'Drees', 'De Quay', 'Marijnen', 'Cals', 'Zijlstra', 'De Jong', 'Biesheuvel', 'Den Uyl', 'Van Agt', 'Lubbers', 'Kok', 'Balkenende', 'Rutte', 'Schoof', 'Jetten'], { 'De Quay': ['Quay'], 'De Jong': ['Jong'], 'Den Uyl': ['Den Uijl', 'Uyl'], 'Van Agt': ['Agt'] }), note: 'Stand november 2026.' },
  { key: 'usa', title: 'Amerikaanse presidenten sinds 1945 (achternaam)', group: 'Wereld', seconds: 180, items: simple(['Truman', 'Eisenhower', 'Kennedy', 'Johnson', 'Nixon', 'Ford', 'Carter', 'Reagan', 'Bush', 'Clinton', 'Obama', 'Trump', 'Biden']), note: 'Bush en Trump tellen één keer.' },
  { key: 'g7', title: 'De landen van de G7', group: 'Wereld', seconds: 90, items: ['USA', 'CAN', 'GBR', 'FRA', 'DEU', 'ITA', 'JPN'].map(c => ({ answers: countryAnswers(byC3.get(c)!), show: byC3.get(c)!.name })) },
  { key: 'vnvr', title: 'Permanente leden van de VN-Veiligheidsraad', group: 'Wereld', seconds: 60, items: ['USA', 'RUS', 'CHN', 'GBR', 'FRA'].map(c => ({ answers: [...countryAnswers(byC3.get(c)!), ...(c === 'GBR' ? ['Engeland', 'Groot-Brittannië', 'Groot Brittannie', 'UK'] : c === 'USA' ? ['Amerika', 'VS', 'USA'] : [])], show: byC3.get(c)!.name })) },
  { key: 'eu', title: 'De 27 lidstaten van de EU', group: 'Wereld', seconds: 300, items: COUNTRIES.filter(c => c.eu).map(c => ({ answers: countryAnswers(c), show: c.name })) },
  { key: 'buren-de', title: 'Buurlanden van Duitsland', group: 'Wereld', seconds: 90, items: borderList('DEU') },
  { key: 'buren-fr', title: 'Buurlanden van Frankrijk (vasteland Europa)', group: 'Wereld', seconds: 90, items: borderList('FRA').filter(i => !['Brazilië', 'Suriname'].includes(i.show)) },
  { key: 'buren-cn', title: 'Buurlanden van China', group: 'Wereld', seconds: 240, items: borderList('CHN') },
  { key: 'land-eu', title: 'Alle landen van Europa', group: 'Landen per werelddeel', seconds: 600, items: regionList('Europa') },
  { key: 'land-za', title: 'Alle landen van Zuid-Amerika', group: 'Landen per werelddeel', seconds: 180, items: regionList('Zuid-Amerika') },
  { key: 'land-na', title: 'Alle landen van Noord- en Midden-Amerika en de Caraïben', group: 'Landen per werelddeel', seconds: 420, items: regionList('Noord-Amerika') },
  { key: 'land-af', title: 'Alle landen van Afrika', group: 'Landen per werelddeel', seconds: 720, items: regionList('Afrika') },
  { key: 'land-as', title: 'Alle landen van Azië', group: 'Landen per werelddeel', seconds: 720, items: regionList('Azië') },
  { key: 'land-oc', title: 'Alle landen van Oceanië', group: 'Landen per werelddeel', seconds: 180, items: regionList('Oceanië') },
  { key: 'cap-eu', title: 'Hoofdsteden van Europa', group: 'Hoofdsteden', seconds: 600, items: capitalsOf('Europa') },
  { key: 'cap-za', title: 'Hoofdsteden van Zuid-Amerika', group: 'Hoofdsteden', seconds: 240, items: capitalsOf('Zuid-Amerika') },
  { key: 'cap-af', title: 'Hoofdsteden van Afrika', group: 'Hoofdsteden', seconds: 900, items: capitalsOf('Afrika') },
  { key: 'cap-as', title: 'Hoofdsteden van Azië', group: 'Hoofdsteden', seconds: 900, items: capitalsOf('Azië') },
  { key: 'navo-alfabet', title: 'Het NAVO-spellingsalfabet', group: 'Defensie', seconds: 180, items: pairs([['A', 'Alfa', ['Alpha']], ['B', 'Bravo'], ['C', 'Charlie'], ['D', 'Delta'], ['E', 'Echo'], ['F', 'Foxtrot'], ['G', 'Golf'], ['H', 'Hotel'], ['I', 'India'], ['J', 'Juliett', ['Juliet']], ['K', 'Kilo'], ['L', 'Lima'], ['M', 'Mike'], ['N', 'November'], ['O', 'Oscar'], ['P', 'Papa'], ['Q', 'Quebec'], ['R', 'Romeo'], ['S', 'Sierra'], ['T', 'Tango'], ['U', 'Uniform'], ['V', 'Victor'], ['W', 'Whiskey', ['Whisky']], ['X', 'X-ray', ['Xray']], ['Y', 'Yankee'], ['Z', 'Zulu']]) },
  { key: 'march', title: 'MARCH plus O: waar staan de letters voor?', group: 'Defensie', seconds: 75, items: pairs([['M', 'Massive hemorrhage', ['Massive bleeding', 'Massief bloedverlies', 'Massive haemorrhage', 'Massive hemorrhaging']], ['A', 'Airway', ['Luchtweg']], ['R', 'Respiration', ['Ademhaling', 'Breathing']], ['C', 'Circulation', ['Circulatie', 'Bloedsomloop']], ['H', 'Hypothermia', ['Hypothermie', 'Head injury', 'Onderkoeling', 'Head']], ['O', 'Other injuries', ['Overige letsels', 'Overige verwondingen', 'Other', 'Andere letsels']]]), note: 'H mag ook "head injury" zijn.' },
  { key: 'exercitie', title: 'Exercitie: wat is het uitvoeringscommando?', group: 'Defensie', seconds: 120, items: pairs([['Afdeling, geeft...', 'Acht'], ['Op de plaats...', 'Rust'], ['Rechts...', 'Om'], ['Links...', 'Om'], ['Rechtsom...', 'Keert'], ['Voorwaarts...', 'Mars'], ['Afdeling...', 'Halt'], ['Naar rechts...', 'Richten'], ['Hoofd...', 'Front'], ['Brengt...', 'Groet'], ['In de houding...', 'Staat'], ['In, gerukt...', 'Mars'], ['Looppas...', 'Mars'], ['Markeert de pas...', 'Mars'], ['Presenteert...', 'Geweer'], ['Zet af...', 'Geweer']]), note: 'Dubbele antwoorden typ je zo vaak als ze voorkomen.' },
  { key: '5c', title: 'De 5 C’s bij een verdacht explosief', group: 'Defensie', seconds: 60, items: simple(['Confirm', 'Clear', 'Call', 'Cordon', 'Control'], { Call: ['Check'] }), note: 'Er zijn varianten; soms staat Check in plaats van Call.' },
  { key: 'officiersrangen', title: 'Officiersrangen van de Landmacht, van laag naar hoog', group: 'Defensie', seconds: 120, items: simple(['Tweede luitenant', 'Eerste luitenant', 'Kapitein', 'Majoor', 'Luitenant-kolonel', 'Kolonel', 'Brigadegeneraal', 'Generaal-majoor', 'Luitenant-generaal', 'Generaal']) },
  { key: 'planeten', title: 'De acht planeten van ons zonnestelsel', group: 'Wetenschap', seconds: 60, items: simple(['Mercurius', 'Venus', 'Aarde', 'Mars', 'Jupiter', 'Saturnus', 'Uranus', 'Neptunus']) },
  { key: 'edelgassen', title: 'De edelgassen (stabiel)', group: 'Wetenschap', seconds: 60, items: simple(['Helium', 'Neon', 'Argon', 'Krypton', 'Xenon', 'Radon']) },
  { key: 'regenboog', title: 'De kleuren van de regenboog', group: 'Wetenschap', seconds: 45, items: simple(['Rood', 'Oranje', 'Geel', 'Groen', 'Blauw', 'Indigo', 'Violet'], { Violet: ['Paars'] }) },
  { key: 'tienkamp', title: 'De onderdelen van de tienkamp', group: 'Sport', seconds: 120, items: simple(['100 meter', 'Verspringen', 'Kogelstoten', 'Hoogspringen', '400 meter', '110 meter horden', 'Discuswerpen', 'Polsstokhoogspringen', 'Speerwerpen', '1500 meter'], { '100 meter': ['100m', '100 m'], '400 meter': ['400m', '400 m'], '110 meter horden': ['110m horden', 'horden'], '1500 meter': ['1500m', '1500 m'], Polsstokhoogspringen: ['Polsstok'] }) },
  { key: 'evangelisten', title: 'De vier evangelisten', group: 'Cultuur', seconds: 45, items: simple(['Matteüs', 'Marcus', 'Lucas', 'Johannes'], { 'Matteüs': ['Mattheus', 'Matthew', 'Mattheüs'] }) },
];
