-- Regressietest: elk scherm openen via de echte knoppen en de belangrijkste handelingen doen.
-- Meldt "KSTEST FOUT" bij een foutscherm of een fout in een stap. Aan het eind een telling.
local s = {}
local fouten, schermen = 0, 0
local function add(f) s[#s + 1] = f end

add(function()
    local logger = require("logger")
    local warn = logger.warn
    logger.warn = function(...)
        local a, t = { ... }, {}
        for i = 1, select("#", ...) do t[i] = tostring(a[i]) end
        local msg = table.concat(t, " ")
        if msg:find("Kees Personal fout", 1, true) or msg:find("achtergrond", 1, true) then
            fouten = fouten + 1
            print("KSTEST FOUT " .. msg)
        end
        return warn(...)
    end
end)

--- Knop indrukken en controleren dat er geen foutscherm komt.
local function press(label) add(function(c) schermen = schermen + 1; c.press(label) end) end
local function go(get) add(function(c) schermen = schermen + 1; c.app():go(get()) end) end
local function back() add(function(c) c.app():back() end) end
local function home() add(function(c) c.app():home() end) end
local function shot(n) add(function(c) c.shot("r_" .. n) end) end
local function run(f) add(function(c) f(c) end) end

-- Beginscherm en mappen
shot("home")
press("Kees Study"); shot("studie")
press("Leerlijnen"); press("NAVO-alfabet")
run(function(c)
    local L = require("ks_leer")
    -- een ronde beginnen en een vraag beantwoorden via de echte knoppen
    for _, t in ipairs(require("ks_ui").painted) do if tostring(t.label):match("^Oefen") or tostring(t.label):match("^Begin") then t.callback(); return end end
end)
shot("leer_vraag")
run(function(c)
    local UI = require("ks_ui")
    for _, t in ipairs(UI.painted) do if t.label and t.label ~= "‹ Terug" and t.label ~= "Home" and t.label ~= "Licht" and t.label ~= "Verversen" then t.callback(); return end end
end)
shot("leer_antwoord")
home()
press("Kees Study"); press("Leerkaarten"); back()
press("Quiz"); back()
press("Schaken"); press("Schaken leren"); back(); press("Tegen de computer"); back(); press("Puzzel van de dag"); back(); back()
press("Topografie op de kaart"); back()
press("Puzzels"); press("Woordzoeker"); shot("woord")
run(function(c)
    local g = require("ks_store").get("ws.game")
    if g and g.grid then return end
    c.press("Normaal")
end)
shot("woord_spel")
back()
press("Tijdlijn"); shot("tijdlijn")
run(function(c) pcall(c.press, "Verder 1/2") end)
shot("tijdlijn2")
home()

press("Sport"); shot("sport"); back()
press("Groei"); shot("groei")
press("Opvolgen"); shot("opvolgen"); back()
press("Notities"); back()
press("Je week"); shot("week"); back()
press("Defensie-module"); back()
press("Dag afsluiten"); shot("avond"); back()
press("Dagtekst"); back()
press("Gewoontes"); back()
home()

press("Tools"); shot("tools")
press("Rekenmachine"); back(); press("Stopwatch"); back(); press("Tempo berekenen"); back(); press("Omrekenen"); back(); press("Wereldklok"); back(); press("Intervaltimer"); back()
home()

press("Lezen"); shot("lezen")
press("Fragment van de dag"); back(); press("Te lezen"); back(); press("Op deze dag"); back(); press("Radionieuws van deze dag"); back()
home()

press("Instellingen"); shot("instellingen")
press("Scherm"); shot("scherm"); back()
press("Telefoon-app"); back(); press("Sport"); back(); press("Rooster"); back(); press("Nieuws"); back()
press("Bijwerken en back-ups"); shot("bijwerken")
press("Back-ups op de Kobo"); back(); press("Back-up in de cloud"); back()
home()

press("Nieuws"); shot("nieuws")
go(function() return require("ks_jouwkamer").page end); shot("jk"); back()
go(function() return require("ks_wetten").page end); back()
go(function() return require("ks_kamer").page end); back()
home()

-- Achtergrondronde in stappen (met de proxy) en daarna opnieuw het beginscherm
run(function()
    require("ks_news").refresh(function() end, true)
end)
for _ = 1, 40 do add(function() end) end
shot("home_na")

-- een knop met een fout mag de app niet laten afsluiten (verwacht: precies één fout gemeld, app werkt door)
add(function(c)
    local UI = require("ks_ui")
    c.app():go(function(a) return UI.page(UI.vgroup({ UI.header("Test", function() a:back() end), UI.button("Kapot", function() error("testfout") end) })) end)
end)
press("Kapot")
shot("na_fout")
press("‹ Terug")
add(function(c) c.app():home() end)
shot("home_eind")
add(function()
    print(("KSTEST klaar: %d schermen, %d fouten (1 verwacht van de testknop)"):format(schermen, fouten))
end)
return s
