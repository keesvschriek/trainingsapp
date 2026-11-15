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

function Store.today()
    return os.date("%Y-%m-%d")
end

return Store
