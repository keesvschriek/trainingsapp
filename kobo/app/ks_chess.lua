-- Schaakregels: legale zetten, schaak, mat, pat, rokade, en passant en promotie.
-- Velden 1..64: a1 = 1, h1 = 8, a8 = 57, h8 = 64.
-- Stukken: hoofdletter = wit (PNBRQK), kleine letter = zwart.

local C = {}

local FILES = "abcdefgh"

function C.sq(name)
    local f = FILES:find(name:sub(1, 1), 1, true)
    local r = tonumber(name:sub(2, 2))
    if not f or not r then return nil end
    return (r - 1) * 8 + f
end

function C.name(sq)
    local f = (sq - 1) % 8 + 1
    local r = math.floor((sq - 1) / 8) + 1
    return FILES:sub(f, f) .. r
end

local function file_of(sq) return (sq - 1) % 8 end
local function rank_of(sq) return math.floor((sq - 1) / 8) end
local function color_of(p) if not p then return nil end return p:match("%u") and "w" or "b" end
C.color_of = color_of

function C.fromFEN(fen)
    local parts = {}
    for p in fen:gmatch("%S+") do parts[#parts + 1] = p end
    local s = { board = {}, turn = parts[2] or "w", castle = parts[3] or "-", ep = nil, half = tonumber(parts[5]) or 0, full = tonumber(parts[6]) or 1 }
    local rank, file = 7, 0
    for ch in (parts[1] or ""):gmatch(".") do
        if ch == "/" then
            rank = rank - 1; file = 0
        elseif ch:match("%d") then
            file = file + tonumber(ch)
        else
            s.board[rank * 8 + file + 1] = ch
            file = file + 1
        end
    end
    if parts[4] and parts[4] ~= "-" then s.ep = C.sq(parts[4]) end
    if s.castle == "" then s.castle = "-" end
    return s
end

function C.toFEN(s)
    local rows = {}
    for r = 7, 0, -1 do
        local row, empty = "", 0
        for f = 0, 7 do
            local p = s.board[r * 8 + f + 1]
            if p then
                if empty > 0 then row = row .. empty; empty = 0 end
                row = row .. p
            else
                empty = empty + 1
            end
        end
        if empty > 0 then row = row .. empty end
        rows[#rows + 1] = row
    end
    return table.concat(rows, "/") .. " " .. s.turn .. " " .. s.castle .. " " .. (s.ep and C.name(s.ep) or "-") .. " " .. s.half .. " " .. s.full
end

local function copy(s)
    local b, src = {}, s.board
    for i = 1, 64 do b[i] = src[i] end
    return { board = b, turn = s.turn, castle = s.castle, ep = s.ep, half = s.half, full = s.full, kw = s.kw, kb = s.kb }
end

-- Bestaat het veld (f + df, r + dr)? Geeft het veldnummer terug of nil.
local function step(sq, df, dr)
    local f, r = file_of(sq) + df, rank_of(sq) + dr
    if f < 0 or f > 7 or r < 0 or r > 7 then return nil end
    return r * 8 + f + 1
end

local KNIGHT = { {1,2},{2,1},{2,-1},{1,-2},{-1,-2},{-2,-1},{-2,1},{-1,2} }
local KING = { {1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1} }
local ROOK = { {1,0},{-1,0},{0,1},{0,-1} }
local BISHOP = { {1,1},{1,-1},{-1,1},{-1,-1} }

-- Vooraf berekend per veld: sprongen van paard en koning, en stralen voor toren en loper.
local NJ, KJ, RRAYS, BRAYS = {}, {}, {}, {}
for sq = 1, 64 do
    NJ[sq], KJ[sq], RRAYS[sq], BRAYS[sq] = {}, {}, {}, {}
    for _, d in ipairs(KNIGHT) do local t = step(sq, d[1], d[2]); if t then NJ[sq][#NJ[sq] + 1] = t end end
    for _, d in ipairs(KING) do local t = step(sq, d[1], d[2]); if t then KJ[sq][#KJ[sq] + 1] = t end end
    for _, pair in ipairs({ { ROOK, RRAYS }, { BISHOP, BRAYS } }) do
        for _, d in ipairs(pair[1]) do
            local ray, t = {}, step(sq, d[1], d[2])
            while t do ray[#ray + 1] = t; t = step(t, d[1], d[2]) end
            if #ray > 0 then pair[2][sq][#pair[2][sq] + 1] = ray end
        end
    end
end

local function rayHit(b, rays, a, q)
    for i = 1, #rays do
        local ray = rays[i]
        for j = 1, #ray do
            local p = b[ray[j]]
            if p then
                if p == a or p == q then return true end
                break
            end
        end
    end
    return false
end

--- Wordt veld sq aangevallen door kleur by?
function C.attacked(s, sq, by)
    local b = s.board
    local white = by == "w"
    local f = (sq - 1) % 8
    -- pionnen: een witte pion valt schuin omhoog aan, staat dus een rij lager
    if white then
        if sq > 8 then
            if f > 0 and b[sq - 9] == "P" then return true end
            if f < 7 and b[sq - 7] == "P" then return true end
        end
    else
        if sq <= 56 then
            if f > 0 and b[sq + 7] == "p" then return true end
            if f < 7 and b[sq + 9] == "p" then return true end
        end
    end
    local n, k = white and "N" or "n", white and "K" or "k"
    local nj = NJ[sq]
    for i = 1, #nj do if b[nj[i]] == n then return true end end
    local kj = KJ[sq]
    for i = 1, #kj do if b[kj[i]] == k then return true end end
    if white then
        return rayHit(b, RRAYS[sq], "R", "Q") or rayHit(b, BRAYS[sq], "B", "Q")
    end
    return rayHit(b, RRAYS[sq], "r", "q") or rayHit(b, BRAYS[sq], "b", "q")
end

function C.kingSquare(s, color)
    local k = color == "w" and "K" or "k"
    local cached = color == "w" and s.kw or s.kb
    if cached and s.board[cached] == k then return cached end
    for i = 1, 64 do
        if s.board[i] == k then
            if color == "w" then s.kw = i else s.kb = i end
            return i
        end
    end
end

function C.inCheck(s, color)
    color = color or s.turn
    local k = C.kingSquare(s, color)
    return k ~= nil and C.attacked(s, k, color == "w" and "b" or "w")
end

-- Pseudo-legale zetten: {from, to, promo, flag}. flag: "ep", "castle", "double"
local function pseudo(s)
    local moves, b, me = {}, s.board, s.turn
    local them = me == "w" and "b" or "w"
    local function add(from, to, flag)
        local p = b[from]
        if (p == "P" and rank_of(to) == 7) or (p == "p" and rank_of(to) == 0) then
            for _, pr in ipairs({ "q", "r", "b", "n" }) do
                moves[#moves + 1] = { from = from, to = to, promo = me == "w" and pr:upper() or pr, flag = flag }
            end
        else
            moves[#moves + 1] = { from = from, to = to, flag = flag }
        end
    end
    for sq = 1, 64 do
        local p = b[sq]
        if p and color_of(p) == me then
            local kind = p:lower()
            if kind == "p" then
                local up = me == "w" and 1 or -1
                local one = step(sq, 0, up)
                if one and not b[one] then
                    add(sq, one)
                    local start = me == "w" and 1 or 6
                    local two = step(sq, 0, 2 * up)
                    if rank_of(sq) == start and two and not b[two] then add(sq, two, "double") end
                end
                for _, df in ipairs({ -1, 1 }) do
                    local t = step(sq, df, up)
                    if t then
                        if b[t] and color_of(b[t]) == them then add(sq, t) end
                        if s.ep == t then add(sq, t, "ep") end
                    end
                end
            elseif kind == "n" or kind == "k" then
                local jumps = kind == "n" and NJ[sq] or KJ[sq]
                for i = 1, #jumps do
                    local t = jumps[i]
                    if not b[t] or color_of(b[t]) == them then add(sq, t) end
                end
                if kind == "k" then
                    local rights = s.castle
                    local home = me == "w" and 5 or 61
                    if sq == home and not C.attacked(s, home, them) then
                        local K, Q = (me == "w" and "K" or "k"), (me == "w" and "Q" or "q")
                        if rights:find(K, 1, true) and not b[home + 1] and not b[home + 2] and b[home + 3] == (me == "w" and "R" or "r")
                            and not C.attacked(s, home + 1, them) and not C.attacked(s, home + 2, them) then
                            add(sq, home + 2, "castle")
                        end
                        if rights:find(Q, 1, true) and not b[home - 1] and not b[home - 2] and not b[home - 3] and b[home - 4] == (me == "w" and "R" or "r")
                            and not C.attacked(s, home - 1, them) and not C.attacked(s, home - 2, them) then
                            add(sq, home - 2, "castle")
                        end
                    end
                end
            else
                local lists = {}
                if kind ~= "b" then for _, r in ipairs(RRAYS[sq]) do lists[#lists + 1] = r end end
                if kind ~= "r" then for _, r in ipairs(BRAYS[sq]) do lists[#lists + 1] = r end end
                for i = 1, #lists do
                    local ray = lists[i]
                    for j = 1, #ray do
                        local t = ray[j]
                        if b[t] then
                            if color_of(b[t]) == them then add(sq, t) end
                            break
                        end
                        add(sq, t)
                    end
                end
            end
        end
    end
    return moves
end

local function strip(rights, chars)
    for c in chars:gmatch(".") do rights = rights:gsub(c, "") end
    return rights == "" and "-" or rights
end

--- Voer een zet uit; geeft een nieuwe stand terug.
function C.make(s, m)
    local n = copy(s)
    local b = n.board
    local p = b[m.from]
    local captured = b[m.to]
    b[m.to] = m.promo or p
    b[m.from] = nil
    if m.flag == "ep" then
        b[m.to + (s.turn == "w" and -8 or 8)] = nil
        captured = s.turn == "w" and "p" or "P"
    elseif m.flag == "castle" then
        if m.to > m.from then b[m.to - 1] = b[m.to + 1]; b[m.to + 1] = nil
        else b[m.to + 1] = b[m.to - 2]; b[m.to - 2] = nil end
    end
    n.ep = m.flag == "double" and (m.from + m.to) / 2 or nil
    if p == "K" then n.kw = m.to elseif p == "k" then n.kb = m.to end
    -- rokaderechten
    if p == "K" then n.castle = strip(n.castle, "KQ") elseif p == "k" then n.castle = strip(n.castle, "kq") end
    for _, sqr in ipairs({ m.from, m.to }) do
        if sqr == 1 then n.castle = strip(n.castle, "Q") elseif sqr == 8 then n.castle = strip(n.castle, "K")
        elseif sqr == 57 then n.castle = strip(n.castle, "q") elseif sqr == 64 then n.castle = strip(n.castle, "k") end
    end
    n.half = (p:lower() == "p" or captured) and 0 or s.half + 1
    if s.turn == "b" then n.full = s.full + 1 end
    n.turn = s.turn == "w" and "b" or "w"
    return n, captured
end

function C.legal(s, from)
    local out = {}
    local b = s.board
    local me = s.turn
    local them = me == "w" and "b" or "w"
    local ksq = C.kingSquare(s, me)
    local K = me == "w" and "K" or "k"
    local list = pseudo(s)
    for i = 1, #list do
        local m = list[i]
        if not from or m.from == from then
            -- zet tijdelijk op het bord zelf uitvoeren, controleren en terugzetten (sneller dan kopiëren)
            local piece, captured = b[m.from], b[m.to]
            local epSq, epPiece
            b[m.to] = piece
            b[m.from] = nil
            if m.flag == "ep" then
                epSq = m.to + (me == "w" and -8 or 8)
                epPiece = b[epSq]
                b[epSq] = nil
            end
            local k = piece == K and m.to or ksq
            local illegal = k ~= nil and C.attacked(s, k, them)
            b[m.from] = piece
            b[m.to] = captured
            if epSq then b[epSq] = epPiece end
            if not illegal then out[#out + 1] = m end
        end
    end
    return out
end

--- "mate", "stalemate", "check" of nil
function C.status(s)
    local any = #C.legal(s) > 0
    if C.inCheck(s) then return any and "check" or "mate" end
    if not any then return "stalemate" end
    return nil
end

--- Zoek de legale zet van from naar to (bij promotie standaard een dame).
function C.find(s, from, to, promo)
    local found
    for _, m in ipairs(C.legal(s, from)) do
        if m.to == to then
            if not m.promo then return m end
            if (promo and m.promo:lower() == promo:lower()) or (not promo and m.promo:lower() == "q") then found = m end
        end
    end
    return found
end

--- Zet in gewone notatie, bijv. "e2-e4" of "Pg7-g8=D".
function C.uci(m) return C.name(m.from) .. C.name(m.to) .. (m.promo and m.promo:lower() or "") end

function C.perft(s, depth)
    if depth == 0 then return 1 end
    local n = 0
    for _, m in ipairs(C.legal(s)) do n = n + C.perft(C.make(s, m), depth - 1) end
    return n
end

-- Nederlandse namen van de stukken
C.NAMES = { k = "koning", q = "dame", r = "toren", b = "loper", n = "paard", p = "pion" }

-- Tekens voor op het bord (FreeSerif heeft ze allemaal)
C.GLYPH = { K = "♔", Q = "♕", R = "♖", B = "♗", N = "♘", P = "♙", k = "♚", q = "♛", r = "♜", b = "♝", n = "♞", p = "♟" }

return C
