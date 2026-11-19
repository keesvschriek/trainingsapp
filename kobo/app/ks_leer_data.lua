-- Inhoud van de leerlijnen: NAVO-alfabet, Defensie, Geschiedenis en Topografie.
-- Bouwt op de vragenbank (data/quiz.json), de landen en de jaartallen die er al zijn.

local D = {}

local NAVO = { "Alfa", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliett", "Kilo", "Lima", "Mike",
    "November", "Oscar", "Papa", "Quebec", "Romeo", "Sierra", "Tango", "Uniform", "Victor", "Whiskey", "X-ray", "Yankee", "Zulu" }
local NAVO_ALT = { J = { "Juliet" }, X = { "Xray", "X ray" }, A = { "Alpha" }, W = { "Whisky" } }
D.NAVO = NAVO

local function norm(s) return require("ks_cards").norm(s) end

local function short(a) return #a <= 24 and not a:find("[,;:]") and select(2, a:gsub("%S+", "")) <= 3 end

local function others(list, self, n)
    local out = {}
    for _, x in ipairs(list) do if x ~= self then out[#out + 1] = x end end
    return out
end

-- NAVO-alfabet -------------------------------------------------------------------------------

local function code(letter) return NAVO[letter:byte() - 64] end

--- Vaste set oefenwoorden (elke keer dezelfde, zodat de voortgang klopt).
local function practiceWords(n, minL, maxL, offset)
    local all = require("ks_puzzles").allWords()
    local out, used = {}, {}
    local i = offset
    while #out < n and i < #all do
        local w = all[i]
        if #w >= minL and #w <= maxL and not used[w] then used[w] = true; out[#out + 1] = w end
        i = i + 37
    end
    return out
end

local function spell(w)
    local parts = {}
    for i = 1, #w do parts[#parts + 1] = code(w:sub(i, i)) end
    return table.concat(parts, " · ")
end

local function navoLine()
    local steps = {}
    local ranges = { { "A tot en met F", 1, 6 }, { "G tot en met L", 7, 12 }, { "M tot en met R", 13, 18 }, { "S tot en met Z", 19, 26 } }
    for _, r in ipairs(ranges) do
        local facts = {}
        local words, letters = {}, {}
        for i = r[2], r[3] do words[#words + 1] = NAVO[i]; letters[#letters + 1] = string.char(64 + i) end
        for i = r[2], r[3] do
            local l = string.char(64 + i)
            facts[#facts + 1] = { id = "navo:" .. l, q = "Welk woord hoort bij de letter " .. l .. "?", a = NAVO[i], alt = NAVO_ALT[l], typeable = true,
                opts = others(words, NAVO[i]), rq = "Bij welke letter hoort " .. NAVO[i] .. "?", ra = l, ropts = others(letters, l) }
            -- later in de leerlijn: afleiders uit het hele alfabet
            facts[#facts].optsAll = others(NAVO, NAVO[i])
        end
        steps[#steps + 1] = { name = r[1], facts = facts }
    end
    -- ontcijferen
    local dec = {}
    local dw = practiceWords(30, 4, 6, 11)
    for _, w in ipairs(dw) do
        local pool = {}
        for _, o in ipairs(dw) do if o ~= w and #o == #w then pool[#pool + 1] = o end end
        dec[#dec + 1] = { id = "navo:dec:" .. w, q = spell(w), a = w, typeable = true, opts = pool, why = "Ontcijferen: de eerste letters achter elkaar." }
    end
    steps[#steps + 1] = { name = "Ontcijferen", facts = dec }
    -- spellen
    local sp = {}
    for _, w in ipairs(practiceWords(30, 4, 6, 23)) do
        -- afleiders: steeds één letter verkeerd gespeld
        local wrong = {}
        for k = 1, 3 do
            local pos = ((k * 7) % #w) + 1
            local c = w:byte(pos) - 64
            local alt = ((c + k * 5 - 1) % 26) + 1
            local parts = {}
            for i = 1, #w do parts[i] = code(w:sub(i, i)) end
            parts[pos] = NAVO[alt]
            wrong[#wrong + 1] = table.concat(parts, " · ")
        end
        sp[#sp + 1] = { id = "navo:sp:" .. w, q = "Spel " .. w .. " met het NAVO-alfabet.", a = spell(w), opts = wrong }
    end
    steps[#steps + 1] = { name = "Spellen", facts = sp }
    return { key = "navo", name = "NAVO-alfabet", icon = "flag", sub = "Per groep letters, dan door elkaar, ontcijferen en spellen", steps = steps }
end

-- Vragenbank: feiten met hetzelfde antwoord samenvoegen ----------------------------------------------

local bank
local function questions()
    if bank then return bank end
    local Q = require("ks_quiz")
    Q.load(require("ks_main").dir)
    bank = Q.visible()
    return bank
end

--- Stap uit vragen (filter), met samengevoegde feiten. skip(q) laat vragen weg.
local COMMON = { twee = true, drie = true, vier = true, links = true, rechts = true, ja = true, nee = true }
local function bankStep(name, filter, byAnswer)
    local facts = {}
    byAnswer = byAnswer or {}
    for _, q in ipairs(questions()) do
        if type(q.a) == "table" and type(q.a[1]) == "string" and filter(q) then
            local key = norm(q.a[1])
            local opts = { q.a[2], q.a[3], q.a[4] }
            local mergeable = #key >= 5 and not key:match("^%d") and not COMMON[key]
            local f = mergeable and byAnswer[key]
            if f then
                f.variants = f.variants or { { q = f.q, opts = f.opts } }
                table.insert(f.variants, { q = q.q, opts = opts })
            else
                f = { id = "b:" .. q.id, q = q.q, a = q.a[1], opts = opts, why = q.why, typeable = short(q.a[1]) }
                if mergeable then byAnswer[key] = f end
                facts[#facts + 1] = f
            end
        end
    end
    return { name = name, facts = facts }
end

local function cat(c) return function(q) return q.cat == c end end

local function defensieLine()
    local isMarch = function(q) return q.cat == "zhkh" and (q.q:find("MARCH") or q.q:find("ZHKH") or q.q:find("TCCC")) end
    local seen = {}
    local steps = {
        bankStep("ZHKH: MARCH en de basis", isMarch, seen),
        bankStep("ZHKH: bloedingen, tourniquet en verder", function(q) return q.cat == "zhkh" and not isMarch(q) end, seen),
        bankStep("AAW: munitie en explosieven", cat("aaw"), seen),
        bankStep("Search", cat("search"), seen),
        bankStep("Wapenleer", cat("wapenleer"), seen),
        bankStep("Exercitie", cat("exercitie"), seen),
        -- NAVO-alfabet zit in een eigen leerlijn
        bankStep("Defensie algemeen", function(q) return q.cat == "defensie" and not q.q:find("spellingsalfabet") end, seen),
    }
    -- MARCH op volgorde
    local march = { { "M", "Massive hemorrhage" }, { "A", "Airway" }, { "R", "Respiration" }, { "C", "Circulation" }, { "H", "Hypothermie en hoofdletsel" } }
    local letters = { "M", "A", "R", "C", "H" }
    for i = 1, #march - 1 do
        table.insert(steps[1].facts, { id = "march:na:" .. march[i][1], q = "MARCH op volgorde: welke letter komt na de " .. march[i][1] .. " (" .. march[i][2] .. ")?",
            a = march[i + 1][1] .. " (" .. march[i + 1][2] .. ")", opts = (function()
                local o = {}
                for _, m in ipairs(march) do if m[1] ~= march[i + 1][1] then o[#o + 1] = m[1] .. " (" .. m[2] .. ")" end end
                return o
            end)() })
    end
    return { key = "defensie", name = "Defensie", icon = "flag_checkered", sub = "ZHKH, AAW, Search, wapenleer, exercitie en algemeen", steps = steps }
end

-- Geschiedenis --------------------------------------------------------------------------------------

local ERAS = {
    { "Oudheid", -3000, 499 }, { "Middeleeuwen", 500, 1499 }, { "Vroegmoderne tijd", 1500, 1799 },
    { "19e eeuw", 1800, 1899 }, { "1900 tot 1945", 1900, 1945 }, { "1946 tot 2000", 1946, 1999 }, { "21e eeuw", 2000, 2100 },
}
local function yearText(y) return y < 0 and (-y .. " v.Chr.") or tostring(y) end

local function historyLine()
    local events = require("ks_history_data").events
    local steps = {}
    for _, era in ipairs(ERAS) do
        local inEra = {}
        for _, e in ipairs(events) do if e[1] >= era[2] and e[1] <= era[3] then inEra[#inEra + 1] = e end end
        table.sort(inEra, function(a, b) return a[1] < b[1] end)
        local names = {}
        for _, e in ipairs(inEra) do names[#names + 1] = e[2] end
        local facts = {}
        for _, e in ipairs(inEra) do
            local y = e[1]
            local span = math.max(4, math.floor((era[3] - era[2]) / 25))
            local opts = {}
            for k = 1, 6 do
                local d = ((k % 2 == 0) and 1 or -1) * (span * math.ceil(k / 2) + (k * 3) % 7)
                local o = y + d
                if o ~= 0 and o ~= y then opts[#opts + 1] = yearText(o) end
            end
            facts[#facts + 1] = { id = "ev:" .. e[2], q = "Wanneer: " .. e[2] .. "?", a = yearText(y), typeable = true, opts = opts, why = e[3],
                rq = "Wat gebeurde er in " .. yearText(y) .. "?", ra = e[2], ropts = others(names, e[2]) }
        end
        if #facts > 0 then steps[#steps + 1] = { name = era[1] .. " (" .. #facts .. " jaartallen)", facts = facts } end
    end
    local seen = {}
    steps[#steps + 1] = bankStep("Vragen: vaderlandse geschiedenis", cat("geschiedenis"), seen)
    steps[#steps + 1] = bankStep("Vragen: wereldgeschiedenis", cat("wereldgeschiedenis"), seen)
    steps[#steps + 1] = bankStep("Vragen: wereldleiders", cat("wereldleiders"), seen)
    return { key = "geschiedenis", name = "Geschiedenis", icon = "history", sub = "Jaartallen per tijdvak, daarna vragen", steps = steps }
end

-- Topografie ----------------------------------------------------------------------------------------

local function topoLine()
    local Q = require("ks_quiz")
    local data = Q.load(require("ks_main").dir)
    local byRegion = {}
    for _, c in ipairs(data.countries or {}) do
        if type(c.cap) == "string" and c.region then
            byRegion[c.region] = byRegion[c.region] or {}
            table.insert(byRegion[c.region], c)
        end
    end
    local steps = {}
    local order = { "Europa", "Noord-Amerika", "Zuid-Amerika", "Azië", "Afrika", "Oceanië" }
    for _, r in ipairs(order) do
        local list = byRegion[r] or {}
        table.sort(list, function(a, b) return a.name < b.name end)
        local caps, names = {}, {}
        for _, c in ipairs(list) do caps[#caps + 1] = c.cap; names[#names + 1] = c.name end
        local parts = #list > 30 and 2 or 1
        local per = math.ceil(#list / parts)
        for p = 1, parts do
            local facts = {}
            for i = (p - 1) * per + 1, math.min(#list, p * per) do
                local c = list[i]
                facts[#facts + 1] = { id = "topo:" .. c.name, q = "Wat is de hoofdstad van " .. c.name .. "?", a = c.cap, alt = c.capAll, typeable = true,
                    opts = others(caps, c.cap), rq = c.cap .. " is de hoofdstad van:", ra = c.name, ropts = others(names, c.name),
                    why = type(c.capAll) == "table" and #c.capAll > 1 and ("Ook goed: " .. table.concat(c.capAll, ", ")) or nil }
            end
            local label = r
            if parts > 1 then label = r .. " " .. p .. " (" .. list[(p - 1) * per + 1].name:sub(1, 1) .. " tot " .. list[math.min(#list, p * per)].name:sub(1, 1) .. ")" end
            steps[#steps + 1] = { name = label, facts = facts }
        end
    end
    -- hoofdstadvragen zitten al in de stappen hierboven
    steps[#steps + 1] = bankStep("Vragen: aardrijkskunde", function(q) return q.cat == "aardrijkskunde" and not q.q:lower():find("hoofdstad") end)
    return { key = "topografie", name = "Topografie", icon = "earth", sub = "Hoofdsteden per werelddeel, beide kanten op", steps = steps }
end

-- Eigen stof (van je telefoon) en uit je leeswerk ---------------------------------------------------

local function yearOpts(a)
    local y = tonumber(a:match("%d+"))
    local bc = a:find("v%.Chr%.") ~= nil
    local out = {}
    if not y then return out end
    for _, d in ipairs({ -1, 1, -3, 4, -10, 12, -25, 30 }) do
        local o = y + d
        if o > 0 then out[#out + 1] = bc and (o .. " v.Chr.") or tostring(o) end
    end
    return out
end

local function ownLine()
    local decks = require("ks_store").get("leer.own", {})
    if #decks == 0 then return nil end
    local steps = {}
    for _, dk in ipairs(decks) do
        local answers = {}
        for _, f in ipairs(dk.facts or {}) do answers[#answers + 1] = f[2] end
        local facts = {}
        for i, f in ipairs(dk.facts or {}) do
            facts[#facts + 1] = { id = "own:" .. dk.id .. ":" .. i, q = f[1], a = f[2], typeable = short(f[2]), opts = others(answers, f[2]) }
        end
        steps[#steps + 1] = { name = dk.name, facts = facts, deck = dk.id }
    end
    return { key = "eigen", name = "Eigen stof", icon = "pencil", sub = "Wat je vanaf je telefoon stuurt als vraag :: antwoord", steps = steps, allOpen = true }
end

local function readLine()
    local read = require("ks_store").get("leer.read", {})
    local list = {}
    for id, r in pairs(read) do if type(r) == "table" and type(r.facts) == "table" and #r.facts > 0 then list[#list + 1] = { id = id, r = r } end end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return (a.r.at or 0) < (b.r.at or 0) end)
    local steps = {}
    for _, e in ipairs(list) do
        local facts = {}
        for i, f in ipairs(e.r.facts) do
            facts[#facts + 1] = { id = "read:" .. e.id .. ":" .. i, q = f[1], a = f[2], typeable = true, opts = yearOpts(f[2]), why = "Uit: " .. (e.r.title or "je leeswerk") }
        end
        steps[#steps + 1] = { name = e.r.title or "Stuk", facts = facts }
    end
    return { key = "gelezen", name = "Uit je leeswerk", icon = "book", sub = "Jaartallen uit stukken die je hebt uitgelezen", steps = steps, allOpen = true }
end

function D.lines()
    local out = { navoLine(), defensieLine(), historyLine(), topoLine() }
    local own, rd = ownLine(), readLine()
    if own then out[#out + 1] = own end
    if rd then out[#out + 1] = rd end
    return out
end

--- Invulkaarten uit een uitgelezen stuk: zinnen met één jaartal, het jaartal wordt het antwoord.
function D.clozeFromDoc(doc, max)
    max = max or 8
    local found, years = {}, {}
    for _, b in ipairs(doc.blocks or {}) do
        if b.k == "p" and type(b.t) == "string" then
            for sent in (b.t .. " "):gmatch("[^%.!?]+[%.!?]%s") do
                sent = sent:gsub("^%s+", ""):gsub("%s+$", "")
                if #sent >= 40 and #sent <= 230 then
                    local ys = {}
                    for y in sent:gmatch("%f[%d](%d%d%d%d?)%f[%D]") do ys[#ys + 1] = y end
                    local y = ys[1]
                    local n = tonumber(y or "")
                    local bc = y and sent:find(y .. " v%.Chr%.") ~= nil
                    -- vier cijfers (1000 tot 2030), of drie cijfers alleen met v.Chr. erachter
                    local isYear = n and ((#y == 4 and n >= 1000 and n <= 2030) or (#y == 3 and bc))
                    if #ys == 1 and isYear and not years[y] then
                        local q = sent:gsub("%f[%d]" .. y .. "%f[%D]", "____", 1)
                        if bc then q = q:gsub("____ v%.Chr%.", "____", 1) end
                        years[y] = true
                        found[#found + 1] = { q, bc and (y .. " v.Chr.") or y }
                    end
                end
            end
        end
    end
    -- verspreid over het stuk kiezen
    if #found <= max then return found end
    local out = {}
    for i = 1, max do out[i] = found[math.floor((i - 1) * #found / max) + 1] end
    return out
end

return D
