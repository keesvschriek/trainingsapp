-- Licht: helderheid en warmte via een paneel onder de bovenbalk, en een automatische avondstand.
-- De Elipsa 2E heeft een lamp met instelbare kleur (ComfortLight PRO). Warmte 0 = koel, 100 = warm.

local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local UIManager = require("ui/uimanager")
local UI = require("ks_ui")
local Store = require("ks_store")

local L = {}

local function pd() return Device:getPowerDevice() end
function L.hasLight() local ok, v = pcall(function() return Device:hasFrontlight() end) return ok and v end
function L.hasWarmth() local ok, v = pcall(function() return Device:hasNaturalLight() end) return ok and v end

function L.intensity()
    local ok, v = pcall(function() return pd():isFrontlightOn() and pd():frontlightIntensity() or 0 end)
    return ok and v or 0
end
function L.warmth() local ok, v = pcall(function() return pd():frontlightWarmth() end) return ok and v or 0 end

function L.setIntensity(v)
    pcall(function()
        if v <= 0 then pd():turnOffFrontlight()
        else
            if not pd():isFrontlightOn() then pd():turnOnFrontlight() end
            pd():setIntensity(v)
        end
    end)
end
function L.setWarmth(v) pcall(function() pd():setWarmth(v) end) end

-- Avondstand -------------------------------------------------------------------------
-- Tussen 20:00 en 06:00 warmer en zachter licht. Alleen bij de overgang aanpassen,
-- zodat wat je zelf instelt daarna gewoon blijft staan.

function L.autoOn() return Store.get("light.auto", true) end
local function phase(h) h = h or tonumber(os.date("%H")); return (h >= 20 or h < 6) and "avond" or "dag" end
L.phase = phase

-- Weergave: licht, donker of automatisch (donker van 20:00 tot 06:00).
-- In automatisch kun je het even omzetten; dat geldt tot de volgende wissel.
-- Donker is de nachtmodus van KOReader: de Elipsa keert het beeld in hardware om.

function L.themeMode() return Store.get("theme.mode", "auto") end

local function phaseId()
    local h = tonumber(os.date("%H"))
    local p = phase(h)
    -- de avond van 20:00 tot 06:00 hoort bij de datum waarop hij begon
    local ts = (p == "avond" and h < 6) and (os.time() - 7 * 3600) or os.time()
    return p .. os.date("%Y%m%d", ts)
end

function L.overridden()
    local o = Store.get("theme.ovr")
    return L.themeMode() == "auto" and type(o) == "table" and o.id == phaseId()
end

function L.wantDark()
    local m = L.themeMode()
    if m == "donker" then return true elseif m == "licht" then return false end
    if L.overridden() then return Store.get("theme.ovr").dark == true end
    return phase() == "avond"
end

function L.isDark()
    local ok, v = pcall(function() return G_reader_settings:isTrue("night_mode") end)
    return ok and v or false
end

function L.setDark(on)
    if L.isDark() == on then return end
    pcall(function()
        Device.screen:toggleNightMode()
        UIManager:ToggleNightMode(on)
        G_reader_settings:saveSetting("night_mode", on)
    end)
    UIManager.FULL_REFRESH_COUNT = 0
    UIManager:setDirty("all", "full")
end

function L.applyTheme() L.setDark(L.wantDark()) end

--- Even omzetten tot de volgende wissel (alleen in automatisch).
function L.flipNow()
    Store.set("theme.ovr", { id = phaseId(), dark = not L.wantDark() })
    L.applyTheme()
end

function L.applyPhase(force)
    pcall(L.applyTheme)
    if not L.autoOn() or not L.hasLight() then return end
    local p = phase()
    if not force and Store.get("light.phase") == p then return end
    Store.set("light.phase", p)
    if p == "avond" then
        -- wat je overdag had, onthouden voor morgen
        Store.set("light.day", { i = L.intensity(), w = L.warmth() })
        local ev = Store.get("light.evening", { i = 25, w = 75 })
        if L.intensity() > 0 then L.setIntensity(math.min(L.intensity(), ev.i)) end
        if L.hasWarmth() then L.setWarmth(ev.w) end
    else
        Store.set("light.evening", { i = L.intensity() > 0 and L.intensity() or 25, w = L.warmth() })
        local day = Store.get("light.day")
        if day and L.hasWarmth() then L.setWarmth(day.w) end
    end
end

-- Paneel -------------------------------------------------------------------------------

--- Balk van 10 vakjes; tik op vakje n = n * 10 procent.
local function stepBar(value, onPick, width, label)
    local n = 10
    local gap = UI.px(6)
    local cw = math.floor((width - gap * (n - 1)) / n)
    local row = UI.hgroup({}, "center")
    local filled = math.floor(value / 10 + 0.5)
    for i = 1, n do
        local on = i <= filled
        table.insert(row, UI.Tap:new{ label = label .. " " .. (i * 10), callback = function() onPick(i * 10) end,
            FrameContainer:new{ bordersize = UI.FINE(), color = on and UI.BLACK or UI.INK2, background = on and UI.BLACK or UI.WHITE, radius = UI.px(6), padding = 0, margin = 0,
                UI.box(UI.vspace(0), cw - 2 * UI.px(2), UI.px(40)) } })
        if i < n then table.insert(row, UI.hspan(gap)) end
    end
    return row
end

local Panel = InputContainer:extend{}

function Panel:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = UI.W(), h = UI.H() }
    self.ges_events = { TapOutside = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    self:build()
end

function Panel:build()
    local W = UI.INNER()
    local inner = W - UI.px(44)
    local light = L.intensity()
    local items = {
        UI.hgroup({ UI.icon("sun", 24), UI.hspace(10), UI.text("Helderheid", { font = "bold", size = 18 }), UI.hspace(10),
            UI.text(light > 0 and (light .. "%") or "uit", { size = 17, color = UI.INK2 }) }),
        UI.vspace(10),
        stepBar(light, function(v) L.setIntensity(v); self:update() end, inner, "Helderheid"),
        UI.vspace(10),
        UI.buttonRow({
            { "Uit", function() L.setIntensity(0); self:update() end, small = true },
            { "Zachter", function() L.setIntensity(math.max(1, L.intensity() - 5)); self:update() end, small = true },
            { "Feller", function() L.setIntensity(math.min(100, L.intensity() + 5)); self:update() end, small = true },
        }, inner),
    }
    if L.hasWarmth() or os.getenv("KS_FAKE_WARMTH") then
        local w = L.warmth()
        table.insert(items, UI.vspace(20))
        table.insert(items, UI.hgroup({ UI.icon("sunset", 24), UI.hspace(10), UI.text("Warmte", { font = "bold", size = 18 }), UI.hspace(10),
            UI.text(w .. "%", { size = 17, color = UI.INK2 }) }))
        table.insert(items, UI.vspace(10))
        table.insert(items, stepBar(w, function(v) L.setWarmth(v); self:update() end, inner, "Warmte"))
    end
    table.insert(items, UI.vspace(20))
    table.insert(items, UI.segmented({ "Avondlicht automatisch", "Zelf regelen" }, L.autoOn() and 1 or 2, function(i)
        Store.set("light.auto", i == 1)
        if i == 1 then L.applyPhase(true) end
        self:update()
    end, inner))
    table.insert(items, UI.vspace(6))
    table.insert(items, UI.text("Automatisch: van 20:00 tot 06:00 warmer en zachter licht.", { size = 15, color = UI.INK2, width = inner }))
    -- weergave
    table.insert(items, UI.vspace(20))
    table.insert(items, UI.hgroup({ UI.icon("moon", 24), UI.hspace(10), UI.text("Weergave", { font = "bold", size = 18 }), UI.hspace(10),
        UI.text(L.isDark() and "donker" or "licht", { size = 17, color = UI.INK2 }) }))
    table.insert(items, UI.vspace(10))
    local modes = { "licht", "donker", "auto" }
    local cur = ({ licht = 1, donker = 2, auto = 3 })[L.themeMode()] or 3
    table.insert(items, UI.segmented({ "Licht", "Donker", "Automatisch" }, cur, function(i)
        Store.set("theme.mode", modes[i])
        Store.set("theme.ovr", nil)
        L.applyTheme()
        self:update()
    end, inner))
    if L.themeMode() == "auto" then
        table.insert(items, UI.vspace(10))
        local dark = L.wantDark()
        local untilT = phase() == "avond" and "06:00" or "20:00"
        local label = L.overridden() and "Terug naar automatisch" or ((dark and "Nu licht" or "Nu donker") .. " tot " .. untilT)
        table.insert(items, UI.buttonRow({
            { label, function()
                if L.overridden() then Store.set("theme.ovr", nil); L.applyTheme() else L.flipNow() end
                self:update()
            end, small = true },
        }, inner))
        table.insert(items, UI.vspace(6))
        table.insert(items, UI.text("Automatisch: donker van 20:00 tot 06:00.", { size = 15, color = UI.INK2, width = inner }))
    end
    -- snelknoppen: wifi en slaapscherm
    local Net = require("ks_net")
    local Sleep = require("ks_sleep")
    local wifiOn = Net.isOn()
    table.insert(items, UI.vspace(20))
    table.insert(items, UI.buttonRow({
        { self.wifiBusy and "Wifi..." or (wifiOn and "Wifi aan" or "Wifi uit"), function()
            self.wifiBusy = true
            self:update()
            UIManager:scheduleIn(0.2, function() Net.toggle(function() self.wifiBusy = nil; self:update() end) end)
        end, primary = wifiOn, icon = "wifi", small = true },
        { Sleep.on() and "Slaapscherm aan" or "Slaapscherm uit", function()
            Store.set("sleep.on", not Sleep.on())
            self:update()
        end, primary = Sleep.on(), icon = "sleep", small = true },
    }, inner))
    local card = UI.card(UI.vgroup(items), { pad = UI.px(22), border = UI.px(2), edge = UI.BLACK })
    self.cardRect = Geom:new{ x = UI.MARGIN(), y = UI.px(UI.TOPPAD - 6), w = card:getSize().w, h = card:getSize().h }
    self[1] = OverlapGroup:new{ dimen = Geom:new{ w = UI.W(), h = UI.H() },
        FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, overlap_offset = { self.cardRect.x, self.cardRect.y }, card } }
end

function Panel:update()
    self:build()
    UIManager:setDirty(self, function() return "partial", self.cardRect end)
end

function Panel:onTapOutside(_, ges)
    if ges and ges.pos and self.cardRect and ges.pos:intersectWith(self.cardRect) then return false end
    UIManager:close(self)
    if L.app then L.app:render("ui") end
    return true
end

function L.showPanel(app)
    L.app = app
    local p = Panel:new{}
    UIManager:show(p)
    UIManager:setDirty(p, function() return "partial", p.cardRect end)
end

return L
