-- Systeemzaken: klok, batterij, schermtijd, automatisch slapen en de instellingen.
--
-- Schermtijd = de tijd dat Kees Study open is en het scherm aan staat.
-- Na de laatste tik telt hooguit IDLE seconden mee, zodat een vergeten app niet blijft tellen.
-- Lezen in de gewone Kobo-bibliotheek kan deze app niet zien en telt dus niet mee.

local Device = require("device")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local UI = require("ks_ui")
local Store = require("ks_store")

local Sys = {}

Sys.FONTS = { { 0.9, "Klein" }, { 1.0, "Normaal" }, { 1.12, "Groot" }, { 1.25, "Groter" } }
Sys.SLEEP = { 5, 10, 15, 30 } -- minuten
Sys.IDLE = 300 -- seconden die na de laatste tik nog als schermtijd tellen

local state = { lastTick = os.time(), lastAction = os.time(), suspended = false }

function Sys.fontIndex() return Store.get("set.font", 2) end
function Sys.applyFont()
    local f = Sys.FONTS[Sys.fontIndex()] or Sys.FONTS[2]
    UI.scale = f[1]
end
function Sys.sleepMinutes() return Store.get("set.sleep", 10) end

-- Schermtijd -----------------------------------------------------------------

local function addSeconds(n)
    if n <= 0 then return end
    local t = Store.get("screen", {})
    local d = Store.today()
    t[d] = (t[d] or 0) + n
    Store.set("screen", t)
end

--- Telt de tijd sinds de vorige keer, voor zover er recent getikt is.
function Sys.account()
    local now = os.time()
    if not state.suspended then
        local untilT = math.min(now, state.lastAction + Sys.IDLE)
        local dt = untilT - state.lastTick
        if dt > 0 and dt < 3600 then addSeconds(dt) end
    end
    state.lastTick = now
end

function Sys.secondsOn(date)
    return (Store.get("screen", {})[date or Store.today()] or 0)
end

function Sys.fmt(sec)
    sec = math.floor(sec or 0)
    return ("%d:%02d"):format(math.floor(sec / 3600), math.floor(sec / 60) % 60)
end

--- Oude dagen weggooien (alles ouder dan 35 dagen).
local function prune()
    local t = Store.get("screen", {})
    local limit = os.date("%Y-%m-%d", os.time() - 35 * 86400)
    local changed = false
    for d in pairs(t) do
        if d < limit then t[d] = nil; changed = true end
    end
    if changed then Store.set("screen", t) end
end

-- Batterij -------------------------------------------------------------------

function Sys.battery()
    local ok, cap, charging = pcall(function()
        local p = Device:getPowerDevice()
        return p:getCapacity(), p:isCharging()
    end)
    if not ok then return nil end
    return cap, charging
end

-- Statusbalk -----------------------------------------------------------------

function Sys.statusText()
    local st = { time = os.date("%H:%M") }
    local okW, wifi = pcall(function() return require("ui/network/manager"):isWifiOn() end)
    st.wifi = okW and wifi or false
    local cap, charging = Sys.battery()
    if cap then st.battery = cap; st.charging = charging end
    local ok, err = pcall(Sys.account)
    if not ok then require("logger").warn("Kees Personal schermtijd:", err) end
    st.screen = Sys.fmt(Sys.secondsOn())
    st.busy = Sys.busy
    return st
end

-- Klok, slapen en tikken ----------------------------------------------------

function Sys.touch()
    local now = os.time()
    -- eerst de rustige periode afsluiten, dan opnieuw beginnen met tellen
    if now - state.lastAction > Sys.IDLE then
        Sys.account()
        state.lastTick = now
    end
    state.lastAction = now
end

local function tick()
    Sys.account()
    local app = Sys.app
    local mins = Sys.sleepMinutes()
    if mins > 0 and not state.suspended and os.time() - state.lastAction >= mins * 60 then
        Store.flush()
        UIManager:suspend()
    elseif app and not state.suspended then
        -- alleen de statusbalk verversen: geen knipperen, de rest van het scherm blijft staan
        local rect = Geom:new{ x = 0, y = 0, w = UI.W(), h = UI.px(UI.TOPPAD - 8) }
        UIManager:setDirty(app, function() return "partial", rect end)
    end
    -- volgende keer net na de volgende minuutwissel
    UIManager:scheduleIn(61 - os.date("*t").sec, tick)
end

function Sys.onSuspend()
    Sys.account()
    state.suspended = true
    Store.flush()
end

--- Ochtend- en avondronde: krant (en training) ophalen als die editie er nog niet is.
function Sys.autoRound()
    local ok, due = pcall(function() return require("ks_news").due() end)
    if not ok or not due or Sys.busy then return end
    Sys.busy = "krant ophalen"
    if Sys.app then Sys.app:render("ui") end
    require("ks_news").refresh(function()
        Sys.busy = nil
        if Sys.app then Sys.app:render("ui") end
    end, true)
end

function Sys.onResume()
    local now = os.time()
    state.suspended = false
    state.lastTick, state.lastAction = now, now
    if Sys.app then Sys.app:render("ui") end
    UIManager:scheduleIn(3, Sys.autoRound)
end

function Sys.start(app)
    Sys.app = app
    Sys.applyFont()
    prune()
    local now = os.time()
    state.lastTick, state.lastAction = now, now
    UI.status = Sys.statusText
    UIManager:unschedule(tick)
    UIManager:scheduleIn(61 - os.date("*t").sec, tick)
    if not os.getenv("KS_NO_AUTO") then UIManager:scheduleIn(3, Sys.autoRound) end
end

function Sys.stop()
    UIManager:unschedule(tick)
    Sys.account()
end

-- Instellingen ---------------------------------------------------------------

local DAYS = { "zo", "ma", "di", "wo", "do", "vr", "za" }

--- Klein staafdiagram van de laatste 7 dagen, vandaag rechts.
local function weekBlock()
    local Blitbuffer = require("ffi/blitbuffer")
    local LineWidget = require("ui/widget/linewidget")
    local VerticalSpan = require("ui/widget/verticalspan")
    local days, max, total = {}, 60, 0
    for i = 6, 0, -1 do
        local ts = os.time() - i * 86400
        local s = Sys.secondsOn(os.date("%Y-%m-%d", ts))
        max = math.max(max, s)
        total = total + s
        table.insert(days, { ts = ts, s = s })
    end
    local colW = math.floor(UI.INNER() / 7)
    local barH = UI.px(56)
    local row = UI.hgroup({}, "bottom")
    for _, d in ipairs(days) do
        local h = d.s >= 60 and math.max(UI.px(2), math.floor(barH * d.s / max)) or 0
        local col = UI.vgroup({
            UI.text(Sys.fmt(d.s), { size = 14, color = UI.INK2 }),
            UI.vspace(4),
            VerticalSpan:new{ width = barH - h },
            h > 0 and LineWidget:new{ dimen = Geom:new{ w = math.floor(colW * 0.5), h = h }, background = Blitbuffer.COLOR_GRAY_7 } or UI.vspace(0),
            UI.line(math.floor(colW * 0.8), UI.BLACK, UI.px(1)),
            UI.vspace(4),
            UI.text(DAYS[tonumber(os.date("%w", d.ts)) + 1], { size = 15 }),
        }, "center")
        table.insert(row, UI.center(col, colW, col:getSize().h))
    end
    return row, total
end

function Sys.settingsPage(app)
    local W = UI.INNER()
    local items = { UI.header("Instellingen", function() app:back() end) }
    local big = UI.scale > 1.1

    table.insert(items, UI.section("Lettergrootte"))
    local fl = {}
    for i, f in ipairs(Sys.FONTS) do fl[i] = f[2] end
    table.insert(items, UI.segmented(fl, Sys.fontIndex(), function(i)
        Store.set("set.font", i)
        Sys.applyFont()
        app:render("ui")
    end))
    table.insert(items, UI.vspace(big and 12 or 18))

    table.insert(items, UI.section("Automatisch slapen na"))
    local sl, cur = {}, 2
    for i, m in ipairs(Sys.SLEEP) do
        sl[i] = m .. " min"
        if m == Sys.sleepMinutes() then cur = i end
    end
    table.insert(items, UI.segmented(sl, cur, function(i)
        Store.set("set.sleep", Sys.SLEEP[i])
        app:refresh()
    end))
    table.insert(items, UI.vspace(big and 14 or 22))

    UI.rowPad = big and 16 or 22
    local _, total = weekBlock()
    table.insert(items, UI.row("Schermtijd", "Vandaag " .. Sys.fmt(Sys.secondsOn()) .. " · deze week " .. Sys.fmt(total), "›", function() app:go(Sys.screenPage) end, W, "clock"))
    local Sport = require("ks_sport")
    table.insert(items, UI.row("Sport", Sport.connected() and "Gekoppeld met intervals.icu" or "Nog niet gekoppeld", "›", function() app:go(Sys.sportPage) end, W, "run"))
    table.insert(items, UI.row("Nieuws", "Rubrieken en automatisch ophalen", "›", function() app:go(require("ks_news").settings) end, W, "news"))
    local Net = require("ks_net")
    local wifiOn = Net.isOn()
    table.insert(items, UI.row("Wifi", app.wifiBusy and "Bezig..." or (wifiOn and "Aan · tik om uit te zetten" or "Uit · tik om aan te zetten"), wifiOn and "Aan" or "Uit", function()
        app.wifiBusy = true
        app:refresh()
        UIManager:scheduleIn(0.2, function() Net.toggle(function() app.wifiBusy = nil; app:refresh() end) end)
    end, W, "wifi"))
    table.insert(items, UI.row("Bijwerken via wifi", "Versie " .. require("ks_update").localVersion(), "›", function() app:go(require("ks_main").updatePage) end, W, "download"))
    table.insert(items, UI.row("Back-ups", "Elke dag een kopie, 7 dagen bewaard", "›", function() app:go(Sys.backupPage) end, W, "history"))
    UI.rowPad = nil
    return UI.page(UI.vgroup(items))
end

function Sys.sportPage(app)
    local Sport = require("ks_sport")
    local W = UI.INNER()
    local items = { UI.header("Sport", function() app.forgetKey = nil; app:back() end, "Koppeling met intervals.icu") }
    if Sport.connected() then
        table.insert(items, UI.text("Gekoppeld. De sleutel staat alleen op deze Kobo.", { size = 19, width = W }))
        table.insert(items, UI.vspace(18))
        table.insert(items, UI.button(app.forgetKey and "Zeker? Tik nog een keer" or "Koppeling verwijderen", function()
            if not app.forgetKey then app.forgetKey = true; return app:refresh() end
            app.forgetKey = nil
            Store.set("sport.key", nil)
            Store.set("sport.cache", nil)
            Store.flush()
            app:refresh()
        end, { width = W }))
    else
        table.insert(items, UI.text("Nog niet gekoppeld.", { size = 19 }))
        table.insert(items, UI.vspace(18))
        table.insert(items, UI.button("Koppelen", function() app:go(Sport.page) end, { width = W, primary = true }))
    end
    return UI.page(UI.vgroup(items))
end

function Sys.screenPage(app)
    local chart, total = weekBlock()
    local items = {
        UI.header("Schermtijd", function() app:back() end, "Vandaag " .. Sys.fmt(Sys.secondsOn()) .. " · deze week " .. Sys.fmt(total)),
        UI.vspace(10),
        chart,
        UI.vspace(26),
        UI.text("Wat telt mee", { font = "serif", size = 22 }),
        UI.vspace(6),
        UI.text("De tijd dat deze app open is en het scherm aan staat. Na je laatste tik tellen nog hooguit vijf minuten mee, zodat lezen gewoon telt maar een vergeten scherm niet. Lezen in je Kobo-bibliotheek kan deze app niet zien.", { size = 18, width = UI.INNER() }),
    }
    return UI.page(UI.vgroup(items))
end

function Sys.backupPage(app)
    local items = { UI.header("Back-ups", function() app.restorePick = nil; app:back() end, "Elke dag als je de app opent wordt een kopie van je voortgang gemaakt: quiz, schaken, gewoontes en instellingen.") }
    local list = Store.backups()
    if #list == 0 then
        table.insert(items, UI.text("Er is nog geen back-up. Die wordt gemaakt de volgende keer dat je de app opent.", { size = 19, width = UI.INNER() }))
    end
    UI.rowPad = 26
    for _, d in ipairs(list) do
        local picked = app.restorePick == d
        table.insert(items, UI.row(d, picked and "Tik nog een keer om deze terug te zetten. De app herstart daarna." or nil, picked and "Zeker?" or "Terugzetten", function()
            if app.restorePick == d then
                Store.restore(d)
                app:restart()
            else
                app.restorePick = d
                app:refresh()
            end
        end))
    end
    UI.rowPad = nil
    table.insert(items, UI.vspace(16))
    table.insert(items, UI.text("Voor het terugzetten wordt je huidige voortgang apart bewaard als voor-herstel.lua.", { size = 15, color = UI.INK2, width = UI.INNER() }))
    return UI.page(UI.vgroup(items))
end

return Sys
