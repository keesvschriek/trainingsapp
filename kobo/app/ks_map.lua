-- Kaart: landen vooraf geprojecteerd (data/map.json), hier zelf getekend en aantikbaar.

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local json = require("json")

local SEA = Blitbuffer.Color8(0xD8)
local LAND = Blitbuffer.COLOR_WHITE
local OTHER = Blitbuffer.Color8(0xEE)   -- landen die niet meedoen
local BORDER = Blitbuffer.Color8(0x40)
local MARK = {
    target = Blitbuffer.COLOR_BLACK,
    right = Blitbuffer.COLOR_BLACK,
    wrong = Blitbuffer.Color8(0x80),
}

local M = {}
local data
local cache = {} -- getekende basiskaart per gebied en breedte

function M.load(dir)
    if data then return data end
    local f = io.open(dir .. "/data/map.json", "rb")
    if not f then return nil end
    local ok, d = pcall(json.decode, f:read("*a"))
    f:close()
    data = ok and d or nil
    -- per land alle delen samen
    if data then
        for _, R in pairs(data) do
            R.byC3 = {}
            for _, c in ipairs(R.countries) do
                if c.c3 then
                    local e = R.byC3[c.c3]
                    if not e then
                        e = { c3 = c.c3, name = c.n, parts = {}, t = 0, a = 0 }
                        R.byC3[c.c3] = e
                    end
                    table.insert(e.parts, c)
                    if c.t == 1 then e.t = 1 end
                    for _, r in ipairs(c.rings) do
                        for i = 1, #r, 2 do
                            local x, y = r[i], r[i + 1]
                            e.x0 = math.min(e.x0 or x, x); e.x1 = math.max(e.x1 or x, x)
                            e.y0 = math.min(e.y0 or y, y); e.y1 = math.max(e.y1 or y, y)
                        end
                    end
                    if c.a > e.a then e.a, e.cx, e.cy = c.a, c.cx, c.cy end
                end
            end
        end
    end
    return data
end

function M.region(key) return data and data[key] end

--- Landen die je kunt aantikken in een gebied.
function M.playable(key)
    local R = M.region(key)
    local out = {}
    if not R then return out end
    for _, e in pairs(R.byC3) do if e.t == 1 then out[#out + 1] = e end end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Vlak vullen met de even-oneven-regel over alle ringen (gaten en eilanden gaan dan vanzelf goed)
local function fillRings(bb, rings, s, ox, oy, color, w, h)
    local edges = {}
    local ymin, ymax = math.huge, -math.huge
    for _, r in ipairs(rings) do
        local n = #r
        for i = 1, n, 2 do
            local x0, y0 = r[i] * s, r[i + 1] * s
            local j = i + 2
            if j > n then j = 1 end
            local x1, y1 = r[j] * s, r[j + 1] * s
            if y0 ~= y1 then
                edges[#edges + 1] = { x0, y0, x1, y1 }
                if y0 < ymin then ymin = y0 end
                if y1 < ymin then ymin = y1 end
                if y0 > ymax then ymax = y0 end
                if y1 > ymax then ymax = y1 end
            end
        end
    end
    if #edges == 0 then return end
    local ystart = math.max(0, math.floor(ymin))
    local yend = math.min(h - 1, math.ceil(ymax))
    local xs = {}
    for y = ystart, yend do
        local yc = y + 0.5
        local n = 0
        for i = 1, #edges do
            local e = edges[i]
            local y0, y1 = e[2], e[4]
            if (y0 <= yc and y1 > yc) or (y1 <= yc and y0 > yc) then
                n = n + 1
                xs[n] = e[1] + (yc - y0) * (e[3] - e[1]) / (y1 - y0)
            end
        end
        if n > 1 then
            for k = n + 1, #xs do xs[k] = nil end
            table.sort(xs)
            for k = 1, n - 1, 2 do
                local a = math.max(0, math.floor(xs[k] + 0.5))
                local b = math.min(w, math.floor(xs[k + 1] + 0.5))
                if b > a then bb:paintRect(ox + a, oy + y, b - a, 1, color) end
            end
        end
    end
end

local function line(bb, x0, y0, x1, y1, ox, oy, color, w, h)
    x0, y0, x1, y1 = math.floor(x0 + 0.5), math.floor(y0 + 0.5), math.floor(x1 + 0.5), math.floor(y1 + 0.5)
    local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
    local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
    local err = dx + dy
    while true do
        if x0 >= 0 and y0 >= 0 and x0 < w and y0 < h then bb:paintRect(ox + x0, oy + y0, 1, 1, color) end
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 >= dy then err = err + dy; x0 = x0 + sx end
        if e2 <= dx then err = err + dx; y0 = y0 + sy end
    end
end

local function outline(bb, rings, s, ox, oy, color, w, h)
    for _, r in ipairs(rings) do
        local n = #r
        for i = 1, n, 2 do
            local j = i + 2
            if j > n then j = 1 end
            line(bb, r[i] * s, r[i + 1] * s, r[j] * s, r[j + 1] * s, ox, oy, color, w, h)
        end
    end
end

local function allRings(e)
    local rings = {}
    for _, p in ipairs(e.parts) do for _, r in ipairs(p.rings) do rings[#rings + 1] = r end end
    return rings
end

-- Punt in land? (even-oneven over alle ringen)
local function inside(e, x, y)
    local hit = false
    for _, p in ipairs(e.parts) do
        for _, r in ipairs(p.rings) do
            local n = #r
            local j = n - 1
            for i = 1, n, 2 do
                local xi, yi, xj, yj = r[i], r[i + 1], r[j], r[j + 1]
                if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then hit = not hit end
                j = i
            end
        end
    end
    return hit
end

local SMALL = 140 -- oppervlakte in kaartpixels waaronder een land een rondje krijgt

local MapWidget = InputContainer:extend{
    region = nil,    -- sleutel in map.json
    width = nil,
    maxh = nil,
    marks = nil,     -- { [c3] = "target" | "right" | "wrong" }
    clickable = true,
    onPick = nil,
}

function MapWidget:init()
    local R = M.region(self.region)
    self.R = R
    self.s = math.min(self.width / R.w, (self.maxh or math.huge) / R.h)
    self.w = math.floor(R.w * self.s)
    self.h = math.floor(R.h * self.s)
    self.dimen = Geom:new{ x = 0, y = 0, w = self.w, h = self.h }
    self.ges_events = { TapMap = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function MapWidget:getSize() return Geom:new{ w = self.w, h = self.h } end

function MapWidget:base()
    local key = self.region .. ":" .. self.w
    if cache[key] then return cache[key] end
    local bb = Blitbuffer.new(self.w, self.h, Blitbuffer.TYPE_BB8)
    bb:fill(SEA)
    local R, s = self.R, self.s
    for _, c in ipairs(R.countries) do
        fillRings(bb, c.rings, s, 0, 0, c.t == 1 and LAND or OTHER, self.w, self.h)
    end
    for _, c in ipairs(R.countries) do
        outline(bb, c.rings, s, 0, 0, BORDER, self.w, self.h)
    end
    -- kleine landen die meedoen: rondje
    for _, e in pairs(R.byC3) do
        if self.region ~= "Wereld" and e.t == 1 and e.a < SMALL and e.cx then
            bb:paintCircle(math.floor(e.cx * s), math.floor(e.cy * s), math.max(6, math.floor(10 * s)), BORDER, 2)
        end
    end
    cache[key] = bb
    return bb
end

function MapWidget:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local base = self:base()
    bb:blitFrom(base, x, y, 0, 0, self.w, self.h)
    for c3, mark in pairs(self.marks or {}) do
        local e = self.R.byC3[c3]
        if e then
            local color = MARK[mark] or MARK.target
            fillRings(bb, allRings(e), self.s, x, y, color, self.w, self.h)
            -- klein of uit eilandjes bestaand land: dikke ring eromheen zodat je het ziet
            local big = math.max((e.x1 - e.x0), (e.y1 - e.y0)) * self.s
            if (e.a < SMALL or big < 24) and e.cx then
                local cx, cy = x + math.floor(e.cx * self.s), y + math.floor(e.cy * self.s)
                bb:paintCircle(cx, cy, math.max(7, math.floor(9 * self.s)), color)
                bb:paintCircle(cx, cy, math.max(18, math.floor(22 * self.s)), color, 4)
            end
        end
    end
    bb:paintBorder(x, y, self.w, self.h, 1, BORDER)
end

function MapWidget:countryAt(px, py)
    local x, y = (px - self.dimen.x) / self.s, (py - self.dimen.y) / self.s
    for _, e in pairs(self.R.byC3) do
        if e.t == 1 and inside(e, x, y) then return e.c3 end
    end
    -- kleine landen: tikken in de buurt van het rondje telt
    local best, bestd = nil, (24 / self.s) ^ 2
    for _, e in pairs(self.R.byC3) do
        if e.t == 1 and e.a < SMALL * 4 and e.cx then
            local d = (e.cx - x) ^ 2 + (e.cy - y) ^ 2
            if d < bestd then best, bestd = e.c3, d end
        end
    end
    return best
end

function MapWidget:onTapMap(_, ges)
    if not self.onPick then return true end
    local c3 = self:countryAt(ges.pos.x, ges.pos.y)
    if c3 then self.onPick(c3) end
    return true
end

M.MapWidget = MapWidget
function M.clearCache() cache = {} end
M.inside = inside
return M
