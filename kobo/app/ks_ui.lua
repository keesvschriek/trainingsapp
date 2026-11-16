-- Bouwstenen voor de schermen van Kees Personal.
--
-- Ontwerp "rustig grijs": wit papier, zachtgrijze vlakken met een dunne lijn eromheen.
-- Inter voor de bediening, Noto Serif voor leesteksten, één set lijniconen zonder kaders.
-- Zwart vlak alleen voor wat je nu moet doen.
-- Geen animaties, geen schaduwen: alles moet er na één verversing goed uitzien.

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
local Widget = require("ui/widget/widget")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local Screen = Device.screen

local UI = {}

UI.W = function() return Screen:getWidth() end
UI.H = function() return Screen:getHeight() end
UI.px = function(n) return Screen:scaleBySize(n) end
--- Van pixels terug naar de maat die Font:getFace verwacht.
UI.unpx = function(p) return p * 1000 / Screen:scaleBySize(1000) end
UI.MARGIN = function() return Screen:scaleBySize(30) end
UI.INNER = function() return UI.W() - 2 * UI.MARGIN() end

UI.WHITE = Blitbuffer.COLOR_WHITE
UI.BLACK = Blitbuffer.COLOR_BLACK
UI.INK2 = Blitbuffer.COLOR_GRAY_5    -- tweede inkt: bijschriften
UI.INK3 = Blitbuffer.COLOR_GRAY_9    -- derde inkt: hints, uit-stand
UI.LINE = Blitbuffer.COLOR_GRAY_D    -- scheidingslijnen binnen een kaart
UI.EDGE = Blitbuffer.COLOR_GRAY_B    -- dunne rand van kaarten en knoppen
UI.FILL = Blitbuffer.COLOR_GRAY_E    -- licht vlak
UI.PAPER2 = UI.FILL
UI.RADIUS = function() return Screen:scaleBySize(12) end
--- Dunne lijn: één echte pixel (fineline)
UI.FINE = function() return 1 end
--- Alle letters iets kleiner dan de maten in de code (rustiger beeld)
UI.TYPE = 0.9

--- Lettergrootte uit de instellingen: 1 = normaal.
UI.scale = 1
--- Ruimte boven elk scherm, voor de statusbalk.
UI.TOPPAD = 50
--- Geeft { tijd, batterij%, laadt, wifi, schermtijd } voor de statusbalk. Gezet door ks_system.
UI.status = nil
--- Wordt aangeroepen door de verversknop en de home-knop. Gezet door ks_main.
UI.onRefresh = nil
UI.onLight = nil
UI.onHome = nil

-- Lettertypes ------------------------------------------------------------------

-- map van deze app, afgeleid van waar dit bestand staat
local appDir = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or os.getenv("KEES_STUDY_DIR") or "/mnt/onboard/.adds/keesstudy/app"
local function own(file)
    local path = appDir .. "/fonts/" .. file
    if lfs.attributes(path, "mode") ~= "file" then return nil end
    -- Font:getFace zoekt vanuit de fontmap van KOReader; via ../ komen we bij een absoluut pad uit.
    return string.rep("../", 20) .. path:gsub("^/", "")
end

local FACES = {
    sans = own("Inter-Regular.ttf") or "NotoSans-Regular.ttf",
    medium = own("Inter-Medium.ttf") or "NotoSans-Regular.ttf",
    bold = own("Inter-SemiBold.ttf") or "NotoSans-Bold.ttf",
    display = own("InterDisplay-SemiBold.ttf") or "NotoSans-Bold.ttf",
    displaybold = own("InterDisplay-Bold.ttf") or "NotoSans-Bold.ttf",
    serif = "NotoSerif-Regular.ttf",
    serifbold = "NotoSerif-Bold.ttf",
    serifitalic = "NotoSerif-Italic.ttf",
    icon = own("ks-icons.ttf") or "nerdfonts/symbols.ttf",
}
UI.FACES = FACES

function UI.face(kind, size) return Font:getFace(FACES[kind] or kind, math.floor(size * UI.scale * UI.TYPE + 0.5)) end
--- Vaste grootte, schaalt niet mee (statusbalk, iconen in de balk).
function UI.fixedFace(kind, size) return Font:getFace(FACES[kind] or kind, size) end

-- Tekst --------------------------------------------------------------------------

-- Tekstblok zonder eigen achtergrond: wordt als inkt op de ondergrond gezet, zodat tekst
-- op een grijs vlak geen witte rechthoek krijgt. (Rendert wit op zwart en gebruikt dat als dekking.)
local InkText = TextBoxWidget:extend{ ink = nil }
function InkText:init()
    self.ink = self.ink or Blitbuffer.COLOR_BLACK
    self.fgcolor = Blitbuffer.COLOR_WHITE
    self.bgcolor = Blitbuffer.COLOR_BLACK
    TextBoxWidget.init(self)
end
function InkText:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:colorblitFrom(self._bb, x, y, 0, 0, self.width, self._bb:getHeight(), self.ink)
end

--- Tekst. Met opts.width wordt het een tekstblok dat afbreekt.
function UI.text(str, opts)
    opts = opts or {}
    local face = opts.fixed and UI.fixedFace(opts.font or "sans", opts.size or 20) or UI.face(opts.font or "sans", opts.size or 20)
    if opts.width then
        local Class = opts.bg and TextBoxWidget or InkText
        return Class:new{
            ink = opts.color or UI.BLACK,
            text = str,
            face = face,
            width = opts.width,
            alignment = opts.align or "left",
            fgcolor = opts.color or UI.BLACK,
            bgcolor = opts.bg,
            line_height = opts.line_height or 0.3,
            height = opts.height,
            height_adjust = opts.height and true or nil,
            height_overflow_show_ellipsis = opts.height and true or nil,
        }
    end
    return TextWidget:new{ text = str, face = face, fgcolor = opts.color or UI.BLACK, max_width = opts.max_width, bgcolor = opts.bg }
end

local ICONS
--- Lijnicoon uit fonts/ks-icons.ttf. name: zie ks_icons.lua
function UI.icon(name, size, color, opts)
    ICONS = ICONS or require("ks_icons")
    local cp = ICONS[name] or ICONS.help
    opts = opts or {}
    local face = opts.fixed and UI.fixedFace("icon", size or 24) or UI.face("icon", size or 24)
    return TextWidget:new{ text = util.unicodeCodepointToUtf8(cp), face = face, fgcolor = color or UI.BLACK, bgcolor = opts.bg, padding = 0 }
end

function UI.vspace(n) return VerticalSpan:new{ width = UI.px(n) } end
function UI.hspace(n) return HorizontalSpan:new{ width = UI.px(n) } end
function UI.vspan(px) return VerticalSpan:new{ width = px } end
function UI.hspan(px) return HorizontalSpan:new{ width = px } end

function UI.line(width, color, thick)
    return LineWidget:new{ dimen = Geom:new{ w = width or UI.INNER(), h = thick or UI.px(1) }, background = color or UI.LINE }
end

function UI.vgroup(list, align)
    local g = VerticalGroup:new{ align = align or "left" }
    for _, w in ipairs(list) do if w then table.insert(g, w) end end
    return g
end

function UI.hgroup(list, align)
    local g = HorizontalGroup:new{ align = align or "center" }
    for _, w in ipairs(list) do if w then table.insert(g, w) end end
    return g
end

function UI.center(w, width, height)
    return CenterContainer:new{ dimen = Geom:new{ w = width or UI.INNER(), h = height or w:getSize().h }, w }
end

--- Vlak van vaste maat; inhoud links boven.
function UI.box(w, width, height)
    return OverlapGroup:new{ dimen = Geom:new{ w = width, h = height or w:getSize().h }, w }
end

-- Tikken ---------------------------------------------------------------------------

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

-- Kaarten en knoppen -----------------------------------------------------------------

--- Afgeronde kaart. opts: width, height, pad, fill (grijs vlak), dark (zwart vlak), border, radius
function UI.card(content, opts)
    opts = opts or {}
    local pad = opts.pad or UI.px(18)
    local b = opts.dark and 0 or UI.FINE()
    local w = opts.width or UI.INNER()
    local innerW = w - 2 * pad - 2 * b
    local ih = content:getSize().h
    if opts.height then ih = math.max(ih, opts.height - 2 * pad - 2 * b) end
    return FrameContainer:new{
        bordersize = b,
        color = opts.dark and UI.BLACK or (opts.edge or UI.EDGE),
        background = opts.dark and UI.BLACK or (opts.white and UI.WHITE or UI.FILL),
        radius = opts.radius or UI.RADIUS(),
        padding = pad,
        margin = 0,
        UI.box(content, innerW, ih),
    }
end

--- Knop. opts: width, primary (zwart vlak), small, disabled, icon, minh
function UI.button(label, callback, opts)
    opts = opts or {}
    local size = opts.size or (opts.small and 17 or 19)
    local padv = UI.px(opts.small and 10 or 14)
    local fg = opts.primary and UI.WHITE or (opts.disabled and UI.INK3 or UI.BLACK)
    local bg = opts.primary and UI.BLACK or UI.WHITE
    local font = opts.primary and "bold" or "medium"
    local txt = UI.text(label, { font = font, size = size, color = fg, bg = bg })
    local w = opts.width or (txt:getSize().w + UI.px(52) + (opts.icon and UI.px(34) or 0))
    local room = w - UI.px(28) - (opts.icon and UI.px(34) or 0)
    if txt:getSize().w > room then
        txt:free()
        txt = UI.text(label, { font = font, size = size, color = fg, bg = bg, width = room, align = "center", line_height = 0.2 })
    end
    local inner = txt
    if opts.icon then
        inner = UI.hgroup({ UI.icon(opts.icon, size + 4, fg, { bg = bg }), UI.hspace(10), txt })
    end
    local b = opts.primary and 0 or UI.FINE()
    local h = math.max(inner:getSize().h + 2 * padv, opts.minh or 0)
    local frame = FrameContainer:new{
        bordersize = b,
        color = opts.disabled and UI.LINE or UI.EDGE,
        background = bg,
        radius = UI.px(10),
        padding = 0,
        margin = 0,
        CenterContainer:new{ dimen = Geom:new{ w = w - 2 * b, h = h - 2 * b }, inner },
    }
    if opts.disabled then return frame end
    return Tap:new{ callback = callback, label = label, frame }
end

--- Twee of meer knoppen naast elkaar over de volle breedte.
function UI.buttonRow(list, width)
    width = width or UI.INNER()
    local gap = UI.px(12)
    local n = #list
    local bw = math.floor((width - gap * (n - 1)) / n)
    local row = HorizontalGroup:new{}
    for i, b in ipairs(list) do
        if i > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
        table.insert(row, UI.button(b[1], b[2], { width = bw, primary = b.primary, small = b.small, disabled = b.disabled, icon = b.icon, size = b.size, minh = b.minh }))
    end
    return row
end

--- Gesegmenteerde keuze (zoals Ochtend | Avond). list = { "A", "B" }, current = index
function UI.segmented(list, current, onPick, width)
    width = width or UI.INNER()
    local n = #list
    local b = UI.FINE()
    local inner = width - 2 * b
    local sw = math.floor(inner / n)
    local row = HorizontalGroup:new{}
    for i, label in ipairs(list) do
        local on = i == current
        local w = (i == n) and (inner - sw * (n - 1)) or sw
        local cell = FrameContainer:new{
            bordersize = 0, padding = 0, margin = 0,
            background = on and UI.BLACK or UI.WHITE,
            radius = on and UI.px(8) or nil,
            CenterContainer:new{ dimen = Geom:new{ w = w, h = UI.px(42) },
                UI.text(label, { font = on and "bold" or "medium", size = 17, color = on and UI.WHITE or UI.BLACK, bg = on and UI.BLACK or UI.WHITE }) },
        }
        table.insert(row, Tap:new{ callback = function() onPick(i) end, label = label, cell })
    end
    return FrameContainer:new{ bordersize = b, color = UI.EDGE, background = UI.WHITE, radius = UI.px(10), padding = 0, margin = 0, row }
end

--- Rond icoon in een vierkantje, zoals in Instellingen op een telefoon.
function UI.badge(icon, size, dark)
    size = size or UI.px(44)
    return FrameContainer:new{
        bordersize = dark and 0 or UI.px(1), color = UI.EDGE,
        background = dark and UI.BLACK or UI.FILL,
        radius = math.floor(size * 0.26), padding = 0, margin = 0,
        CenterContainer:new{ dimen = Geom:new{ w = size - (dark and 0 or 2 * UI.px(1)), h = size - (dark and 0 or 2 * UI.px(1)) },
            UI.icon(icon, math.floor(UI.unpx(size) * 0.56), dark and UI.WHITE or UI.BLACK, { bg = dark and UI.BLACK or UI.FILL, fixed = true }) },
    }
end

-- Lijsten ----------------------------------------------------------------------------

--- Lijstregel: (icoon) titel, bijschrift eronder, waarde rechts. Tikbaar.
--- right = "›" geeft een pijltje.
function UI.row(title, sub, right, callback, width, icon)
    width = width or UI.INNER()
    local chevron = right == "›"
    local rightW
    local rightWidget
    if chevron then
        rightWidget = UI.icon("chevron_right", 22, UI.INK3)
    elseif right and right ~= "" then
        rightWidget = UI.text(right, { size = 17, color = UI.INK2, font = "medium" })
    end
    rightW = rightWidget and (rightWidget:getSize().w + UI.px(16)) or 0
    local iconW = icon and UI.px(26 + 18) or 0
    local textW = width - rightW - iconW - UI.px(6)
    local left = VerticalGroup:new{ align = "left" }
    table.insert(left, UI.text(title, { size = 20, width = textW, font = "medium" }))
    if sub and sub ~= "" then
        table.insert(left, UI.vspace(3))
        table.insert(left, UI.text(sub, { size = 16, color = UI.INK2, width = textW }))
    end
    local pad = UI.compact and math.min(14, UI.rowPad or 26) or (UI.rowPad or 26)
    local h = math.max(left:getSize().h, icon and UI.px(26) or 0) + UI.px(pad)
    local content = OverlapGroup:new{ dimen = Geom:new{ w = width, h = h } }
    if icon then
        table.insert(content, LeftContainer:new{ dimen = Geom:new{ w = width, h = h }, UI.icon(icon, 26, UI.BLACK) })
        table.insert(content, LeftContainer:new{ dimen = Geom:new{ w = width, h = h }, UI.hgroup({ UI.hspan(iconW), left }) })
    else
        table.insert(content, LeftContainer:new{ dimen = Geom:new{ w = width, h = h }, left })
    end
    if rightWidget then
        table.insert(content, RightContainer:new{ dimen = Geom:new{ w = width, h = h }, rightWidget })
    end
    local block = VerticalGroup:new{ align = "left", content, UI.line(width, UI.LINE, UI.FINE()) }
    if not callback then return block end
    return Tap:new{ callback = callback, label = title, block }
end

--- Kleine kop boven een groep.
function UI.section(text, width)
    return UI.vgroup({ UI.vspace(10), UI.text(text, { font = "medium", size = 16, color = UI.INK2, width = width or UI.INNER() }), UI.vspace(6) })
end

--- Kopregel van een scherm: terug links (met naam van het vorige scherm), home rechts, grote titel eronder.
function UI.header(title, onBack, extra)
    local W = UI.INNER()
    local g = VerticalGroup:new{ align = "left" }
    if onBack then
        local back = UI.Tap:new{ label = "‹ Terug", callback = onBack, FrameContainer:new{ bordersize = 0, padding = 0, padding_right = UI.px(40), padding_bottom = UI.px(8),
            UI.hgroup({ UI.icon("chevron_left", 22, UI.INK2), UI.text("Terug", { size = 17, color = UI.INK2 }) }) } }
        local bar = OverlapGroup:new{ dimen = Geom:new{ w = W, h = back:getSize().h } , back }
        if UI.onHome then
            local home = UI.Tap:new{ label = "Home", callback = function() UI.onHome() end, FrameContainer:new{ bordersize = 0, padding = 0, padding_left = UI.px(40), padding_bottom = UI.px(8),
                UI.icon("home_outline", 22, UI.INK2) } }
            table.insert(bar, RightContainer:new{ dimen = Geom:new{ w = W, h = back:getSize().h }, home })
        end
        table.insert(g, bar)
        table.insert(g, UI.vspace(6))
    end
    table.insert(g, UI.text(title, { font = "display", size = 30, width = W }))
    if extra then
        table.insert(g, UI.vspace(4))
        table.insert(g, UI.text(extra, { size = 16, color = UI.INK2, width = W }))
    end
    table.insert(g, UI.vspace(16))
    return g
end

-- Statusbalk --------------------------------------------------------------------------

local StatusBar = Widget:extend{}
function StatusBar:getSize() return Geom:new{ w = UI.W(), h = UI.px(UI.TOPPAD - 10) } end
local function blit(bb, w, x, y) w:paintTo(bb, x, y); local s = w:getSize().w; w:free(); return s end
function StatusBar:paintTo(bb, x, y)
    if not UI.status then return end
    local ok, st = pcall(UI.status)
    if not ok or not st then return end
    local M = UI.MARGIN()
    local face = UI.fixedFace("medium", 15)
    local small = UI.fixedFace("sans", 14)
    local iconFace = 19
    local ty = y + UI.px(12)
    -- links: tijd
    local tw = blit(bb, TextWidget:new{ text = st.time, face = face, fgcolor = UI.BLACK }, x + M, ty)
    if st.busy then blit(bb, TextWidget:new{ text = st.busy .. "...", face = small, fgcolor = UI.INK2 }, x + M + tw + UI.px(14), ty + UI.px(1)) end
    -- rechts: verversen, batterij, wifi, schermtijd (van rechts naar links)
    local rx = x + UI.W() - M
    local function place(w, gap)
        local sw = w:getSize().w
        rx = rx - sw
        w:paintTo(bb, rx, ty + math.floor((UI.px(22) - w:getSize().h) / 2))
        w:free()
        rx = rx - (gap or UI.px(14))
    end
    place(UI.icon("refresh", iconFace, UI.BLACK, { fixed = true }), UI.px(22))
    StatusBar.refreshX = rx
    if st.battery then
        place(TextWidget:new{ text = st.battery .. "%", face = small, fgcolor = UI.BLACK }, UI.px(4))
        local lvl = math.max(1, math.min(9, math.floor(st.battery / 10 + 0.5)))
        local name = st.charging and "battery_charging" or (st.battery >= 95 and "battery" or ("battery_" .. lvl * 10))
        place(UI.icon(name, iconFace, UI.BLACK, { fixed = true }))
    end
    if st.wifi then place(UI.icon("wifi", iconFace, UI.BLACK, { fixed = true })) end
    if st.light then
        place(TextWidget:new{ text = st.light > 0 and (st.light .. "%") or "uit", face = small, fgcolor = UI.BLACK }, UI.px(4))
        place(UI.icon("sun", iconFace, UI.BLACK, { fixed = true }))
    end
    if st.screen then
        place(TextWidget:new{ text = st.screen, face = small, fgcolor = UI.INK2 }, UI.px(4))
        place(UI.icon("clock", 19, UI.INK2, { fixed = true }))
    end
end
UI.StatusBar = StatusBar

--- Tikvlak rechtsboven: scherm verversen.
local function refreshTap()
    local size = UI.px(UI.TOPPAD + 6)
    return Tap:new{ label = "Verversen", callback = function() if UI.onRefresh then UI.onRefresh() end end,
        overlap_offset = { UI.W() - UI.MARGIN() - size + UI.px(16), 0 },
        Widget:new{ dimen = Geom:new{ w = size, h = size } } }
end

--- Tikvlak over de rest van de bovenbalk: licht instellen.
local function lightTap()
    local size = UI.px(UI.TOPPAD + 6)
    return Tap:new{ label = "Licht", callback = function() if UI.onLight then UI.onLight() end end,
        overlap_offset = { 0, 0 },
        Widget:new{ dimen = Geom:new{ w = UI.W() - size, h = size } } }
end

--- Volledig scherm: wit, met marges. Inhoud bovenaan, optioneel een voet onderaan.
function UI.page(body, footer)
    local W, H, M = UI.W(), UI.H(), UI.MARGIN()
    local over = OverlapGroup:new{
        dimen = Geom:new{ w = W, h = H },
        FrameContainer:new{ bordersize = 0, padding = M, padding_top = UI.px(UI.TOPPAD), margin = 0, background = UI.WHITE, width = W, height = H, body },
        StatusBar:new{},
        lightTap(),
        refreshTap(),
    }
    -- past het niet, dan meldt de pagina dat; ks_main bouwt hem dan compacter opnieuw
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

-- Kleine onderdelen ------------------------------------------------------------------

--- Tegel als app-icoon: afgerond vierkant met icoon, naam eronder.
function UI.appIcon(icon, label, size, callback, dark, width)
    local w = width or math.max(size, UI.px(120))
    local ic = UI.icon(icon, math.floor(UI.unpx(size) * 0.5), UI.BLACK, { fixed = true })
    local g = UI.vgroup({ UI.center(ic, w, math.floor(size * 0.62)), UI.vspace(4), UI.center(UI.text(label, { size = 13, color = UI.INK2, max_width = w - UI.px(2) }), w) }, "center")
    return Tap:new{ callback = callback, label = label, g }
end

--- Rond stipje (gedaan = zwart, open = alleen een dunne rand).
function UI.dot(on, size)
    local s = UI.px(size or 14)
    return FrameContainer:new{ bordersize = on and 0 or UI.FINE(), color = UI.INK2, background = on and UI.BLACK or UI.WHITE,
        radius = math.floor(s / 2), padding = 0, margin = 0, Widget:new{ dimen = Geom:new{ w = s - (on and 0 or 2), h = s - (on and 0 or 2) } } }
end

--- Vierkantje om af te vinken (afgerond).
function UI.checkbox(on)
    local s = UI.px(32)
    return FrameContainer:new{ bordersize = UI.FINE(), color = on and UI.BLACK or UI.INK2, background = on and UI.BLACK or UI.WHITE, radius = UI.px(8), padding = 0, margin = 0,
        CenterContainer:new{ dimen = Geom:new{ w = s - 2 * UI.FINE(), h = s - 2 * UI.FINE() },
            on and UI.icon("check", 22, UI.WHITE, { bg = UI.BLACK }) or UI.vspace(0) } }
end

--- Voortgangsring (zoals bij een activiteitenring). frac 0..1
local Ring = Widget:extend{ size = 100, frac = 0, thick = 12 }
function Ring:getSize() return Geom:new{ w = self.size, h = self.size } end
function Ring:paintTo(bb, x, y)
    local r = self.size / 2
    local inner = r - self.thick
    local cx, cy = x + r, y + r
    local limit = self.frac * 2 * math.pi
    local dark, light = UI.BLACK, UI.FILL
    for py = 0, self.size - 1 do
        local dy = py + 0.5 - r
        for px = 0, self.size - 1 do
            local dx = px + 0.5 - r
            local d2 = dx * dx + dy * dy
            if d2 <= r * r and d2 >= inner * inner then
                -- hoek vanaf boven, met de klok mee
                local a = math.atan2(dx, -dy)
                if a < 0 then a = a + 2 * math.pi end
                bb:setPixelClamped(x + px, y + py, (limit > 0 and a <= limit) and dark or light)
            end
        end
    end
end
UI.Ring = Ring

--- Tegel voor oudere schermen (wordt niet meer op het beginscherm gebruikt).
function UI.tile(title, sub, w, h, callback)
    local content = UI.vgroup({ UI.text(title, { font = "display", size = 26, width = w - UI.px(44) }), UI.vspace(6), UI.text(sub, { size = 16, color = UI.INK2, width = w - UI.px(44) }) })
    return Tap:new{ callback = callback, label = title, UI.card(content, { width = w, height = h }) }
end

return UI
