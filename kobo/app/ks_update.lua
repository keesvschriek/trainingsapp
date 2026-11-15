-- De app zelf bijwerken via wifi. Haalt manifest.json op van GitHub Pages,
-- vergelijkt per bestand de md5 en downloadt alleen wat veranderd is.

local DataStorage = require("datastorage")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local md5 = require("ffi/MD5")
local Net = require("ks_net")

local U = {}
U.BASE = os.getenv("KEES_STUDY_UPDATE_URL") or "https://keesvschriek.github.io/trainingsapp/kobo/"

local function appDir() return require("ks_main").dir end

-- Waar komt een bestand uit het manifest terecht?
local function target(path)
    if path:sub(1, 8) == "patches/" then return DataStorage:getDataDir() .. "/" .. path end
    return appDir() .. "/" .. path
end

local function mkdirs(file)
    local dir = file:match("(.*)/[^/]+$")
    local cur = ""
    for part in dir:gmatch("[^/]+") do
        cur = cur .. "/" .. part
        if lfs.attributes(cur, "mode") ~= "directory" then lfs.mkdir(cur) end
    end
end

function U.localVersion()
    local f = io.open(appDir() .. "/version.txt", "rb")
    if not f then return "onbekend" end
    local v = f:read("*l") or "onbekend"
    f:close()
    return v
end

--- Controleer welke bestanden nieuw of anders zijn. callback(ok, info|fout)
--- info = { version, files = { {p, md5, size} }, bytes }
function U.check(callback)
    Net.online(function()
        local ok, body = Net.get(U.BASE .. "manifest.json?t=" .. os.time())
        if not ok then return callback(false, body) end
        local good, m = pcall(json.decode, body)
        if not good or type(m) ~= "table" or type(m.files) ~= "table" then return callback(false, "Onverwacht bestand ontvangen.") end
        local changed, bytes = {}, 0
        for _, f in ipairs(m.files) do
            local have = lfs.attributes(target(f.p), "mode") == "file" and md5.sumFile(target(f.p)) or nil
            if have ~= f.md5 then
                changed[#changed + 1] = f
                bytes = bytes + (f.size or 0)
            end
        end
        callback(true, { version = m.version, files = changed, bytes = bytes })
    end)
end

--- Download de veranderde bestanden en zet ze pas op hun plek als alles goed binnen is.
function U.apply(info, callback)
    Net.online(function()
        local tmp = appDir() .. "/.update"
        local staged = {}
        for _, f in ipairs(info.files) do
            local ok, body = Net.get(U.BASE .. "files/" .. f.p .. "?v=" .. f.md5)
            if not ok then return callback(false, f.p .. ": " .. body) end
            local file = tmp .. "/" .. f.p
            mkdirs(file)
            local out = io.open(file, "wb")
            if not out then return callback(false, "Kan " .. f.p .. " niet opslaan.") end
            out:write(body)
            out:close()
            if md5.sumFile(file) ~= f.md5 then return callback(false, f.p .. " is niet goed binnengekomen. Probeer het opnieuw.") end
            staged[#staged + 1] = { from = file, to = target(f.p) }
        end
        for _, s in ipairs(staged) do
            mkdirs(s.to)
            os.remove(s.to)
            local ok = os.rename(s.from, s.to)
            if not ok then return callback(false, "Kan " .. s.to .. " niet vervangen.") end
        end
        -- tijdelijke mappen opruimen
        pcall(function()
            lfs.rmdir(tmp .. "/data")
            lfs.rmdir(tmp .. "/patches")
            lfs.rmdir(tmp)
        end)
        local v = io.open(appDir() .. "/version.txt", "wb")
        if v then v:write(info.version or "", "\n"); v:close() end
        callback(true, #staged)
    end)
end

return U
