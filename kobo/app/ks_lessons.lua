-- Schaaklessen van nul af. Elke stap is één scherm.
-- kind:
--   info    uitleg, eventueel met bord (fen), gemarkeerde velden (marks) en zetten van een stuk (show)
--   tap     tik op één veld (target)
--   reach   tik alle velden aan waar het stuk op `from` heen kan
--   move    doe een zet; goal = lijst met goede zetten, "mate", "any" of "nomate"
--   choice  meerkeuzevraag; het eerste antwoord is goed

local START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
local EMPTY = "8/8/8/8/8/8/8/8 w - - 0 1"

return {
    {
        title = "Het bord en de stukken",
        intro = "64 velden, namen van velden en de beginstand",
        steps = {
            { kind = "info", fen = EMPTY, marks = { "h1" }, text = "Een schaakbord heeft 64 velden: 8 rijen en 8 lijnen. Leg het bord altijd zo neer dat er rechtsonder een wit veld ligt." },
            { kind = "info", fen = EMPTY, marks = { "e4" }, text = "Elk veld heeft een naam. Eerst de letter van de lijn (a tot en met h), dan het nummer van de rij (1 tot en met 8). Het gemarkeerde veld heet e4. De letters en cijfers staan klein langs de rand van het bord." },
            { kind = "tap", fen = EMPTY, target = "d5", text = "Tik op veld d5." },
            { kind = "tap", fen = EMPTY, target = "a8", text = "Tik op veld a8." },
            { kind = "tap", fen = EMPTY, target = "g2", text = "Tik op veld g2." },
            { kind = "choice", fen = EMPTY, marks = { "c6" }, text = "Hoe heet het gemarkeerde veld?", a = { "c6", "c3", "f6", "b6" }, why = "Lijn c, rij 6." },
            { kind = "info", fen = START, text = "Dit is de beginstand. Wit begint altijd. Achteraan staan van links naar rechts: toren, paard, loper, dame, koning, loper, paard, toren. Daarvoor staan acht pionnen." },
            { kind = "choice", fen = START, text = "Op welk veld staat de witte dame aan het begin?", a = { "d1", "e1", "d8", "c1" }, why = "De dame staat op haar eigen kleur: de witte dame op het witte veld d1, de zwarte dame op het zwarte veld d8." },
            { kind = "choice", fen = START, marks = { "e1" }, text = "Welk stuk staat op e1?", a = { "De koning", "De dame", "De loper", "Het paard" }, why = "Naast de dame staat de koning: de witte koning op e1, de zwarte op e8." },
        },
    },
    {
        title = "Hoe de stukken lopen",
        intro = "Toren, loper, dame, koning, paard en pion",
        steps = {
            { kind = "info", fen = "8/8/8/8/3R4/8/8/8 w - - 0 1", show = "d4", text = "De toren gaat recht: vooruit, achteruit en opzij, zo ver als hij wil. De stippen tonen waar hij heen kan." },
            { kind = "reach", fen = "8/8/8/8/2R2p2/8/8/8 w - - 0 1", from = "c4", text = "Tik alle velden aan waar deze toren heen kan. Tik daarna op Klaar.", hint = "Een toren kan een stuk van de tegenstander slaan, maar er niet overheen springen." },
            { kind = "info", fen = "8/8/8/8/3B4/8/8/8 w - - 0 1", show = "d4", text = "De loper gaat schuin, zo ver als hij wil. Daardoor blijft een loper altijd op dezelfde kleur." },
            { kind = "reach", fen = "8/8/8/2P5/8/4B3/8/8 w - - 0 1", from = "e3", text = "Tik alle velden aan waar deze loper heen kan.", hint = "Op een veld met een eigen stuk mag je niet komen, en je kunt er niet overheen." },
            { kind = "info", fen = "8/8/8/8/3Q4/8/8/8 w - - 0 1", show = "d4", text = "De dame is toren en loper in één: recht en schuin, zo ver als ze wil. Het sterkste stuk." },
            { kind = "info", fen = "8/8/8/8/4K3/8/8/8 w - - 0 1", show = "e4", text = "De koning zet één stap, in elke richting. Hij mag nooit op een veld komen dat wordt aangevallen." },
            { kind = "reach", fen = "8/8/8/8/8/8/8/K7 w - - 0 1", from = "a1", text = "Tik alle velden aan waar deze koning heen kan.", hint = "In de hoek heeft de koning maar weinig ruimte." },
            { kind = "info", fen = "8/8/8/8/3N4/8/8/8 w - - 0 1", show = "d4", text = "Het paard springt in een L: twee velden recht en dan één opzij. Het is het enige stuk dat over andere stukken heen springt." },
            { kind = "reach", fen = START, from = "g1", text = "Waar kan het paard op g1 heen in de beginstand?", hint = "Het springt over de pionnen heen." },
            { kind = "info", fen = "8/8/8/8/8/8/4P3/8 w - - 0 1", show = "e2", text = "De pion gaat één veld rechtdoor. Vanaf zijn beginveld mag hij ook twee velden. Hij gaat nooit terug." },
            { kind = "reach", fen = "8/8/8/2pbp3/3P4/8/8/8 w - - 0 1", from = "d4", text = "Een pion slaat anders dan hij loopt: schuin vooruit. Waar kan deze pion heen?", hint = "Rechtdoor staat een stuk in de weg. Slaan gaat schuin." },
            { kind = "choice", text = "Als een pion 1 punt waard is, wat is een toren dan ongeveer waard?", a = { "5", "3", "9", "2" }, why = "Paard en loper zijn 3, een toren 5 en een dame 9. De koning is onbetaalbaar: verlies je hem, dan verlies je de partij." },
        },
    },
    {
        title = "Slaan, schaak en mat",
        intro = "Stukken winnen, schaak geven en het doel van het spel",
        steps = {
            { kind = "info", text = "Je slaat een stuk door op het veld ervan te gaan. Het geslagen stuk gaat van het bord. Je mag alleen stukken van de tegenstander slaan." },
            { kind = "move", fen = "q3k3/8/8/8/R7/8/8/4K3 w - - 0 1", goal = { "a4a8" }, text = "Wit is aan zet. Sla de zwarte dame.", ok = "Goed. Een dame is 9 punten waard." },
            { kind = "move", fen = "7k/8/3r4/6p1/4N3/8/8/7K w - - 0 1", goal = { "e4d6" }, text = "Het paard kan twee stukken slaan. Sla het stuk dat het meest waard is.", ok = "Goed: de toren is 5 punten, de pion maar 1.", hint = "Een toren is meer waard dan een pion." },
            { kind = "info", fen = "4k3/8/8/8/8/8/8/4R1K1 b - - 0 1", marks = { "e1", "e8" }, text = "Valt een stuk de koning aan, dan staat de koning schaak. Je moet daar meteen iets aan doen. Er zijn drie manieren: de aanvaller slaan, iets ertussen zetten, of de koning wegzetten." },
            { kind = "move", fen = "4k3/8/8/8/7b/8/8/4R1K1 b - - 0 1", goal = { "h4e1" }, text = "Zwart staat schaak. Sla de toren die schaak geeft.", hint = "Kijk naar de zwarte loper." },
            { kind = "move", fen = "4k3/8/8/8/8/8/2b5/4R1K1 b - - 0 1", goal = { "c2e4" }, text = "Zwart staat weer schaak en kan de toren niet slaan. Zet een stuk tussen de toren en de koning.", hint = "De loper kan een veld op de e-lijn bereiken." },
            { kind = "move", fen = "4k3/8/8/8/8/8/8/4R1K1 b - - 0 1", goal = "any", text = "Nu kan zwart alleen de koning wegzetten. Zet de koning op een veilig veld.", ok = "Goed. De koning staat niet meer op de e-lijn." },
            { kind = "info", fen = "3R2k1/5ppp/8/8/8/8/8/6K1 b - - 0 1", marks = { "d8", "g8" }, text = "Kan de koning op geen enkele manier uit schaak komen, dan staat hij mat. De partij is dan afgelopen. Hier staat zwart mat: de eigen pionnen zitten de koning in de weg." },
            { kind = "move", fen = "6k1/5ppp/8/8/8/8/8/3R2K1 w - - 0 1", goal = "mate", text = "Geef mat in één zet.", hint = "De achterste rij van zwart is niet beschermd." },
            { kind = "move", fen = "7k/8/6K1/8/8/8/8/1Q6 w - - 0 1", goal = "mate", text = "Geef mat met de dame.", hint = "De witte koning dekt al de velden g7 en h7." },
            { kind = "info", fen = "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", text = "Let op: staat de speler aan zet niet schaak, maar kan hij geen enkele zet doen, dan is het pat. Pat is remise: gelijkspel. Hier is zwart aan zet en is het pat. Pas daar op als je voorstaat." },
            { kind = "choice", fen = "k7/8/1Q6/8/8/8/8/7K b - - 0 1", text = "Zwart is aan zet. Wat is dit?", a = { "Pat", "Mat", "Schaak", "Niets bijzonders" }, why = "De zwarte koning staat niet schaak, maar elk veld waar hij heen kan wordt aangevallen. En zwart heeft geen andere stukken." },
        },
    },
    {
        title = "Bijzondere zetten",
        intro = "Rokeren, promotie en en passant",
        steps = {
            { kind = "info", fen = "r3k2r/pppq1ppp/2npbn2/2b1p3/2B1P3/2NPBN2/PPPQ1PPP/R3K2R w KQkq - 0 1", text = "Bij rokeren zet je in één beurt de koning twee velden opzij, en springt de toren over de koning heen. Het mag alleen als koning en toren nog niet hebben gezet, er niets tussen staat, en de koning niet schaak staat en niet over of op een aangevallen veld komt." },
            { kind = "move", fen = "r3k2r/pppq1ppp/2npbn2/2b1p3/2B1P3/2NPBN2/PPPQ1PPP/R3K2R w KQkq - 0 1", goal = { "e1g1" }, text = "Rokeer kort: tik op de koning en dan op g1.", ok = "Goed. De toren staat nu op f1." },
            { kind = "move", fen = "r3k2r/pppq1ppp/2npbn2/2b1p3/2B1P3/2NPBN2/PPPQ1PPP/R3K2R w KQkq - 0 1", goal = { "e1c1" }, text = "Rokeer nu lang: de koning gaat naar c1.", ok = "Goed. De toren staat nu op d1." },
            { kind = "choice", fen = "4kr2/8/8/8/8/8/8/4K2R w K - 0 1", text = "Mag wit hier kort rokeren?", a = { "Nee, de koning zou over een aangevallen veld gaan", "Ja", "Nee, de toren heeft al gezet", "Nee, de koning staat schaak" }, why = "De zwarte toren valt f1 aan. Daar moet de koning overheen." },
            { kind = "info", fen = "8/1P5k/8/8/8/8/8/K7 w - - 0 1", text = "Komt een pion op de laatste rij, dan wordt hij een ander stuk naar keuze: dame, toren, loper of paard. Dat heet promotie. Bijna altijd kies je een dame. In deze app wordt het automatisch een dame." },
            { kind = "move", fen = "8/1P5k/8/8/8/8/8/K7 w - - 0 1", goal = { "b7b8" }, text = "Promoveer de pion.", ok = "Goed. De pion is een dame geworden." },
            { kind = "info", fen = "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2", marks = { "d5", "e5" }, text = "En passant: zet een pion twee velden vooruit en komt hij naast een pion van de tegenstander, dan mag die hem slaan alsof hij maar één veld had gezet. Dat mag alleen direct in de volgende zet." },
            { kind = "move", fen = "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2", goal = { "e5d6" }, text = "Zwart speelde net d7-d5. Sla en passant.", hint = "Je pion gaat schuin naar d6 en neemt de pion op d5 mee.", ok = "Goed. De pion op d5 is van het bord." },
        },
    },
    {
        title = "Eenvoudige matpatronen",
        intro = "Patronen die je steeds weer tegenkomt",
        steps = {
            { kind = "info", fen = "3R2k1/5ppp/8/8/8/8/8/6K1 b - - 0 1", text = "Het achterste-rij-mat: de koning zit opgesloten achter zijn eigen pionnen. Een toren of dame op de achterste rij is dan genoeg." },
            { kind = "move", fen = "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", goal = "mate", text = "Geef mat in één zet.", hint = "Gebruik de toren." },
            { kind = "move", fen = "k7/8/1K6/8/8/8/8/7Q w - - 0 1", goal = "mate", text = "Dame en koning werken samen. Geef mat in één zet.", hint = "De witte koning dekt a7 en b7 al. Er zijn twee manieren." },
            { kind = "move", fen = "6k1/R7/8/8/8/8/8/1R4K1 w - - 0 1", goal = "mate", text = "Twee torens: de ene sluit een rij af, de andere geeft mat.", hint = "De toren op a7 dekt de zevende rij al." },
            { kind = "move", fen = "6rk/6pp/8/6N1/8/8/8/6K1 w - - 0 1", goal = "mate", text = "Een paard kan ook mat geven, als de koning ingesloten zit door eigen stukken.", hint = "Welk veld valt h8 aan?" },
            { kind = "move", fen = "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4", goal = "mate", text = "Een bekende val in de opening. Wit is aan zet. Geef mat.", hint = "Kijk naar f7: alleen de koning verdedigt dat veld." },
        },
    },
    {
        title = "Goed beginnen: de opening",
        intro = "Drie vuistregels en een val om te vermijden",
        steps = {
            { kind = "info", fen = START, marks = { "d4", "e4", "d5", "e5" }, text = "Drie vuistregels voor de opening. Eén: zet pionnen in het centrum (de vier gemarkeerde velden). Twee: breng paarden en lopers snel naar voren. Drie: rokeer vroeg, zodat je koning veilig staat." },
            { kind = "choice", fen = START, text = "Welke eerste zet past het best bij de vuistregels?", a = { "e2-e4", "a2-a4", "h2-h4", "Pg1-h3" }, why = "e4 neemt het centrum in en maakt de weg vrij voor dame en loper. Een paard aan de rand (h3) staat minder actief." },
            { kind = "choice", text = "Waarom brengt je je dame meestal niet heel vroeg naar voren?", a = { "Ze wordt makkelijk aangevallen, waardoor je tijd verliest", "Ze mag pas na de tiende zet bewegen", "Dan kun je niet meer rokeren", "De dame kan in de opening niet slaan" }, why = "Elke keer dat de dame moet vluchten, ontwikkelt de tegenstander een stuk." },
            { kind = "info", fen = "r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 3 3", marks = { "f7", "h5", "c4" }, text = "Het herdersmat: wit dreigt met dame en loper samen op f7 mat te geven. Zwart is aan zet en moet dat voorkomen." },
            { kind = "move", fen = "r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 3 3", goal = "nomate", prefer = { "g7g6", "d8e7", "d8f6" }, text = "Zwart is aan zet. Voorkom het mat.", ok = "Goed, het mat is voorkomen.", better = "Dat werkt, maar g7-g6 (valt meteen de dame aan) of De7 is sterker." },
            { kind = "choice", text = "Wat is het voordeel van rokeren?", a = { "Je koning staat veiliger en je toren komt in het spel", "Je krijgt een extra zet", "Je mag daarna een stuk terugzetten", "Je pionnen kunnen daarna niet meer worden geslagen" }, why = "In het midden staat de koning open en bloot. Na rokeren staat hij achter pionnen, en de toren komt naar het midden." },
        },
    },
    {
        title = "Eerste tactieken",
        intro = "Vork, penning en aftrekschaak",
        steps = {
            { kind = "info", text = "Een vork is een aanval op twee stukken tegelijk. De tegenstander kan er maar één redden. Paarden zijn hier heel goed in." },
            { kind = "move", fen = "r3k3/8/8/3N4/8/8/8/4K3 w - - 0 1", goal = { "d5c7" }, text = "Speel een paardvork op koning en toren.", hint = "Zoek een veld waarvan het paard zowel e8 als a8 aanvalt.", ok = "Goed. Zwart moet de koning redden en verliest de toren." },
            { kind = "move", fen = "4k3/8/8/2n1b3/8/3P4/8/4K3 w - - 0 1", goal = { "d3d4" }, text = "Ook een pion kan een vork geven. Vind hem.", ok = "Goed. De pion valt paard en loper tegelijk aan." },
            { kind = "info", fen = "4k3/8/2n5/1B6/8/8/8/4K3 b - - 0 1", marks = { "b5", "c6", "e8" }, text = "Een penning: een stuk kan niet weg, omdat er een belangrijker stuk achter staat. Hier staat het zwarte paard tussen de loper en de koning." },
            { kind = "choice", fen = "4k3/8/2n5/1B6/8/8/8/4K3 b - - 0 1", text = "Mag het zwarte paard op c6 een zet doen?", a = { "Nee, dan staat de eigen koning schaak", "Ja, overal heen", "Alleen naar voren", "Alleen als het een stuk slaat" }, why = "Een zet waarbij je eigen koning schaak komt te staan, is nooit toegestaan." },
            { kind = "info", text = "Aftrekschaak: je zet een stuk weg en daardoor geeft een ander stuk schaak. Het stuk dat je wegzet, kan intussen zelf iets aanvallen. De tegenstander moet eerst het schaak oplossen." },
            { kind = "move", fen = "4k3/8/8/1q6/4N3/8/8/4R1K1 w - - 0 1", goal = { "e4c3", "e4d6" }, text = "Speel aftrekschaak en val tegelijk de dame aan.", hint = "Zet het paard weg van de e-lijn, naar een veld dat b5 aanvalt.", ok = "Goed. De toren geeft schaak en het paard valt de dame aan. Na het schaak sla je de dame." },
        },
    },
}
