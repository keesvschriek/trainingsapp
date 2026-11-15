local here = (arg and arg[0] or ""):match("(.*/)") or "./"
package.path = here .. "../app/?.lua;" .. package.path
local C = require("ks_chess")
local AI = require("ks_ai")
local function seq(seed) local x = seed return function() x = (x * 1103515245 + 12345) % 2147483648; return x / 2147483648 end end
local function uci(m) return m and C.uci(m) or "nil" end
-- 1. hangende dame slaan
for _, lv in ipairs({"makkelijk","normaal","sterk"}) do
  local m = AI.choose(C.fromFEN("4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1"), lv, seq(1))
  assert(uci(m) == "d2d5", lv .. " slaat dame niet: " .. uci(m))
end
-- 2. mat in 1
for _, lv in ipairs({"makkelijk","normaal","sterk"}) do
  local m = AI.choose(C.fromFEN("6k1/5ppp/8/8/8/8/8/3R2K1 w - - 0 1"), lv, seq(2))
  assert(uci(m) == "d1d8", lv .. " mist mat: " .. uci(m))
end
-- 3. herdersmat voorkomen (zwart aan zet)
for _, lv in ipairs({"normaal","sterk"}) do
  local s = C.fromFEN("r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 3 3")
  local m = AI.choose(s, lv, seq(3))
  local n = C.make(s, m)
  for _, r in ipairs(C.legal(n)) do assert(C.status(C.make(n, r)) ~= "mate", lv .. " laat mat toe na " .. uci(m)) end
  print(lv .. " verdedigt met " .. uci(m))
end
-- 4. snelheid
local positions = {
  "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
  "r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P4/2PBPN2/PP1N1PPP/R2QK2R w KQ - 0 8",
  "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
}
for _, lv in ipairs({"beginner","makkelijk","normaal","sterk"}) do
  local worst, total = 0, 0
  for _, f in ipairs(positions) do
    local t = os.clock()
    local m, n = AI.choose(C.fromFEN(f), lv, seq(4))
    local d = os.clock() - t
    total = total + d
    if d > worst then worst = d end
  end
  print(("%-10s gemiddeld %.2fs, langst %.2fs"):format(lv, total / #positions, worst))
end
-- 5. partij computer tegen computer tot het einde (max 120 zetten)
local s = C.fromFEN("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
local r = seq(9)
local moves = 0
while moves < 120 do
  local st = C.status(s)
  if st == "mate" or st == "stalemate" or AI.insufficient(s) or s.half >= 100 then print("einde: " .. tostring(st) .. " na " .. moves .. " zetten") break end
  local m = AI.choose(s, s.turn == "w" and "normaal" or "makkelijk", r)
  s = C.make(s, m)
  moves = moves + 1
end
print("partij ok, stand: " .. C.toFEN(s))
