-- Bouwstenen voor de schermen: tekst, knoppen, lijstregels en een paginakader.
-- Rustige stijl: wit papier, zwarte inkt, dunne lijnen, geen rondingen of schaduwen.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local UI = {}

UI.W = function() return Screen:getWidth() end
UI.H = function() return Screen:getHeight() end
UI.px = function(n) return Screen:scaleBySize(n) end
UI.MARGIN = function() return Screen:scaleBySize(28) end
UI.INNER = function() return UI.W() - 2 * UI.MARGIN() end

UI.WHITE = Blitbuffer.COLOR_WHITE
UI.BLACK = Blitbuffer.COLOR_BLACK
UI.INK2 = Blitbuffer.COLOR_GRAY_5   -- tweede inkt, voor bijzaken
UI.LINE = Blitbuffer.COLOR_GRAY_B   -- dunne scheidingslijnen
UI.PAPER2 = Blitbuffer.COLOR_GRAY_E -- licht vlak

local FACES = {
    sans = "NotoSans-Regular.ttf",
    bold = "NotoSans-Bold.ttf",
    serif = "NotoSerif-Regular.ttf",
    serifbold = "NotoSerif-Bold.ttf",
}
--- Lettergrootte uit de instellingen: 1 = normaal. Geldt voor alle tekst in de app.
UI.scale = 1
--- Ruimte boven elk scherm, voor de statusbalk (tijd, batterij, schermtijd).
UI.TOPPAD = 46
--- Geeft { links, rechts } voor de statusbalk, of nil. Wordt gezet door ks_system.
UI.status = nil

function UI.face(kind, size) return Font:getFace(FACES[kind] or kind, math.floor(size * UI.scale + 0.5)) end

--- Tekst. Met opts.width wordt het een tekstblok dat afbreekt.
function UI.text(str, opts)
    opts = opts or {}
    local face = UI.face(opts.font or "sans", opts.size or 20)
    if opts.width then
        return TextBoxWidget:new{
            text = str,
            face = face,
            width = opts.width,
            alignment = opts.align or "left",
            fgcolor = opts.color or UI.BLACK,
            bgcolor = opts.bg,
            line_height = opts.line_height or 0.3,
        }
    end
    return TextWidget:new{ text = str, face = face, fgcolor = opts.color or UI.BLACK, max_width = opts.max_width }
end

function UI.vspace(n) return VerticalSpan:new{ width = UI.px(n) } end
function UI.hspace(n) return HorizontalSpan:new{ width = UI.px(n) } end

function UI.line(width, color, thick)
    return LineWidget:new{ dimen = Geom:new{ w = width or UI.INNER(), h = thick or UI.px(1) }, background = color or UI.LINE }
end

--- Een tikbaar vlak rond een willekeurige widget.
local Tap = InputContainer:extend{ callback = nil, hold = nil }
function Tap:init()
    local sz = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = sz.w, h = sz.h }
    self.ges_events = {
        TapIt = { GestureRange:new{ ges = "tap", range = self.dimen } },
        HoldIt = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
end
UI.painted = {} -- voor tests: welke tikvlakken staan er op het scherm
function Tap:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    table.insert(UI.painted, self)
    InputContainer.paintTo(self, bb, x, y)
end
function Tap:onTapIt()
    if self.callback then self.callback() end
    return true
end
function Tap:onHoldIt()
    if self.hold then self.hold() return true end
    if self.callback then self.callback() end
    return true
end
UI.Tap = Tap

--- Knop. opts: width, primary (zwart vlak), small, disabled
function UI.button(label, callback, opts)
    opts = opts or {}
    local size = opts.small and 17 or 20
    local padv = UI.px(opts.small and 10 or 16)
    local fg = opts.primary and UI.WHITE or (opts.disabled and UI.INK2 or UI.BLACK)
    local txt = UI.text(label, { font = opts.primary and "bold" or "sans", size = size, color = fg })
    if opts.width and txt:getSize().w > opts.width - UI.px(28) then
        -- te lang voor één regel: laten afbreken, gecentreerd
        txt:free()
        txt = UI.text(label, { font = opts.primary and "bold" or "sans", size = size, color = fg, bg = opts.primary and UI.BLACK or nil, width = opts.width - UI.px(28), align = "center", line_height = 0.2 })
    end
    local inner = txt
    local w = opts.width or (txt:getSize().w + UI.px(48))
    local frame = FrameContainer:new{
        bordersize = UI.px(opts.primary and 0 or 2),
        color = opts.disabled and UI.LINE or UI.BLACK,
        background = opts.primary and UI.BLACK or UI.WHITE,
        radius = 0,
        padding = 0,
        margin = 0,
        CenterContainer:new{ dimen = Geom:new{ w = w - UI.px(opts.primary and 0 or 4), h = math.max(txt:getSize().h + 2 * padv, opts.minh or 0) }, inner },
    }
    if opts.disabled then return frame end
    return Tap:new{ callback = callback, label = label, frame }
end

--- Twee of meer knoppen naast elkaar over de volle breedte.
function UI.buttonRow(list, width)
    width = width or UI.INNER()
    local gap = UI.px(14)
    local n = #list
    local bw = math.floor((width - gap * (n - 1)) / n)
    local row = HorizontalGroup:new{}
    for i, b in ipairs(list) do
        if i > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
        table.insert(row, UI.button(b[1], b[2], { width = bw, primary = b.primary, small = b.small, disabled = b.disabled }))
    end
    return row
end

--- Lijstregel: titel links, bijschrift eronder, waarde rechts. Tikbaar.
function UI.row(title, sub, right, callback, width)
    width = width or UI.INNER()
    local rightw = (right and right ~= "") and math.max(UI.px(40), UI.text(right, { size = 17 }):getSize().w + UI.px(20)) or 0
    local left = VerticalGroup:new{ align = "left" }
    table.insert(left, UI.text(title, { size = 21, width = width - rightw - UI.px(10) }))
    if sub and sub ~= "" then
        table.insert(left, UI.vspace(4))
        table.insert(left, UI.text(sub, { size = 16, color = UI.INK2, width = width - rightw - UI.px(10) }))
    end
    local h = left:getSize().h + UI.px(UI.compact and math.min(14, UI.rowPad or 32) or (UI.rowPad or 32))
    local content = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = h },
        LeftContainer:new{ dimen = Geom:new{ w = width, h = h }, left },
    }
    if right then
        table.insert(content, RightContainer:new{ dimen = Geom:new{ w = width, h = h }, UI.text(right, { size = 17, color = UI.INK2 }) })
    end
    local block = VerticalGroup:new{ align = "left", content, UI.line(width) }
    if not callback then return block end
    return Tap:new{ callback = callback, label = title, block }
end

--- Kopregel van een scherm: "‹ terug" links, titel eronder.
function UI.header(title, onBack, extra)
    local g = VerticalGroup:new{ align = "left" }
    if onBack then
        table.insert(g, UI.Tap:new{ callback = onBack, FrameContainer:new{ bordersize = 0, padding = 0, padding_bottom = UI.px(10), padding_right = UI.px(40), UI.text("‹ Terug", { size = 18, color = UI.INK2 }) } })
    end
    table.insert(g, UI.text(title, { font = "serif", size = 32, width = UI.INNER() }))
    if extra then
        table.insert(g, UI.vspace(4))
        table.insert(g, UI.text(extra, { size = 17, color = UI.INK2, width = UI.INNER() }))
    end
    table.insert(g, UI.vspace(14))
    table.insert(g, UI.line(UI.INNER(), UI.BLACK, UI.px(2)))
    table.insert(g, UI.vspace(10))
    return g
end

--- Statusbalk bovenaan: wordt bij elke keer tekenen opnieuw ingevuld, zodat de klok klopt.
local Widget = require("ui/widget/widget")
local StatusBar = Widget:extend{}
function StatusBar:getSize() return Geom:new{ w = UI.W(), h = UI.px(UI.TOPPAD - 8) } end
function StatusBar:paintTo(bb, x, y)
    if not UI.status then return end
    local st = UI.status()
    if not st then return end
    local M = UI.MARGIN()
    local face = Font:getFace(FACES.sans, 15) -- niet meeschalen: de balk blijft klein
    local l = TextWidget:new{ text = st[1], face = face, fgcolor = UI.INK2 }
    local r = TextWidget:new{ text = st[2], face = face, fgcolor = UI.INK2 }
    local ty = y + UI.px(10)
    l:paintTo(bb, x + M, ty)
    r:paintTo(bb, x + UI.W() - M - r:getSize().w, ty)
    l:free(); r:free()
end
UI.StatusBar = StatusBar

--- Volledig scherm: wit, met marges. Inhoud bovenaan, optioneel een voet onderaan.
function UI.page(body, footer)
    local W, H, M = UI.W(), UI.H(), UI.MARGIN()
    local over = OverlapGroup:new{
        dimen = Geom:new{ w = W, h = H },
        FrameContainer:new{ bordersize = 0, padding = M, padding_top = UI.px(UI.TOPPAD), margin = 0, background = UI.WHITE, width = W, height = H, body },
        StatusBar:new{},
    }
    -- past het niet, dan meldt de pagina dat; ks_main bouwt hem dan met iets kleinere letters opnieuw
    local need = UI.px(UI.TOPPAD) + body:getSize().h + (footer and (footer:getSize().h + UI.px(30 + 14)) or M)
    if need > H then UI.overflow = true end
    if footer then
        local fh = footer:getSize().h
        table.insert(over, FrameContainer:new{
            bordersize = 0, padding = 0, margin = 0, overlap_offset = { M, H - fh - UI.px(30) },
            footer,
        })
    end
    return over
end

--- Tegel voor het beginscherm: kader met titel en bijschrift.
function UI.tile(title, sub, w, h, callback)
    local pad = UI.px(18)
    local inner = VerticalGroup:new{ align = "left",
        UI.text(title, { font = "serif", size = 27, width = w - 2 * pad - 2 * UI.px(2) }),
        UI.vspace(6),
        UI.text(sub, { size = 16, color = UI.INK2, width = w - 2 * pad - 2 * UI.px(2) }),
    }
    local b = UI.px(2)
    local ih = math.max(h - 2 * pad - 2 * b, inner:getSize().h)
    local frame = FrameContainer:new{
        bordersize = b, color = UI.BLACK, background = UI.WHITE, radius = 0, margin = 0, padding = pad,
        OverlapGroup:new{ dimen = Geom:new{ w = w - 2 * pad - 2 * b, h = ih }, inner },
    }
    return Tap:new{ callback = callback, label = title, frame }
end

--- Vierkantje om af te vinken.
function UI.checkbox(on)
    local s = UI.px(30)
    local box = FrameContainer:new{ bordersize = UI.px(2), color = UI.BLACK, background = UI.WHITE, padding = UI.px(5), margin = 0,
        LineWidget:new{ dimen = Geom:new{ w = s - UI.px(14), h = s - UI.px(14) }, background = on and UI.BLACK or UI.WHITE } }
    return box
end

function UI.vgroup(list, align)
    local g = VerticalGroup:new{ align = align or "left" }
    for _, w in ipairs(list) do table.insert(g, w) end
    return g
end

function UI.hgroup(list, align)
    local g = HorizontalGroup:new{ align = align or "center" }
    for _, w in ipairs(list) do table.insert(g, w) end
    return g
end

function UI.center(w, width, height)
    return CenterContainer:new{ dimen = Geom:new{ w = width or UI.INNER(), h = height or w:getSize().h }, w }
end

return UI
