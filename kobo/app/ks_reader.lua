-- Leesscherm in de app zelf: achtergrondstukken en Wikipedia-artikelen, in bladzijden.
-- Tik rechts of veeg naar links voor de volgende bladzijde, tik links of veeg naar rechts voor de vorige.
-- Terug brengt je meteen naar het menu.

local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Store = require("ks_store")
local UI = require("ks_ui")

local RD = {}

-- Tik- en veegvlak rond de tekst
local Zone = InputContainer:extend{ onPrev = nil, onNext = nil }
function Zone:init()
    local sz = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = sz.w, h = sz.h }
    self.ges_events = {
        TapZone = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        SwipeZone = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } },
    }
end
function Zone:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    InputContainer.paintTo(self, bb, x, y)
end
function Zone:onTapZone(_, ges)
    if ges.pos.x < self.dimen.x + self.dimen.w / 3 then self.onPrev() else self.onNext() end
    return true
end
function Zone:onSwipeZone(_, ges)
    if ges.direction == "west" then self.onNext() return true end
    if ges.direction == "east" then self.onPrev() return true end
end

local STYLE = {
    h2 = { font = "medium", size = 21 },
    h3 = { font = "medium", size = 19 },
    p = { font = "serif", size = 20, line_height = 0.45 },
    li = { font = "serif", size = 20, line_height = 0.45 },
    sub = { font = "serif", size = 18, color = UI.INK2 },
    small = { size = 14, color = UI.INK3 },
}
local GAP = { h2 = 22, h3 = 16, p = 12, li = 6, sub = 14, small = 14 }

local function widget(b, W, text)
    local st = STYLE[b.k] or STYLE.p
    local t = text or b.t
    if b.k == "li" then t = "•  " .. t end
    return UI.text(t, { font = st.font, size = st.size, color = st.color, line_height = st.line_height, width = W })
end

-- Zinnen van een alinea
local function sentences(t)
    local out = {}
    for s in (t .. " "):gmatch("(.-[%.%?!;:]%s+)") do table.insert(out, s) end
    local used = table.concat(out)
    local rest = t:sub(#used + 1)
    if rest:match("%S") then table.insert(out, rest) end
    if #out == 0 then out = { t } end
    return out
end

-- Zoveel mogelijk zinnen die samen in 'room' passen; geeft eerste stuk en de rest (of nil).
local function take(b, W, room)
    local ss = sentences(b.t)
    local cur, n = "", 0
    for i, s in ipairs(ss) do
        local try = cur .. s
        if widget(b, W, try):getSize().h > room then break end
        cur, n = try, i
    end
    if n == 0 then return nil, b end
    if n == #ss then return b, nil end
    local rest = table.concat(ss, "", n + 1)
    return { k = b.k, t = (cur:gsub("%s+$", "")) }, { k = b.k, t = (rest:gsub("^%s+", "")) }
end

--- Verdeel de blokken over bladzijden.
function RD.paginate(doc, W, firstAvail, avail)
    local pages, cur, used = {}, {}, 0
    local cap = firstAvail
    local function flush() table.insert(pages, cur); cur, used = {}, 0; cap = avail end
    local queue = {}
    for _, b in ipairs(doc.blocks or {}) do table.insert(queue, b) end
    local i, guard = 1, 0
    while i <= #queue and guard < 5000 do
        guard = guard + 1
        local b = queue[i]
        local gap = UI.px(GAP[b.k] or 12)
        local h = widget(b, W):getSize().h + gap
        local isHead = b.k == "h2" or b.k == "h3"
        -- een kopje alleen als er nog minstens een paar regels onder passen
        local need = isHead and (h + UI.px(90)) or h
        if used + need <= cap then
            table.insert(cur, b); used = used + h; i = i + 1
        elseif (b.k == "p" or b.k == "li") and cap - used - gap > UI.px(60) then
            local first, rest = take(b, W, cap - used - gap)
            if first and rest then
                table.insert(cur, first)
                queue[i] = rest
                flush()
            elseif #cur > 0 then
                flush()
            else
                -- past zelfs op een lege bladzijde niet als één zin: dan toch plaatsen
                table.insert(cur, b); i = i + 1; flush()
            end
        elseif #cur > 0 then
            flush()
        else
            table.insert(cur, b); i = i + 1; flush()
        end
    end
    if #cur > 0 then table.insert(pages, cur) end
    return pages
end

local function posKey(doc) return doc.id or doc.title end

--- app.rdDoc = { id, title, sub, blocks } (door ks_reading gevuld)
function RD.page(app)
    -- het leesscherm verdeelt zelf over bladzijden; nooit kleiner maken
    UI.noShrink = true
    local doc = app.rdDoc
    local W = UI.INNER()
    local function back() app.rdDoc = nil; app.rdPages = nil; app:back() end
    if not doc then return UI.page(UI.vgroup({ UI.header("Lezen", back, "") })) end
    local backRow = UI.Tap:new{ label = "‹ Terug", callback = back,
        UI.hgroup({ UI.icon("chevron_left", 18, UI.INK2), UI.hspace(4), UI.text(doc.kind or "Te lezen", { size = 15, color = UI.INK2 }) }) }
    local head1 = UI.vgroup({ backRow, UI.vspace(12), UI.text(doc.title, { font = "display", size = 26, width = W }), UI.vspace(14) })
    local headN = UI.vgroup({ backRow, UI.vspace(10) })
    local sample = UI.buttonRow({ { "Vorige", function() end, small = true }, { "1 / 1", function() end, small = true }, { "Verder", function() end, small = true } })
    local footerH = sample:getSize().h + UI.px(30 + 14 + 16)
    local base = UI.H() - UI.px(UI.TOPPAD) - footerH
    local keyP = posKey(doc) .. "|" .. UI.scale
    if not app.rdPages or app.rdPages.key ~= keyP then
        app.rdPages = { key = keyP, list = RD.paginate(doc, W, base - head1:getSize().h - UI.px(20), base - headN:getSize().h - UI.px(20)) }
    end
    local pages = app.rdPages.list
    local pos = Store.get("rd.pos", {})
    local p = math.max(1, math.min(pos[posKey(doc)] or 1, #pages))
    local function go(n)
        if n < 1 or n > #pages then return end
        local all = Store.get("rd.pos", {})
        all[posKey(doc)] = n
        Store.set("rd.pos", all)
        app:refresh()
    end
    local body = {}
    for _, b in ipairs(pages[p] or {}) do
        table.insert(body, widget(b, W))
        table.insert(body, UI.vspace(GAP[b.k] or 12))
    end
    local zone = Zone:new{ onPrev = function() go(p - 1) end, onNext = function() go(p + 1) end,
        UI.vgroup({ UI.vgroup(body), UI.vspace(math.max(0, (p == 1 and base - head1:getSize().h or base - headN:getSize().h) - UI.vgroup(body):getSize().h - UI.px(4))) }) }
    local footer = UI.buttonRow({
        { "Vorige", function() go(p - 1) end, small = true, disabled = p <= 1 },
        { p .. " / " .. #pages, function() end, small = true, disabled = true },
        p < #pages and { "Verder", function() go(p + 1) end, small = true, primary = true }
            or { "Klaar", back, small = true, primary = true },
    })
    return UI.page(UI.vgroup({ p == 1 and head1 or headN, zone }), footer)
end

return RD
