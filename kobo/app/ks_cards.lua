-- Leerkaarten: open vragen met herhaling volgens Leitner.
-- Je ziet de vraag, bedenkt (of typt) het antwoord, draait de kaart om en zegt zelf of het goed was.
-- Goed: de kaart schuift een bak op en komt later pas terug. Fout: terug naar bak 1, morgen weer.

local UIManager = require("ui/uimanager")
local Store = require("ks_store")
local UI = require("ks_ui")

local C = {}

-- dagen tot de volgende keer, per bak
C.WAIT = { 1, 2, 4, 8, 16 }
C.NEW_PER_DAY = 10
C.SESSION = 20

local function today() local t = os.date("*t"); return math.floor(os.time{ year = t.year, month = t.month, day = t.day, hour = 12 } / 86400) end

local NAVO = { "Alfa", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliett", "Kilo", "Lima", "Mike",
    "November", "Oscar", "Papa", "Quebec", "Romeo", "Sierra", "Tango", "Uniform", "Victor", "Whiskey", "X-ray", "Yankee", "Zulu" }

-- vragen die alleen met de vier keuzes werken, laten we weg
local function openOk(q)
    local l = q:lower()
    return not (l:find("welke van") or l:find("onderstaande") or l:find("bewering") or l:find("klopt") or l:find(":%s*$"))
end

local function yearText(y) return y < 0 and (-y .. " v.Chr.") or tostring(y) end

local decksCache
--- Alle stapels: { key, name, group, cards = function() -> { {id, front, back, why, alt} } }
function C.decks()
    if decksCache then return decksCache end
    local Q = require("ks_quiz")
    local data = Q.load(require("ks_main").dir)
    local list = {}
    local byCat = {}
    for _, q in ipairs(Q.visible()) do
        if type(q.a) == "table" and type(q.a[1]) == "string" and openOk(q.q) then
            byCat[q.cat] = byCat[q.cat] or {}
            table.insert(byCat[q.cat], { id = "q:" .. q.id, front = q.q, back = q.a[1], why = q.why ~= "" and q.why or nil })
        end
    end
    for _, c in ipairs(data.cats or {}) do
        if byCat[c.key] and #byCat[c.key] >= 5 then
            local cards = byCat[c.key]
            table.insert(list, { key = "cat:" .. c.key, name = c.name, group = c.group or "Quiz", cards = function() return cards end })
        end
    end
    table.insert(list, { key = "jaartallen", name = "Jaartallen", group = "Extra", cards = function()
        local out = {}
        for i, e in ipairs(require("ks_history_data").events) do
            table.insert(out, { id = "jt:" .. e[2], front = "Wanneer? " .. e[2], back = yearText(e[1]), why = e[3] })
        end
        return out
    end })
    table.insert(list, { key = "hoofdsteden", name = "Hoofdsteden", group = "Extra", cards = function()
        local out = {}
        for _, c in ipairs(data.countries or {}) do
            if type(c.cap) == "string" then
                table.insert(out, { id = "hs:" .. c.name, front = "Wat is de hoofdstad van " .. c.name .. "?", back = c.cap, alt = c.capAll,
                    why = type(c.capAll) == "table" and #c.capAll > 1 and ("Ook goed: " .. table.concat(c.capAll, ", ")) or nil })
            end
        end
        return out
    end })
    table.insert(list, { key = "otd", name = "Op deze dag (bewaard)", group = "Extra", cards = function()
        local out = {}
        for _, c in ipairs(require("ks_otd").saved()) do table.insert(out, { id = "otd:" .. c.id, front = c.front, back = c.back, why = c.why }) end
        return out
    end })
    table.insert(list, { key = "navo", name = "NAVO-alfabet", group = "Extra", cards = function()
        local out = {}
        for i, w in ipairs(NAVO) do
            local l = string.char(64 + i)
            table.insert(out, { id = "navo:" .. l, front = "Letter " .. l, back = w })
        end
        return out
    end })
    decksCache = list
    return list
end

function C.deck(key) for _, d in ipairs(C.decks()) do if d.key == key then return d end end end

local function boxes() return Store.get("cards.box", {}) end

--- Telling per stapel: te herhalen vandaag, nieuw, en hoeveel in bak 5.
function C.count(deck)
    local bx, t = boxes(), today()
    local due, new, top, total = 0, 0, 0, 0
    for _, c in ipairs(deck.cards()) do
        total = total + 1
        local b = bx[c.id]
        if not b then new = new + 1
        else
            if b.d <= t then due = due + 1 end
            if b.b >= 5 then top = top + 1 end
        end
    end
    return due, new, top, total
end

local function newToday()
    local n = Store.get("cards.new", {})
    return n.day == today() and n.n or 0
end

--- Een sessie: eerst wat al moet, dan nieuwe kaarten tot het dagmaximum.
function C.session(keys, extra, max)
    max = max or C.SESSION
    local bx, t = boxes(), today()
    local due, fresh = {}, {}
    for _, k in ipairs(keys) do
        local d = C.deck(k)
        if d then
            for _, c in ipairs(d.cards()) do
                local b = bx[c.id]
                if b and b.d <= t then table.insert(due, c)
                elseif not b then table.insert(fresh, c) end
            end
        end
    end
    require("ks_quiz").shuffle(due)
    table.sort(due, function(a, b) return bx[a.id].b < bx[b.id].b end)
    require("ks_quiz").shuffle(fresh)
    local out = {}
    for _, c in ipairs(due) do if #out < max then table.insert(out, c) end end
    local room = extra and C.NEW_PER_DAY or math.max(0, C.NEW_PER_DAY - newToday())
    for _, c in ipairs(fresh) do
        if #out < max and room > 0 then table.insert(out, c); room = room - 1 end
    end
    return out
end

--- grade: "goed", "twijfel" of "fout"
function C.grade(card, grade)
    local bx, t = boxes(), today()
    local b = bx[card.id]
    if not b then
        local n = Store.get("cards.new", {})
        if n.day ~= t then n = { day = t, n = 0 } end
        n.n = n.n + 1
        Store.set("cards.new", n)
        b = { b = 1, d = t }
    end
    if grade == "goed" then b.b = math.min(5, b.b + 1)
    elseif grade == "fout" then b.b = 1 end
    b.d = t + C.WAIT[b.b]
    bx[card.id] = b
    Store.set("cards.box", bx)
    local st = Store.get("cards.stats", {})
    st[grade] = (st[grade] or 0) + 1
    st.days = st.days or {}
    st.days[tostring(t)] = (st.days[tostring(t)] or 0) + 1
    -- alleen de laatste 60 dagen bewaren
    for k in pairs(st.days) do if tonumber(k) < t - 60 then st.days[k] = nil end end
    Store.set("cards.stats", st)
end

-- Typt Kees een antwoord, dan kijken we of het (bijna) klopt. Kleine tikfouten mogen.
local function norm(s)
    s = (s or ""):lower()
    local map = { ["á"] = "a", ["à"] = "a", ["ä"] = "a", ["â"] = "a", ["é"] = "e", ["è"] = "e", ["ë"] = "e", ["ê"] = "e", ["í"] = "i", ["ï"] = "i",
        ["ó"] = "o", ["ö"] = "o", ["ô"] = "o", ["ú"] = "u", ["ü"] = "u", ["ç"] = "c", ["ñ"] = "n" }
    for k, v in pairs(map) do s = s:gsub(k, v) end
    s = s:gsub("%b()", ""):gsub("[^%w ]", " "):gsub("^%s*de ", ""):gsub("^%s*het ", ""):gsub("^%s*een ", "")
    s = s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return s
end
local function lev(a, b)
    if #a > 40 or #b > 40 then return a == b and 0 or 99 end
    local prev = {}
    for j = 0, #b do prev[j] = j end
    for i = 1, #a do
        local cur = { [0] = i }
        for j = 1, #b do
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a:byte(i) == b:byte(j) and 0 or 1))
        end
        prev = cur
    end
    return prev[#b]
end
function C.check(card, typed)
    local t = norm(typed)
    if t == "" then return false end
    local opts = { card.back }
    for _, a in ipairs(type(card.alt) == "table" and card.alt or {}) do table.insert(opts, a) end
    for _, o in ipairs(opts) do
        local n = norm(o)
        if n == t then return true end
        local allowed = #n >= 10 and 2 or (#n >= 5 and 1 or 0)
        if lev(n, t) <= allowed then return true end
        -- jaartal "1066" tegen "1066" of "44 v.Chr." tegen "44 vc"
        local y1, y2 = n:match("^(%d+)"), t:match("^(%d+)")
        if y1 and y1 == y2 and (n:find("v chr") ~= nil) == (t:find("v") ~= nil) then return true end
    end
    return false
end
C.norm = norm

function C.summary()
    local due, new = 0, 0
    for _, d in ipairs(C.decks()) do
        if C.picked()[d.key] then
            local a, b = C.count(d)
            due, new = due + a, new + b
        end
    end
    local room = math.max(0, C.NEW_PER_DAY - newToday())
    if due == 0 and room == 0 then return "Klaar voor vandaag" end
    return ("%d te herhalen, %d nieuw vandaag"):format(due, math.min(room, new))
end

--- Welke stapels doen mee in "Vandaag leren" (standaard: geschiedenis, NAVO-alfabet en jaartallen)
function C.picked()
    return Store.get("cards.picked", { ["cat:geschiedenis"] = true, jaartallen = true, navo = true, otd = true })
end

-- Schermen ---------------------------------------------------------------------------------

function C.home(app)
    local W = UI.INNER()
    local items = { UI.header("Leerkaarten", function() app:back() end, "Open vragen. Wat je goed hebt, komt pas later terug.") }
    local picked = C.picked()
    local keys = {}
    for k in pairs(picked) do table.insert(keys, k) end
    local sum = C.summary()
    local st = Store.get("cards.stats", {})
    local todayN = (st.days or {})[tostring(today())] or 0
    table.insert(items, UI.card(UI.vgroup({
        UI.text("Vandaag", { font = "bold", size = 17, color = UI.INK2, bg = UI.FILL }),
        UI.vspace(4),
        UI.text(sum, { size = 24, font = "medium", width = W - UI.px(44), bg = UI.FILL }),
        UI.vspace(4),
        UI.text(todayN > 0 and ("Al " .. todayN .. " kaarten gedaan vandaag") or "Een ronde is hooguit 20 kaarten", { size = 16, color = UI.INK2, bg = UI.FILL }),
    }), { fill = true, border = 0 }))
    table.insert(items, UI.vspace(12))
    table.insert(items, UI.buttonRow({
        sum == "Klaar voor vandaag" and { "Nog 10 nieuwe", function() C.start(app, keys, "Extra ronde", true) end }
            or { "Start", function() C.start(app, keys, "Vandaag") end, primary = true },
        { "Stapels kiezen", function() app:go(C.pick) end },
    }))
    table.insert(items, UI.vspace(16))
    table.insert(items, UI.section("Of één stapel"))
    local shown = 0
    for _, d in ipairs(C.decks()) do
        if picked[d.key] then
            local due, new, top, total = C.count(d)
            table.insert(items, UI.row(d.name, ("%d te herhalen · %d nieuw · %d van %d in bak 5"):format(due, new, top, total), "›",
                function() C.start(app, { d.key }, d.name) end, W))
            shown = shown + 1
        end
    end
    return UI.page(UI.vgroup(items))
end

function C.pick(app)
    local W = UI.INNER()
    local picked = C.picked()
    local items = { UI.header("Stapels kiezen", function() app.cardsPg = nil; app:back() end, "Wat doet mee in je dagelijkse ronde?") }
    local rows = {}
    for _, d in ipairs(C.decks()) do
        local on = picked[d.key] == true
        local _, _, _, total = C.count(d)
        table.insert(rows, UI.Tap:new{ label = d.name, callback = function()
            local p = {}
            for k, v in pairs(picked) do p[k] = v end
            p[d.key] = (not on) or nil
            Store.set("cards.picked", p)
            app:refresh()
        end, UI.vgroup({ UI.vspace(10), UI.hgroup({ UI.checkbox(on), UI.hspace(16),
            UI.text(d.name, { size = 20, font = "medium", max_width = W - UI.px(160) }), UI.hspace(10), UI.text(tostring(total), { size = 16, color = UI.INK3 }) }),
            UI.vspace(10), UI.line(W) }) })
    end
    local head = UI.vgroup(items)
    local avail = UI.H() - UI.px(UI.TOPPAD) - head:getSize().h - UI.px(60 + 40)
    local per = math.max(1, math.floor(avail / rows[1]:getSize().h))
    local np = math.ceil(#rows / per)
    local pg = math.max(1, math.min(app.cardsPg or 1, np))
    for i = (pg - 1) * per + 1, math.min(#rows, pg * per) do table.insert(items, rows[i]) end
    local footer = UI.buttonRow({
        { "Vorige", function() app.cardsPg = pg - 1; app:refresh() end, small = true, disabled = pg <= 1 },
        { "Verder " .. pg .. "/" .. np, function() app.cardsPg = pg + 1; app:refresh() end, small = true, primary = pg < np, disabled = pg >= np },
    })
    return UI.page(UI.vgroup(items), footer)
end

--- Korte ronde van 10 kaarten (avond). Is er niets te herhalen, dan 10 nieuwe.
function C.ten(app)
    local keys = {}
    for k in pairs(C.picked()) do table.insert(keys, k) end
    local extra = #C.session(keys, false, 10) == 0
    C.start(app, keys, "10 kaarten", extra, 10)
end

function C.start(app, keys, title, extra, max)
    local list = C.session(keys, extra, max)
    app.cs = { list = list, i = 1, title = title, shown = false, typed = nil, ok = nil, goed = 0, fout = 0, twijfel = 0, again = {} }
    app:go(C.card)
end

local function ask(app)
    local InputDialog = require("ui/widget/inputdialog")
    local dlg
    dlg = InputDialog:new{
        title = "Jouw antwoord",
        input = "",
        buttons = { {
            { text = "Annuleren", id = "close", callback = function() UIManager:close(dlg) end },
            { text = "Controleer", is_enter_default = true, callback = function()
                local s = app.cs
                s.typed = dlg:getInputText()
                s.ok = C.check(s.list[s.i], s.typed)
                s.shown = true
                UIManager:close(dlg)
                app:refresh()
            end },
        } },
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function C.card(app)
    local W = UI.INNER()
    local s = app.cs
    if not s or s.i > #s.list then return C.done(app) end
    local card = s.list[s.i]
    local bx = boxes()[card.id]
    local items = { UI.header(s.title, function() app.cs = nil; app:back() end,
        ("Kaart %d van %d · %s"):format(s.i, #s.list, bx and ("bak " .. bx.b) or "nieuw")) }
    table.insert(items, UI.vspace(10))
    table.insert(items, UI.card(UI.vgroup({
        UI.text(card.front, { font = "serif", size = 28, width = W - UI.px(56), bg = UI.FILL, height = UI.px(260) }),
    }), { fill = true, border = 0, pad = UI.px(28) }))
    table.insert(items, UI.vspace(20))
    local footer
    if not s.shown then
        table.insert(items, UI.text("Bedenk het antwoord, of typ het. Draai dan de kaart om.", { size = 17, color = UI.INK2, width = W }))
        footer = UI.buttonRow({
            { "Typ antwoord", function() ask(app) end, icon = "pencil" },
            { "Draai om", function() s.shown = true; app:refresh() end, primary = true },
        })
    else
        table.insert(items, UI.text("Antwoord", { font = "bold", size = 16, color = UI.INK2 }))
        table.insert(items, UI.vspace(4))
        table.insert(items, UI.text(card.back, { font = "medium", size = 28, width = W }))
        if card.why then
            table.insert(items, UI.vspace(8))
            table.insert(items, UI.text(card.why, { size = 18, color = UI.INK2, width = W, height = UI.px(110) }))
        end
        if s.typed then
            table.insert(items, UI.vspace(14))
            table.insert(items, UI.text("Jij typte: " .. s.typed .. (s.ok and "  (klopt)" or "  (klopt niet)"), { size = 18, font = "bold", width = W }))
        end
        local function rate(grade)
            C.grade(card, grade)
            s[grade] = s[grade] + 1
            -- fout gegaan: aan het eind van deze ronde nog één keer
            if grade == "fout" and not s.again[card.id] then s.again[card.id] = true; table.insert(s.list, card) end
            s.i = s.i + 1
            s.shown, s.typed, s.ok = false, nil, nil
            app:refresh()
        end
        footer = UI.buttonRow({
            { "Fout", function() rate("fout") end, primary = s.typed ~= nil and not s.ok },
            { "Twijfel", function() rate("twijfel") end },
            { "Goed", function() rate("goed") end, primary = s.typed == nil or s.ok },
        })
    end
    return UI.page(UI.vgroup(items), footer)
end

function C.done(app)
    local W = UI.INNER()
    local s = app.cs or { goed = 0, fout = 0, twijfel = 0, list = {} }
    local items = { UI.header("Klaar", function() app.cs = nil; app:back() end, s.title) }
    table.insert(items, UI.vspace(20))
    if #s.list == 0 then
        table.insert(items, UI.text("Niets te doen in deze stapel vandaag. Morgen komen de volgende kaarten terug.", { size = 21, width = W }))
    else
        table.insert(items, UI.text(("%d goed, %d twijfel, %d fout"):format(s.goed, s.twijfel, s.fout), { font = "medium", size = 26, width = W }))
        table.insert(items, UI.vspace(10))
        table.insert(items, UI.text("Goede kaarten zie je pas over een paar dagen terug. Foute komen morgen weer.", { size = 18, color = UI.INK2, width = W }))
    end
    table.insert(items, UI.vspace(24))
    table.insert(items, UI.button("Terug naar leerkaarten", function() app.cs = nil; app:back() end, { width = W }))
    return UI.page(UI.vgroup(items))
end

return C
