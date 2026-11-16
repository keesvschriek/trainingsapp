-- Slaapscherm: als de Kobo in slaap valt terwijl de app open is, komt er een rustig scherm
-- met de dagtekst, je training en je gewoontes. E-ink kost geen stroom om stil te staan.

local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local UIManager = require("ui/uimanager")
local UI = require("ks_ui")
local Store = require("ks_store")

local S = {}

function S.on() return Store.get("sleep.on", true) end

local Screen = InputContainer:extend{}

local function build()
    local W = UI.INNER()
    local D = require("ks_dagtekst")
    local t = D.today()
    local evening = tonumber(os.date("%H")) >= 16
    local items = {
        UI.text(require("ks_main").dateText(), { size = 22, color = UI.INK2, font = "medium" }),
        UI.vspace(4),
        UI.text(os.date("%H:%M"), { font = "displaybold", size = 72 }),
        UI.vspace(24),
        UI.icon("quote", 40),
        UI.vspace(10),
        UI.text(t.tekst, { font = "serif", size = 24, width = W, line_height = 0.4, height = math.floor(UI.H() * 0.33) }),
        UI.vspace(14),
        UI.text(t.wie .. " · " .. t.werk, { size = 18, color = UI.INK2, width = W }),
        UI.vspace(20),
        UI.line(W, UI.BLACK, UI.px(2)),
        UI.vspace(16),
        UI.text(evening and "Terugblik" or "Vraag voor vandaag", { font = "bold", size = 18 }),
        UI.vspace(6),
        UI.text(evening and t.avond or t.ochtend, { font = "serif", size = 21, width = W, line_height = 0.4, height = UI.px(90) }),
    }
    -- onderaan: training en gewoontes
    local foot = {}
    local okS, name, sub = pcall(function()
        local Sport = require("ks_sport")
        if not Sport.connected() or not Sport.cache() then return nil end
        local d = os.date("%Y-%m-%d", os.time() + (evening and 86400 or 0))
        local list = Sport.eventsOn(d)
        if #list == 0 then return (evening and "Morgen: rustdag" or "Vandaag: rustdag"), nil end
        return (evening and "Morgen: " or "Vandaag: ") .. list[1].name, Sport.fmtDur(list[1].dur)
    end)
    if okS and name then
        table.insert(foot, UI.hgroup({ UI.icon("run", 24), UI.hspace(10), UI.text(name .. (sub and (" · " .. sub) or ""), { size = 20, width = W - UI.px(40), height = UI.px(30) }) }))
        table.insert(foot, UI.vspace(10))
    end
    local okH, done, total = pcall(function() return require("ks_habits").summary() end)
    if okH and total and total > 0 then
        table.insert(foot, UI.hgroup({ UI.icon("list_checks", 24), UI.hspace(10), UI.text(("Gewoontes vandaag: %d van %d"):format(done, total), { size = 20 }) }))
    end
    local body = UI.vgroup(items)
    local footer = UI.vgroup(foot)
    local H, M = UI.H(), UI.MARGIN()
    return OverlapGroup:new{
        dimen = Geom:new{ w = UI.W(), h = H },
        FrameContainer:new{ bordersize = 0, background = UI.WHITE, padding = M, padding_top = UI.px(50), margin = 0, width = UI.W(), height = H, body },
        FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, overlap_offset = { M, H - footer:getSize().h - UI.px(60) }, footer },
    }
end

function Screen:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = UI.W(), h = UI.H() }
    local ok, w = pcall(build)
    self[1] = ok and w or UI.page(UI.text("Kees Personal", { font = "display", size = 40 }))
end

--- Voor het slapen: scherm tonen en meteen volledig tekenen.
function S.show()
    if not S.on() then return end
    if S.widget then return end
    S.widget = Screen:new{}
    UIManager:show(S.widget, "full")
    UIManager:forceRePaint()
end

--- Na het wakker worden: weg ermee.
function S.hide()
    if S.widget then
        UIManager:close(S.widget, "full")
        S.widget = nil
    end
end

return S
