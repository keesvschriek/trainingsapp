-- Opslag van voortgang, records en extra vragen. Eén bestand in de KOReader-instellingenmap.

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local Store = {}
local settings

function Store.open()
    if not settings then
        settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/keesstudy.lua")
    end
    return settings
end

function Store.get(key, default)
    local v = Store.open():readSetting(key)
    if v == nil then return default end
    return v
end

function Store.set(key, value)
    Store.open():saveSetting(key, value)
end

function Store.flush()
    if settings then settings:flush() end
end

-- Back-ups ---------------------------------------------------------------------
-- Eén keer per dag een kopie van het opslagbestand, de laatste 7 dagen blijven bewaard.

local function file() return DataStorage:getSettingsDir() .. "/keesstudy.lua" end
local function backupDir() return DataStorage:getSettingsDir() .. "/keesstudy-backup" end

local function copy(from, to)
    local f = io.open(from, "rb")
    if not f then return false end
    local data = f:read("*a")
    f:close()
    if not data or #data == 0 then return false end
    local tmp = to .. ".tmp"
    local o = io.open(tmp, "wb")
    if not o then return false end
    o:write(data)
    o:close()
    os.remove(to)
    return os.rename(tmp, to)
end

function Store.backups()
    local lfs = require("libs/libkoreader-lfs")
    local list = {}
    if lfs.attributes(backupDir(), "mode") ~= "directory" then return list end
    for name in lfs.dir(backupDir()) do
        local d = name:match("^(%d%d%d%d%-%d%d%-%d%d)%.lua$")
        if d then table.insert(list, d) end
    end
    table.sort(list, function(a, b) return a > b end)
    return list
end

function Store.backup()
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(file(), "mode") ~= "file" then return end
    if lfs.attributes(backupDir(), "mode") ~= "directory" then lfs.mkdir(backupDir()) end
    local target = backupDir() .. "/" .. os.date("%Y-%m-%d") .. ".lua"
    if lfs.attributes(target, "mode") ~= "file" then copy(file(), target) end
    local list = Store.backups()
    for i = 8, #list do os.remove(backupDir() .. "/" .. list[i] .. ".lua") end
end

--- Zet een back-up terug. Daarna moet de app herstarten.
function Store.restore(date)
    local src = backupDir() .. "/" .. date .. ".lua"
    settings = nil -- niet meer wegschrijven wat nu in het geheugen staat
    copy(file(), backupDir() .. "/voor-herstel.lua")
    return copy(src, file())
end

function Store.today()
    return os.date("%Y-%m-%d")
end

return Store
