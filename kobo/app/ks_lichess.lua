-- Schaakpuzzel van de dag, van Lichess (openbaar, zonder inloggen).
-- Ophalen via wifi; daarna offline op te lossen op het bord van de app.

local UIManager = require("ui/uimanager")
local UI = require("ks_ui")
local Store = require("ks_store")
local C = require("ks_chess")
local Board = require("ks_board")

local L = {}

L.URL = os.getenv("KEES_STUDY_LICHESS_URL") or "https://lichess.org/api/puzzle/daily"

local THEMES = {
    mate = "mat", mateIn1 = "mat in 1", mateIn2 = "mat in 2", mateIn3 = "mat in 3", fork = "vork", pin = "penning",
    skewer = "spies", sacrifice = "offer", endgame = "eindspel", middlegame = "middenspel", opening = "opening",
    short = "kort", long = "lang", crushing = "beslissend voordeel", advantage = "voordeel", hangingPiece = "hangend stuk",
    discoveredAttack = "aftrekaanval", deflection = "afleiding", attraction = "lokken", backRankMate = "mat op de onderste rij",
    promotion = "promotie", kingsideAttack = "aanval op de koningsvleugel", quietMove = "stille zet", defensiveMove = "verdedigende zet",
}

--- SAN ("Nf3", "exd5", "O-O", "e8=Q+") naar een legale zet in stand s.
function L.fromSAN(s, san)
    san = san:gsub("[+#!?]", "")
    local list = C.legal(s)
    if san == "O-O" or san == "O-O-O" then
        for _, m in ipairs(list) do
            if m.flag == "castle" and ((san == "O-O" and m.to > m.from) or (san == "O-O-O" and m.to < m.from)) then return m end
        end
        return nil
    end
    local piece, rest = san:match("^([KQRBN]?)(.*)$")
    local promo = rest:match("=?([QRBN])$")
    if promo then rest = rest:gsub("=?[QRBN]$", "") end
    rest = rest:gsub("x", "")
    local dis, dest = rest:match("^(.-)(%a%d)$")
    if not dest then return nil end
    local to = C.sq(dest)
    for _, m in ipairs(list) do
        local p = s.board[m.from]
        local kind = p:upper()
        local want = piece ~= "" and piece or "P"
        if m.to == to and kind == want then
            local from = C.name(m.from)
            local okDis = dis == "" or (#dis == 1 and (from:sub(1, 1) == dis or from:sub(2, 2) == dis)) or from == dis
            local okPromo = (not promo and not m.promo) or (promo and m.promo and m.promo:upper() == promo)
            if okDis and okPromo then return m end
        end
    end
end

--- Stand na de partijzetten, of nil.
function L.positionFrom(pgn, initialPly)
    local s = C.fromFEN("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    local moves = {}
    for tok in pgn:gmatch("%S+") do
        if not tok:match("^%d+%.") and not tok:match("^[%d%-/%*]+$") then table.insert(moves, tok) end
    end
    local n = #moves
    if type(initialPly) == "number" and initialPly + 1 < n then n = initialPly + 1 end
    local last
    for i = 1, n do
        local m = L.fromSAN(s, moves[i])
        if not m then return nil end
        last = { from = m.from, to = m.to }
        s = C.make(s, m)
    end
    return s, last
end

function L.fetch(done)
    require("ks_net").online(function()
        local ok, body = require("ks_net").get(L.URL, { Accept = "application/json" })
        if not ok then return done(false, body) end
        local good, j = pcall(require("json").decode, body)
        if not good or type(j) ~= "table" or type(j.puzzle) ~= "table" or type(j.game) ~= "table" then return done(false, "Onverwacht antwoord van Lichess.") end
        local pz = j.puzzle
        if type(j.game.pgn) ~= "string" or type(pz.solution) ~= "table" then return done(false, "Puzzel onvolledig.") end
        local s, last = L.positionFrom(j.game.pgn, type(pz.initialPly) == "number" and pz.initialPly or nil)
        if not s then return done(false, "Kon de stand niet opbouwen.") end
        local sol = {}
        for _, u in ipairs(pz.solution) do if type(u) == "string" then table.insert(sol, u) end end
        local themes = {}
        for _, t in ipairs(type(pz.themes) == "table" and pz.themes or {}) do if type(t) == "string" and THEMES[t] then table.insert(themes, THEMES[t]) end end
        Store.set("lichess.puzzle", {
            id = type(pz.id) == "string" and pz.id or "?", date = os.date("%Y-%m-%d"),
            rating = type(pz.rating) == "number" and pz.rating or nil, fen = C.toFEN(s), last = last,
            solution = sol, themes = themes, step = 1, wrong = 0, solved = false,
        })
        done(true)
    end, { onFail = function(msg) done(false, msg) end })
end

local function findUci(s, u)
    local from, to, promo = C.sq(u:sub(1, 2)), C.sq(u:sub(3, 4)), u:sub(5, 5)
    return C.find(s, from, to, promo ~= "" and promo or nil)
end

function L.page(app)
    local W = UI.INNER()
    local p = Store.get("lichess.puzzle")
    local st = app.lpz or {}
    app.lpz = st
    local header = UI.header("Puzzel van de dag", function() app.lpz = nil; app:back() end,
        p and (("Lichess · rating %s%s"):format(p.rating or "?", #(p.themes or {}) > 0 and (" · " .. table.concat(p.themes, ", ")) or "")) or "Van Lichess, elke dag een nieuwe")
    local function fetchBtn(primary)
        return { p and p.date == os.date("%Y-%m-%d") and "Opnieuw ophalen" or "Puzzel ophalen", function()
            app.lpzMsg = "Bezig met ophalen..."
            app:refresh()
            UIManager:scheduleIn(0.2, function()
                L.fetch(function(ok, err)
                    app.lpz = nil
                    if ok then app.lpzMsg = nil else app.lpzMsg = "Ophalen mislukt: " .. tostring(err) end
                    app:refresh()
                end)
            end)
        end, small = true, primary = primary }
    end
    if not p then
        local items = { header, UI.text("Nog geen puzzel. Tik op Puzzel ophalen; daarna kun je hem ook zonder wifi oplossen.", { size = 19, width = W }) }
        if app.lpzMsg then table.insert(items, UI.vspace(10)); table.insert(items, UI.text(app.lpzMsg, { size = 17, font = "bold", width = W })) end
        return UI.page(UI.vgroup(items), UI.buttonRow({ fetchBtn(true) }))
    end
    local s = C.fromFEN(p.fen)
    -- zetten die al gedaan zijn opnieuw toepassen
    local last = p.last
    for i = 1, (p.step or 1) - 1 do
        local m = findUci(s, p.solution[i])
        if m then s = C.make(s, m); last = { from = m.from, to = m.to } end
    end
    local myColor = C.fromFEN(p.fen).turn
    local solved = (p.step or 1) > #p.solution
    local function save() Store.set("lichess.puzzle", p) end
    local function onTap(sq)
        if solved or s.turn ~= myColor then return end
        if st.selected then
            local m = C.find(s, st.selected, sq)
            if m then
                st.selected, st.dots = nil, nil
                local want = p.solution[p.step]
                local isMate = false
                local n = C.make(s, m)
                if C.status(n) == "mate" then isMate = true end
                if C.uci(m) == want or (isMate and p.step == #p.solution) then
                    p.step = p.step + 1
                    st.wrongSq = nil
                    app.lpzMsg = nil
                    save()
                    if p.step <= #p.solution then
                        -- tegenzet na een korte pauze
                        app:refresh()
                        UIManager:scheduleIn(0.6, function() p.step = p.step + 1; save(); app:refresh() end)
                        return
                    end
                    p.solved = true
                    local stats = Store.get("lichess.stats", { solved = 0, clean = 0 })
                    stats.solved = stats.solved + 1
                    if (p.wrong or 0) == 0 then stats.clean = stats.clean + 1 end
                    Store.set("lichess.stats", stats)
                    save()
                else
                    p.wrong = (p.wrong or 0) + 1
                    st.wrongSq = m.to
                    app.lpzMsg = "Niet de beste zet. Probeer het nog eens."
                    save()
                end
                app:refresh()
                return
            end
        end
        local b = s.board
        if b[sq] and ((b[sq]:match("%u") and "w" or "b") == myColor) then
            st.selected = sq
            st.dots = {}
            for _, mv in ipairs(C.legal(s, sq)) do st.dots[mv.to] = true end
        else
            st.selected, st.dots = nil, nil
        end
        app:refresh()
    end
    local status
    if solved then
        status = "Opgelost" .. ((p.wrong or 0) == 0 and ", in één keer goed." or (" met " .. p.wrong .. " misser" .. (p.wrong == 1 and "" or "s") .. "."))
    else
        status = (myColor == "w" and "Wit" or "Zwart") .. " aan zet. Vind de beste zet."
    end
    local stats = Store.get("lichess.stats", { solved = 0, clean = 0 })
    local statusW = UI.vgroup({
        UI.text(app.lpzMsg or status, { size = 19, font = "medium", width = W }),
        UI.vspace(4),
        UI.text(("Opgelost: %d, waarvan %d in één keer"):format(stats.solved, stats.clean), { size = 15, color = UI.INK2 }),
    })
    local marks = {}
    if st.tip then marks[st.tip] = true end
    local footer = UI.buttonRow({
        { "Tip", function()
            local u = p.solution[p.step]
            if u then st.tip = C.sq(u:sub(1, 2)); app:refresh() end
        end, small = true, disabled = solved },
        { "Oplossing", function()
            if solved then return end
            p.wrong = (p.wrong or 0) + 1
            p.step = p.step + 1
            save()
            if p.step <= #p.solution then
                app:refresh()
                UIManager:scheduleIn(0.6, function() p.step = p.step + 1; save(); app:refresh() end)
                return
            end
            app:refresh()
        end, small = true, disabled = solved },
        fetchBtn(solved),
    })
    local used = header:getSize().h + statusW:getSize().h + footer:getSize().h + UI.px(UI.TOPPAD + 30 + 16 + 40)
    local size = math.max(UI.px(200), math.min(W, UI.H() - used))
    local board = Board:new{ size = size, state = s, flip = myColor == "b", onTap = onTap, selected = st.selected, dots = st.dots, last = last, marks = marks, wrong = st.wrongSq }
    return UI.page(UI.vgroup({ header, UI.center(board, W, board:getSize().h), UI.vspace(16), statusW }), footer)
end

return L
