-- Topografie op de kaart: landen aanwijzen en gemarkeerde landen herkennen.

local Map = require("ks_map")
local Q = require("ks_quiz")
local UI = require("ks_ui")

local M = {}

local REGIONS = { "Wereld", "Europa", "Afrika", "Azië", "Noord-Amerika", "Zuid-Amerika", "Oceanië" }
local ROUNDS = 10

local function dir() return require("ks_main").dir end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

--- Aanwijzen: tik het gevraagde land aan. Drie pogingen per land.
function M.point(region)
    local S = {}
    local function reset()
        local pool = shuffle(Map.playable(region))
        S.targets, S.i, S.tries, S.points, S.right, S.marks, S.msg, S.done = {}, 1, 0, 0, 0, {}, nil, false
        for k = 1, math.min(ROUNDS, #pool) do S.targets[k] = pool[k] end
    end
    reset()
    return function(app)
        local title = "Aanwijzen: " .. region
        if S.done then
            if not S.saved then S.saved = { Q.saveResult("map:" .. region, S.points) } end
            local line = S.saved[1] and ("Nieuw record. Vorige: " .. S.saved[2] .. ".") or (S.saved[2] and ("Record: " .. math.max(S.saved[2], S.points) .. ".") or "Eerste keer: dit is je record.")
            return UI.page(UI.vgroup({
                UI.header(title, function() app:back() end),
                UI.text(S.points .. " punten", { font = "serif", size = 52 }),
                UI.vspace(10),
                UI.text(S.right .. " van " .. #S.targets .. " in één keer goed. " .. line, { size = 20, width = UI.INNER() }),
            }), UI.buttonRow({
                { "Nog een keer", function() reset(); S.saved = nil; app:render("page") end, primary = true },
                { "Terug", function() app:back() end },
            }))
        end
        local t = S.targets[S.i]
        local function advance()
            if S.i >= #S.targets then S.done = true else S.i, S.tries, S.marks, S.msg, S.locked = S.i + 1, 0, {}, nil, false end
            app:render("page")
        end
        local function pick(c3)
            if S.locked then return end
            if c3 == t.c3 then
                local p = S.tries == 0 and 100 or (S.tries == 1 and 50 or 20)
                S.points = S.points + p
                if S.tries == 0 then S.right = S.right + 1 end
                S.marks = { [c3] = "right" }
                S.msg = S.tries == 0 and "Goed." or "Goed, in de herkansing."
                S.locked = true
            else
                S.tries = S.tries + 1
                S.marks[c3] = "wrong"
                local name = Map.region(region).byC3[c3].name
                if S.tries >= 3 then
                    S.marks = { [t.c3] = "target" }
                    S.msg = "Dat is " .. name .. ". Hier ligt " .. t.name .. "."
                    S.locked = true
                else
                    S.msg = "Dat is " .. name .. ". Nog " .. (3 - S.tries) .. " " .. (3 - S.tries == 1 and "poging" or "pogingen") .. "."
                end
            end
            app:refresh()
        end
        local header = UI.header(title, function() app:back() end, ("Land %d van %d · %d punten"):format(S.i, #S.targets, S.points))
        local ask = UI.text("Tik aan: " .. t.name, { font = "serif", size = 28, width = UI.INNER() })
        local msg = UI.text(S.msg or (region == "Wereld" and "Kleine landen: tik er vlakbij." or "Kleine landen hebben een rondje."), { size = 19, width = UI.INNER(), color = S.msg and UI.BLACK or UI.INK2 })
        local footer = UI.buttonRow(S.locked and {
            { S.i >= #S.targets and "Uitslag" or "Volgende", advance, primary = true },
        } or { { "Stoppen", function() app:back() end, small = true } })
        local used = header:getSize().h + ask:getSize().h + msg:getSize().h + footer:getSize().h + UI.px(UI.TOPPAD + 30 + 16 + 16 + 40)
        local map = Map.MapWidget:new{ region = region, width = UI.INNER(), maxh = UI.H() - used, marks = S.marks, onPick = pick }
        return UI.page(UI.vgroup({ header, ask, UI.vspace(12), UI.center(map, UI.INNER(), map:getSize().h), UI.vspace(12), msg }), footer)
    end
end

--- Welk land is dit? Gemarkeerd land, vier keuzes uit dezelfde buurt.
function M.which(region)
    local S = {}
    local function reset()
        local pool = shuffle(Map.playable(region))
        S.list, S.i, S.right, S.answer, S.done, S.saved = {}, 1, 0, nil, false, nil
        for k = 1, math.min(ROUNDS, #pool) do
            local c = pool[k]
            -- afleiders: landen die dichtbij liggen, zodat je echt moet kijken
            local others = {}
            for _, o in ipairs(pool) do
                if o.c3 ~= c.c3 and o.cx and c.cx then others[#others + 1] = { o = o, d = (o.cx - c.cx) ^ 2 + (o.cy - c.cy) ^ 2 } end
            end
            table.sort(others, function(a, b) return a.d < b.d end)
            local near = {}
            for q = 1, math.min(6, #others) do near[#near + 1] = others[q].o end
            shuffle(near)
            local opts = { c.name }
            for q = 1, 3 do if near[q] then opts[#opts + 1] = near[q].name end end
            S.list[k] = { c = c, a = opts, order = shuffle({ 1, 2, 3, 4 }) }
        end
    end
    reset()
    return function(app)
        local title = "Welk land is dit? " .. region
        if S.done then
            if not S.saved then S.saved = { Q.saveResult("which:" .. region, S.right) } end
            local line = S.saved[1] and ("Nieuw record. Vorige: " .. S.saved[2] .. ".") or (S.saved[2] and ("Record: " .. math.max(S.saved[2], S.right) .. ".") or "Eerste keer: dit is je record.")
            return UI.page(UI.vgroup({
                UI.header(title, function() app:back() end),
                UI.text(S.right .. " van " .. #S.list, { font = "serif", size = 52 }),
                UI.vspace(10),
                UI.text(line, { size = 20, width = UI.INNER() }),
            }), UI.buttonRow({
                { "Nog een keer", function() reset(); app:render("page") end, primary = true },
                { "Terug", function() app:back() end },
            }))
        end
        local item = S.list[S.i]
        local header = UI.header(title, function() app:back() end, ("Vraag %d van %d · %d goed"):format(S.i, #S.list, S.right))
        local below = {}
        local bw = math.floor((UI.INNER() - UI.px(14)) / 2)
        local buttons = {}
        for pos, k in ipairs(item.order) do
            local label = item.a[k]
            if label then
                local primary = false
                if S.answer then
                    if k == 1 then label = "✓ " .. label; primary = true
                    elseif pos == S.answer then label = "✗ " .. label end
                end
                buttons[#buttons + 1] = UI.button(label, function()
                    if S.answer then return end
                    S.answer = pos
                    if k == 1 then S.right = S.right + 1 end
                    app:refresh()
                end, { width = bw, primary = primary, small = true })
            end
        end
        for r = 1, #buttons, 2 do
            below[#below + 1] = UI.hgroup({ buttons[r], UI.hspace(14), buttons[r + 1] or UI.hspace(bw) }, "top")
            below[#below + 1] = UI.vspace(10)
        end
        local footer = UI.buttonRow(S.answer and {
            { S.i >= #S.list and "Uitslag" or "Volgende", function()
                if S.i >= #S.list then S.done = true else S.i, S.answer = S.i + 1, nil end
                app:render("page")
            end, primary = true },
        } or { { "Stoppen", function() app:back() end, small = true } })
        local belowG = UI.vgroup(below)
        local used = header:getSize().h + belowG:getSize().h + footer:getSize().h + UI.px(UI.TOPPAD + 30 + 16 + 40)
        local map = Map.MapWidget:new{ region = region, width = UI.INNER(), maxh = UI.H() - used, marks = { [item.c.c3] = "target" } }
        return UI.page(UI.vgroup({ header, UI.center(map, UI.INNER(), map:getSize().h), UI.vspace(16), belowG }), footer)
    end
end

function M.menu(app)
    if not Map.load(dir()) then
        return UI.page(UI.vgroup({ UI.header("Kaart", function() app:back() end), UI.text("Kaartbestand niet gevonden.", { size = 20 }) }))
    end
    app.mapMode = app.mapMode or "point"
    local items = { UI.header("Topografie", function() app:back() end, "Kies wat je wilt doen en welk gebied.") }
    table.insert(items, UI.buttonRow({
        { (app.mapMode == "point" and "● " or "") .. "Aanwijzen", function() app.mapMode = "point"; app:refresh() end, primary = app.mapMode == "point", small = true },
        { (app.mapMode == "which" and "● " or "") .. "Welk land is dit?", function() app.mapMode = "which"; app:refresh() end, primary = app.mapMode == "which", small = true },
    }))
    table.insert(items, UI.vspace(10))
    UI.rowPad = 24
    for _, r in ipairs(REGIONS) do
        local key = (app.mapMode == "point" and "map:" or "which:") .. r
        local best = Q.record(key)
        local n = #Map.playable(r)
        table.insert(items, UI.row(r, n .. " landen", best and ("record " .. best .. (app.mapMode == "which" and "/10" or "")) or "", function()
            app:go(app.mapMode == "point" and M.point(r) or M.which(r))
        end))
    end
    UI.rowPad = nil
    return UI.page(UI.vgroup(items))
end

return M
