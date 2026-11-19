-- Sport: de training van vandaag en de komende dagen, deze week en je vorm.
-- Bron: je intervals.icu-agenda (daar zet de Kees Study-app op je telefoon het schema neer)
-- en je activiteiten van Garmin via intervals.icu.
-- De sleutel staat alleen op deze Kobo (in de opslag van de app), nooit online of in de code.

local UIManager = require("ui/uimanager")
local UI = require("ks_ui")
local Store = require("ks_store")

local S = {}

local DAYS = { "zondag", "maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag" }
local SHORT = { "zo", "ma", "di", "wo", "do", "vr", "za" }

S.BASE = os.getenv("KEES_STUDY_INTERVALS_URL") or "https://intervals.icu"

function S.connected() return (Store.get("sport.key") or "") ~= "" end
-- JSON "null" komt binnen als een functie (zo doet KOReader dat). Alles wat geen tekst
-- of getal is, maken we leeg, zodat een lege waarde nooit een scherm kan breken.
local function str(v) return type(v) == "string" and v or nil end
local function num(v) return type(v) == "number" and v or nil end
local function cleanList(list, fields)
    local out = {}
    for _, e in ipairs(type(list) == "table" and list or {}) do
        if type(e) == "table" then
            local c = {}
            for k, kind in pairs(fields) do c[k] = kind == "n" and num(e[k]) or str(e[k]) end
            table.insert(out, c)
        end
    end
    return out
end
local EV = { date = "s", name = "s", desc = "s", type = "s", dur = "n", load = "n", cat = "s", ext = "s" }
local AC = { date = "s", name = "s", type = "s", dist = "n", dur = "n", load = "n", hr = "n" }

function S.cache()
    local c = Store.get("sport.cache")
    if type(c) ~= "table" then return nil end
    if not c.clean then
        c = { at = num(c.at) or 0, clean = true, events = cleanList(c.events, EV), acts = cleanList(c.acts, AC), well = c.well }
        local w = {}
        for _, x in ipairs(type(c.well) == "table" and c.well or {}) do
            if type(x) == "table" and num(x.ctl) and num(x.atl) then table.insert(w, { date = str(x.date) or "", ctl = x.ctl, atl = x.atl }) end
        end
        c.well = w
    end
    return c
end

local function iso(ts) return os.date("%Y-%m-%d", ts) end
local function dateTs(d) -- "2026-11-15..." -> tijd om 12:00
    local y, m, dd = d:match("^(%d+)-(%d+)-(%d+)")
    if not y then return nil end
    return os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12 }
end

--- Notities hebben geen sporttype: afleiden uit de naam.
function S.noteType(name)
    name = (name or ""):lower()
    if name:find("test") then return "Test" end
    if name:find("kracht") or name:find("kettle") or name:find("push") or name:find("pull") or name:find("press") then return "WeightTraining" end
    return "Note"
end

local function sportIcon(t)
    t = (type(t) == "string" and t or ""):lower()
    if t == "test" then return "target" end
    if t == "note" then return "flag" end
    if t:find("ride") or t:find("cycl") or t:find("bike") then return "bike" end
    if t:find("swim") then return "swim" end
    if t:find("walk") or t:find("hike") then return "walk" end
    if t:find("weight") or t:find("strength") or t:find("kettle") or t:find("crossfit") or t:find("workout") then return "dumbbell" end
    return "run"
end
S.sportIcon = sportIcon

function S.fmtDur(sec)
    sec = tonumber(sec) or 0
    if sec <= 0 then return nil end
    local h, m = math.floor(sec / 3600), math.floor(sec / 60) % 60
    if h > 0 then return ("%d u %02d"):format(h, m) end
    return m .. " min"
end

local function km(m)
    m = tonumber(m) or 0
    if m <= 0 then return nil end
    local s = ("%.1f km"):format(m / 1000):gsub("%.", ",")
    return s
end

-- Ophalen ----------------------------------------------------------------------

local function api(path)
    local mime = require("mime")
    local key = Store.get("sport.key")
    local athlete = Store.get("sport.athlete", "0")
    local ok, body, code = require("ks_net").get(S.BASE .. "/api/v1/athlete/" .. athlete .. path, {
        Authorization = "Basic " .. mime.b64("API_KEY:" .. key),
        Accept = "application/json",
    })
    if not ok then
        if code == 401 or code == 403 then return nil, "Sleutel geweigerd door intervals.icu." end
        return nil, body
    end
    local good, data = pcall(require("ks_json").decode, body)
    if not good then return nil, "Onverwacht antwoord van intervals.icu." end
    return data
end

--- Haalt agenda, activiteiten en vorm op. Moet al online zijn. Geeft (true) of (false, fout).
function S.fetchNow()
    if not S.connected() then return false, "Nog niet gekoppeld." end
    local now = os.time()
    local events, err = api("/events?oldest=" .. iso(now - 7 * 86400) .. "&newest=" .. iso(now + 21 * 86400))
    if not events then return false, err end
    local acts = api("/activities?oldest=" .. iso(now - 28 * 86400) .. "&newest=" .. iso(now)) or {}
    local well = api("/wellness?oldest=" .. iso(now - 42 * 86400) .. "&newest=" .. iso(now)) or {}
    if type(events) ~= "table" then return false, "Onverwacht antwoord van intervals.icu." end
    local c = { at = now, clean = true, events = {}, acts = {}, well = {} }
    for _, e in ipairs(events) do
        local cat = str(e.category)
        if cat == "WORKOUT" or cat == "NOTE" or cat == "RACE_A" or cat == "RACE_B" or cat == "RACE_C" then
            table.insert(c.events, { date = (str(e.start_date_local) or ""):sub(1, 10), name = str(e.name) or "Training", desc = str(e.description),
                type = str(e.type) or (cat == "NOTE" and S.noteType(str(e.name)) or nil), dur = num(e.moving_time), load = num(e.icu_training_load), cat = cat, ext = str(e.external_id) })
        end
    end
    table.sort(c.events, function(a, b) return a.date < b.date end)
    for _, a in ipairs(type(acts) == "table" and acts or {}) do
        table.insert(c.acts, { date = (str(a.start_date_local) or ""):sub(1, 10), name = str(a.name), type = str(a.type), dist = num(a.distance),
            dur = num(a.moving_time), load = num(a.icu_training_load), hr = num(a.average_heartrate) })
    end
    table.sort(c.acts, function(a, b) return a.date > b.date end)
    for _, w in ipairs(type(well) == "table" and well or {}) do
        if num(w.ctl) and num(w.atl) then table.insert(c.well, { date = str(w.id) or str(w.date) or "", ctl = w.ctl, atl = w.atl }) end
    end
    table.sort(c.well, function(a, b) return a.date < b.date end)
    Store.set("sport.cache", c)
    return true
end

--- Ophalen met wifi (zelf aanzetten en daarna weer uit).
function S.refresh(done)
    require("ks_net").online(function()
        local ok, err = S.fetchNow()
        done(ok, err)
    end, { onFail = function(msg) done(false, msg) end })
end

-- Samenvattingen -------------------------------------------------------------

function S.eventsOn(date)
    local list = {}
    for _, e in ipairs((S.cache() or {}).events or {}) do if e.date == date then table.insert(list, e) end end
    return list
end

--- Voor het beginscherm: titel en regel over vandaag.
function S.today()
    if not S.connected() then return nil, "Koppel intervals.icu in Sport" end
    local c = S.cache()
    if not c then return nil, "Nog niet opgehaald" end
    local list = S.eventsOn(iso(os.time()))
    if #list == 0 then return "Rustdag", "Geen training gepland" end
    local e = list[1]
    local bits = {}
    if S.fmtDur(e.dur) then table.insert(bits, S.fmtDur(e.dur)) end
    if #list > 1 then table.insert(bits, "+" .. (#list - 1) .. " meer") end
    return e.name, table.concat(bits, " · "), sportIcon(e.type)
end

--- Gedaan vandaag?
function S.doneToday()
    local d = iso(os.time())
    for _, a in ipairs((S.cache() or {}).acts or {}) do if a.date == d then return a end end
end

local function weekStart(ts)
    local wd = tonumber(os.date("%w", ts)) -- 0 = zondag
    local back = (wd + 6) % 7
    return ts - back * 86400
end

function S.week()
    local c = S.cache() or {}
    local start = weekStart(os.time())
    local days = {}
    for i = 0, 6 do days[i + 1] = { date = iso(start + i * 86400), ts = start + i * 86400, dur = 0, load = 0, n = 0 } end
    local tot = { dur = 0, dist = 0, n = 0 }
    for _, a in ipairs(c.acts or {}) do
        for _, d in ipairs(days) do
            if d.date == a.date then
                d.dur = d.dur + (tonumber(a.dur) or 0)
                d.load = d.load + (tonumber(a.load) or 0)
                d.n = d.n + 1
                tot.dur = tot.dur + (tonumber(a.dur) or 0)
                tot.dist = tot.dist + (tonumber(a.dist) or 0)
                tot.n = tot.n + 1
            end
        end
    end
    return days, tot
end

function S.form()
    local w = (S.cache() or {}).well or {}
    local last = w[#w]
    if not last then return nil end
    local prev = w[math.max(1, #w - 7)]
    return { ctl = last.ctl, atl = last.atl, tsb = last.ctl - last.atl, trend = last.ctl - (prev and prev.ctl or last.ctl), series = w }
end

-- Tekenen -----------------------------------------------------------------------

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")

--- Lijntje van fitheid over 6 weken.
local Spark = Widget:extend{ w = 200, h = 50, values = {} }
function Spark:getSize() return Geom:new{ w = self.w, h = self.h } end
function Spark:paintTo(bb, x, y)
    local v = self.values
    if #v < 2 then return end
    local lo, hi = math.huge, -math.huge
    for _, n in ipairs(v) do lo = math.min(lo, n); hi = math.max(hi, n) end
    if hi - lo < 1 then hi = lo + 1 end
    local th = math.max(2, UI.px(2))
    local function pt(i) return x + math.floor((i - 1) * (self.w - th) / (#v - 1)), y + math.floor((1 - (v[i] - lo) / (hi - lo)) * (self.h - th)) end
    for i = 1, #v - 1 do
        local x1, y1 = pt(i)
        local x2, y2 = pt(i + 1)
        local steps = math.max(math.abs(x2 - x1), math.abs(y2 - y1), 1)
        for s = 0, steps do
            local px = x1 + math.floor((x2 - x1) * s / steps)
            local py = y1 + math.floor((y2 - y1) * s / steps)
            bb:paintRect(px, py, th, th, Blitbuffer.COLOR_BLACK)
        end
    end
end

--- Staafjes per dag van deze week.
local function weekBars(width)
    local days = S.week()
    local max = 1800
    for _, d in ipairs(days) do max = math.max(max, d.dur) end
    local colW = math.floor(width / 7)
    local barH = UI.px(46)
    local today = iso(os.time())
    local row = UI.hgroup({}, "bottom")
    local LineWidget = require("ui/widget/linewidget")
    local FrameContainer = require("ui/widget/container/framecontainer")
    for _, d in ipairs(days) do
        local h = d.dur > 0 and math.max(UI.px(4), math.floor(barH * d.dur / max)) or 0
        local planned = #S.eventsOn(d.date) > 0 and d.date >= today
        local bar
        if h > 0 then
            bar = LineWidget:new{ dimen = Geom:new{ w = math.floor(colW * 0.46), h = h }, background = UI.BLACK }
        elseif planned then
            bar = FrameContainer:new{ bordersize = UI.px(2), color = UI.INK3, padding = 0, margin = 0, radius = UI.px(4),
                UI.box(UI.vspace(0), math.floor(colW * 0.46) - 2 * UI.px(2), UI.px(14)) }
        else
            bar = LineWidget:new{ dimen = Geom:new{ w = math.floor(colW * 0.46), h = UI.px(2) }, background = UI.LINE }
        end
        local isToday = d.date == today
        local col = UI.vgroup({
            UI.vspan(barH - bar:getSize().h),
            bar,
            UI.vspace(8),
            UI.text(SHORT[tonumber(os.date("%w", d.ts)) + 1], { size = 15, font = isToday and "bold" or "sans", color = isToday and UI.BLACK or UI.INK2 }),
        }, "center")
        table.insert(row, UI.center(col, colW, col:getSize().h))
    end
    return row
end

-- Schermen ----------------------------------------------------------------------

local function connectPage(app)
    local W = UI.INNER()
    local items = {
        UI.header("Sport koppelen", function() app:back() end),
        UI.text("Sport haalt je trainingen op uit intervals.icu: wat er vandaag en de komende dagen gepland staat (daar zet de Kees Study-app op je telefoon je schema neer), wat je deze week gedaan hebt en hoe fit je bent.", { size = 19, width = W, line_height = 0.35 }),
        UI.vspace(18),
        UI.section("Zo koppel je"),
        UI.text("1. Ga op je telefoon of computer naar intervals.icu, Settings, Developer Settings.\n2. Kopieer de API key.\n3. Tik hieronder op Sleutel invullen en typ hem over.", { size = 18, width = W, line_height = 0.35 }),
        UI.vspace(18),
        UI.card(UI.vgroup({
            UI.hgroup({ UI.icon("info", 22, UI.INK2), UI.hspace(10), UI.text("Over je sleutel", { font = "bold", size = 17 }) }),
            UI.vspace(6),
            UI.text("De sleutel blijft op deze Kobo staan, in het opslagbestand van de app. Hij gaat niet naar GitHub. Wel kan iedereen die je Kobo via de kabel opent hem lezen. Je kunt hem bij intervals.icu altijd vernieuwen.", { size = 16, color = UI.INK2, width = W - UI.px(44) }),
        }), { fill = true }),
    }
    local footer = UI.button("Sleutel invullen", function()
        local InputDialog = require("ui/widget/inputdialog")
        local dlg
        dlg = require("ks_ui").inputDialog{
            title = "API key van intervals.icu",
            input = "",
            buttons = { {
                { text = "Annuleren", id = "close", callback = function() UIManager:close(dlg) end },
                { text = "Opslaan", is_enter_default = true, callback = function()
                    local k = (dlg:getInputText() or ""):gsub("%s+", "")
                    UIManager:close(dlg)
                    if k ~= "" then
                        Store.set("sport.key", k)
                        Store.flush()
                        app.sportMsg = "Opgeslagen. Tik op Bijwerken om je trainingen op te halen."
                        app:replace(S.page)
                    end
                end },
            } },
        }
        UIManager:show(dlg)
        dlg:onShowKeyboard()
    end, { width = W, primary = true, icon = "pencil" })
    return UI.page(UI.vgroup(items), footer)
end

function S.page(app)
    if not S.connected() then return connectPage(app) end
    local W = UI.INNER()
    local c = S.cache()
    local items = { UI.header("Sport", function() app.sportMsg = nil; app:back() end,
        c and ("Bijgewerkt " .. os.date("%d-%m om %H:%M", c.at)) or "Nog niet opgehaald") }

    -- Vandaag: grote zwarte kaart
    local todayList = S.eventsOn(iso(os.time()))
    local done = S.doneToday()
    local tg = {}
    if #todayList == 0 then
        table.insert(tg, UI.text(c and "Rustdag" or "Tik op Bijwerken", { font = "display", size = 30, color = UI.WHITE, bg = UI.BLACK, width = W - UI.px(48) }))
        table.insert(tg, UI.vspace(4))
        table.insert(tg, UI.text(c and "Er staat vandaag niets gepland." or "Dan haalt de app je agenda op.", { size = 17, color = UI.WHITE, bg = UI.BLACK, width = W - UI.px(48) }))
    else
        for i, e in ipairs(todayList) do
            if i > 1 then table.insert(tg, UI.vspace(14)) end
            table.insert(tg, UI.hgroup({
                UI.icon(sportIcon(e.type), 30, UI.WHITE, { bg = UI.BLACK }), UI.hspace(12),
                UI.text(e.name, { font = "display", size = 26, color = UI.WHITE, bg = UI.BLACK, width = W - UI.px(48 + 44), height = UI.px(36) }),
            }))
            local bits = {}
            if S.fmtDur(e.dur) then table.insert(bits, S.fmtDur(e.dur)) end
            if tonumber(e.load) then table.insert(bits, "belasting " .. math.floor(e.load + 0.5)) end
            if #bits > 0 then
                table.insert(tg, UI.vspace(4))
                table.insert(tg, UI.text(table.concat(bits, " · "), { size = 17, color = UI.WHITE, bg = UI.BLACK }))
            end
            if e.desc and e.desc ~= "" then
                table.insert(tg, UI.vspace(10))
                table.insert(tg, UI.text(e.desc, { size = 18, color = UI.WHITE, bg = UI.BLACK, width = W - UI.px(48), line_height = 0.35, height = UI.px(UI.compact and 26 or 52) }))
            end
        end
    end
    if done then
        table.insert(tg, UI.vspace(12))
        local bits = { done.name or "Activiteit" }
        if km(done.dist) then table.insert(bits, km(done.dist)) end
        if S.fmtDur(done.dur) then table.insert(bits, S.fmtDur(done.dur)) end
        table.insert(tg, UI.hgroup({ UI.icon("circle_check", 22, UI.WHITE, { bg = UI.BLACK }), UI.hspace(8),
            UI.text("Gedaan: " .. table.concat(bits, " · "), { size = 17, color = UI.WHITE, bg = UI.BLACK, width = W - UI.px(48 + 30) }) }))
    end
    table.insert(items, UI.Tap:new{ label = "Vandaag", callback = function() app.sportDay = 0; app:go(S.day) end,
        UI.card(UI.vgroup(tg), { dark = true, pad = UI.px(22) }) })
    table.insert(items, UI.vspace(14))

    -- Ochtend-check-in (gedeeld met de telefoon-app)
    local Sync = require("ks_sync")
    if Sync.connected() then
        local ci = Sync.checkin()
        table.insert(items, UI.row("Ochtend-check-in", ci and ("Gedaan: slaap " .. ci.sleep .. ", benen " .. ci.legs .. ", energie " .. ci.energy .. ", rust " .. ci.calm) or "Nog niet gedaan vandaag",
            "›", function() app:go(Sync.checkinPage) end, W, "sun"))
        table.insert(items, UI.vspace(10))
    end

    -- Deze week + vorm, naast elkaar
    local half = math.floor((W - UI.px(14)) / 2)
    local _, tot = S.week()
    local wk = UI.vgroup({
        UI.text("Deze week", { font = "bold", size = 17 }),
        UI.vspace(4),
        UI.text((S.fmtDur(tot.dur) or "0 min") .. (km(tot.dist) and (" · " .. km(tot.dist)) or ""), { size = 16, color = UI.INK2, width = half - UI.px(40) }),
        UI.vspace(12),
        weekBars(half - UI.px(40)),
    })
    local f = S.form()
    local fv
    if f then
        local vals = {}
        for _, w in ipairs(f.series) do table.insert(vals, w.ctl) end
        local trendIcon = f.trend > 1 and "trend_up" or (f.trend < -1 and "trend_down" or "trend_flat")
        fv = UI.vgroup({
            UI.text("Vorm", { font = "bold", size = 17 }),
            UI.vspace(4),
            UI.hgroup({ UI.text(("%d"):format(math.floor(f.ctl + 0.5)), { font = "display", size = 34 }), UI.hspace(8), UI.icon(trendIcon, 26, UI.BLACK) }, "center"),
            UI.text(("fitheid · vermoeidheid %d · vorm %+d"):format(math.floor(f.atl + 0.5), math.floor(f.tsb + 0.5)), { size = 15, color = UI.INK2, width = half - UI.px(40) }),
            UI.vspace(10),
            Spark:new{ w = half - UI.px(40), h = UI.px(30), values = vals },
        })
    else
        fv = UI.vgroup({ UI.text("Vorm", { font = "bold", size = 17 }), UI.vspace(6), UI.text("Nog geen gegevens.", { size = 16, color = UI.INK2 }) })
    end
    local h = math.max(wk:getSize().h, fv:getSize().h) + UI.px(36)
    table.insert(items, UI.hgroup({ UI.card(wk, { width = half, height = h, pad = UI.px(18) }), UI.hspace(14), UI.card(fv, { width = half, height = h, pad = UI.px(18) }) }, "top"))
    table.insert(items, UI.vspace(10))

    -- Komende dagen: korte regels, zoveel als er nog past
    local used = UI.vgroup(items):getSize().h
    local room = UI.H() - UI.px(UI.TOPPAD) - used - UI.px(64) - UI.px(30 + 14 + 12) - (app.sportMsg and UI.px(40) or 0)
    local lines = {}
    for i = 1, 6 do
        local ts = os.time() + i * 86400
        local list = S.eventsOn(iso(ts))
        if #list > 0 then
            local e = list[1]
            local day = i == 1 and "Morgen" or DAYS[tonumber(os.date("%w", ts)) + 1]
            day = day:sub(1, 1):upper() .. day:sub(2)
            table.insert(lines, UI.vgroup({ UI.hgroup({
                UI.icon(sportIcon(e.type), 20, UI.INK2), UI.hspace(10),
                UI.text(day, { size = 17, font = "bold" }), UI.hspace(10),
                UI.text(e.name .. (S.fmtDur(e.dur) and (" · " .. S.fmtDur(e.dur)) or ""), { size = 17, width = W - UI.px(160), height = UI.px(24) }),
            }), UI.vspace(8) }))
        end
    end
    local sec = UI.section("Komende dagen")
    if #lines > 0 and room > sec:getSize().h + lines[1]:getSize().h then
        table.insert(items, sec)
        room = room - sec:getSize().h
        for _, l in ipairs(lines) do
            if l:getSize().h > room then break end
            table.insert(items, l)
            room = room - l:getSize().h
        end
    end

    if app.sportMsg then
        table.insert(items, UI.vspace(10))
        table.insert(items, UI.text(app.sportMsg, { size = 17, font = "bold", width = W }))
    end

    local footer = UI.buttonRow({
        { "Bijwerken", function()
            app.sportMsg = "Bezig met ophalen..."
            app:refresh()
            UIManager:scheduleIn(0.2, function()
                S.refresh(function(ok, err)
                    if ok then app.sportMsg = nil else app.sportMsg = "Ophalen mislukt: " .. tostring(err) end
                    app:refresh()
                end)
            end)
        end, icon = "sync" },
        { "Schema", function() app:go(S.schedule) end, icon = "calendar", primary = true },
        { "Timer", function() app:go(require("ks_timer").menu) end, icon = "timer" },
    })
    return UI.page(UI.vgroup(items), footer)
end

-- Schema: twee weken overzicht, en per dag alles wat er staat --------------------

local MONTHS = { "januari", "februari", "maart", "april", "mei", "juni", "juli", "augustus", "september", "oktober", "november", "december" }

local function dayTs(offset)
    local t = os.date("*t")
    return os.time{ year = t.year, month = t.month, day = t.day + offset, hour = 12 }
end

local function dayLabel(offset)
    local ts = dayTs(offset)
    local t = os.date("*t", ts)
    local name = DAYS[t.wday]
    if offset == 0 then name = "Vandaag"
    elseif offset == 1 then name = "Morgen"
    elseif offset == -1 then name = "Gisteren"
    else name = name:sub(1, 1):upper() .. name:sub(2) end
    return name, DAYS[t.wday] .. " " .. t.day .. " " .. MONTHS[t.month]
end

function S.actsOn(date)
    local list = {}
    for _, a in ipairs((S.cache() or {}).acts or {}) do if a.date == date then table.insert(list, a) end end
    return list
end

--- Eén dag, met Vorige en Volgende.
function S.day(app)
    local W = UI.INNER()
    local off = app.sportDay or 0
    local date = iso(dayTs(off))
    local name, full = dayLabel(off)
    local items = { UI.header(name, function() app:back() end, full) }
    local list = S.eventsOn(date)
    local acts = S.actsOn(date)
    if #list == 0 and #acts == 0 then
        table.insert(items, UI.vspace(30))
        table.insert(items, UI.center(UI.icon("coffee", 54, UI.INK3), W))
        table.insert(items, UI.vspace(12))
        local cached = S.cache()
        local far = cached and (dayTs(off) > (cached.at or 0) + 21 * 86400)
        table.insert(items, UI.center(UI.text(far and "Zo ver vooruit is nog niets opgehaald." or "Rustdag. Er staat niets gepland.", { size = 19, color = UI.INK2 }), W))
    end
    for i, e in ipairs(list) do
        if i > 1 then table.insert(items, UI.vspace(14)) end
        local g = {
            UI.hgroup({ UI.icon(sportIcon(e.type), 30), UI.hspace(12), UI.text(e.name, { font = "display", size = 26, width = W - UI.px(44 + 44) }) }, "top"),
        }
        local bits = {}
        if S.fmtDur(e.dur) then table.insert(bits, S.fmtDur(e.dur)) end
        if tonumber(e.load) then table.insert(bits, "belasting " .. math.floor(e.load + 0.5)) end
        if #bits > 0 then table.insert(g, UI.vspace(4)); table.insert(g, UI.text(table.concat(bits, " · "), { size = 17, color = UI.INK2 })) end
        if e.desc and e.desc ~= "" then
            table.insert(g, UI.vspace(12))
            table.insert(g, UI.text(e.desc, { size = 19, width = W - UI.px(44), line_height = 0.4, height = #list > 1 and UI.px(150) or UI.px(420) }))
        end
        -- afvinken (als de Kobo aan de telefoon-app gekoppeld is en de training uit de app komt)
        local Sync = require("ks_sync")
        if Sync.connected() and Sync.slotOf(e) and off <= 0 then
            table.insert(g, UI.vspace(12))
            if Sync.isDone(date, Sync.slotOf(e)) then
                table.insert(g, UI.hgroup({ UI.icon("circle_check", 22), UI.hspace(8), UI.text("Gedaan", { font = "medium", size = 18 }), UI.hspace(16),
                    UI.Tap:new{ label = "Ongedaan maken", callback = function() Sync.undo(date, e); app:refresh() end, UI.text("ongedaan maken", { size = 15, color = UI.INK2 }) } }))
            else
                table.insert(g, UI.button("Gedaan", function() app.doneEv = { date = date, ev = e }; app:go(Sync.donePage) end, { small = true, primary = true, icon = "check" }))
            end
        end
        table.insert(items, UI.card(UI.vgroup(g)))
    end
    if #acts > 0 then
        table.insert(items, UI.section("Gedaan"))
        for _, a in ipairs(acts) do
            local bits = {}
            if km(a.dist) then table.insert(bits, km(a.dist)) end
            if S.fmtDur(a.dur) then table.insert(bits, S.fmtDur(a.dur)) end
            if tonumber(a.hr) then table.insert(bits, math.floor(a.hr + 0.5) .. " bpm") end
            table.insert(items, UI.row(a.name or "Activiteit", table.concat(bits, " · "), nil, nil, W, "circle_check"))
        end
    end
    local footer = UI.buttonRow({
        { "Vorige", function() app.sportDay = off - 1; app:refresh() end, icon = "chevron_left", small = true, disabled = off <= -7 },
        { off == 0 and "Schema" or "Vandaag", function()
            if off == 0 then app:replace(S.schedule) else app.sportDay = 0; app:refresh() end
        end, small = true },
        { "Volgende", function() app.sportDay = off + 1; app:refresh() end, icon = "chevron_right", small = true, primary = true, disabled = off >= 13 },
    })
    return UI.page(UI.vgroup(items), footer)
end

--- Overzicht van de komende twee weken, per dag één regel. Tik voor de hele dag.
function S.schedule(app)
    local W = UI.INNER()
    -- 0 = vandaag en de 6 dagen erna, 7 = de week daarna.
    -- Verder niet: de telefoon-app zet 14 dagen vooruit in intervals.icu.
    local start = app.sportWeek or 0
    local items = { UI.header("Schema", function() app.sportWeek = nil; app:back() end,
        start == 0 and "Vandaag en de komende 6 dagen" or (dayLabel(start) and select(2, dayLabel(start)) .. " tot " .. select(2, dayLabel(start + 6)))) }
    if not S.cache() then
        table.insert(items, UI.text("Je schema is nog niet opgehaald. Tik in Sport op Bijwerken.", { size = 19, width = W }))
        return UI.page(UI.vgroup(items))
    end
    UI.rowPad = 22
    for off = start, start + 6 do
        local name = dayLabel(off)
        local ts = dayTs(off)
        local short = SHORT[tonumber(os.date("%w", ts)) + 1] .. " " .. os.date("%d", ts):gsub("^0", "")
        local list = S.eventsOn(iso(ts))
        local title, sub, icon
        if #list > 0 then
            local names = {}
            for _, e in ipairs(list) do table.insert(names, e.name) end
            title = table.concat(names, " + ")
            local dur = 0
            for _, e in ipairs(list) do dur = dur + (tonumber(e.dur) or 0) end
            sub = (off <= 1 and (name .. " · ") or "") .. short .. (S.fmtDur(dur) and (" · " .. S.fmtDur(dur)) or "")
            icon = sportIcon(list[1].type)
        else
            title = "Rust"
            sub = (off <= 1 and (name .. " · ") or "") .. short
            icon = "coffee"
        end
        local o = off
        table.insert(items, UI.row(title, sub, "›", function() app.sportDay = o; app:go(S.day) end, W, icon))
    end
    UI.rowPad = nil
    local footer = UI.buttonRow({
        { "Eerder", function() app.sportWeek = start - 7; app:refresh() end, small = true, disabled = start <= 0, icon = "chevron_left" },
        { "Later", function() app.sportWeek = start + 7; app:refresh() end, small = true, primary = start < 7, disabled = start >= 7, icon = "chevron_right" },
    })
    return UI.page(UI.vgroup(items), footer)
end

return S
