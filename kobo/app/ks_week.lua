-- Weekoverzicht: training, gewoontes en schermtijd van maandag tot zondag, met één vraag om terug te kijken.

local FrameContainer = require("ui/widget/container/framecontainer")
local UIManager = require("ui/uimanager")
local UI = require("ks_ui")
local Store = require("ks_store")

local Wk = {}

local SHORT = { "ma", "di", "wo", "do", "vr", "za", "zo" }
local MONTHS = { "jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec" }

--- Maandag (12:00) van de week waar ts in valt.
local function monday(ts)
    local t = os.date("*t", ts)
    local back = (t.wday + 5) % 7 -- zondag=1 -> 6, maandag=2 -> 0
    return os.time{ year = t.year, month = t.month, day = t.day - back, hour = 12 }
end
Wk.monday = monday

local function dayTs(mon, i) local t = os.date("*t", mon); return os.time{ year = t.year, month = t.month, day = t.day + i, hour = 12 } end

function Wk.range(mon)
    local a, b = os.date("*t", mon), os.date("*t", dayTs(mon, 6))
    return ("%d %s - %d %s"):format(a.day, MONTHS[a.month], b.day, MONTHS[b.month])
end

function Wk.key(mon) return os.date("%Y-%m-%d", mon) end

local function square(on, size)
    return FrameContainer:new{ bordersize = UI.px(2), color = UI.BLACK, background = on and UI.BLACK or UI.WHITE, radius = UI.px(5), padding = 0, margin = 0,
        UI.box(UI.vspace(0), size - 2 * UI.px(2), size - 2 * UI.px(2)) }
end

function Wk.page(app)
    local W = UI.INNER()
    local mon = monday(os.time() - (app.weekBack or 0) * 7 * 86400)
    local today = os.date("%Y-%m-%d")
    local items = { UI.header(app.weekBack and app.weekBack > 0 and "Vorige week" or "Deze week", function() app.weekBack = nil; app:back() end, Wk.range(mon)) }

    -- Training
    local Sport = require("ks_sport")
    local acts = {}
    local cache = Sport.cache()
    local tot = { n = 0, dur = 0, dist = 0 }
    local perDay = {}
    for i = 0, 6 do
        local d = os.date("%Y-%m-%d", dayTs(mon, i))
        perDay[i + 1] = {}
        for _, a in ipairs(cache and cache.acts or {}) do
            if a.date == d then
                table.insert(perDay[i + 1], a)
                tot.n = tot.n + 1
                tot.dur = tot.dur + (a.dur or 0)
                tot.dist = tot.dist + (a.dist or 0)
            end
        end
    end
    local colW = math.floor((W - UI.px(44)) / 7)
    local trainRow = UI.hgroup({}, "top")
    for i = 1, 7 do
        local n = #perDay[i]
        local d = os.date("%Y-%m-%d", dayTs(mon, i - 1))
        local icon = n > 0 and Sport.sportIcon(perDay[i][1].type) or nil
        trainRow[#trainRow + 1] = UI.center(UI.vgroup({
            UI.center(icon and UI.icon(icon, 26) or UI.text("·", { size = 22, color = UI.INK3 }), colW, UI.px(34)),
            UI.center(UI.text(SHORT[i], { size = 15, font = d == today and "bold" or "sans", color = d > today and UI.INK3 or UI.BLACK }), colW),
        }, "center"), colW)
    end
    local km = tot.dist > 0 and (" · " .. (("%.1f km"):format(tot.dist / 1000):gsub("%.", ","))) or ""
    table.insert(items, UI.card(UI.vgroup({
        UI.hgroup({ UI.icon("run", 22), UI.hspace(8), UI.text("Training", { font = "bold", size = 17 }), UI.hspace(10),
            UI.text(cache and (tot.n .. "x · " .. (Sport.fmtDur(tot.dur) or "0 min") .. km) or "Sport niet opgehaald", { size = 16, color = UI.INK2 }) }),
        UI.vspace(12),
        trainRow,
    })))
    table.insert(items, UI.vspace(14))

    -- Gewoontes
    local H = require("ks_habits")
    local hg = { UI.hgroup({ UI.icon("list_checks", 22), UI.hspace(8), UI.text("Gewoontes", { font = "bold", size = 17 }) }), UI.vspace(10) }
    local sq = UI.px(22)
    for _, h in ipairs(H.list()) do
        local row = UI.hgroup({}, "center")
        local count = 0
        for i = 0, 6 do
            local d = os.date("%Y-%m-%d", dayTs(mon, i))
            local on = H.isDone(h.id, d)
            if on then count = count + 1 end
            table.insert(row, square(on, sq))
            if i < 6 then table.insert(row, UI.hspace(5)) end
        end
        local nameW = W - UI.px(44) - row:getSize().w - UI.px(70)
        table.insert(hg, UI.hgroup({ UI.box(UI.text(h.name, { size = 17, width = nameW, height = UI.px(26) }), nameW), UI.hspace(10), row, UI.hspace(12), UI.text(count .. "/7", { size = 16, font = "bold" }) }))
        table.insert(hg, UI.vspace(8))
    end
    table.insert(items, UI.card(UI.vgroup(hg)))
    table.insert(items, UI.vspace(14))

    -- Schermtijd
    local Sys = require("ks_system")
    local st, days = 0, 0
    for i = 0, 6 do
        local d = os.date("%Y-%m-%d", dayTs(mon, i))
        if d <= today then days = days + 1; st = st + Sys.secondsOn(d) end
    end
    table.insert(items, UI.card(UI.hgroup({ UI.icon("clock", 22), UI.hspace(8), UI.text("Schermtijd", { font = "bold", size = 17 }), UI.hspace(10),
        UI.text(Sys.fmt(st) .. " in totaal · gemiddeld " .. Sys.fmt(days > 0 and st / days or 0) .. " per dag", { size = 16, color = UI.INK2 }) })))
    table.insert(items, UI.vspace(14))

    -- Terugblik
    local notes = Store.get("week.notes", {})
    local note = notes[Wk.key(mon)]
    table.insert(items, UI.Tap:new{ label = "Terugblik", callback = function()
        local InputDialog = require("ui/widget/inputdialog")
        local dlg
        dlg = InputDialog:new{
            title = "Wat ging goed, en wat neem je mee?",
            input = note or "",
            allow_newline = true,
            buttons = { {
                { text = "Annuleren", id = "close", callback = function() UIManager:close(dlg) end },
                { text = "Bewaren", is_enter_default = false, callback = function()
                    local n2 = Store.get("week.notes", {})
                    local txt = dlg:getInputText()
                    n2[Wk.key(mon)] = (txt and txt ~= "") and txt or nil
                    Store.set("week.notes", n2)
                    UIManager:close(dlg)
                    app:refresh()
                end },
            } },
        }
        UIManager:show(dlg)
        dlg:onShowKeyboard()
    end, UI.card(UI.vgroup({
        UI.hgroup({ UI.icon("pencil", 22, UI.BLACK, { bg = UI.FILL }), UI.hspace(8), UI.text("Terugblik", { font = "bold", size = 17, bg = UI.FILL }) }),
        UI.vspace(8),
        UI.text(note or "Wat ging goed deze week, en wat neem je mee naar volgende week? Tik om te schrijven.", { font = "serif", size = 19, width = W - UI.px(44), color = note and UI.BLACK or UI.INK2, bg = UI.FILL, height = UI.px(110) }),
    }), { fill = true, border = 0 }) })

    local footer = UI.buttonRow({
        { "Vorige week", function() app.weekBack = (app.weekBack or 0) + 1; app:refresh() end, small = true, icon = "chevron_left", disabled = (app.weekBack or 0) >= 4 },
        { "Deze week", function() app.weekBack = nil; app:refresh() end, small = true, disabled = not app.weekBack or app.weekBack == 0 },
    })
    return UI.page(UI.vgroup(items), footer)
end

return Wk
