-- JSON lezen met rapidjson (in KOReader ingebouwd, in C): ongeveer tien keer sneller dan de Lua-versie.
-- Lukt dat niet, dan de gewone Lua-versie. Schrijven blijft via de Lua-versie (bekend gedrag voor lege lijsten).

local J = {}
local okRj, rj = pcall(require, "rapidjson")
local slow = require("json")

-- rapidjson geeft null als userdata; de rest van de app (en json.encode) kent de null van de Lua-versie.
local NULL = slow.util and slow.util.null
local function fix(t, depth)
    if depth > 40 then return end
    for k, v in pairs(t) do
        if type(v) == "table" then fix(v, depth + 1)
        elseif type(v) == "userdata" then t[k] = NULL end
    end
end

function J.decode(s)
    if okRj and type(s) == "string" then
        local ok, v = pcall(rj.decode, s)
        if ok and v ~= nil then
            if type(v) == "table" then fix(v, 0) elseif type(v) == "userdata" then v = NULL end
            return v
        end
    end
    return slow.decode(s)
end

J.encode = slow.encode
J.util = slow.util

return J
