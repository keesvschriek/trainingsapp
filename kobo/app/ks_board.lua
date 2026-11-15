-- Schaakbord om op te tikken. Wit staat altijd onderaan.

local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local Blitbuffer = require("ffi/blitbuffer")
local C = require("ks_chess")
local Screen = Device.screen

local LIGHT = Blitbuffer.COLOR_WHITE
local DARK = Blitbuffer.Color8(0xB4)
local BLACK = Blitbuffer.COLOR_BLACK

local Board = InputContainer:extend{
    size = nil,      -- breedte en hoogte in pixels
    state = nil,     -- stand uit ks_chess
    marks = nil,     -- { [sq] = true }: veld met dikke rand
    dots = nil,      -- { [sq] = true }: stip (mogelijke zet)
    selected = nil,  -- veld dat gekozen is
    last = nil,      -- { from, to } van de laatste zet
    wrong = nil,     -- veld met een kruis (foute keuze)
    onTap = nil,     -- function(sq)
}

-- Lettergrootte zo kiezen dat een teken ongeveer de gegeven hoogte in pixels krijgt
local function faceForPixels(name, px)
    return Font:getFace(name, math.max(6, math.floor(px * 100 / Screen:scaleBySize(100))))
end

function Board:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.size, h = self.size }
    self.sqpx = math.floor(self.size / 8)
    self.size = self.sqpx * 8
    self.dimen.w, self.dimen.h = self.size, self.size
    self.pieceFace = faceForPixels("FreeSerif.ttf", self.sqpx * 1.25)
    self.coordFace = faceForPixels("NotoSans-Bold.ttf", self.sqpx * 0.24)
    self.ges_events = { TapBoard = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function Board:getSize() return Geom:new{ w = self.size, h = self.size } end

function Board:squareAt(x, y)
    local f = math.floor((x - self.dimen.x) / self.sqpx)
    local r = 7 - math.floor((y - self.dimen.y) / self.sqpx)
    if f < 0 or f > 7 or r < 0 or r > 7 then return nil end
    return r * 8 + f + 1
end

function Board:onTapBoard(_, ges)
    local sq = self:squareAt(ges.pos.x, ges.pos.y)
    if sq and self.onTap then self.onTap(sq) end
    return true
end

local function drawText(bb, face, text, x, y, color)
    -- x, y = linksboven; tekent op de basislijn
    local m = RenderText:sizeUtf8Text(0, 1000, face, text, true, false)
    RenderText:renderUtf8Text(bb, x, y + m.y_top, face, text, true, false, color)
    return m.x, m.y_top + m.y_bottom
end

local function centerText(bb, face, text, x, y, w, h, color)
    local m = RenderText:sizeUtf8Text(0, 1000, face, text, true, false)
    local tx = x + math.floor((w - m.x) / 2)
    local ty = y + math.floor((h - (m.y_top + m.y_bottom)) / 2) + m.y_top
    RenderText:renderUtf8Text(bb, tx, ty, face, text, true, false, color)
end

function Board:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    Board.lastPainted = self
    local s = self.sqpx
    local b = self.state and self.state.board or {}
    for r = 0, 7 do
        for f = 0, 7 do
            local sq = r * 8 + f + 1
            local px, py = x + f * s, y + (7 - r) * s
            local light = (r + f) % 2 == 1
            bb:paintRect(px, py, s, s, light and LIGHT or DARK)
            if self.last and (self.last.from == sq or self.last.to == sq) then
                bb:paintBorder(px + 3, py + 3, s - 6, s - 6, math.max(2, math.floor(s / 40)), BLACK)
            end
            if self.marks and self.marks[sq] then
                bb:paintBorder(px + 2, py + 2, s - 4, s - 4, math.max(4, math.floor(s / 14)), BLACK)
            end
            if self.selected == sq then
                bb:paintBorder(px, py, s, s, math.max(5, math.floor(s / 11)), BLACK)
            end
            local p = b[sq]
            if p then
                -- Witte stukken krijgen een wit vlak onder het omlijnde teken, zodat ze op donkere velden leesbaar zijn
                if p:match("%u") then
                    centerText(bb, self.pieceFace, C.GLYPH[p:lower()], px, py, s, s, LIGHT)
                end
                centerText(bb, self.pieceFace, C.GLYPH[p], px, py, s, s, BLACK)
            end
            if self.dots and self.dots[sq] then
                local rr = math.floor(s / (p and 2.3 or 7))
                if p then
                    bb:paintCircle(px + math.floor(s / 2), py + math.floor(s / 2), rr, BLACK, math.max(3, math.floor(s / 22)))
                else
                    bb:paintCircle(px + math.floor(s / 2), py + math.floor(s / 2), rr, BLACK)
                end
            end
            if self.wrong == sq then
                local t = math.max(3, math.floor(s / 20))
                for i = 0, s - 1, 1 do
                    if i > s * 0.25 and i < s * 0.75 then
                        bb:paintRect(px + i, py + i - math.floor(t / 2), 1, t, BLACK)
                        bb:paintRect(px + s - i, py + i - math.floor(t / 2), 1, t, BLACK)
                    end
                end
            end
            -- coördinaten: cijfers in de a-lijn, letters op rij 1
            local cc = light and Blitbuffer.COLOR_GRAY_6 or LIGHT
            if f == 0 then drawText(bb, self.coordFace, tostring(r + 1), px + 4, py + 3, cc) end
            if r == 0 then
                local m = RenderText:sizeUtf8Text(0, 1000, self.coordFace, "h", true, false)
                drawText(bb, self.coordFace, ("abcdefgh"):sub(f + 1, f + 1), px + s - m.x - 5, py + s - (m.y_top + m.y_bottom) - 4, cc)
            end
        end
    end
    bb:paintBorder(x, y, self.size, self.size, 2, BLACK)
end

return Board
