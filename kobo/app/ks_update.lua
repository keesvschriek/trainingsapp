-- De app zelf bijwerken via wifi. Haalt manifest.json op van GitHub Pages,
-- vergelijkt per bestand de md5 en downloadt alleen wat veranderd is.

local DataStorage = require("datastorage")
local json = require("ks_json")
local lfs = require("libs/libkoreader-lfs")
local md5 = require("ffi/MD5")
local Net = require("ks_net")

local U = {}
U.BASE = os.getenv("KEES_STUDY_UPDATE_URL") or "https://keesvschriek.github.io/trainingsapp/kobo/"

local function appDir() return require("ks_main").dir end

-- Waar komt een bestand uit het manifest terecht?
-- Bestanden voor NickelMenu staan buiten de app; alleen bijwerken als die map er is (dus op de Kobo).
U.NM_DIR = os.getenv("KEES_STUDY_NM_DIR") or "/mnt/onboard/.adds/nm"

local function target(path)
    if path:sub(1, 8) == "patches/" then return DataStorage:getDataDir() .. "/" .. path end
    if path:sub(1, 3) == "nm/" then
        if lfs.attributes(U.NM_DIR, "mode") ~= "directory" then return nil end
        return U.NM_DIR .. "/" .. path:sub(4)
    end
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
            local t = target(f.p)
            local have = t and lfs.attributes(t, "mode") == "file" and md5.sumFile(t) or nil
            if t and have ~= f.md5 then
                changed[#changed + 1] = f
                bytes = bytes + (f.size or 0)
            end
        end
        callback(true, { version = m.version, files = changed, bytes = bytes, changes = type(m.changes) == "table" and m.changes or nil })
    end, { onFail = function(msg) callback(false, msg) end })
end

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
end

local function writeAll(path, data)
    mkdirs(path)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

local function rmTree(dir)
    if lfs.attributes(dir, "mode") ~= "directory" then return end
    for name in lfs.dir(dir) do
        if name ~= "." and name ~= ".." then
            local p = dir .. "/" .. name
            if lfs.attributes(p, "mode") == "directory" then rmTree(p) else os.remove(p) end
        end
    end
    lfs.rmdir(dir)
end

local function backupDir() return appDir() .. "/.backup" end

--- Is er een vorige versie om naar terug te gaan?
function U.hasBackup()
    return lfs.attributes(backupDir() .. "/files.txt", "mode") == "file"
end

function U.backupVersion()
    local v = readAll(backupDir() .. "/version.txt")
    return v and v:match("[^\n]+") or "onbekend"
end

--- Zet de bestanden van voor de laatste update terug.
function U.rollback()
    local list = readAll(backupDir() .. "/files.txt")
    if not list then return false, "Er is geen vorige versie bewaard." end
    for p in list:gmatch("[^\n]+") do
        local kind, path = p:match("^(%a+) (.+)$")
        local t = target(path)
        if kind == "old" then
            local data = readAll(backupDir() .. "/files/" .. path)
            if data then writeAll(t, data) end
        elseif kind == "new" then
            os.remove(t) -- bestond voor de update nog niet
        end
    end
    local v = readAll(backupDir() .. "/version.txt")
    if v then writeAll(appDir() .. "/version.txt", v) end
    rmTree(backupDir())
    return true
end

--- Download de veranderde bestanden en zet ze pas op hun plek als alles goed binnen is.
--- Eerst gaat er een kopie van de huidige bestanden naar .backup, zodat je terug kunt.
--- progress(i, n) wordt aangeroepen tussen de bestanden, zodat het scherm kan bijwerken.
--- Je voortgang (in de instellingenmap van KOReader) wordt nooit aangeraakt.
function U.apply(info, callback, progress)
    local UIManager = require("ui/uimanager")
    Net.online(function()
        local tmp = appDir() .. "/.update"
        rmTree(tmp)
        local staged = {}
        local i = 0
        local function finish()
            -- 1. kopie van wat er nu staat
            rmTree(backupDir())
            local lines = {}
            for _, st in ipairs(staged) do
                local old = readAll(st.to)
                if old then
                    if not writeAll(backupDir() .. "/files/" .. st.p, old) then return callback(false, "Kan geen kopie maken van " .. st.p .. ".") end
                    lines[#lines + 1] = "old " .. st.p
                else
                    lines[#lines + 1] = "new " .. st.p
                end
            end
            writeAll(backupDir() .. "/version.txt", (readAll(appDir() .. "/version.txt") or "onbekend\n"))
            writeAll(backupDir() .. "/files.txt", table.concat(lines, "\n") .. "\n")
            -- 2. nieuwe bestanden op hun plek; gaat er iets mis, dan alles terug
            for _, st in ipairs(staged) do
                mkdirs(st.to)
                os.remove(st.to)
                if not os.rename(st.from, st.to) then
                    U.rollback()
                    rmTree(tmp)
                    return callback(false, "Kan " .. st.p .. " niet vervangen. De vorige versie is teruggezet.")
                end
            end
            rmTree(tmp)
            writeAll(appDir() .. "/version.txt", (info.version or "") .. "\n")
            callback(true, #staged)
        end
        local function step()
            i = i + 1
            local f = info.files[i]
            if not f then return finish() end
            if progress then progress(i, #info.files) end
            local ok, body = Net.get(U.BASE .. "files/" .. f.p .. "?v=" .. f.md5)
            if not ok then rmTree(tmp); return callback(false, f.p .. ": " .. body) end
            local file = tmp .. "/" .. f.p
            if not writeAll(file, body) then rmTree(tmp); return callback(false, "Kan " .. f.p .. " niet opslaan.") end
            if md5.sumFile(file) ~= f.md5 then rmTree(tmp); return callback(false, f.p .. " is niet goed binnengekomen. Probeer het opnieuw.") end
            staged[#staged + 1] = { p = f.p, from = file, to = target(f.p) }
            Net.touch()
            UIManager:scheduleIn(0.05, step)
        end
        step()
    end, { onFail = function(msg) callback(false, msg) end })
end

return U
