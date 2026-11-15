-- Eenvoudig ophalen van bestanden via wifi (https).

local Net = {}

--- Haal een url op. Geeft (true, inhoud) of (false, foutmelding).
function Net.get(url)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local sink = {}
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local ok, code = pcall(function()
        return socket.skip(1, http.request{ url = url, method = "GET", sink = ltn12.sink.table(sink) })
    end)
    socketutil:reset_timeout()
    if not ok then return false, "Verbinding mislukt." end
    if code ~= 200 then return false, "Ophalen mislukt (" .. tostring(code) .. ")." end
    return true, table.concat(sink)
end

--- Zet wifi aan als dat nodig is en voer daarna callback uit.
function Net.online(callback)
    if os.getenv("KEES_STUDY_NO_WIFI_CHECK") then return callback() end -- alleen voor tests op de computer
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenOnline(callback)
end

return Net
