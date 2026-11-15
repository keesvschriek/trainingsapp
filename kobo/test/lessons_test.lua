local here = (arg and arg[0] or ""):match("(.*/)") or "./"
package.path = here .. "../app/?.lua;" .. package.path
local C = require("ks_chess")
local L = require("ks_lessons")
local errors, n = 0, 0
local function err(l, i, msg) errors = errors + 1; print(("FOUT les %d stap %d: %s"):format(l, i, msg)) end
local function mates(s)
  local out = {}
  for _, m in ipairs(C.legal(s)) do if C.status(C.make(s, m)) == "mate" then out[#out+1] = C.uci(m) end end
  return out
end
for li, les in ipairs(L) do
  for si, st in ipairs(les.steps) do
    n = n + 1
    local s = st.fen and C.fromFEN(st.fen)
    if st.fen then assert(C.toFEN(s):match("^%S+") == st.fen:match("^%S+"), "fen " .. st.fen) end
    if st.kind == "tap" then if not C.sq(st.target) then err(li, si, "target") end end
    if st.kind == "reach" then
      local m = C.legal(s, C.sq(st.from))
      if #m == 0 then err(li, si, "geen zetten vanaf " .. st.from) end
      local t = {} for _, x in ipairs(m) do t[#t+1] = C.name(x.to) end
      print(("  les %d stap %d reach %s: %s"):format(li, si, st.from, table.concat(t, " ")))
    end
    if st.kind == "choice" then if not (st.a and #st.a == 4) then err(li, si, "4 antwoorden") end end
    if st.kind == "move" then
      if type(st.goal) == "table" and s.turn ~= C.color_of(s.board[C.sq(st.goal[1]:sub(1,2))]) then err(li, si, "kleur aan zet past niet") end
      if type(st.goal) == "table" then
        for _, g in ipairs(st.goal) do
          local mv = C.find(s, C.sq(g:sub(1,2)), C.sq(g:sub(3,4)))
          if not mv then err(li, si, "zet niet legaal: " .. g) end
        end
      elseif st.goal == "mate" then
        local m = mates(s)
        if #m == 0 then err(li, si, "geen mat in 1") else print(("  les %d stap %d mat: %s"):format(li, si, table.concat(m, " "))) end
      elseif st.goal == "nomate" then
        local ok = {}
        for _, m in ipairs(C.legal(s)) do if #mates(C.make(s, m)) == 0 then ok[#ok+1] = C.uci(m) end end
        print(("  les %d stap %d verdedigingen: %s"):format(li, si, table.concat(ok, " ")))
        for _, p in ipairs(st.prefer or {}) do local f = false for _, x in ipairs(ok) do if x == p then f = true end end if not f then err(li, si, "prefer werkt niet: " .. p) end end
      end
    end
  end
end
-- losse controles op inhoud
local function st(l, i) return L[l].steps[i] end
assert(C.status(C.fromFEN(st(3,11).fen)) == "stalemate", "info pat")
assert(C.status(C.fromFEN(st(3,12).fen)) == "stalemate", "vraag pat")
assert(C.status(C.fromFEN(st(3,8).fen)) == "mate", "info mat")
assert(C.status(C.fromFEN(st(5,1).fen)) == "mate", "info achterste rij")
assert(C.status(C.fromFEN(st(3,4).fen)) == "check", "schaak")
do local s = C.fromFEN(st(4,4).fen); for _, m in ipairs(C.legal(s)) do assert(m.flag ~= "castle", "rokade zou niet mogen") end end
do local s = C.fromFEN(st(7,5).fen); assert(#C.legal(s, C.sq("c6")) == 0, "penning") end
do local s = C.make(C.fromFEN(st(7,2).fen), C.find(C.fromFEN(st(7,2).fen), C.sq("d5"), C.sq("c7"))); assert(C.inCheck(s), "vork geeft schaak") end
for _, g in ipairs(st(7,7).goal) do local s0 = C.fromFEN(st(7,7).fen); local s = C.make(s0, C.find(s0, C.sq(g:sub(1,2)), C.sq(g:sub(3,4)))); assert(C.inCheck(s), "aftrek " .. g) end
assert(not C.inCheck(C.fromFEN(st(7,7).fen)), "beginstand aftrek niet schaak")
print(("%d stappen in %d lessen, %d fouten"):format(n, #L, errors))
