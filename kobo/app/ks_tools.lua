-- Toolbox: rekenmachine, stopwatch, tempo berekenen, omrekenen en wereldklok.
-- Bij tikken op toetsen ververst alleen het getal bovenaan, niet het hele scherm.

local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local time = require("ui/time")
local UI = require("ks_ui")
local Store = require("ks_store")

local T = {}

-- Onthoudt waar een stuk scherm staat, zodat we alleen dat stuk kunnen verversen.
local Spot = Widget:extend{ name = "spot" }
function Spot:getSize() return self[1]:getSize() end
function Spot:paintTo(bb, x, y)
    local s = self[1]:getSize()
    T.spots = T.spots or {}
    T.spots[self.name] = Geom:new{ x = x, y = y, w = s.w, h = s.h }
    self[1]:paintTo(bb, x, y)
end

local function refreshSpot(app, name, mode)
    app:rebuild()
    local r = T.spots and T.spots[name]
    if r then
        UIManager:setDirty(app, function() return mode or "ui", r end)
    else
        app:render("ui")
    end
end

-- Getallen in het Nederlands: komma, geen eindeloze decimalen.
local function fmtNum(n)
    if n ~= n or n == math.huge or n == -math.huge then return "Fout" end
    if math.abs(n) >= 1e12 then return (("%.6g"):format(n):gsub("%.", ",")) end
    local s = ("%.10f"):format(n):gsub("0+$", ""):gsub("%.$", "")
    local int, dec = s:match("^(-?%d+)%.?(%d*)$")
    if not int then return s end
    if #dec > 8 then dec = dec:sub(1, 8):gsub("0+$", "") end
    return dec ~= "" and (int .. "," .. dec) or int
end
T.fmtNum = fmtNum

--- Toetsenbord: rows = { {"7","8","9"}, ... }. special[label] = { primary = true }
local function keypad(rows, onKey, width, keyH, special)
    local gap = UI.px(10)
    local g = {}
    for r, row in ipairs(rows) do
        local items = {}
        for _, k in ipairs(row) do
            local sp = special and special[k] or {}
            table.insert(items, { k, function() onKey(k) end, primary = sp.primary, size = 26, minh = keyH })
        end
        local br = UI.buttonRow(items, width)
        table.insert(g, br)
        if r < #rows then table.insert(g, UI.vspan(gap)) end
    end
    return UI.vgroup(g)
end

-- Rekenmachine ------------------------------------------------------------------

local OPS = { ["+"] = 1, ["−"] = 1, ["×"] = 2, ["÷"] = 2 }

--- Lengte in bytes van een operator aan het eind, of 0.
local function lastOp(expr)
    for op in pairs(OPS) do
        if #expr >= #op and expr:sub(-#op) == op then return #op end
    end
    return 0
end

--- Rekent "12,5+3×4" uit (met voorrang voor × en ÷).
function T.eval(expr)
    local tokens = {}
    local i = 1
    while i <= #expr do
        local num = expr:match("^%d+,?%d*", i)
        if num then
            table.insert(tokens, tonumber((num:gsub(",", "."))))
            i = i + #num
            if expr:sub(i, i) == "%" then tokens[#tokens] = tokens[#tokens] / 100; i = i + 1 end
        else
            local found
            for op in pairs(OPS) do
                if expr:sub(i, i + #op - 1) == op then found = op break end
            end
            if not found then return nil end
            -- minteken vooraan of na een operator: negatief getal
            if found == "−" and (#tokens == 0 or type(tokens[#tokens]) == "string") then
                local n2 = expr:match("^%d+,?%d*", i + #found)
                if not n2 then return nil end
                table.insert(tokens, -tonumber((n2:gsub(",", "."))))
                i = i + #found + #n2
            else
                table.insert(tokens, found)
                i = i + #found
            end
        end
    end
    if #tokens == 0 or type(tokens[#tokens]) == "string" then table.remove(tokens) end
    -- shunting-yard
    local out, ops = {}, {}
    for _, t in ipairs(tokens) do
        if type(t) == "number" then table.insert(out, t)
        else
            while #ops > 0 and OPS[ops[#ops]] >= OPS[t] do table.insert(out, table.remove(ops)) end
            table.insert(ops, t)
        end
    end
    while #ops > 0 do table.insert(out, table.remove(ops)) end
    local st = {}
    for _, t in ipairs(out) do
        if type(t) == "number" then table.insert(st, t)
        else
            local b, a = table.remove(st), table.remove(st)
            if not a or not b then return nil end
            if t == "+" then table.insert(st, a + b)
            elseif t == "−" then table.insert(st, a - b)
            elseif t == "×" then table.insert(st, a * b)
            else table.insert(st, a / b) end
        end
    end
    return st[1]
end

function T.calc(app)
    local W = UI.INNER()
    local c = app.calc or { expr = "", result = nil }
    app.calc = c
    local function key(k)
        if k == "C" then c.expr, c.result = "", nil
        elseif k == "←" then c.expr = c.expr:gsub("[%z\1-\127\194-\244][\128-\191]*$", ""); c.result = nil
        elseif k == "=" then
            local r = T.eval(c.expr)
            if r then c.result = r; c.last = c.expr; c.expr = (fmtNum(r):gsub("^%-", "−")) end
        elseif k == "±" then
            local head, num = c.expr:match("^(.-)(%d+,?%d*)$")
            if num then
                local before = head:sub(-3) == "−" and head:sub(1, -4) or nil
                if before and (before == "" or lastOp(before) > 0) then c.expr = before .. num
                else c.expr = head .. "−" .. num end
            end
        else
            if c.result and not OPS[k] and k ~= "%" then c.expr = "" end
            c.result = nil
            if OPS[k] then
                if c.expr == "" and k ~= "−" then return end
                local n = lastOp(c.expr)
                if n > 0 and k ~= "−" then c.expr = c.expr:sub(1, -n - 1) end
            end
            if not (k == "," and (c.expr:match("%d+,%d*$"))) then c.expr = c.expr .. k end
        end
        refreshSpot(app, "calc")
    end
    local preview = T.eval(c.expr)
    local shown = c.expr ~= "" and c.expr or "0"
    local display = UI.card(UI.vgroup({
        UI.text(c.result and (c.last .. " =") or (preview and c.expr:match("[+−×÷%%]") and ("= " .. fmtNum(preview)) or " "), { size = 20, color = UI.INK2, width = W - UI.px(44), align = "right", bg = UI.FILL }),
        UI.vspace(6),
        UI.text(shown, { font = "displaybold", size = #shown > 14 and 34 or 52, width = W - UI.px(44), align = "right", bg = UI.FILL }),
    }), { fill = true, border = 0, pad = UI.px(22) })
    local items = {
        UI.header("Rekenmachine", function() app:back() end),
        Spot:new{ name = "calc", display },
        UI.vspace(18),
        keypad({
            { "C", "←", "%", "÷" },
            { "7", "8", "9", "×" },
            { "4", "5", "6", "−" },
            { "1", "2", "3", "+" },
            { "±", "0", ",", "=" },
        }, key, W, UI.px(62), { ["="] = { primary = true } }),
    }
    return UI.page(UI.vgroup(items))
end

-- Stopwatch -----------------------------------------------------------------------

local function now() return time.to_s(time.now()) end

local function fmtSw(sec, tenths)
    sec = math.max(0, sec)
    local m = math.floor(sec / 60)
    local s = sec - m * 60
    if m >= 60 then return ("%d:%02d:%02d"):format(math.floor(m / 60), m % 60, math.floor(s)) end
    if tenths then return ("%d:%02d,%d"):format(m, math.floor(s), math.floor((s * 10) % 10)) end
    return ("%d:%02d"):format(m, math.floor(s))
end

function T.stopwatch(app)
    local W = UI.INNER()
    local sw = app.sw or { acc = 0, laps = {} }
    app.sw = sw
    local elapsed = sw.acc + (sw.start and (now() - sw.start) or 0)
    local function tick()
        if app.sw ~= sw or not sw.start then return end
        pcall(function() require("ks_system").touch() end)
        refreshSpot(app, "sw", "fast")
        UIManager:scheduleIn(1, tick)
    end
    sw.tick = sw.tick or tick
    local lapRows = {}
    for i = #sw.laps, math.max(1, #sw.laps - 5), -1 do
        local l = sw.laps[i]
        table.insert(lapRows, UI.row("Ronde " .. i, "totaal " .. fmtSw(l.total, true), fmtSw(l.split, true), nil, W))
    end
    local items = {
        UI.header("Stopwatch", function() if sw.start then sw.acc = sw.acc + now() - sw.start; sw.start = nil end app:back() end),
        UI.vspace(30),
        Spot:new{ name = "sw", UI.center(UI.text(fmtSw(elapsed, not sw.start), { font = "displaybold", size = 110 }), W) },
        UI.vspace(30),
    }
    for _, r in ipairs(lapRows) do table.insert(items, r) end
    local footer = UI.buttonRow({
        { sw.start and "Stop" or (elapsed > 0 and "Verder" or "Start"), function()
            if sw.start then
                sw.acc = sw.acc + now() - sw.start
                sw.start = nil
            else
                sw.start = now()
                UIManager:unschedule(sw.tick)
                UIManager:scheduleIn(1, sw.tick)
            end
            app:refresh()
        end, primary = true, icon = sw.start and "pause" or "play" },
        { sw.start and "Ronde" or "Opnieuw", function()
            if sw.start then
                local total = sw.acc + now() - sw.start
                local prev = #sw.laps > 0 and sw.laps[#sw.laps].total or 0
                table.insert(sw.laps, { total = total, split = total - prev })
            else
                app.sw = nil
            end
            app:refresh()
        end, icon = sw.start and "flag" or "history" },
    })
    return UI.page(UI.vgroup(items), footer)
end

-- Tempo berekenen ----------------------------------------------------------------

local DISTS = { { 5, "5 km" }, { 10, "10 km" }, { 21.0975, "Halve" }, { 42.195, "Hele" } }

function T.pace(app)
    local W = UI.INNER()
    local p = app.pace or Store.get("tools.pace") or { dist = 10, t = 43 * 60 }
    app.pace = p
    local function save() Store.set("tools.pace", { dist = p.dist, t = p.t }); app:refresh() end
    local cur
    for i, d in ipairs(DISTS) do if math.abs(d[1] - p.dist) < 0.001 then cur = i end end
    local perKm = p.t / p.dist
    local kmh = p.dist / (p.t / 3600)
    local function adj(label, f) return { label, function() f(); save() end, small = true } end
    local distTxt = fmtNum(math.floor(p.dist * 100 + 0.5) / 100) .. " km"
    local items = {
        UI.header("Tempo berekenen", function() app:back() end, "Afstand en tijd erin, tempo eruit"),
        UI.section("Afstand"),
        UI.segmented({ "5 km", "10 km", "Halve", "Hele" }, cur or 0, function(i) p.dist = DISTS[i][1]; save() end),
        UI.vspace(10),
        UI.hgroup({
            UI.buttonRow({ adj("− 1 km", function() p.dist = math.max(1, p.dist - 1) end), adj("− 0,1", function() p.dist = math.max(0.5, p.dist - 0.1) end) }, math.floor(W * 0.36)),
            UI.center(UI.text(distTxt, { font = "display", size = 26 }), W - 2 * math.floor(W * 0.36)),
            UI.buttonRow({ adj("+ 0,1", function() p.dist = p.dist + 0.1 end), adj("+ 1 km", function() p.dist = p.dist + 1 end) }, math.floor(W * 0.36)),
        }),
        UI.vspace(10),
        UI.section("Tijd"),
        UI.hgroup({
            UI.buttonRow({ adj("− 1 min", function() p.t = math.max(60, p.t - 60) end), adj("− 5 s", function() p.t = math.max(30, p.t - 5) end) }, math.floor(W * 0.36)),
            UI.center(UI.text(fmtSw(p.t), { font = "display", size = 26 }), W - 2 * math.floor(W * 0.36)),
            UI.buttonRow({ adj("+ 5 s", function() p.t = p.t + 5 end), adj("+ 1 min", function() p.t = p.t + 60 end) }, math.floor(W * 0.36)),
        }),
        UI.vspace(22),
    }
    local half = math.floor((W - UI.px(14)) / 2)
    local paceCard = UI.card(UI.vgroup({
        UI.text("Tempo", { size = 16, font = "bold", color = UI.WHITE, bg = UI.BLACK }),
        UI.text(fmtSw(perKm) .. " /km", { font = "displaybold", size = 34, color = UI.WHITE, bg = UI.BLACK }),
    }), { dark = true, width = half })
    local speedCard = UI.card(UI.vgroup({
        UI.text("Snelheid", { size = 16, font = "bold" }),
        UI.text(fmtNum(math.floor(kmh * 100 + 0.5) / 100) .. " km/u", { font = "display", size = 34 }),
    }), { width = half, height = paceCard:getSize().h })
    table.insert(items, UI.hgroup({ paceCard, UI.hspace(14), speedCard }, "top"))
    table.insert(items, UI.vspace(14))
    -- tussentijden
    local marks = {}
    for _, k in ipairs({ 1, 5, 10, 15, 20, 21.0975, 30, 40, 42.195 }) do
        if k <= p.dist + 0.001 then table.insert(marks, k) end
    end
    if #marks > 5 then marks = { marks[1], marks[2], marks[3], marks[#marks - 1], marks[#marks] } end
    table.insert(items, UI.section("Tussentijden"))
    for _, k in ipairs(marks) do
        local label = k == 21.0975 and "Halve marathon" or (k == 42.195 and "Marathon" or (fmtNum(k) .. " km"))
        table.insert(items, UI.hgroup({ UI.box(UI.text(label, { size = 18 }), math.floor(W * 0.6)), UI.text(fmtSw(perKm * k), { size = 18, font = "bold" }) }))
        table.insert(items, UI.vspace(6))
    end
    return UI.page(UI.vgroup(items))
end

-- Omrekenen ------------------------------------------------------------------------

local CONV = {
    { name = "Afstand", units = { "km", "mijl" }, f = { function(v) return v / 1.609344 end, function(v) return v * 1.609344 end } },
    { name = "Gewicht", units = { "kg", "lb" }, f = { function(v) return v * 2.2046226218 end, function(v) return v / 2.2046226218 end } },
    { name = "Temperatuur", units = { "°C", "°F" }, f = { function(v) return v * 9 / 5 + 32 end, function(v) return (v - 32) * 5 / 9 end } },
    { name = "Snelheid", units = { "km/u", "mijl/u" }, f = { function(v) return v / 1.609344 end, function(v) return v * 1.609344 end } },
}

function T.convert(app)
    local W = UI.INNER()
    local c = app.conv or { cat = 1, from = 1, input = "" }
    app.conv = c
    local cat = CONV[c.cat]
    local v = tonumber((c.input:gsub(",", "."))) or 0
    local out = cat.f[c.from](v)
    local to = cat.units[3 - c.from]
    local extra = ""
    if cat.name == "Snelheid" and c.from == 1 and v > 0 then extra = "tempo " .. fmtSw(3600 / v) .. " /km" end
    local function key(k)
        if k == "C" then c.input = ""
        elseif k == "←" then c.input = c.input:sub(1, -2)
        elseif k == "±" then c.input = c.input:sub(1, 1) == "-" and c.input:sub(2) or ("-" .. c.input)
        elseif k == "," then if not c.input:find(",") then c.input = (c.input == "" and "0" or c.input) .. "," end
        elseif #c.input < 12 then c.input = c.input .. k end
        refreshSpot(app, "conv")
    end
    local names = {}
    for i, x in ipairs(CONV) do names[i] = x.name end
    local display = UI.card(UI.vgroup({
        UI.text((c.input ~= "" and c.input:gsub("^%-", "−") or "0") .. " " .. cat.units[c.from], { font = "display", size = 30, width = W - UI.px(44), bg = UI.FILL }),
        UI.vspace(6),
        UI.text("= " .. fmtNum(math.floor(out * 100 + 0.5) / 100) .. " " .. to, { font = "displaybold", size = 40, width = W - UI.px(44), bg = UI.FILL }),
        extra ~= "" and UI.text(extra, { size = 18, color = UI.INK2, bg = UI.FILL }) or nil,
    }), { fill = true, border = 0, pad = UI.px(22) })
    local items = {
        UI.header("Omrekenen", function() app:back() end),
        UI.segmented(names, c.cat, function(i) c.cat = i; c.from = 1; app:refresh() end),
        UI.vspace(10),
        UI.segmented({ cat.units[1] .. " → " .. cat.units[2], cat.units[2] .. " → " .. cat.units[1] }, c.from, function(i) c.from = i; app:refresh() end),
        UI.vspace(14),
        Spot:new{ name = "conv", display },
        UI.vspace(14),
        keypad({ { "7", "8", "9", "←" }, { "4", "5", "6", "C" }, { "1", "2", "3", "±" }, { "0", "," } }, key, W),
    }
    return UI.page(UI.vgroup(items))
end

-- Wereldklok -----------------------------------------------------------------------

-- dagen sinds 1970-01-01 voor een datum (algoritme van Howard Hinnant)
local function days(y, m, d)
    y = m <= 2 and y - 1 or y
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end
local function utc(y, m, d, h) return days(y, m, d) * 86400 + (h or 0) * 3600 end
local function weekday(y, m, d) return (days(y, m, d) + 4) % 7 end -- 0 = zondag
local function lastSunday(y, m)
    local dim = ({ 31, (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 })[m]
    return dim - weekday(y, m, dim)
end
local function nthSunday(y, m, n)
    local first = (7 - weekday(y, m, 1)) % 7 + 1
    return first + (n - 1) * 7
end

-- Zomertijdregels. base = standaard verschil met UTC in uren.
local DST = {
    -- Europa: overal tegelijk om 01:00 UTC
    eu = function(t, y) return t >= utc(y, 3, lastSunday(y, 3), 1) and t < utc(y, 10, lastSunday(y, 10), 1) end,
    -- VS: tweede zondag maart 02:00 lokaal tot eerste zondag november 02:00 lokaal
    us = function(t, y, base) return t >= utc(y, 3, nthSunday(y, 3, 2), 2 - base) and t < utc(y, 11, nthSunday(y, 11, 1), 2 - base - 1) end,
    -- Israël: vrijdag voor de laatste zondag van maart tot de laatste zondag van oktober, 02:00 lokaal
    il = function(t, y) return t >= utc(y, 3, lastSunday(y, 3) - 2, 0) and t < utc(y, 10, lastSunday(y, 10), -1) end,
    -- Australië (zuidelijk halfrond): zomertijd van oktober tot april
    au = function(t, y) return not (t >= utc(y, 4, nthSunday(y, 4, 1), -8) and t < utc(y, 10, nthSunday(y, 10, 1), -8)) end,
}

T.CITIES = {
    { "Amsterdam", 1, "eu" }, { "Londen", 0, "eu" }, { "Kyiv", 2, "eu" }, { "Moskou", 3 }, { "Tel Aviv", 2, "il" },
    { "New York", -5, "us" }, { "Beijing", 8 }, { "Tokio", 9 }, { "Sydney", 10, "au" },
}

function T.cityTime(city, t)
    t = t or os.time()
    local y = tonumber(os.date("!%Y", t))
    local off = city[2]
    if city[3] and DST[city[3]](t, y, city[2]) then off = off + 1 end
    return t + off * 3600, off
end

function T.clock(app)
    local W = UI.INNER()
    local now = os.time()
    local ams = T.cityTime(T.CITIES[1], now)
    local amsDay = os.date("!%Y-%m-%d", ams)
    local items = { UI.header("Wereldklok", function() app:back() end, "Tijd en verschil met Amsterdam") }
    for _, c in ipairs(T.CITIES) do
        local lt, off = T.cityTime(c, now)
        local day = os.date("!%Y-%m-%d", lt)
        local rel = day == amsDay and "" or (day > amsDay and "morgen · " or "gisteren · ")
        local diff = off - (select(2, T.cityTime(T.CITIES[1], now)))
        local sub = rel .. (diff == 0 and "zelfde tijd" or (("%+d uur"):format(diff):gsub("^%-", "−")))
        local timeW = UI.text(os.date("!%H:%M", lt), { font = "display", size = 28 })
        local left = UI.vgroup({ UI.text(c[1], { size = 20, font = "medium" }), UI.text(sub, { size = 15, color = UI.INK2 }) })
        local h = math.max(left:getSize().h, timeW:getSize().h) + UI.px(14)
        local OverlapGroup = require("ui/widget/overlapgroup")
        local LeftContainer = require("ui/widget/container/leftcontainer")
        local RightContainer = require("ui/widget/container/rightcontainer")
        table.insert(items, OverlapGroup:new{ dimen = Geom:new{ w = W, h = h },
            LeftContainer:new{ dimen = Geom:new{ w = W, h = h }, left },
            RightContainer:new{ dimen = Geom:new{ w = W, h = h }, timeW } })
        table.insert(items, UI.line(W))
    end
    return UI.page(UI.vgroup(items))
end

-- Menu ------------------------------------------------------------------------------

function T.menu(app)
    local items = {
        UI.header("Tools", function() app:back() end, "Handige dingen, zonder internet"),
        UI.row("Rekenmachine", "Met voorrang voor keer en delen", "›", function() app:go(T.calc) end, nil, "calculator"),
        UI.row("Stopwatch", "Met rondetijden", "›", function() app:go(T.stopwatch) end, nil, "av_timer"),
        UI.row("Tempo berekenen", "Afstand en tijd naar tempo en tussentijden", "›", function() app:go(T.pace) end, nil, "gauge"),
        UI.row("Omrekenen", "Afstand, gewicht, temperatuur, snelheid", "›", function() app:go(T.convert) end, nil, "swap"),
        UI.row("Wereldklok", "Amsterdam, Kyiv, New York, Tokio en meer", "›", function() app:go(T.clock) end, nil, "web"),
        UI.row("Intervaltimer", "Kettlebells, Tabata, rust tussen sets", "›", function() app:go(require("ks_timer").menu) end, nil, "timer"),
    }
    return UI.page(UI.vgroup(items))
end

return T
