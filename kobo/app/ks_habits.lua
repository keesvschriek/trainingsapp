-- Gewoontes: eigen gewoontes, dagelijks afvinken, reeksen en een overzicht van de laatste 30 dagen.

local Blitbuffer = require("ffi/blitbuffer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LineWidget = require("ui/widget/linewidget")
local UIManager = require("ui/uimanager")
local UI = require("ks_ui")
local Store = require("ks_store")

local H = {}

H.SUGGESTIES = {
    "Bewogen of getraind",
    "Twintig minuten gelezen",
    "Telefoon weg om 21:00",
    "Voor 23:00 naar bed",
    "Vijf minuten stilte",
    "Dagtekst gelezen",
    "Iets geleerd",
    "Buiten geweest",
}
H.MAX = 8

function H.list()
    local l = Store.get("habits.list")
    if not l then
        l = {}
        for i = 1, 4 do l[i] = { id = "h" .. i, name = H.SUGGESTIES[i] } end
        Store.set("habits.list", l)
        Store.set("habits.next", 5)
    end
    return l
end

local function dateOf(daysAgo) return os.date("%Y-%m-%d", os.time() - daysAgo * 86400) end

function H.isDone(id, date)
    local d = Store.get("habits.done", {})[date or Store.today()]
    return d and d[id] or false
end

function H.toggle(id)
    local all = Store.get("habits.done", {})
    local today = Store.today()
    all[today] = all[today] or {}
    all[today][id] = (not all[today][id]) or nil
    if next(all[today]) == nil then all[today] = nil end
    -- ouder dan een jaar hoeft niet bewaard te worden
    local limit = dateOf(400)
    for d in pairs(all) do if d < limit then all[d] = nil end end
    Store.set("habits.done", all)
end

--- Aantal dagen op rij. Vandaag telt mee als hij al is afgevinkt, anders tellen we vanaf gisteren.
function H.streak(id)
    local n, start = 0, H.isDone(id) and 0 or 1
    for i = start, 400 do
        if H.isDone(id, dateOf(i)) then n = n + 1 else break end
    end
    return n
end

function H.countLast(id, days)
    local n = 0
    for i = 0, days - 1 do if H.isDone(id, dateOf(i)) then n = n + 1 end end
    return n
end

function H.summary()
    local l = H.list()
    local done = 0
    for _, h in ipairs(l) do if H.isDone(h.id) then done = done + 1 end end
    return done, #l
end

local function add(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    local l = H.list()
    if #l >= H.MAX then return end
    for _, h in ipairs(l) do if h.name == name then return end end
    local n = Store.get("habits.next", #l + 1)
    table.insert(l, { id = "h" .. n, name = name })
    Store.set("habits.next", n + 1)
    Store.set("habits.list", l)
end

local function remove(id)
    local l = H.list()
    for i, h in ipairs(l) do if h.id == id then table.remove(l, i) break end end
    Store.set("habits.list", l)
end

local function streakText(n)
    if n == 0 then return "nog geen reeks" end
    return n == 1 and "1 dag op rij" or (n .. " dagen op rij")
end

--- Rij met hokjes voor de laatste `days` dagen; vandaag rechts.
local function dots(id, days, width)
    local gap = UI.px(days > 10 and 3 or 6)
    local size = math.min(UI.px(26), math.floor((width - gap * (days - 1)) / days))
    local g = HorizontalGroup:new{}
    for i = days - 1, 0, -1 do
        local on = H.isDone(id, dateOf(i))
        table.insert(g, FrameContainer:new{
            bordersize = UI.px(1), color = UI.INK2, padding = 0, margin = 0, background = on and UI.BLACK or UI.WHITE,
            LineWidget:new{ dimen = Geom:new{ w = size - 2 * UI.px(1), h = size - 2 * UI.px(1) }, background = on and UI.BLACK or UI.WHITE },
        })
        if i > 0 then table.insert(g, HorizontalSpan:new{ width = gap }) end
    end
    return g
end

function H.page(app)
    local l = H.list()
    local done, total = H.summary()
    local items = { UI.header("Gewoontes", function() app:back() end, require("ks_main").dateText() .. " · " .. done .. " van " .. total .. " gedaan") }
    local compact = #l > 5 or UI.scale > 1.05 or UI.compact
    for _, h in ipairs(l) do
        local on = H.isDone(h.id)
        local textW = UI.INNER() - UI.px(56)
        local row = UI.vgroup({
            UI.vspace(compact and 10 or 14),
            UI.hgroup({
                UI.checkbox(on), UI.hspace(18),
                UI.vgroup({
                    UI.text(h.name, { size = 21, width = textW, font = on and "bold" or "sans" }),
                    UI.vspace(4),
                    UI.text(streakText(H.streak(h.id)) .. " · deze week " .. H.countLast(h.id, 7) .. " van 7", { size = 16, color = UI.INK2, width = textW }),
                    compact and UI.vspace(0) or UI.vspace(8),
                    compact and UI.vspace(0) or dots(h.id, 7, UI.px(7 * 32)),
                }),
            }, "top"),
            UI.vspace(compact and 10 or 14),
            UI.line(UI.INNER()),
        })
        table.insert(items, UI.Tap:new{ callback = function() H.toggle(h.id); app:refresh() end, label = h.name, row })
    end
    if #l == 0 then
        table.insert(items, UI.text("Je hebt nog geen gewoontes. Tik op Aanpassen om er een paar te kiezen.", { size = 19, width = UI.INNER() }))
    end
    local footer = UI.buttonRow({
        { "Overzicht", function() app:go(H.overview) end, small = true },
        { "Aanpassen", function() app:go(H.edit) end, small = true },
    })
    return UI.page(UI.vgroup(items), footer)
end

function H.overview(app)
    local items = { UI.header("Laatste 30 dagen", function() app:back() end, "Elk hokje is een dag, vandaag staat rechts.") }
    for _, h in ipairs(H.list()) do
        table.insert(items, UI.text(h.name, { size = 20, width = UI.INNER() }))
        table.insert(items, UI.vspace(4))
        table.insert(items, UI.text(H.countLast(h.id, 30) .. " van 30 dagen · " .. streakText(H.streak(h.id)), { size = 16, color = UI.INK2 }))
        table.insert(items, UI.vspace(8))
        table.insert(items, dots(h.id, 30, UI.INNER()))
        table.insert(items, UI.vspace(22))
    end
    return UI.page(UI.vgroup(items))
end

function H.edit(app)
    local l = H.list()
    local items = { UI.header("Gewoontes aanpassen", function() app:back() end, ("Je hebt er %d van maximaal %d. Je afgevinkte dagen blijven bewaard."):format(#l, H.MAX)) }
    UI.rowPad = 20
    for _, h in ipairs(l) do
        table.insert(items, UI.row(h.name, nil, "Weghalen", function() remove(h.id); app:refresh() end))
    end
    if #l < H.MAX then
        table.insert(items, UI.vspace(18))
        table.insert(items, UI.text("Toevoegen", { font = "serif", size = 22 }))
        table.insert(items, UI.vspace(6))
        local have = {}
        for _, h in ipairs(l) do have[h.name] = true end
        local free = {}
        for _, s in ipairs(H.SUGGESTIES) do
            if not have[s] then table.insert(free, s) end
        end
        for i = 1, #free, 2 do
            local pair = {}
            for j = i, math.min(i + 1, #free) do
                local name = free[j]
                table.insert(pair, { name, function() add(name); app:refresh() end, small = true })
            end
            table.insert(items, UI.buttonRow(pair, #pair == 1 and math.floor((UI.INNER() - UI.px(14)) / 2) or nil))
            table.insert(items, UI.vspace(10))
        end
    end
    UI.rowPad = nil
    local footer = UI.button("Eigen gewoonte typen", function()
        local InputDialog = require("ui/widget/inputdialog")
        local dlg
        dlg = require("ks_ui").inputDialog{
            title = "Nieuwe gewoonte",
            input = "",
            buttons = { {
                { text = "Annuleren", id = "close", callback = function() UIManager:close(dlg) end },
                { text = "Toevoegen", is_enter_default = true, callback = function()
                    add(dlg:getInputText())
                    UIManager:close(dlg)
                    app:refresh()
                end },
            } },
        }
        UIManager:show(dlg)
        dlg:onShowKeyboard()
    end, { width = UI.INNER(), disabled = #l >= H.MAX })
    return UI.page(UI.vgroup(items), footer)
end

return H
