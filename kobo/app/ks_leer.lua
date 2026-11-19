-- Leerlijnen: een onderwerp in stappen, van basis naar alles door elkaar.
-- Per feit opbouwend: eerst meerkeuze, dan andersom, dan zelf typen (of zelf ophalen bij lange antwoorden).
-- Herhaling op tijd: een feit dat goed ging komt pas na 1, 2, 4, 8, 16 en 32 dagen terug.
-- Vragen met hetzelfde antwoord zijn één feit; in één ronde komt een antwoord maar één keer voor.

local UIManager = require("ui/uimanager")
local UI = require("ks_ui")
local Store = require("ks_store")

local L = {}

L.WAIT = { 1, 2, 4, 8, 16, 32 }
L.NEW = 6 -- nieuwe feiten per ronde
L.ROUND = 12 -- vragen per ronde (zonder de herkansingen)
L.MASTER = 3 -- vanaf dit vak telt een feit als beheerst
L.UNLOCK = 0.8 -- volgende stap open als 80% van de vorige beheerst is

local function today() local t = os.date("*t"); return math.floor(os.time{ year = t.year, month = t.month, day = t.day, hour = 12 } / 86400) end
local function shuffle(t) for i = #t, 2, -1 do local j = math.random(i); t[i], t[j] = t[j], t[i] end return t end
L.shuffle = shuffle

-- Antwoorden vergelijken (zelfde als bij de leerkaarten)
local norm = require("ks_cards").norm
local function lev(a, b)
    if #a > 40 or #b > 40 then return a == b and 0 or 99 end
    local prev = {}
    for j = 0, #b do prev[j] = j end
    for i = 1, #a do
        local cur = { [0] = i }
        for j = 1, #b do cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a:byte(i) == b:byte(j) and 0 or 1)) end
        prev = cur
    end
    return prev[#b]
end
function L.check(answers, typed)
    local t = norm(typed)
    if t == "" then return false end
    for _, o in ipairs(answers) do
        local n = norm(o)
        if n == t then return true end
        if lev(n, t) <= (#n >= 10 and 2 or (#n >= 5 and 1 or 0)) then return true end
    end
    return false
end

-- Opslag -------------------------------------------------------------------------------

local function boxes() return Store.get("leer.box", {}) end
function L.box(id) return boxes()[id] end

function L.grade(fact, ok, unsure)
    local bx, t = boxes(), today()
    local b = bx[fact.id] or { b = 0, n = 0 }
    if ok and not unsure then b.b = math.min(#L.WAIT, b.b + 1)
    elseif ok and unsure then b.b = math.max(1, b.b)
    else b.b = 1 end
    b.n = (b.n or 0) + 1
    b.d = t + L.WAIT[math.max(1, b.b)]
    b.at = os.time()
    bx[fact.id] = b
    Store.set("leer.box", bx)
    local st = Store.get("leer.stats", {})
    st[ok and "goed" or "fout"] = (st[ok and "goed" or "fout"] or 0) + 1
    Store.set("leer.stats", st)
end

-- Leerlijnen en stappen ------------------------------------------------------------------

local cache = {}
function L.lines()
    if cache.lines then return cache.lines end
    cache.lines = require("ks_leer_data").lines()
    return cache.lines
end
function L.reset() cache.lines = nil end

--- Een uitgelezen stuk: jaartallen worden invulkaarten in "Uit je leeswerk". Geeft het aantal nieuwe kaarten.
function L.fromDoc(doc)
    if not doc or not (doc.id or doc.title) then return 0 end
    local id = tostring(doc.id or doc.title):gsub("[^%w%-]", ""):sub(1, 60)
    local read = Store.get("leer.read", {})
    if read[id] then return 0 end
    local facts = require("ks_leer_data").clozeFromDoc(doc)
    read[id] = { title = doc.title, at = os.time(), facts = facts }
    Store.set("leer.read", read)
    L.reset()
    return #facts
end

--- Eigen stof van de telefoon: regels "vraag :: antwoord" (of met een tab ertussen).
function L.parseOwn(text)
    local facts = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local q, a = line:match("^%s*(.-)%s*::%s*(.-)%s*$")
        if not q then q, a = line:match("^%s*([^\t]-)%s*\t%s*(.-)%s*$") end
        if q and a and q ~= "" and a ~= "" then facts[#facts + 1] = { q, a } end
    end
    return facts
end

function L.addOwn(id, name, facts)
    local decks = Store.get("leer.own", {})
    for _, d in ipairs(decks) do if d.id == id then return false end end
    decks[#decks + 1] = { id = id, name = name, facts = facts, at = os.time() }
    Store.set("leer.own", decks)
    L.reset()
    return true
end

function L.removeOwn(id)
    local decks = Store.get("leer.own", {})
    for i, d in ipairs(decks) do if d.id == id then table.remove(decks, i); break end end
    Store.set("leer.own", decks)
    L.reset()
end

function L.line(key) for _, l in ipairs(L.lines()) do if l.key == key then return l end end end

--- Voortgang van een stap: beheerst, gezien, totaal, te herhalen.
function L.stepStats(step)
    local bx, t = boxes(), today()
    local m, seen, due = 0, 0, 0
    for _, f in ipairs(step.facts) do
        local b = bx[f.id]
        if b then
            seen = seen + 1
            if b.b >= L.MASTER then m = m + 1 end
            if b.d <= t then due = due + 1 end
        end
    end
    return m, seen, #step.facts, due
end

--- Welke stappen open zijn: de eerste altijd, de rest als de vorige voor 80% beheerst is.
function L.openSteps(line)
    local open = {}
    for i, st in ipairs(line.steps) do
        if i == 1 or line.allOpen then open[i] = true
        else
            local m, _, n = L.stepStats(line.steps[i - 1])
            open[i] = open[i - 1] and (n == 0 or m / n >= L.UNLOCK)
        end
    end
    return open
end

function L.lineStats(line)
    local m, n, due, cur = 0, 0, 0, 1
    local open = L.openSteps(line)
    for i, st in ipairs(line.steps) do
        local a, _, c, d = L.stepStats(st)
        m, n = m + a, n + c
        if open[i] then due = due + d; cur = i end
    end
    return m, n, due, cur
end

--- Een ronde: eerst wat te herhalen is, dan nieuwe feiten uit de eerste open stap met nog onbekende.
--- onlyStep: alleen deze stap. Elk antwoord hooguit één keer per ronde.
function L.round(line, onlyStep)
    local bx, t = boxes(), today()
    local open = L.openSteps(line)
    local due, fresh = {}, {}
    for i, st in ipairs(line.steps) do
        if (onlyStep and i == onlyStep) or (not onlyStep and open[i]) then
            for _, f in ipairs(st.facts) do
                local b = bx[f.id]
                if b and b.d <= t then table.insert(due, f)
                elseif not b and (#fresh < L.NEW * 3) then table.insert(fresh, f) end
            end
        end
    end
    shuffle(due)
    table.sort(due, function(a, b) return bx[a.id].b < bx[b.id].b end)
    local out, answers = {}, {}
    local function add(f)
        local key = norm(f.a)
        if answers[key] then return false end
        answers[key] = true
        table.insert(out, f)
        return true
    end
    for _, f in ipairs(due) do if #out < L.ROUND then add(f) end end
    -- nieuwe feiten in volgorde van de stap (van basis naar verder)
    local room = L.NEW
    for _, f in ipairs(fresh) do
        if #out < L.ROUND and room > 0 then if add(f) then room = room - 1 end end
    end
    -- niets te doen maar wel open stappen: alvast herhalen wat het eerst terug zou komen
    if #out == 0 then
        local soon = {}
        for i, st in ipairs(line.steps) do
            if (onlyStep and i == onlyStep) or (not onlyStep and open[i]) then
                for _, f in ipairs(st.facts) do if bx[f.id] then table.insert(soon, f) end end
            end
        end
        table.sort(soon, function(a, b) return bx[a.id].d < bx[b.id].d end)
        for _, f in ipairs(soon) do if #out < 8 then add(f) end end
    end
    shuffle(out)
    return out
end

--- Vorm van de vraag, afhankelijk van hoe goed je het feit kent.
--- "mc": meerkeuze, "rev": andersom meerkeuze, "type": zelf typen, "recall": zelf ophalen en beoordelen.
function L.form(fact)
    local b = (L.box(fact.id) or {}).b or 0
    if b <= 1 then return "mc" end
    if b == 2 then return fact.rq and "rev" or "mc" end
    if fact.typeable then return "type" end
    return "recall"
end

--- Regel voor het menu: hoeveel er vandaag te herhalen is.
function L.summary()
    local due, m, n = 0, 0, 0
    for _, line in ipairs(L.lines()) do
        local a, b, d = L.lineStats(line)
        due, m, n = due + d, m + a, n + b
    end
    return (due > 0 and (due .. " te herhalen · ") or "") .. m .. " van " .. n .. " beheerst"
end

-- Schermen -----------------------------------------------------------------------------------

local function bar(frac, w)
    local h = UI.px(6)
    local full = math.floor(w * math.max(0, math.min(1, frac)))
    local parts = {}
    if full > 0 then table.insert(parts, UI.line(full, UI.BLACK, h)) end
    if w - full > 0 then table.insert(parts, UI.line(w - full, UI.LINE, h)) end
    return UI.hgroup(parts)
end

function L.home(app)
    local W = UI.INNER()
    local items = { UI.header("Leerlijnen", function() app:back() end, "Stap voor stap, van basis naar alles door elkaar") }
    for _, line in ipairs(L.lines()) do
        local m, n, due, cur = L.lineStats(line)
        local sub = ("Stap %d van %d · %d van %d beheerst"):format(cur, #line.steps, m, n) .. (due > 0 and (" · " .. due .. " te herhalen") or "")
        table.insert(items, UI.Tap:new{ label = line.name, callback = function() app.leerLine = line.key; app:go(L.linePage) end, UI.vgroup({
            UI.vspace(12),
            UI.hgroup({ UI.icon(line.icon or "school", 24, UI.BLACK), UI.hspace(14), UI.vgroup({
                UI.text(line.name, { size = 21, font = "medium" }),
                UI.vspace(3),
                UI.text(sub, { size = 15, color = UI.INK2, width = W - UI.px(40) }),
                UI.vspace(8),
                bar(n > 0 and m / n or 0, W - UI.px(40)),
            }) }, "top"),
            UI.vspace(12),
            UI.line(W),
        }) })
    end
    return UI.page(UI.vgroup(items))
end

function L.linePage(app)
    local W = UI.INNER()
    local line = L.line(app.leerLine)
    local open = L.openSteps(line)
    local edit = app.leerEdit and line.key == "eigen"
    local items = { UI.header(line.name, function() app.leerEdit = nil; app:back() end, edit and "Tik op een stap om hem weg te halen" or line.sub) }
    for i, st in ipairs(line.steps) do
        local m, seen, n, due = L.stepStats(st)
        local sub
        if not open[i] then sub = "Gaat open als de vorige stap voor 80% beheerst is"
        else sub = ("%d van %d beheerst"):format(m, n) .. (seen < n and (" · " .. (n - seen) .. " nieuw") or "") .. (due > 0 and (" · " .. due .. " te herhalen") or "") end
        table.insert(items, UI.Tap:new{ label = st.name, callback = function()
            if edit and st.deck then
                L.removeOwn(st.deck)
                if not L.line("eigen") then app.leerEdit = nil; return app:back() end
                return app:refresh()
            end
            if not open[i] then return end
            L.start(app, line, i)
        end, UI.vgroup({
            UI.vspace(10),
            UI.hgroup({
                UI.icon(m == n and n > 0 and "circle_check" or "checkbox_off", 20, open[i] and UI.BLACK or UI.INK3), UI.hspace(12),
                UI.vgroup({
                    UI.text(i .. ". " .. st.name .. (edit and "  · weghalen" or ""), { size = 19, font = "medium", color = open[i] and UI.BLACK or UI.INK3 }),
                    UI.text(sub, { size = 15, color = UI.INK2, width = W - UI.px(36) }),
                }),
            }, "top"),
            UI.vspace(10),
            UI.line(W),
        }) })
    end
    if line.key == "eigen" then
        return UI.page(UI.vgroup(items), UI.buttonRow({
            { edit and "Klaar" or "Opruimen", function() app.leerEdit = not edit or nil; app:refresh() end },
            { "Oefenen", function() app.leerEdit = nil; L.start(app, line) end, primary = not edit, disabled = edit },
        }))
    end
    return UI.page(UI.vgroup(items), UI.button("Oefenen", function() L.start(app, line) end, { width = W, primary = true }))
end

function L.start(app, line, onlyStep)
    local list = L.round(line, onlyStep)
    app.lr = { line = line, list = list, i = 1, again = {}, goed = 0, fout = 0, title = onlyStep and line.steps[onlyStep].name or line.name }
    app:go(L.q)
end

local function options(fact, rev)
    local good = rev and fact.ra or fact.a
    local pool = rev and fact.ropts or fact.opts
    local b = (L.box(fact.id) or {}).b or 0
    if not rev and fact.optsAll and b >= 1 then pool = fact.optsAll end
    if type(pool) == "function" then pool = pool() end
    local opts, used = { good }, { [norm(good)] = true }
    local copy = {}
    for i, o in ipairs(pool or {}) do copy[i] = o end
    for _, o in ipairs(shuffle(copy)) do
        if #opts >= 4 then break end
        if type(o) == "string" and not used[norm(o)] then used[norm(o)] = true; table.insert(opts, o) end
    end
    return shuffle(opts), good
end

function L.q(app)
    local s = app.lr
    if not s or s.i > #s.list then return L.done(app) end
    local W = UI.INNER()
    local fact = s.list[s.i]
    if not s.form then
        s.form = L.form(fact)
        -- bij meerdere vraagvarianten (zelfde feit) wisselen
        if fact.variants then
            local v = fact.variants[math.random(#fact.variants)]
            s.prompt, s.vopts = v.q, v.opts
        else
            s.prompt, s.vopts = nil, nil
        end
        if s.form == "mc" or s.form == "rev" then
            local f2 = fact
            if s.vopts then f2 = setmetatable({ opts = s.vopts }, { __index = fact }) end
            s.opts, s.good = options(f2, s.form == "rev")
        end
    end
    local b = L.box(fact.id)
    local level = ({ mc = "meerkeuze", rev = "andersom", type = "zelf typen", recall = "zelf ophalen" })[s.form]
    -- de kop blijft gelijk tijdens het antwoord (een fout antwoord komt achteraan erbij, dat telt pas bij de volgende vraag)
    if not s.result or not s.sub then s.sub = ("Vraag %d van %d · %s · %s"):format(s.i, #s.list, b and ("vak " .. b.b) or "nieuw", level) end
    local items = { UI.header(s.title, function() app.lr = nil; app:back() end, s.sub) }
    local prompt = s.form == "rev" and fact.rq or (s.prompt or fact.q)
    table.insert(items, UI.vspace(6))
    table.insert(items, UI.card(UI.text(prompt, { font = "serif", size = #prompt > 90 and 22 or 26, width = W - UI.px(56), bg = UI.FILL }), { fill = true, border = 0, pad = UI.px(24) }))
    table.insert(items, UI.vspace(18))

    local function finish(ok, unsure)
        L.grade(fact, ok, unsure)
        s[ok and "goed" or "fout"] = s[ok and "goed" or "fout"] + 1
        if not ok and not s.again[fact.id] then s.again[fact.id] = true; table.insert(s.list, fact) end
        s.result = { ok = ok, unsure = unsure }
        app:refresh()
    end
    local function nextQ()
        s.i = s.i + 1
        s.form, s.result, s.picked, s.typed, s.shown = nil, nil, nil, nil, nil
        app:refresh()
    end

    local answer = s.form == "rev" and fact.ra or fact.a
    local footer
    if s.result then
        table.insert(items, UI.text(s.result.ok and (s.result.unsure and "Goed, maar je twijfelde" or "Goed") or "Niet goed", { font = "bold", size = 22 }))
        table.insert(items, UI.vspace(6))
        if s.typed then table.insert(items, UI.text("Jij: " .. s.typed, { size = 17, color = UI.INK2, width = W })) end
        if s.picked and not s.result.ok then table.insert(items, UI.text("Jij koos: " .. s.picked, { size = 17, color = UI.INK2, width = W })) end
        table.insert(items, UI.text(answer, { font = "medium", size = 24, width = W }))
        if fact.why and fact.why ~= "" then
            table.insert(items, UI.vspace(8))
            table.insert(items, UI.text(fact.why, { size = 17, color = UI.INK2, width = W, height = UI.px(120) }))
        end
        local nb = L.box(fact.id)
        table.insert(items, UI.vspace(10))
        table.insert(items, UI.text(s.result.ok and ("Komt terug over " .. L.WAIT[math.max(1, nb.b)] .. (L.WAIT[math.max(1, nb.b)] == 1 and " dag." or " dagen.")) or "Komt aan het eind van deze ronde nog een keer, en morgen weer.", { size = 15, color = UI.INK2, width = W }))
        footer = UI.button(s.i >= #s.list and "Klaar" or "Volgende", nextQ, { width = W, primary = true })
    elseif s.form == "mc" or s.form == "rev" then
        for _, o in ipairs(s.opts) do
            table.insert(items, UI.button(o, function()
                s.picked = o
                finish(norm(o) == norm(s.good))
            end, { width = W, align = "left" }))
            table.insert(items, UI.vspace(10))
        end
    elseif s.form == "type" then
        table.insert(items, UI.text("Typ het antwoord. Kleine tikfouten mogen.", { size = 17, color = UI.INK2, width = W }))
        footer = UI.buttonRow({
            { "Weet ik niet", function() finish(false) end },
            { "Typ antwoord", function()
                require("ks_opvolg").ask("Jouw antwoord", "", function(txt)
                    s.typed = txt
                    local ans = { fact.a }
                    for _, x in ipairs(fact.alt or {}) do table.insert(ans, x) end
                    finish(L.check(ans, txt))
                end, { ok = "Controleer" })
            end, primary = true },
        })
    else -- recall
        if not s.shown then
            table.insert(items, UI.text("Bedenk het antwoord. Draai dan om en zeg eerlijk of je het wist.", { size = 17, color = UI.INK2, width = W }))
            footer = UI.button("Draai om", function() s.shown = true; app:refresh() end, { width = W, primary = true })
        else
            table.insert(items, UI.text(answer, { font = "medium", size = 24, width = W }))
            footer = UI.buttonRow({
                { "Wist ik niet", function() finish(false) end },
                { "Twijfel", function() finish(true, true) end },
                { "Wist ik", function() finish(true) end, primary = true },
            })
        end
    end
    return UI.page(UI.vgroup(items), footer)
end

function L.done(app)
    local W = UI.INNER()
    local s = app.lr or { goed = 0, fout = 0, list = {} }
    local items = { UI.header("Ronde klaar", function() app.lr = nil; app:back() end, s.title) }
    table.insert(items, UI.vspace(16))
    if #s.list == 0 then
        table.insert(items, UI.text("Niets te doen vandaag. Alles wat je kent, komt pas terug als het tijd is.", { size = 20, width = W }))
    else
        table.insert(items, UI.text(("%d goed, %d fout"):format(s.goed, s.fout), { font = "medium", size = 26 }))
        if s.line then
            local m, n, _, cur = L.lineStats(s.line)
            table.insert(items, UI.vspace(10))
            table.insert(items, UI.text(("%s: stap %d van %d, %d van %d beheerst."):format(s.line.name, cur, #s.line.steps, m, n), { size = 18, color = UI.INK2, width = W }))
        end
    end
    table.insert(items, UI.vspace(24))
    table.insert(items, UI.buttonRow({
        { "Nog een ronde", function() local line = s.line; app.lr = nil; app:back(); if line then L.start(app, line) end end },
        { "Terug", function() app.lr = nil; app:back() end, primary = true },
    }))
    return UI.page(UI.vgroup(items))
end

return L
