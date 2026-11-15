-- Intervaltimer voor kettlebells, core en rust tussen sets.
-- Alleen de cijfers worden elke seconde ververst (snel en zonder knipperen).
-- De Kobo heeft geen geluid; bij een wissel knippert de leeslamp kort, als die er is.

local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local time = require("ui/time")
local UI = require("ks_ui")

local T = {}

T.PRESETS = {
    { name = "EMOM 10 minuten", sub = "Elke minuut een nieuwe ronde", work = 60, rest = 0, rounds = 10 },
    { name = "Tabata", sub = "8 × 20 s werk, 10 s rust", work = 20, rest = 10, rounds = 8 },
    { name = "30/30", sub = "10 × 30 s werk, 30 s rust", work = 30, rest = 30, rounds = 10 },
    { name = "Plank 45/15", sub = "6 × 45 s houden, 15 s rust", work = 45, rest = 15, rounds = 6 },
    { name = "Rust 60 s", sub = "Tussen twee sets", work = 0, rest = 60, rounds = 1 },
    { name = "Rust 90 s", sub = "Tussen zware sets", work = 0, rest = 90, rounds = 1 },
    { name = "Rust 2 min", sub = "Na een zware oefening", work = 0, rest = 120, rounds = 1 },
}

local function now() return time.to_s(time.now()) end

--- Lijst van fasen: { kind = "Werk"/"Rust", len, round }
local function phases(p)
    local list = {}
    for r = 1, p.rounds do
        if p.work > 0 then table.insert(list, { kind = "Werk", len = p.work, round = r }) end
        if p.rest > 0 and not (p.work > 0 and r == p.rounds) then table.insert(list, { kind = "Rust", len = p.rest, round = r }) end
    end
    return list
end

local function flashLight()
    pcall(function()
        local Device = require("device")
        if not Device:hasFrontlight() then return end
        local pd = Device:getPowerDevice()
        local was = pd:frontlightIntensity()
        local wasOn = pd:isFrontlightOn()
        pd:setIntensity(100)
        UIManager:scheduleIn(0.5, function()
            pd:setIntensity(was)
            if not wasOn then pd:turnOffFrontlight() end
        end)
    end)
end

--- Onthoudt waar hij getekend is, zodat alleen dat stuk ververst kan worden.
local Spot = Widget:extend{}
function Spot:getSize() return self[1]:getSize() end
function Spot:paintTo(bb, x, y)
    local s = self[1]:getSize()
    T.spot = Geom:new{ x = x, y = y, w = s.w, h = s.h }
    self[1]:paintTo(bb, x, y)
end

local function fmt(sec)
    sec = math.max(0, math.ceil(sec))
    return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

local function stop(app)
    if app.timer then UIManager:unschedule(app.timer.tick) end
    app.timer = nil
end

function T.run(app)
    local st = app.timer
    local W = UI.INNER()
    local p = st.preset
    local ph = st.list[st.i]
    local left = st.paused and st.left or (st.endAt - now())
    local isWork = ph and ph.kind == "Werk"
    local items = {
        UI.header(p.name, function() stop(app); app:back() end, p.sub),
        UI.vspace(30),
        UI.center(UI.text(ph and (isWork and "Werk" or "Rust") or "Klaar", { font = "display", size = 40, color = isWork and UI.BLACK or UI.INK2 }), W),
        UI.vspace(10),
    }
    local digits = UI.center(UI.text(fmt(left), { font = "displaybold", size = 150 }), W)
    table.insert(items, Spot:new{ digits })
    table.insert(items, UI.vspace(10))
    if ph and p.rounds > 1 then
        table.insert(items, UI.center(UI.text(("Ronde %d van %d"):format(ph.round, p.rounds), { size = 22, font = "medium", color = UI.INK2 }), W))
        -- stapjes voor de rondes
        local dots = {}
        local size = UI.px(16)
        for r = 1, p.rounds do
            local FrameContainer = require("ui/widget/container/framecontainer")
            table.insert(dots, FrameContainer:new{ bordersize = UI.px(2), color = UI.BLACK, background = r < ph.round and UI.BLACK or (r == ph.round and UI.INK3 or UI.WHITE),
                radius = size / 2, padding = 0, margin = 0, UI.box(UI.vspace(0), size - 2 * UI.px(2), size - 2 * UI.px(2)) })
            if r < p.rounds then table.insert(dots, UI.hspace(8)) end
        end
        table.insert(items, UI.vspace(14))
        table.insert(items, UI.center(UI.hgroup(dots), W))
    end
    local nextPh = st.list[st.i + 1]
    if nextPh then
        table.insert(items, UI.vspace(30))
        table.insert(items, UI.center(UI.text("Hierna: " .. nextPh.kind:lower() .. " " .. fmt(nextPh.len), { size = 19, color = UI.INK2 }), W))
    end
    local footer
    if ph then
        footer = UI.buttonRow({
            { st.paused and "Verder" or "Pauze", function()
                if st.paused then st.endAt = now() + st.left; st.paused = false
                else st.left = st.endAt - now(); st.paused = true end
                app:refresh()
            end, primary = true, icon = st.paused and "play" or "pause" },
            { "Volgende", function() st.skip = true; st.tick() end, icon = "skip" },
            { "Stop", function() stop(app); app:back() end, icon = "stop" },
        })
    else
        footer = UI.buttonRow({
            { "Nog een keer", function() T.start(app, p, true) end, primary = true, icon = "play" },
            { "Klaar", function() stop(app); app:back() end },
        })
    end
    return UI.page(UI.vgroup(items), footer)
end

function T.start(app, preset, replace)
    stop(app)
    local st = { preset = preset, list = phases(preset), i = 1 }
    st.endAt = now() + st.list[1].len
    st.tick = function()
        if app.timer ~= st then return end
        pcall(function() require("ks_system").touch() end) -- niet in slaap vallen tijdens de timer
        if st.paused then
            UIManager:scheduleIn(1, st.tick)
            return
        end
        local left = st.endAt - now()
        if left <= 0 or st.skip then
            st.skip = false
            st.i = st.i + 1
            flashLight()
            if st.list[st.i] then
                st.endAt = now() + st.list[st.i].len
                app:render("ui")
                UIManager:unschedule(st.tick)
                UIManager:scheduleIn(1, st.tick)
            else
                app:render("ui")
            end
            return
        end
        -- alleen de cijfers opnieuw: "fast" is de snelle zwart-wit-verversing
        app:rebuild()
        if T.spot then
            local r = T.spot
            UIManager:setDirty(app, function() return "fast", r end)
        end
        UIManager:unschedule(st.tick)
        UIManager:scheduleIn(math.max(0.2, left - math.floor(left)) + 0.02, st.tick)
    end
    app.timer = st
    if replace then app:replace(T.run) else app:go(T.run) end
    UIManager:scheduleIn(1, st.tick)
end

function T.menu(app)
    local items = { UI.header("Intervaltimer", function() app:back() end, "Tik op een schema om te beginnen. Bij elke wissel knippert de lamp even.") }
    for _, p in ipairs(T.PRESETS) do
        table.insert(items, UI.row(p.name, p.sub, "›", function() T.start(app, p) end, nil, p.work > 0 and "timer" or "coffee"))
    end
    return UI.page(UI.vgroup(items))
end

return T
