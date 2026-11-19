-- Meet per scherm: bouwtijd (koud en warm), aantal bouwpogingen en tekentijd.
local T = require("ui/time")
local UIManager = require("ui/uimanager")
local function now() return T.to_ms(T.now()) end

local screens = {
    { "home", nil },
    { "studie", function() return require("ks_main").studyFolder end },
    { "lezen", function() return require("ks_main").readFolder end },
    { "groei", function() return require("ks_main").growFolder end },
    { "leerlijnen", function() return require("ks_leer").home end },
    { "quiz", function() return require("ks_quizui").home end },
    { "kaarten", function() return require("ks_cards").home end },
    { "schaaklessen", function() return require("ks_chessui").lessonList end },
    { "topo", function() return require("ks_mapui").menu end },
    { "woordzoeker", function() return require("ks_puzzles").themes end },
    { "tijdlijn", function() return require("ks_puzzles").timeline end },
    { "sport", function() return require("ks_sport").page end },
    { "nieuws", function() return require("ks_news").page end },
    { "instellingen", function() return require("ks_system").settingsPage end },
    { "tools", function() return require("ks_tools").menu end },
    { "week", function() return require("ks_week").page end },
    { "opvolgen", function() return require("ks_opvolg").page end },
    { "notities", function() return require("ks_notes").page end },
    { "avond", function() return require("ks_avond").page end },
    { "module", function() return require("ks_module").page end },
    { "dagtekst", function() return require("ks_dagtekst").page end },
    { "gewoontes", function() return require("ks_habits").page end },
    { "fragment", function() return require("ks_fragment").page end },
    { "te lezen", function() return require("ks_reading").page end },
    { "op deze dag", function() return require("ks_otd").page end },
    { "rooster", function() return require("ks_rooster").page end },
    { "jouw kamer", function() return require("ks_jouwkamer").page end },
    { "wetten", function() return require("ks_wetten").page end },
}

local res = {}
local steps = {}
local function measure(name, getBuilder, pass)
    return function(c)
        local app = c.app()
        collectgarbage("collect")
        local t0, c0 = now(), os.clock()
        local n = 0
        local b
        if getBuilder then
            local real = getBuilder()
            b = function(a) n = n + 1; return real(a) end
            app:go(b)
        else
            local real = app.stack[1]
            app.stack[1] = function(a) n = n + 1; return real(a) end
            app:home()
            app.stack[1] = real
        end
        local t1, c1 = now(), os.clock()
        UIManager:forceRePaint()
        local t2 = now()
        res[name] = res[name] or {}
        res[name][pass] = { build = t1 - t0, cpu = (c1 - c0) * 1000, n = n, paint = t2 - t1 }
        if getBuilder then app.stack[#app.stack] = nil end
    end
end
for pass = 1, 2 do
    for _, s in ipairs(screens) do table.insert(steps, measure(s[1], s[2], pass)) end
end
table.insert(steps, function()
    local Store = require("ks_store")
    local t0 = now(); Store.flush(); local t1 = now()
    local f = io.open(require("datastorage"):getSettingsDir() .. "/keesstudy.lua"); local size = f:seek("end"); f:close()
    print(("KSTEST flush %.0f ms, opslag %d kB"):format(t1 - t0, size / 1024))
    -- grootste sleutels in de opslag
    local data = Store.open().data
    local sizes = {}
    for k, v in pairs(data) do
        local ok, s = pcall(require("dump"), v)
        table.insert(sizes, { k, ok and #s or 0 })
    end
    table.sort(sizes, function(a, b) return a[2] > b[2] end)
    for i = 1, math.min(12, #sizes) do print(("KSTEST   %-22s %6.1f kB"):format(sizes[i][1], sizes[i][2] / 1024)) end
    print("KSTEST scherm             koud bouw/cpu/x  teken | warm bouw/x  teken")
    for _, s in ipairs(screens) do
        local r = res[s[1]] or {}
        local a, b = r[1] or {}, r[2] or {}
        print(("KSTEST %-16s %6.0f %6.0f %2d %6.0f | %6.0f %2d %6.0f"):format(s[1], a.build or -1, a.cpu or -1, a.n or 0, a.paint or -1, b.build or -1, b.n or 0, b.paint or -1))
    end
end)
return steps
