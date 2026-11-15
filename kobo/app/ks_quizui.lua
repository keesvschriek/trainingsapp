-- Quizschermen: menu, vraag, uitslag en categorieën.

local Q = require("ks_quiz")
local UI = require("ks_ui")

local M = {}

local REGIONS = { "Europa", "Afrika", "Azië", "Noord-Amerika", "Zuid-Amerika", "Oceanië" }

local function dir() return require("ks_main").dir end

function M.summary()
    Q.load(dir())
    local s = Q.stats()
    local n = #Q.visible()
    local pct = s.answered > 0 and math.floor(s.correct * 100 / s.answered + 0.5) or 0
    local streak = Q.streak()
    return ("%d vragen%s%s"):format(n, s.answered > 0 and (" · " .. pct .. "% goed") or "", streak > 0 and (" · " .. streak .. " dag" .. (streak == 1 and "" or "en") .. " op rij") or "")
end

local function rec(key, unit)
    local r = Q.record(key)
    return r and ("record " .. r .. (unit or "")) or ""
end

--- Speler voor een reeks vragen. key = recordnaam.
function M.run(title, key, makeQuestions)
    local S = { i = 1, right = 0, answer = nil, list = nil, hidden = false }
    return function(app)
        if not S.list then
            S.list = makeQuestions()
            S.orders = {}
        end
        local list = S.list
        if #list == 0 then
            return UI.page(UI.vgroup({ UI.header(title, function() app:back() end), UI.text("Geen vragen gevonden.", { size = 20 }) }))
        end
        if S.done then
            local isRecord, prev = S.isRecord, S.prev
            local line = isRecord and ("Nieuw record. Vorige: " .. prev .. ".") or (prev and ("Record: " .. math.max(prev, S.right) .. ".") or "Eerste keer: dit is je record.")
            return UI.page(UI.vgroup({
                UI.header(title, function() app:back() end),
                UI.text(S.right .. " van " .. #list, { font = "serif", size = 56 }),
                UI.vspace(8),
                UI.text("goed", { size = 20, color = UI.INK2 }),
                UI.vspace(24),
                UI.text(line, { size = 20, width = UI.INNER() }),
            }), UI.buttonRow({
                { "Nog een keer", function() S.i, S.right, S.answer, S.list, S.done = 1, 0, nil, nil, nil; app:render("page") end, primary = true },
                { "Terug", function() app:back() end },
            }))
        end

        local q = list[S.i]
        if not S.orders[S.i] then S.orders[S.i] = Q.shuffle({ 1, 2, 3, 4 }) end
        local order = S.orders[S.i]

        local items = {}
        local extra = ("Vraag %d van %d · %s%s"):format(S.i, #list, Q.catName(q.cat), (q.asOf and q.asOf ~= "") and (" · stand " .. q.asOf) or "")
        table.insert(items, UI.header(title, function() app:back() end, extra))
        table.insert(items, UI.vspace(10))
        table.insert(items, UI.text(q.q, { font = "serif", size = 27, width = UI.INNER(), line_height = 0.35 }))
        table.insert(items, UI.vspace(28))
        for pos, k in ipairs(order) do
            local label = q.a[k]
            local primary = false
            if S.answer then
                if k == 1 then label = "✓ " .. label; primary = true
                elseif pos == S.answer then label = "✗ " .. label end
            end
            table.insert(items, UI.button(label, function()
                if S.answer then return end
                S.answer = pos
                local ok = k == 1
                if ok then S.right = S.right + 1 end
                Q.answered(q, ok)
                app:refresh()
            end, { width = UI.INNER(), primary = primary }))
            table.insert(items, UI.vspace(14))
        end
        if S.answer then
            local ok = order[S.answer] == 1
            local txt = (ok and "Goed." or ("Het was: " .. q.a[1] .. ".")) .. ((q.why and q.why ~= "") and (" " .. q.why) or "")
            table.insert(items, UI.vspace(6))
            table.insert(items, UI.text(txt, { size = 19, width = UI.INNER() }))
        end

        local row = {}
        if S.answer then
            if q.id:sub(1, 4) ~= "gen:" and not S.hidden then
                table.insert(row, { "Klopt niet", function() Q.hide(q); S.hidden = true; app:refresh() end, small = true })
            end
            table.insert(row, { S.i < #list and "Volgende" or "Uitslag", function()
                if S.i < #list then
                    S.i, S.answer, S.hidden = S.i + 1, nil, false
                else
                    S.done = true
                    S.isRecord, S.prev = Q.saveResult(key, S.right)
                end
                app:render("page")
            end, primary = true })
        else
            table.insert(row, { "Stoppen", function() app:back() end, small = true })
        end
        return UI.page(UI.vgroup(items), UI.buttonRow(row))
    end
end

local function categories(app)
    Q.load(dir())
    local counts = Q.counts()
    local S = app.catPage or 1
    local all = {}
    for _, g in ipairs(Q.load(dir()).groups) do
        for _, c in ipairs(Q.load(dir()).cats) do
            if c.group == g and (counts[c.key] or 0) > 0 then all[#all + 1] = c end
        end
    end
    local per = 8
    local pages = math.ceil(#all / per)
    UI.rowPad = 26
    local items = { UI.header("Per categorie", function() app.catPage = nil; app:back() end, ("Pagina %d van %d"):format(S, pages)) }
    for i = (S - 1) * per + 1, math.min(#all, S * per) do
        local c = all[i]
        table.insert(items, UI.row(c.name, nil, tostring(counts[c.key]), function()
            app:go(M.run(c.name, "cat:" .. c.key, function() return Q.pick({ c.key }, 10) end))
        end))
    end
    UI.rowPad = nil
    local row = {
        { "Vorige", function() app.catPage = S - 1; app:render("page") end, disabled = S <= 1 },
        { "Volgende", function() app.catPage = S + 1; app:render("page") end, disabled = S >= pages },
    }
    return UI.page(UI.vgroup(items), UI.buttonRow(row))
end

local function capitalsMenu(app)
    local items = { UI.header("Hoofdsteden", function() app:back() end, "Tien vragen per keer, steeds andere landen.") }
    table.insert(items, UI.row("De hele wereld", "Land bij hoofdstad en andersom", rec("cap:Wereld", "/10"), function()
        app:go(M.run("Hoofdsteden: wereld", "cap:Wereld", function()
            local a = Q.capitals(nil, 5, "cap")
            for _, q in ipairs(Q.capitals(nil, 5, "land")) do a[#a + 1] = q end
            return Q.shuffle(a)
        end))
    end))
    for _, r in ipairs(REGIONS) do
        table.insert(items, UI.row(r, nil, rec("cap:" .. r, "/10"), function()
            app:go(M.run("Hoofdsteden: " .. r, "cap:" .. r, function()
                local a = Q.capitals(r, 5, "cap")
                for _, q in ipairs(Q.capitals(r, 5, "land")) do a[#a + 1] = q end
                return Q.shuffle(a)
            end))
        end))
    end
    return UI.page(UI.vgroup(items))
end

function M.home(app)
    Q.load(dir())
    local wrongN = #Q.wrongList(1000)
    local items = { UI.header("Quiz", function() app:back() end, M.summary()) }
    table.insert(items, UI.row("Snelle mix", "Tien vragen uit alle categorieën", rec("mix", "/10"), function()
        app:go(M.run("Snelle mix", "mix", function() return Q.pick(nil, 10) end))
    end))
    table.insert(items, UI.row("Per categorie", "Geschiedenis, Defensie, sport en meer", "›", function() app.catPage = 1; app:go(categories) end))
    table.insert(items, UI.row("Hoofdsteden", "Per werelddeel of de hele wereld", "›", function() app:go(capitalsMenu) end))
    table.insert(items, UI.row("Topografie op de kaart", "Landen aanwijzen en herkennen", "›", function() app:go(require("ks_mapui").menu) end))
    if wrongN > 0 then
        table.insert(items, UI.row("Fouten herhalen", wrongN .. " vragen die je fout had", "", function()
            app:go(M.run("Fouten herhalen", "wrong", function() return Q.wrongList(10) end))
        end))
    end
    table.insert(items, UI.row("Nieuwe vragen ophalen", "Via wifi, uit dezelfde pakketten als Kees Study", "", function()
        app.quizMsg = "Bezig met ophalen..."
        app:refresh()
        Q.updatePacks(function(_, msg)
            app.quizMsg = msg
            app:refresh()
        end)
    end))
    if app.quizMsg then
        table.insert(items, UI.vspace(12))
        table.insert(items, UI.text(app.quizMsg, { size = 18, width = UI.INNER() }))
    end
    return UI.page(UI.vgroup(items))
end

return M
