-- Computertegenstander: alfa-bètazoeken met een eenvoudige evaluatie.
-- Sterk genoeg om van te leren, niet om te winnen van een clubspeler.

local C = require("ks_chess")

local AI = {}

local VALUE = { p = 100, n = 320, b = 330, r = 500, q = 900, k = 0 }

-- Plaatstabellen vanuit wit gezien, rij 8 bovenaan (zoals je naar het bord kijkt).
local PST = {
    p = {
        0, 0, 0, 0, 0, 0, 0, 0,
        50, 50, 50, 50, 50, 50, 50, 50,
        10, 10, 20, 30, 30, 20, 10, 10,
        5, 5, 10, 25, 25, 10, 5, 5,
        0, 0, 0, 20, 20, 0, 0, 0,
        5, -5, -10, 0, 0, -10, -5, 5,
        5, 10, 10, -20, -20, 10, 10, 5,
        0, 0, 0, 0, 0, 0, 0, 0,
    },
    n = {
        -50, -40, -30, -30, -30, -30, -40, -50,
        -40, -20, 0, 0, 0, 0, -20, -40,
        -30, 0, 10, 15, 15, 10, 0, -30,
        -30, 5, 15, 20, 20, 15, 5, -30,
        -30, 0, 15, 20, 20, 15, 0, -30,
        -30, 5, 10, 15, 15, 10, 5, -30,
        -40, -20, 0, 5, 5, 0, -20, -40,
        -50, -40, -30, -30, -30, -30, -40, -50,
    },
    b = {
        -20, -10, -10, -10, -10, -10, -10, -20,
        -10, 0, 0, 0, 0, 0, 0, -10,
        -10, 0, 5, 10, 10, 5, 0, -10,
        -10, 5, 5, 10, 10, 5, 5, -10,
        -10, 0, 10, 10, 10, 10, 0, -10,
        -10, 10, 10, 10, 10, 10, 10, -10,
        -10, 5, 0, 0, 0, 0, 5, -10,
        -20, -10, -10, -10, -10, -10, -10, -20,
    },
    r = {
        0, 0, 0, 0, 0, 0, 0, 0,
        5, 10, 10, 10, 10, 10, 10, 5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        0, 0, 0, 5, 5, 0, 0, 0,
    },
    q = {
        -20, -10, -10, -5, -5, -10, -10, -20,
        -10, 0, 0, 0, 0, 0, 0, -10,
        -10, 0, 5, 5, 5, 5, 0, -10,
        -5, 0, 5, 5, 5, 5, 0, -5,
        0, 0, 5, 5, 5, 5, 0, -5,
        -10, 5, 5, 5, 5, 5, 0, -10,
        -10, 0, 5, 0, 0, 0, 0, -10,
        -20, -10, -10, -5, -5, -10, -10, -20,
    },
    k = {
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -20, -30, -30, -40, -40, -30, -30, -20,
        -10, -20, -20, -20, -20, -20, -20, -10,
        20, 20, 0, 0, 0, 0, 20, 20,
        20, 30, 10, 0, 0, 10, 30, 20,
    },
    -- koning in het eindspel: naar het midden
    ke = {
        -50, -40, -30, -20, -20, -30, -40, -50,
        -30, -20, -10, 0, 0, -10, -20, -30,
        -30, -10, 20, 30, 30, 20, -10, -30,
        -30, -10, 30, 40, 40, 30, -10, -30,
        -30, -10, 30, 40, 40, 30, -10, -30,
        -30, -10, 20, 30, 30, 20, -10, -30,
        -30, -30, 0, 0, 0, 0, -30, -30,
        -50, -30, -30, -30, -30, -30, -30, -50,
    },
}

-- index in de tabel voor veld sq (1 = a1) vanuit de kleur
local function pstIndex(sq, white)
    local f = (sq - 1) % 8
    local r = math.floor((sq - 1) / 8)
    if white then return (7 - r) * 8 + f + 1 end
    return r * 8 + f + 1
end

--- Evaluatie vanuit wit gezien (positief = goed voor wit).
function AI.evaluate(s)
    local score, material = 0, 0
    for sq = 1, 64 do
        local p = s.board[sq]
        if p and p:lower() ~= "k" and p:lower() ~= "p" then material = material + VALUE[p:lower()] end
    end
    local endgame = material <= 2600
    for sq = 1, 64 do
        local p = s.board[sq]
        if p then
            local kind = p:lower()
            local white = p ~= kind
            local tbl = (kind == "k" and endgame) and PST.ke or PST[kind]
            local v = VALUE[kind] + tbl[pstIndex(sq, white)]
            score = score + (white and v or -v)
        end
    end
    return score
end

local MATE = 100000

-- Zetten sorteren: slagzetten eerst, grootste buit met de kleinste dader eerst
local function ordered(s, moves)
    local b = s.board
    for _, m in ipairs(moves) do
        local victim = b[m.to] or (m.flag == "ep" and "p") or nil
        m.order = (victim and (10 * VALUE[victim:lower()] - VALUE[b[m.from]:lower()]) or 0) + (m.promo and 800 or 0)
    end
    table.sort(moves, function(a, c) return a.order > c.order end)
    return moves
end

local nodes = 0
local deadline = nil -- os.clock()-tijd waarna het zoeken stopt
local aborted = false

-- Alleen slagzetten doorrekenen aan het einde, zodat de computer geen stuk "weggeeft" net voorbij de horizon
local function quiesce(s, alpha, beta, color, depth)
    nodes = nodes + 1
    local stand = color * AI.evaluate(s)
    if stand >= beta then return beta end
    if stand > alpha then alpha = stand end
    if depth <= 0 then return alpha end
    local caps = {}
    for _, m in ipairs(C.legal(s)) do
        if s.board[m.to] or m.flag == "ep" or m.promo then caps[#caps + 1] = m end
    end
    for _, m in ipairs(ordered(s, caps)) do
        local v = -quiesce(C.make(s, m), -beta, -alpha, -color, depth - 1)
        if v >= beta then return beta end
        if v > alpha then alpha = v end
    end
    return alpha
end

local function negamax(s, depth, alpha, beta, color, ply, qdepth)
    nodes = nodes + 1
    if deadline and nodes % 256 == 0 and os.clock() > deadline then aborted = true end
    if aborted then return 0 end
    local moves = C.legal(s)
    if #moves == 0 then
        if C.inCheck(s) then return -MATE + ply end -- mat: liever snel mat geven, laat mat krijgen
        return 0 -- pat
    end
    if s.half >= 100 then return 0 end
    if depth <= 0 then return qdepth > 0 and quiesce(s, alpha, beta, color, qdepth) or color * AI.evaluate(s) end
    local best = -math.huge
    for _, m in ipairs(ordered(s, moves)) do
        local v = -negamax(C.make(s, m), depth - 1, -beta, -alpha, -color, ply + 1, qdepth)
        if v > best then best = v end
        if v > alpha then alpha = v end
        if alpha >= beta then break end
    end
    return best
end

AI.LEVELS = {
    { key = "beginner", name = "Beginner", depth = 1, q = 0, noise = 120, blunder = 0.25 },
    { key = "makkelijk", name = "Makkelijk", depth = 2, q = 0, noise = 40, blunder = 0.05 },
    { key = "normaal", name = "Normaal", depth = 2, q = 4, noise = 10, blunder = 0 },
    { key = "sterk", name = "Sterker", depth = 3, maxdepth = 5, budget = 3, q = 4, noise = 0, blunder = 0 },
}

function AI.level(key)
    for _, l in ipairs(AI.LEVELS) do if l.key == key then return l end end
    return AI.LEVELS[2]
end

--- Kies een zet voor de partij aan zet. rnd() geeft 0..1 (voor tests vast te zetten).
function AI.choose(s, levelKey, rnd)
    rnd = rnd or math.random
    local lv = AI.level(levelKey)
    local moves = C.legal(s)
    if #moves == 0 then return nil end
    nodes = 0
    local color = s.turn == "w" and 1 or -1
    -- Een mat in één zet laat de computer nooit liggen (behalve de beginner soms)
    if lv.blunder == 0 or rnd() > lv.blunder then
        for _, m in ipairs(moves) do
            if C.status(C.make(s, m)) == "mate" then return m, nodes end
        end
    end
    if rnd() < lv.blunder then
        return moves[math.floor(rnd() * #moves) + 1], nodes
    end
    local function search(depth)
        local best, bestScore = nil, -math.huge
        local alpha, beta = -math.huge, math.huge
        for _, m in ipairs(ordered(s, moves)) do
            local v = -negamax(C.make(s, m), depth - 1, -beta, -alpha, -color, 1, lv.q)
            if aborted then return nil end
            if lv.noise > 0 then v = v + (rnd() * 2 - 1) * lv.noise end
            if v > bestScore then best, bestScore = m, v end
            if lv.noise == 0 and v > alpha then alpha = v end
        end
        return best, bestScore
    end
    deadline, aborted = nil, false
    local best, score = search(lv.depth)
    -- Dieper zoeken zolang er tijd is; een onafgemaakte zoektocht telt niet mee
    if lv.maxdepth then
        local start = os.clock()
        for d = lv.depth + 1, lv.maxdepth do
            deadline = start + lv.budget
            local b2, s2 = search(d)
            if not b2 then break end
            best, score = b2, s2
            if score > MATE / 2 then break end
        end
        deadline, aborted = nil, false
    end
    return best, nodes
end

--- Is er nog genoeg materiaal om mat te geven? (koning tegen koning, of met één licht stuk: remise)
function AI.insufficient(s)
    local minor, other = 0, 0
    for sq = 1, 64 do
        local p = s.board[sq]
        if p then
            local k = p:lower()
            if k == "n" or k == "b" then minor = minor + 1 elseif k ~= "k" then other = other + 1 end
        end
    end
    return other == 0 and minor <= 1
end

return AI
