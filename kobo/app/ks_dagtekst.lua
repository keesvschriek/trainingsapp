-- Dagtekst: elke dag een korte passage van een filosoof, met een vraag voor de ochtend en een voor de avond.

local UI = require("ks_ui")

local D = {}

local function data()
    if not D.list then D.list = dofile(require("ks_main").dir .. "/ks_dagtekst_data.lua") end
    return D.list
end

--- Dagnummer, zodat elke dag een andere tekst geeft en de volgorde vast ligt.
local function dayNumber(t)
    t = t or os.date("*t")
    return math.floor(os.time{ year = t.year, month = t.month, day = t.day, hour = 12 } / 86400)
end

function D.today()
    local list = data()
    return list[dayNumber() % #list + 1]
end

function D.isEvening() return tonumber(os.date("%H")) >= 16 end

--- Korte samenvatting voor het beginscherm.
function D.summary()
    local ok, t = pcall(D.today)
    if not ok or not t then return "Dagtekst", "" end
    local first = t.tekst:match("^(.-[%.%?!])%s") or t.tekst
    if #first > 150 then first = first:sub(1, 147):gsub("%s+%S*$", "") .. "..." end
    return t.wie, first
end

function D.page(app)
    local t = D.today()
    if app.dagMode == nil then app.dagMode = D.isEvening() and "avond" or "ochtend" end
    local evening = app.dagMode == "avond"
    local items = {
        UI.header("Dagtekst", function() app.dagMode = nil; app:back() end, require("ks_main").dateText()),
        UI.icon("quote", 40, UI.BLACK),
        UI.vspace(6),
        UI.text(t.wie, { font = "display", size = 26, width = UI.INNER() }),
        UI.vspace(2),
        UI.text(t.werk, { size = 16, color = UI.INK2, width = UI.INNER() }),
        UI.vspace(18),
        UI.text(t.tekst, { font = "serif", size = 23, width = UI.INNER(), line_height = 0.45 }),
        UI.vspace(26),
        UI.card(UI.vgroup({
            UI.hgroup({ UI.icon(evening and "moon" or "sun", 22, UI.BLACK, { bg = UI.FILL }), UI.hspace(8),
                UI.text(evening and "Terugblik voor vanavond" or "Vraag voor vandaag", { font = "bold", size = 17, bg = UI.FILL }) }),
            UI.vspace(8),
            UI.text(evening and t.avond or t.ochtend, { font = "serif", size = 22, width = UI.INNER() - UI.px(48), line_height = 0.4, bg = UI.FILL }),
        }), { fill = true, border = 0, pad = UI.px(22) }),
    }
    local footer = UI.vgroup({
        UI.text("Vrij vertaald uit het origineel. Elke dag een nieuwe tekst.", { size = 15, color = UI.INK2, width = UI.INNER() }),
        UI.vspace(10),
        UI.segmented({ "Ochtend", "Avond" }, evening and 2 or 1, function(i) app.dagMode = i == 2 and "avond" or "ochtend"; app:refresh() end),
    })
    return UI.page(UI.vgroup(items), footer)
end

return D
