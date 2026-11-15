-- Schaaklessen: overzicht en de speler die stap voor stap door een les gaat.

local Board = require("ks_board")
local C = require("ks_chess")
local LESSONS = require("ks_lessons")
local Store = require("ks_store")
local UI = require("ks_ui")

local M = {}

local function progress()
    return Store.get("chess", {})
end

local function saveStep(li, si, done)
    local p = progress()
    local cur = p[li] or { step = 0, done = false }
    cur.step = math.max(cur.step or 0, si)
    if done then cur.done = true end
    p[li] = cur
    Store.set("chess", p)
    Store.flush()
end

function M.summary()
    local p = progress()
    for i, les in ipairs(LESSONS) do
        if not (p[i] and p[i].done) then
            return ("Les %d van %d: %s"):format(i, #LESSONS, les.title)
        end
    end
    return "Alle lessen afgerond. Herhalen kan altijd."
end

function M.lessonList(app)
    UI.rowPad = 22
    local p = progress()
    local list = {}
    for i, les in ipairs(LESSONS) do
        local st = p[i]
        local right = st and st.done and "klaar" or (st and st.step > 0 and (st.step .. "/" .. #les.steps) or "")
        table.insert(list, UI.row(i .. ". " .. les.title, les.intro, right, function() app:go(M.player(i)) end))
    end
    table.insert(list, 1, UI.header("Schaken leren", function() app:back() end, "Van nul af. Elke les heeft uitleg en oefeningen op het bord."))
    local page = UI.page(UI.vgroup(list))
    UI.rowPad = nil
    return page
end

local function sqset(names)
    local t = {}
    for _, n in ipairs(names or {}) do t[C.sq(n)] = true end
    return t
end

local function movesFrom(s, sqname)
    local t = {}
    for _, m in ipairs(C.legal(s, C.sq(sqname))) do t[m.to] = true end
    return t
end

--- Speler voor les li. Geeft een builder terug met eigen toestand.
function M.player(li)
    local les = LESSONS[li]
    local saved = progress()[li]
    -- verder waar je gebleven was, tenzij de les al af is
    local S = { i = (saved and not saved.done) and math.min(#les.steps, (saved.step or 0) + 1) or 1 }

    local function resetStep()
        local st = les.steps[S.i]
        S.state = st.fen and C.fromFEN(st.fen) or nil
        S.selected, S.last, S.wrong = nil, nil, nil
        S.dots = st.show and movesFrom(S.state, st.show) or nil
        S.picked = {}       -- bij "reach": aangetikte velden
        S.solved = st.kind == "info"
        S.feedback = nil
        S.failed = nil
        S.marks = nil
        S.answer = nil      -- bij "choice": gekozen index (in volgorde op scherm)
        S.order = nil
        if st.kind == "choice" then
            -- vaste, maar door elkaar gehusselde volgorde per stap
            local idx = { 1, 2, 3, 4 }
            local seed = li * 31 + S.i * 7
            for k = 4, 2, -1 do
                seed = (seed * 1103515245 + 12345) % 2147483648
                local j = seed % k + 1
                idx[k], idx[j] = idx[j], idx[k]
            end
            S.order = idx
        end
    end
    resetStep()

    return function(app)
        local st = les.steps[S.i]
        local n = #les.steps

        local function go(delta)
            S.i = math.max(1, math.min(n, S.i + delta))
            resetStep()
            app:render("page")
        end

        local function solved(msg)
            S.solved = true
            S.feedback = msg
            saveStep(li, S.i, S.i == n)
        end

        -- tikken op het bord ----------------------------------------------------
        local function onTap(sq)
            if S.solved and st.kind ~= "info" then return end
            if st.kind == "info" then
                -- vrij verkennen: tik een stuk aan om te zien waar het heen kan
                local p = S.state.board[sq]
                if p then
                    local save = S.state.turn
                    S.state.turn = C.color_of(p)
                    S.dots = movesFrom(S.state, C.name(sq))
                    S.state.turn = save
                    S.selected = sq
                else
                    S.dots, S.selected = nil, nil
                end
            elseif st.kind == "tap" then
                if sq == C.sq(st.target) then
                    S.marks = { [sq] = true }
                    S.wrong = nil
                    solved("Goed, dat is " .. st.target .. ".")
                else
                    S.wrong = sq
                    S.feedback = "Dat is " .. C.name(sq) .. ". Probeer het nog eens."
                end
            elseif st.kind == "reach" then
                if sq == C.sq(st.from) then return end
                S.picked[sq] = not S.picked[sq] or nil
                S.feedback = nil
            elseif st.kind == "move" then
                local b = S.state.board
                if S.selected then
                    local m = C.find(S.state, S.selected, sq)
                    if m then
                        local before = S.state
                        S.state = C.make(before, m)
                        S.last = { from = m.from, to = m.to }
                        S.selected, S.dots = nil, nil
                        local uci = C.uci(m):sub(1, 4)
                        local ok = false
                        if type(st.goal) == "table" then
                            for _, g in ipairs(st.goal) do if g == uci then ok = true end end
                        elseif st.goal == "mate" then
                            ok = C.status(S.state) == "mate"
                        elseif st.goal == "any" then
                            ok = true
                        elseif st.goal == "nomate" then
                            ok = true
                            for _, r in ipairs(C.legal(S.state)) do
                                if C.status(C.make(S.state, r)) == "mate" then ok = false break end
                            end
                        end
                        if ok then
                            local msg = st.ok or (C.status(S.state) == "mate" and "Mat. Goed gedaan." or "Goed.")
                            if st.prefer then
                                local best = false
                                for _, g in ipairs(st.prefer) do if g == uci then best = true end end
                                if not best then msg = st.better or msg end
                            end
                            solved(msg)
                        else
                            S.feedback = (st.goal == "mate" and "Dat is geen mat." or "Dat is niet de bedoelde zet.") .. " Tik op Opnieuw."
                            S.failed = true
                        end
                        app:refresh()
                        return
                    end
                    if b[sq] and C.color_of(b[sq]) == S.state.turn then
                        S.selected = sq
                        S.dots = movesFrom(S.state, C.name(sq))
                    else
                        S.selected, S.dots = nil, nil
                    end
                else
                    if b[sq] and C.color_of(b[sq]) == S.state.turn then
                        S.selected = sq
                        S.dots = movesFrom(S.state, C.name(sq))
                        if not next(S.dots) then S.feedback = "Dit stuk kan nergens heen." end
                    elseif b[sq] then
                        S.feedback = (S.state.turn == "w" and "Wit" or "Zwart") .. " is aan zet. Tik op een eigen stuk."
                    end
                end
            end
            app:refresh()
        end

        -- opbouw van het scherm -------------------------------------------------
        -- Eerst alles onder het bord maken en meten; het bord krijgt de ruimte die overblijft.
        local header = UI.header(les.title, function() app:back() end, ("Stap %d van %d"):format(S.i, n))
        local below = {}
        if S.state and (st.kind == "move" or st.kind == "reach") and not S.solved then
            table.insert(below, UI.text((S.state.turn == "w" and "Wit" or "Zwart") .. " is aan zet", { size = 15, color = UI.INK2 }))
            table.insert(below, UI.vspace(6))
        end
        table.insert(below, UI.text(st.text, { font = "serif", size = S.state and 21 or 24, width = UI.INNER(), line_height = 0.35 }))

        if st.kind == "choice" then
            table.insert(below, UI.vspace(12))
            local half = S.state ~= nil
            local bw = half and math.floor((UI.INNER() - UI.px(14)) / 2) or UI.INNER()
            local function make(pos, minh)
                local k = S.order[pos]
                local label = st.a[k]
                local primary = false
                if S.answer then
                    if k == 1 then label = "✓ " .. label; primary = true
                    elseif pos == S.answer then label = "✗ " .. label end
                end
                return UI.button(label, function()
                    if S.answer then return end
                    S.answer = pos
                    if k == 1 then solved("Goed. " .. (st.why or "")) else
                        S.solved = true
                        S.feedback = "Niet goed. " .. (st.why or "")
                        saveStep(li, S.i, S.i == n)
                    end
                    app:refresh()
                end, { width = bw, primary = primary, small = half, minh = minh })
            end
            local buttons = {}
            for pos = 1, 4 do buttons[pos] = make(pos) end
            if half then
                for r = 0, 1 do
                    local h = math.max(buttons[r * 2 + 1]:getSize().h, buttons[r * 2 + 2]:getSize().h)
                    buttons[r * 2 + 1] = make(r * 2 + 1, h)
                    buttons[r * 2 + 2] = make(r * 2 + 2, h)
                end
            end
            if half then
                -- twee rijen van twee; knoppen in een rij even hoog maken
                for r = 0, 1 do
                    local a, b = buttons[r * 2 + 1], buttons[r * 2 + 2]
                    table.insert(below, UI.hgroup({ a, UI.hspace(14), b }, "top"))
                    table.insert(below, UI.vspace(10))
                end
            else
                for _, b in ipairs(buttons) do table.insert(below, b); table.insert(below, UI.vspace(12)) end
            end
        end

        if S.feedback then
            table.insert(below, UI.vspace(10))
            table.insert(below, UI.text(S.feedback, { size = 18, width = UI.INNER(), font = S.solved and "bold" or "sans" }))
        end

        -- knoppen onderaan -------------------------------------------------------
        local row = {}
        local last = S.i == n
        local nextLabel = last and "Les afronden" or "Volgende"
        local function nextAction()
            if st.kind == "info" then saveStep(li, S.i, last) end
            if last then app:back() else go(1) end
        end
        if S.i > 1 then table.insert(row, { "Vorige", function() go(-1) end }) end
        if st.kind == "info" or S.solved then
            table.insert(row, { nextLabel, nextAction, primary = true })
        elseif st.kind == "reach" then
            table.insert(row, { "Klaar", function()
                local want = movesFrom(C.fromFEN(st.fen), st.from)
                local missing, extra = {}, {}
                for sq in pairs(want) do if not S.picked[sq] then table.insert(missing, C.name(sq)) end end
                for sq in pairs(S.picked) do if not want[sq] then table.insert(extra, C.name(sq)) end end
                table.sort(missing); table.sort(extra)
                S.dots = want
                if #missing == 0 and #extra == 0 then
                    local count = 0
                    for _ in pairs(want) do count = count + 1 end
                    solved("Goed, alle " .. count .. " velden.")
                else
                    local parts = {}
                    if #missing > 0 then table.insert(parts, "Je miste: " .. table.concat(missing, ", ") .. ".") end
                    if #extra > 0 then table.insert(parts, "Niet goed: " .. table.concat(extra, ", ") .. ".") end
                    table.insert(parts, "De stippen tonen het goede antwoord." .. (st.hint and (" " .. st.hint) or ""))
                    S.solved = true
                    S.feedback = table.concat(parts, " ")
                    saveStep(li, S.i, last)
                end
                app:refresh()
            end, primary = true })
        elseif st.kind == "move" then
            if S.failed then
                table.insert(row, { "Opnieuw", function() resetStep(); S.failed = nil; app:refresh() end, primary = true })
            elseif st.hint then
                table.insert(row, { "Hint", function() S.feedback = st.hint; app:refresh() end })
            end
            table.insert(row, { "Overslaan", function() saveStep(li, S.i, last); if last then app:back() else go(1) end end })
        elseif st.kind == "tap" or st.kind == "choice" then
            table.insert(row, { "Overslaan", function() if last then app:back() else go(1) end end })
        end
        local footer = UI.buttonRow(row)
        local items = { header }
        if S.state then
            local used = header:getSize().h + UI.vgroup(below):getSize().h + footer:getSize().h + UI.px(UI.TOPPAD + 30 + 16 + 40)
            local boardSize = math.max(UI.px(160), math.min(UI.INNER(), UI.H() - used))
            local marks = st.kind == "reach" and S.picked or (S.marks or sqset(st.marks))
            local board = Board:new{
                size = boardSize,
                state = S.state,
                marks = marks,
                dots = S.dots,
                selected = S.selected or (st.kind == "reach" and C.sq(st.from)) or nil,
                last = S.last,
                wrong = S.wrong,
                onTap = onTap,
            }
            table.insert(items, UI.center(board, UI.INNER(), board:getSize().h))
            table.insert(items, UI.vspace(16))
        end
        for _, w in ipairs(below) do table.insert(items, w) end
        return UI.page(UI.vgroup(items), footer)
    end
end

return M
