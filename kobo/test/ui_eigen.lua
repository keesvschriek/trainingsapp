local s = {}
local function add(f) s[#s + 1] = f end
add(function(c)
  local L = require("ks_leer")
  L.addOwn("t1", "Testlijst een", { { "Vraag 1", "Antwoord een" }, { "Vraag 2", "Antwoord twee" } })
  L.addOwn("t2", "Testlijst twee", { { "Vraag A", "Antwoord aa" }, { "Vraag B", "Antwoord bb" } })
  c.app().leerLine = "eigen"; c.app():go(L.linePage)
end)
add(function(c) c.shot("e1"); c.press("Opruimen") end)
add(function(c) c.shot("e2"); c.press("Testlijst een") end)
add(function(c) c.shot("e3"); print("KSTEST over", #require("ks_store").get("leer.own", {})); c.press("Klaar") end)
add(function(c) c.shot("e4") end)
add(function(c) require("ks_leer").removeOwn("t2") end)
return s
