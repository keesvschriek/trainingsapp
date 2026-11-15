-- Ophalen via wifi (https), en wifi zelf aan- en weer uitzetten.

local Net = {}

--- Haal een url op. headers is optioneel. Geeft (true, inhoud) of (false, foutmelding, code).
function Net.get(url, headers)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local sink = {}
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local h = { ["User-Agent"] = "KeesPersonal/1.0 (Kobo)" }
    for k, v in pairs(headers or {}) do h[k] = v end
    local ok, code = pcall(function()
        return socket.skip(1, http.request{ url = url, method = "GET", headers = h, sink = ltn12.sink.table(sink) })
    end)
    socketutil:reset_timeout()
    if not ok then return false, "Verbinding mislukt." end
    if code ~= 200 then return false, "Ophalen mislukt (" .. tostring(code) .. ").", code end
    return true, table.concat(sink)
end

function Net.isOn()
    local ok, on = pcall(function() return require("ui/network/manager"):isWifiOn() end)
    return ok and on
end

--- Zet wifi aan als dat nodig is en voer daarna callback uit.
--- opts.quiet: zonder vraag aanzetten (voor de ochtend- en avondronde).
--- callback krijgt (zelfAangezet) mee: true als wifi voor deze actie is aangezet.
function Net.online(callback, opts)
    if os.getenv("KEES_STUDY_NO_WIFI_CHECK") then return callback(false) end -- alleen voor tests op de computer
    local NetworkMgr = require("ui/network/manager")
    local wasOn = Net.isOn()
    if NetworkMgr:isOnline() then return callback(false) end
    if opts and opts.quiet then
        NetworkMgr:turnOnWifiAndWaitForConnection(function() callback(not wasOn) end)
    else
        NetworkMgr:runWhenOnline(function() callback(not wasOn) end)
    end
end

--- Wifi weer uit, als wij hem hadden aangezet. Spaart batterij.
function Net.offIfWeTurnedOn(weDid)
    if not weDid or os.getenv("KEES_STUDY_NO_WIFI_CHECK") then return end
    pcall(function() require("ui/network/manager"):disableWifi(nil, false) end)
end

return Net
