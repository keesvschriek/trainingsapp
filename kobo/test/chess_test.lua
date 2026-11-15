local here = (arg and arg[0] or ""):match("(.*/)") or "./"
package.path = here .. "../app/?.lua;" .. package.path
local C = require("ks_chess")
local cases = {
  { "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", { 20, 400, 8902, 197281 } },
  { "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", { 48, 2039, 97862 } },
  { "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", { 14, 191, 2812, 43238 } },
  { "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", { 6, 264, 9467 } },
  { "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", { 44, 1486, 62379 } },
}
local fails = 0
for _, c in ipairs(cases) do
  local s = C.fromFEN(c[1])
  assert(C.toFEN(s) == c[1], "fen roundtrip " .. C.toFEN(s))
  for d, want in ipairs(c[2]) do
    local got = C.perft(s, d)
    if got ~= want then fails = fails + 1; print("FAIL", c[1], d, got, want) end
  end
end
-- mat en pat
assert(C.status(C.fromFEN("7k/6Q1/6K1/8/8/8/8/8 b - - 0 1")) == "mate")
assert(C.status(C.fromFEN("7k/8/6QK/8/8/8/8/8 b - - 0 1")) == "stalemate")
assert(C.status(C.fromFEN("4k3/8/8/8/8/8/8/4R1K1 b - - 0 1")) == "check")
print(fails == 0 and "perft ok" or ("fails " .. fails))
