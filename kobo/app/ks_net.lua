-- Ophalen via wifi (https), en wifi zelf aan- en weer uitzetten.
--
-- Wifi gaat pas uit als de app hem zelf heeft aangezet én er een minuut lang
-- niets meer via het netwerk is gedaan. Zo zet de krant van de ochtendronde
-- nooit wifi uit terwijl je net iets aan het bijwerken bent.

local UIManager = require("ui/uimanager")

local Net = {}

local weTurnedOn = false
local active = 0

--- Op de achtergrond korter wachten op een trage server (5 sec per blok, 15 in totaal),
--- zodat één haperende bron de Kobo niet een halve minuut vasthoudt.
Net.bg = false
function Net.setTimeout(socketutil)
    if Net.bg then socketutil:set_timeout(5, 15)
    else socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT) end
end

--- Haal een url op. headers is optioneel. Geeft (true, inhoud) of (false, foutmelding, code).
function Net.get(url, headers)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local sink = {}
    Net.setTimeout(socketutil)
    local req = { url = url, method = "GET", sink = ltn12.sink.table(sink) }
    if headers then
        req.headers = {}
        for k, v in pairs(headers) do req.headers[k] = v end
    end
    local ok, code = pcall(function() return socket.skip(1, http.request(req)) end)
    socketutil:reset_timeout()
    if not ok then return false, "Verbinding mislukt." end
    if code ~= 200 then
        if type(code) == "string" then return false, "Geen verbinding (" .. code .. ")." end
        return false, "Ophalen mislukt (" .. tostring(code) .. ").", code
    end
    return true, table.concat(sink)
end

--- Algemeen verzoek (POST, PATCH...). body is een string. Geeft (true, inhoud, code) bij 2xx.
function Net.request(method, url, headers, body)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local sink = {}
    Net.setTimeout(socketutil)
    local req = { url = url, method = method, sink = ltn12.sink.table(sink), headers = {} }
    for k, v in pairs(headers or {}) do req.headers[k] = v end
    if body then
        req.source = ltn12.source.string(body)
        req.headers["Content-Length"] = tostring(#body)
    end
    local ok, code = pcall(function() return socket.skip(1, http.request(req)) end)
    socketutil:reset_timeout()
    if not ok then return false, "Verbinding mislukt." end
    local text = table.concat(sink)
    if type(code) ~= "number" then return false, "Geen verbinding (" .. tostring(code) .. ")." end
    if code < 200 or code >= 300 then return false, text ~= "" and text or ("Fout " .. code), code end
    return true, text, code
end

local function NM() return require("ui/network/manager") end

function Net.isOn()
    local ok, on = pcall(function() return NM():isWifiOn() end)
    return ok and on
end

local function turnOffLater()
    if active > 0 or not weTurnedOn then return end
    weTurnedOn = false
    pcall(function() NM():disableWifi(nil, false) end)
end

--- Zet wifi aan als dat nodig is en voer daarna callback uit.
--- opts.quiet: zonder vraag aanzetten (voor de ochtend- en avondronde).
--- opts.onFail(msg): als er na 60 seconden nog geen verbinding is.
function Net.online(callback, opts)
    opts = opts or {}
    UIManager:unschedule(turnOffLater)
    if os.getenv("KEES_STUDY_NO_WIFI_CHECK") then return callback() end -- alleen voor tests op de computer
    local nm = NM()
    local done = false
    local function run()
        if done then return end
        done = true
        active = active + 1
        local ok, err = pcall(callback)
        active = active - 1
        if not ok then require("logger").warn("Kees Personal netwerk:", err) end
        -- als wij wifi hebben aangezet: na een minuut zonder netwerkgebruik weer uit
        if weTurnedOn then
            UIManager:unschedule(turnOffLater)
            UIManager:scheduleIn(60, turnOffLater)
        end
    end
    if nm:isOnline() then return run() end
    if not Net.isOn() and opts.quiet then weTurnedOn = true end
    if nm:isConnected() then
        -- verbonden maar de online-check twijfelt: gewoon proberen
        return run()
    end
    if opts.quiet then
        nm:turnOnWifiAndWaitForConnection(run)
    else
        nm:runWhenConnected(run)
    end
    UIManager:scheduleIn(60, function()
        if not done then
            done = true
            if opts.onFail then opts.onFail("Geen verbinding. Staat wifi aan en is het netwerk in de buurt?") end
        end
    end)
end

--- Tijdens lange downloads: wifi nog even laten staan.
function Net.touch()
    if weTurnedOn then
        UIManager:unschedule(turnOffLater)
        UIManager:scheduleIn(60, turnOffLater)
    end
end

-- Achtergrondwerk ------------------------------------------------------------------
-- Een verzoek houdt de Kobo vast zolang het duurt: tikken worden pas daarna verwerkt.
-- Daarom gaat alles wat de app zelf ophaalt in kleine stappen (meestal één verzoek per stap),
-- en begint een stap pas als je een paar seconden niets hebt aangeraakt en niet in een boek leest.

Net.IDLE = os.getenv("KS_TEST") and 0 or 4 -- seconden zonder tikken voor de volgende stap
local queue, running = {}, false

local function idle()
    local Sys = package.loaded["ks_system"]
    if not Sys then return true end
    if Sys.reading and Sys.reading() then return false end
    return not Sys.idleFor or Sys.idleFor() >= Net.IDLE
end

local step
local function later(sec) UIManager:scheduleIn(sec, step) end
step = function()
    local job = queue[1]
    if not job then
        running = false
        active = math.max(0, active - 1)
        if weTurnedOn then
            UIManager:unschedule(turnOffLater)
            UIManager:scheduleIn(60, turnOffLater)
        end
        return
    end
    if not job.now and not idle() then return later(1) end
    Net.bg = not job.now
    local t0 = os.getenv("KS_TEST") and require("ui/time").now()
    local ok, again = pcall(job.fn)
    Net.bg = false
    if t0 then
        local ms = require("ui/time").to_ms(require("ui/time").now() - t0)
        if ms > 300 then print(("KSTEST stap %s %.0f ms"):format(job.name, ms)) end
    end
    if not ok then require("logger").warn("Kees Personal achtergrond:", job.name, again) end
    if not (ok and again == true) then table.remove(queue, 1) end
    later(0.05)
end

--- Bezig met achtergrondwerk?
function Net.busy() return running end

--- Taken uitvoeren in kleine stappen. jobs = { { name, fn, now }, ... }.
--- fn() geeft true terug als hij nog een stap wil (bijvoorbeeld het volgende bericht ophalen).
--- now = true: niet wachten tot je niets aanraakt (iets waar je zelf op wacht).
--- opts.quiet: wifi zonder vraag aanzetten. opts.front: vooraan in de rij. opts.onFail(msg).
function Net.background(jobs, opts)
    opts = opts or {}
    Net.online(function()
        if opts.front then
            for i = #jobs, 1, -1 do table.insert(queue, 1, jobs[i]) end
        else
            for _, j in ipairs(jobs) do table.insert(queue, j) end
        end
        if not running then
            running = true
            active = active + 1
            later(0)
        end
    end, { quiet = opts.quiet, onFail = opts.onFail })
end

--- Oude naam; wifi uitzetten gebeurt nu vanzelf (zie hierboven).
function Net.offIfWeTurnedOn() end

--- Wifi met de hand aan of uit (Instellingen).
function Net.toggle(cb)
    local nm = NM()
    if Net.isOn() then
        weTurnedOn = false
        UIManager:unschedule(turnOffLater)
        pcall(function() nm:disableWifi(function() if cb then cb() end end, true) end)
        UIManager:scheduleIn(3, function() if cb then cb() end end)
    else
        nm:turnOnWifiAndWaitForConnection(function() if cb then cb() end end)
    end
end

return Net
