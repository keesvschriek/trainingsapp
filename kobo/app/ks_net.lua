-- Ophalen via wifi (https), en wifi zelf aan- en weer uitzetten.
--
-- Wifi gaat pas uit als de app hem zelf heeft aangezet én er een minuut lang
-- niets meer via het netwerk is gedaan. Zo zet de krant van de ochtendronde
-- nooit wifi uit terwijl je net iets aan het bijwerken bent.

local UIManager = require("ui/uimanager")

local Net = {}

local weTurnedOn = false
local active = 0

--- Haal een url op. headers is optioneel. Geeft (true, inhoud) of (false, foutmelding, code).
function Net.get(url, headers)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local sink = {}
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
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
