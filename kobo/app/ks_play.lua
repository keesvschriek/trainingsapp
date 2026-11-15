-- Spelen tegen de computer: menu en speelscherm. De partij wordt bewaard.

local UIManager = require("ui/uimanager")
local AI = require("ks_ai")
local Board = require("ks_board")
local C = require("ks_chess")
local Store = require("ks_store")
local UI = require("ks_ui")

local M = {}

local START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

local function posKey(fen) return fen:match("^(%S+ %S+ %S+ %S+)") end

local function results() return Store.get("play.results", {}) end

local function addResult(level, outcome)
    local r = results()
    local cur = r[level] or { win = 0, draw = 0, loss = 0 }
    cur[outcome] = cur[outcome] + 1
    r[level] = cur
    Store.set("play.results", r)
end

function M.summary()
    local g = Store.get("play.game")
    if g and not g.over then return "Partij bezig op niveau " .. AI.level(g.level).name end
    local r, w, d, l = results(), 0, 0, 0
    for _, v in pairs(r) do w, d, l = w + v.win, d + v.draw, l + v.loss end
    if w + d + l == 0 then return "Vier niveaus, van beginner tot sterker" end
    return ("Gewonnen %d, remise %d, verloren %d"):format(w, d, l)
end

--- Einde van de partij? Geeft een tekst en de uitslag voor de speler terug.
local function ending(g, s)
    local st = C.status(s)
    local mine = g.color
    if st == "mate" then
        local loserIsMe = s.turn == mine
        return loserIsMe and "Schaakmat. De computer wint." or "Schaakmat. Jij wint.", loserIsMe and "loss" or "win"
    end
    if st == "stalemate" then return "Pat: remise.", "draw" end
    if AI.insufficient(s) then return "Te weinig materiaal om mat te geven: remise.", "draw" end
    if s.half >= 100 then return "Vijftig zetten zonder slag of pionzet: remise.", "draw" end
    local count = 0
    for _, f in ipairs(g.history) do if posKey(f) == posKey(C.toFEN(s)) then count = count + 1 end end
    if count >= 3 then return "Drie keer dezelfde stelling: remise.", "draw" end
    return nil
end

local function save(g) Store.set("play.game", g); Store.flush() end

local function newGame(level, color)
    local g = { level = level, color = color, history = { START }, over = false }
    save(g)
    return g
end

--- Het speelscherm.
function M.game(app)
    local g = Store.get("play.game")
    if not g then return M.menu(app) end
    local S = app.playState or {}
    app.playState = S
    local s = C.fromFEN(g.history[#g.history])
    local lv = AI.level(g.level)
    local myTurn = s.turn == g.color and not g.over

    local function finishIfOver(state)
        local text, outcome = ending(g, state)
        if text then
            g.over = true
            g.result = text
            addResult(g.level, outcome)
        end
        save(g)
    end

    local function computerMove()
        S.thinking = true
        app:refresh()
        UIManager:scheduleIn(0.15, function()
            local cur = C.fromFEN(g.history[#g.history])
            local m = AI.choose(cur, g.level)
            S.thinking = false
            if m then
                local n = C.make(cur, m)
                table.insert(g.history, C.toFEN(n))
                g.last = { from = m.from, to = m.to }
                finishIfOver(n)
            end
            app:refresh()
        end)
    end

    local function onTap(sq)
        if not myTurn or S.thinking then return end
        local b = s.board
        if S.selected then
            local m = C.find(s, S.selected, sq)
            if m then
                local n = C.make(s, m)
                table.insert(g.history, C.toFEN(n))
                g.last = { from = m.from, to = m.to }
                S.selected, S.dots, S.tip = nil, nil, nil
                finishIfOver(n)
                if not g.over then computerMove() else app:refresh() end
                return
            end
        end
        if b[sq] and C.color_of(b[sq]) == g.color then
            S.selected = sq
            S.dots = {}
            for _, mv in ipairs(C.legal(s, sq)) do S.dots[mv.to] = true end
        else
            S.selected, S.dots = nil, nil
        end
        app:refresh()
    end

    -- computer begint als jij zwart speelt
    if not g.over and s.turn ~= g.color and not S.thinking then
        S.thinking = true
        UIManager:scheduleIn(0.3, function() S.thinking = false; computerMove() end)
    end

    local status
    if g.over then status = g.result
    elseif S.thinking or s.turn ~= g.color then status = "De computer denkt na..."
    elseif C.inCheck(s) then status = "Schaak! Jij bent aan zet."
    else status = "Jij bent aan zet." end
    if S.tip and not g.over then status = status .. " " .. S.tip end

    local marks = {}
    if C.inCheck(s) then marks[C.kingSquare(s, s.turn)] = true end
    if S.tipMove then marks[S.tipMove.from] = true; marks[S.tipMove.to] = true end

    local header = UI.header("Tegen de computer", function() app.playState = nil; app:back() end,
        ("Niveau %s · jij speelt %s · zet %d"):format(lv.name, g.color == "w" and "wit" or "zwart", s.full))
    local statusW = UI.text(status, { size = 21, width = UI.INNER(), font = (g.over or C.inCheck(s)) and "bold" or "sans" })
    local row = {}
    if not g.over then
        table.insert(row, { "Zet terug", function()
            -- terug naar de laatste keer dat jij aan zet was
            if #g.history <= 1 or S.thinking then return end
            repeat table.remove(g.history) until #g.history <= 1 or C.fromFEN(g.history[#g.history]).turn == g.color
            g.last, S.selected, S.dots, S.tip, S.tipMove = nil, nil, nil, nil, nil
            save(g)
            app:refresh()
        end, small = true, disabled = #g.history <= 2 })
        table.insert(row, { "Tip", function()
            if not myTurn then return end
            local m = AI.choose(s, "normaal")
            if m then
                S.tipMove = { from = m.from, to = m.to }
                S.tip = "Tip: " .. C.name(m.from) .. " naar " .. C.name(m.to) .. "."
            end
            app:refresh()
        end, small = true, disabled = not myTurn })
    end
    table.insert(row, { "Nieuwe partij", function() app.playState = nil; app:replace(M.menu) end, small = true, primary = g.over })
    local footer = UI.buttonRow(row)

    local used = header:getSize().h + statusW:getSize().h + footer:getSize().h + UI.px(UI.TOPPAD + 30 + 16 + 40)
    local size = math.max(UI.px(200), math.min(UI.INNER(), UI.H() - used))
    local board = Board:new{
        size = size, state = s, flip = g.color == "b", onTap = onTap,
        selected = S.selected, dots = S.dots, last = g.last, marks = marks,
    }
    return UI.page(UI.vgroup({ header, UI.center(board, UI.INNER(), board:getSize().h), UI.vspace(16), statusW }), footer)
end

--- Menu: niveau en kleur kiezen, of verder met de bewaarde partij.
function M.menu(app)
    local g = Store.get("play.game")
    local choice = app.playChoice or { level = Store.get("play.level", "makkelijk"), color = "w" }
    app.playChoice = choice
    local items = { UI.header("Tegen de computer", function() app:back() end, M.summary() .. ". Achter een niveau: gewonnen-remise-verloren.") }
    if g and not g.over then
        table.insert(items, UI.row("Verder met je partij", ("Niveau %s, zet %d"):format(AI.level(g.level).name, C.fromFEN(g.history[#g.history]).full), "›", function()
            app.playState = nil
            app:replace(M.game)
        end))
        table.insert(items, UI.vspace(16))
    end
    table.insert(items, UI.text("Niveau", { font = "serif", size = 24 }))
    UI.rowPad = 18
    local r = results()
    local desc = {
        beginner = "Doet vaak zomaar iets. Om de regels te oefenen.",
        makkelijk = "Kijkt één zet vooruit en laat soms iets liggen.",
        normaal = "Rekent slagwisselingen goed door.",
        sterker = "Denkt een paar seconden na per zet.",
        sterk = "Denkt een paar seconden na per zet.",
    }
    for _, lv in ipairs(AI.LEVELS) do
        local res = r[lv.key]
        local right = (res and (res.win .. "-" .. res.draw .. "-" .. res.loss .. "  ") or "") .. (choice.level == lv.key and "●" or "")
        table.insert(items, UI.row(lv.name, desc[lv.key], right, function()
            choice.level = lv.key
            Store.set("play.level", lv.key)
            app:refresh()
        end))
    end
    UI.rowPad = nil
    table.insert(items, UI.vspace(14))
    table.insert(items, UI.text("Jij speelt met", { font = "serif", size = 24 }))
    table.insert(items, UI.vspace(10))
    table.insert(items, UI.buttonRow({
        { (choice.color == "w" and "● " or "") .. "Wit", function() choice.color = "w"; app:refresh() end, primary = choice.color == "w", small = true },
        { (choice.color == "b" and "● " or "") .. "Zwart", function() choice.color = "b"; app:refresh() end, primary = choice.color == "b", small = true },
    }))
    local footer = UI.vgroup({
        UI.button("Start nieuwe partij", function()
            newGame(choice.level, choice.color)
            app.playState = nil
            app:replace(M.game)
        end, { width = UI.INNER(), primary = true }),
    })
    return UI.page(UI.vgroup(items), footer)
end

return M
