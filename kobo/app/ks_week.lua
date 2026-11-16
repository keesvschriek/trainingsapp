-- Je week in één blik: rooster, training, Defensie-module en opvolgpunten per dag.
-- Op zondag (vanaf 12:00) is dat de komende week, anders de lopende week.
-- Doorschuiven: een trainingsdag ruilen (wordt een verschuiving in het schema van de app,
-- die zet het daarna in intervals.icu en op je Garmin) of een punt naar een andere dag.

local UI = require("ks_ui")
local Sync = require("ks_sync")

local Wk = {}

Wk.PLAN_START = "2026-11-16" -- maandag week 1 van het schema in de app
local DAYS = { "maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag", "zondag" }
local SHORT = { "ma", "di", "wo", "do", "vr", "za", "zo" }
local MON = { "jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec" }

local function t(iso) local y, m, d = iso:match("(%d+)-(%d+)-(%d+)"); return os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 } end
local function iso(ts) return os.date("%Y-%m-%d", ts) end
local function wd(isoDate) local w = tonumber(os.date("%w", t(isoDate))); return w == 0 and 7 or w end -- 1 = maandag
local function diff(a, b) return math.floor((t(a) - t(b)) / 86400 + 0.5) end

--- Maandag van de week die we tonen.
function Wk.monday(now)
    now = now or os.time()
    local today = iso(now)
    local w = wd(today)
    local mon = iso(t(today) - (w - 1) * 86400)
    if w == 7 and tonumber(os.date("%H", now)) >= 12 then mon = iso(t(mon) + 7 * 86400) end
    return mon
end

function Wk.weekOf(date) return math.floor(diff(date, Wk.PLAN_START) / 7) + 1 end

function Wk.days(mon)
    local out = {}
    for i = 0, 6 do table.insert(out, iso(t(mon) + i * 86400)) end
    return out
end

local function label(date)
    local x = t(date)
    return SHORT[wd(date)] .. " " .. tonumber(os.date("%d", x)) .. " " .. MON[tonumber(os.date("%m", x))]
end
Wk.label = label

-- Gegevens per dag -----------------------------------------------------------------------

function Wk.lessons(date)
    local ok, R = pcall(require, "ks_rooster")
    if not ok or not R.connected() then return nil end
    local list = {}
    for _, ev in ipairs(R.forDay(t(date))) do if not ev.x then table.insert(list, ev) end end
    return list
end

function Wk.training(date)
    local ok, S = pcall(require, "ks_sport")
    if not ok then return {} end
    local out = {}
    for _, e in ipairs(S.eventsOn(date)) do
        if e.cat ~= "NOTE" or (e.name or ""):lower():find("rust") == nil then table.insert(out, e) end
    end
    return out
end

function Wk.module(date)
    for _, b in ipairs(Sync.list("blocks", function(b) return b.kind == "defensie" and type(b.start) == "string" and type(b["end"]) == "string" end)) do
        if b.start <= date and b["end"] >= date then return b end
    end
end

function Wk.points(date, first)
    local O = require("ks_opvolg")
    local out = {}
    for _, r in ipairs(O.open()) do
        if r.due == date or (first and r.due < date) then table.insert(out, r) end
    end
    return out
end

local function lessonLine(list)
    if not list then return nil end
    if #list == 0 then return "Geen les" end
    local first, last = list[1], list[#list]
    local n = 0
    for _, ev in ipairs(list) do if not ev.d then n = n + 1 end end
    return n .. (n == 1 and " les" or " lessen") .. " · " .. os.date("%H:%M", first.s) .. "-" .. os.date("%H:%M", last.e)
end

local function trainingLine(list)
    if #list == 0 then return "Rust" end
    local names = {}
    for _, e in ipairs(list) do table.insert(names, e.name) end
    return table.concat(names, ", ")
end

--- Twee dagen ruilen: als verschuiving in het schema (synct naar de app) en meteen zichtbaar hier.
function Wk.swap(a, b)
    local week = Wk.weekOf(a)
    if week < 1 or Wk.weekOf(b) ~= week then return false end
    local f = io.open("/dev/urandom", "rb")
    local raw = f and f:read(8) or tostring(os.time())
    if f then f:close() end
    local id = "kobo-" .. raw:gsub(".", function(c) return ("%02x"):format(c:byte()) end)
    Sync.put("moves", { id = id, week = week, op = "swap", a = wd(a) - 1, b = wd(b) - 1, at = os.time() * 1000 })
    Sync.soon()
    -- in de bewaarde agenda van intervals.icu alvast omwisselen, tot die opnieuw is opgehaald
    local Store = require("ks_store")
    local c = Store.get("sport.cache")
    if type(c) == "table" and type(c.events) == "table" then
        for _, e in ipairs(c.events) do
            local mine = (e.ext or ""):find("^trainingsapp%-") ~= nil
            if mine and e.date == a then e.date = b elseif mine and e.date == b then e.date = a end
        end
        table.sort(c.events, function(x, y) return x.date < y.date end)
        Store.set("sport.cache", c)
    end
    return true
end

-- Schermen ---------------------------------------------------------------------------------

function Wk.page(app)
    local W = UI.INNER()
    local mon = app.weekMon or Wk.monday()
    app.weekMon = mon
    local days = Wk.days(mon)
    local today = iso(os.time())
    local items = { UI.header("Je week", function() app.weekMon = nil; app:back() end, label(days[1]) .. " t/m " .. label(days[7]) .. " · week " .. Wk.weekOf(mon) .. " van het schema") }
    for i, d in ipairs(days) do
        local lessons = Wk.lessons(d)
        local tr = Wk.training(d)
        local mod = Wk.module(d)
        local pts = Wk.points(d, d == today or (i == 1 and today < d))
        local parts = {}
        local ll = lessonLine(lessons)
        if ll then table.insert(parts, ll) end
        table.insert(parts, mod and ("Module: " .. (mod.label ~= "" and mod.label or "Defensie")) or trainingLine(tr))
        if #pts > 0 then table.insert(parts, #pts == 1 and "1 punt" or (#pts .. " punten")) end
        local isToday = d == today
        local past = d < today
        table.insert(items, UI.Tap:new{ label = DAYS[i], callback = function() app.weekDay = d; app.weekMsg = nil; app:go(Wk.day) end, UI.vgroup({
            UI.vspace(11),
            UI.hgroup({
                UI.text(label(d), { size = 19, font = isToday and "bold" or "medium", width = UI.px(130), color = past and UI.INK3 or UI.BLACK }),
                UI.text(table.concat(parts, "\n"), { size = 16, color = past and UI.INK3 or UI.INK2, width = W - UI.px(130) - UI.px(30) }),
                UI.icon("chevron_right", 18, UI.INK3),
            }, "top"),
            UI.vspace(11),
            UI.line(W, isToday and UI.BLACK or nil, isToday and UI.px(2) or nil),
        }) })
    end
    local O = require("ks_opvolg")
    local later = 0
    for _, r in ipairs(O.open()) do if r.due > days[7] then later = later + 1 end end
    if later > 0 then
        table.insert(items, UI.vspace(10))
        table.insert(items, UI.text("Daarna nog " .. later .. (later == 1 and " punt" or " punten") .. " bij Opvolgen.", { size = 15, color = UI.INK2 }))
    end
    return UI.page(UI.vgroup(items), UI.buttonRow({
        { "Vorige week", function() app.weekMon = iso(t(mon) - 7 * 86400); app:refresh() end, small = true },
        { "Volgende week", function() app.weekMon = iso(t(mon) + 7 * 86400); app:refresh() end, small = true, primary = true },
    }))
end

--- Kiezen naar welke dag iets moet. onPick(date)
local function dayPicker(app, title, sub, mon, except, onPick, extra)
    app.pick = { title = title, sub = sub, mon = mon, except = except, onPick = onPick, extra = extra }
    app:go(Wk.pickPage)
end

function Wk.pickPage(app)
    local p = app.pick
    local W = UI.INNER()
    local items = { UI.header(p.title, function() app:back() end, p.sub) }
    local half = math.floor((W - UI.px(14)) / 2)
    local days = Wk.days(p.mon)
    local btns = {}
    for i, d in ipairs(days) do
        if d ~= p.except then table.insert(btns, { DAYS[i] .. " " .. tonumber(os.date("%d", t(d))), function() p.onPick(d); app:back() end }) end
    end
    if p.extra then table.insert(btns, { p.extra[1], function() p.extra[2](); app:back() end }) end
    for i = 1, #btns, 2 do
        local pair = { btns[i] }
        if btns[i + 1] then table.insert(pair, btns[i + 1]) end
        table.insert(items, UI.buttonRow(pair, #pair == 1 and half or nil))
        table.insert(items, UI.vspace(12))
    end
    return UI.page(UI.vgroup(items))
end

function Wk.day(app)
    local W = UI.INNER()
    local d = app.weekDay
    local mon = iso(t(d) - (wd(d) - 1) * 86400)
    local today = iso(os.time())
    local items = { UI.header(DAYS[wd(d)] .. " " .. label(d):match("%d+ %a+"), function() app:back() end) }

    -- Rooster
    local lessons = Wk.lessons(d)
    if lessons then
        table.insert(items, UI.section("Rooster", W))
        if #lessons == 0 then table.insert(items, UI.text("Geen les.", { size = 17, color = UI.INK2 })) end
        for _, ev in ipairs(lessons) do
            table.insert(items, UI.text((ev.d and "Hele dag" or (os.date("%H:%M", ev.s) .. "  ")) .. ev.what .. (ev.where and ("  ·  " .. ev.where) or ""), { size = 17, width = W }))
            table.insert(items, UI.vspace(4))
        end
        table.insert(items, UI.vspace(12))
    end

    -- Training
    local mod = Wk.module(d)
    table.insert(items, UI.section("Training", W))
    if mod then
        table.insert(items, UI.text("Module: " .. (mod.label ~= "" and mod.label or "Defensie") .. ". Het schema plant hier geen training.", { size = 17, width = W, color = UI.INK2 }))
    else
        local tr = Wk.training(d)
        table.insert(items, UI.text(trainingLine(tr), { size = 18, font = "medium", width = W }))
        if Wk.weekOf(d) >= 1 and d >= today then
            table.insert(items, UI.vspace(8))
            table.insert(items, UI.button("Ruilen met een andere dag", function()
                dayPicker(app, "Training ruilen", "Met welke dag wil je " .. DAYS[wd(d)] .. " ruilen? De hele dag wisselt, ook rust.", mon, d, function(b)
                    if b < today then app.weekMsg = "Een dag in het verleden kan niet meer."; return end
                    if Wk.swap(d, b) then app.weekMsg = "Geruild met " .. DAYS[wd(b)] .. ". De app zet het in intervals.icu zodra hij synchroniseert." end
                end)
            end, { width = W }))
        end
    end
    table.insert(items, UI.vspace(14))

    -- Punten
    local O = require("ks_opvolg")
    local pts = Wk.points(d, d == today)
    table.insert(items, UI.section("Opvolgen", W))
    if #pts == 0 then table.insert(items, UI.text("Niets op deze dag.", { size = 17, color = UI.INK2 })) end
    for _, r in ipairs(pts) do
        table.insert(items, UI.Tap:new{ label = r.title, callback = function()
            dayPicker(app, "Punt verzetten", r.title, mon, r.due, function(nd)
                r.due = nd; Sync.put("opvolg", r); Sync.soon()
            end, { "Volgende week", function() r.due = iso(t(r.due < today and today or r.due) + 7 * 86400); Sync.put("opvolg", r); Sync.soon() end })
        end, UI.vgroup({
            UI.vspace(8),
            UI.hgroup({ UI.text(r.title, { size = 18, width = W - UI.px(120) }), UI.text("verzetten", { size = 15, color = UI.INK2 }) }, "top"),
            UI.text(O.dueText(r.due, today) .. (r.group and (" · " .. r.group) or ""), { size = 15, color = r.due < today and UI.BLACK or UI.INK2 }),
            UI.vspace(8),
            UI.line(W),
        }) })
    end
    if app.weekMsg then
        table.insert(items, UI.vspace(12))
        table.insert(items, UI.text(app.weekMsg, { size = 16, font = "medium", width = W }))
    end
    return UI.page(UI.vgroup(items), UI.buttonRow({
        { "Punt toevoegen", function() O.ask("Punt voor " .. DAYS[wd(d)], "Wat moet er gebeuren?", function(txt)
            local title, due = O.parseLine(txt, today, d)
            if title ~= "" then O.add(title, due) end
            app:refresh()
        end) end },
    }))
end

return Wk
