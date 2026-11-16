-- Woordzoeker (met bij elk gevonden woord de gebeurtenis erachter), tijdlijn en tijdlijnspel.

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")
local UI = require("ks_ui")
local Store = require("ks_store")

local P = {}

local function data()
    if not P.d then P.d = dofile(require("ks_main").dir .. "/ks_history_data.lua") end
    return P.d
end

-- Woordzoeker ------------------------------------------------------------------------

local N = 12
local DIRS = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } } -- rechts, omlaag, schuin omlaag, schuin omhoog
local FILL = "AAAAABBCDDDEEEEEEEEEEFGGHHIIIIIJJKKLLLMMNNNNNNOOOOOPPRRRRRSSSSTTTTTUUVVWWZ"

--- Maakt een rooster met alle woorden erin. Geeft grid (rijen van letters) en posities.
function P.makeGrid(words, seed)
    math.randomseed(seed or os.time())
    for _ = 1, 200 do
        local g = {}
        for y = 1, N do g[y] = {} end
        local pos = {}
        local ok = true
        -- langste woorden eerst
        local order = {}
        for i, w in ipairs(words) do order[i] = i end
        table.sort(order, function(a, b) return #words[a] > #words[b] end)
        for _, wi in ipairs(order) do
            local w = words[wi]
            local placed = false
            for _ = 1, 300 do
                local d = DIRS[math.random(#DIRS)]
                local x0, y0 = math.random(N), math.random(N)
                local x1, y1 = x0 + d[1] * (#w - 1), y0 + d[2] * (#w - 1)
                if x1 >= 1 and x1 <= N and y1 >= 1 and y1 <= N then
                    local fits = true
                    for k = 1, #w do
                        local c = g[y0 + d[2] * (k - 1)][x0 + d[1] * (k - 1)]
                        if c and c ~= w:sub(k, k) then fits = false break end
                    end
                    if fits then
                        for k = 1, #w do g[y0 + d[2] * (k - 1)][x0 + d[1] * (k - 1)] = w:sub(k, k) end
                        pos[wi] = { x0, y0, x1, y1 }
                        placed = true
                        break
                    end
                end
            end
            if not placed then ok = false break end
        end
        if ok then
            for y = 1, N do for x = 1, N do
                if not g[y][x] then local r = math.random(#FILL); g[y][x] = FILL:sub(r, r) end
            end end
            return g, pos
        end
    end
end

local Grid = InputContainer:extend{ size = 600 }

function Grid:init()
    self.cell = math.floor(self.size / N)
    self.size = self.cell * N
    self.dimen = Geom:new{ x = 0, y = 0, w = self.size, h = self.size }
    self.ges_events = { TapGrid = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
end
function Grid:getSize() return Geom:new{ w = self.size, h = self.size } end

function Grid:onTapGrid(_, ges)
    local x = math.floor((ges.pos.x - self.dimen.x) / self.cell) + 1
    local y = math.floor((ges.pos.y - self.dimen.y) / self.cell) + 1
    if x >= 1 and x <= N and y >= 1 and y <= N and self.onTap then self.onTap(x, y) end
    return true
end

function Grid:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local c = self.cell
    local face = Font:getFace(UI.FACES.bold, math.floor(UI.unpx(c) * 0.56))
    for gy = 1, N do
        for gx = 1, N do
            local px, py = x + (gx - 1) * c, y + (gy - 1) * c
            local found = self.found and self.found[gy .. "," .. gx]
            local sel = self.sel and self.sel[1] == gx and self.sel[2] == gy
            if sel then bb:paintRect(px + 1, py + 1, c - 2, c - 2, Blitbuffer.COLOR_BLACK)
            elseif found then bb:paintRect(px + 1, py + 1, c - 2, c - 2, Blitbuffer.COLOR_GRAY_D) end
            local ch = self.grid[gy][gx]
            local m = RenderText:sizeUtf8Text(0, c, face, ch, true, true)
            local tx = px + math.floor((c - m.x) / 2)
            local ty = py + math.floor((c + face.size * 0.72) / 2)
            RenderText:renderUtf8Text(bb, tx, ty, face, ch, true, true, sel and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK)
        end
    end
    -- dunne rand om het geheel
    bb:paintBorder(x, y, self.size, self.size, UI.px(2), Blitbuffer.COLOR_BLACK)
end

local function newGame(themeIdx)
    local d = data()
    local th = d.themes[themeIdx]
    local words = {}
    for i, w in ipairs(th.words) do words[i] = w[1] end
    local seed = os.time()
    local g, pos = P.makeGrid(words, seed)
    return { theme = themeIdx, grid = g, pos = pos, found = {}, seed = seed }
end

function P.wordsearch(app)
    local W = UI.INNER()
    local d = data()
    local st = app.ws or Store.get("ws.game")
    if not st or not st.grid then st = newGame(1) end
    app.ws = st
    local th = d.themes[st.theme]
    local foundCells = {}
    local nFound = 0
    for wi, _ in pairs(st.found) do
        nFound = nFound + 1
        local p = st.pos[wi]
        local dx = p[3] == p[1] and 0 or (p[3] > p[1] and 1 or -1)
        local dy = p[4] == p[2] and 0 or (p[4] > p[2] and 1 or -1)
        local len = math.max(math.abs(p[3] - p[1]), math.abs(p[4] - p[2])) + 1
        for k = 0, len - 1 do foundCells[(p[2] + dy * k) .. "," .. (p[1] + dx * k)] = true end
    end
    local function onTap(x, y)
        if not st.sel then
            st.sel = { x, y }
            app.wsMsg = nil
        else
            local x0, y0 = st.sel[1], st.sel[2]
            st.sel = nil
            local hit
            for wi, p in pairs(st.pos) do
                if not st.found[wi] and ((p[1] == x0 and p[2] == y0 and p[3] == x and p[4] == y) or (p[1] == x and p[2] == y and p[3] == x0 and p[4] == y0)) then hit = wi end
            end
            if hit then
                st.found[hit] = true
                app.wsLast = hit
                app.wsMsg = nil
            elseif not (x0 == x and y0 == y) then
                app.wsMsg = "Dat is geen woord uit de lijst. Tik op de eerste en de laatste letter."
            end
        end
        Store.set("ws.game", st)
        app:refresh()
    end
    -- woordenlijst in vier kolommen: gevonden woorden grijs met een vinkje
    local list = {}
    local cols = 4
    local colW = math.floor(W / cols)
    for i = 1, #th.words, cols do
        local row = {}
        for j = i, math.min(i + cols - 1, #th.words) do
            local w = th.words[j][1]
            local f = st.found[j]
            table.insert(row, UI.box(UI.hgroup({ UI.icon(f and "circle_check" or "checkbox_off", 16, f and UI.BLACK or UI.INK3), UI.hspace(5),
                UI.text(w:sub(1, 1) .. w:sub(2):lower(), { size = 15, font = f and "sans" or "medium", color = f and UI.INK2 or UI.BLACK, max_width = colW - UI.px(26) }) }), colW))
        end
        table.insert(list, UI.hgroup(row))
        table.insert(list, UI.vspace(4))
    end
    -- uitleg bij het laatst gevonden woord
    local info
    if app.wsLast and th.words[app.wsLast] then
        local w = th.words[app.wsLast]
        info = UI.card(UI.vgroup({
            UI.text(w[1]:sub(1, 1) .. w[1]:sub(2):lower(), { font = "bold", size = 18, bg = UI.FILL }),
            UI.vspace(4),
            UI.text(w[2], { font = "serif", size = 18, width = W - UI.px(40), bg = UI.FILL, line_height = 0.35 }),
        }), { fill = true, border = 0, pad = UI.px(18) })
    elseif app.wsMsg then
        info = UI.text(app.wsMsg, { size = 17, color = UI.INK2, width = W })
    else
        info = UI.text(st.sel and "Tik nu op de laatste letter van het woord." or "Tik op de eerste en daarna op de laatste letter van een woord.", { size = 17, color = UI.INK2, width = W })
    end
    local done = nFound == #th.words
    local header = UI.header(th.name, function() app:back() end, done and "Alle woorden gevonden." or (nFound .. " van " .. #th.words .. " gevonden"))
    local footer = UI.buttonRow({
        { "Ander thema", function() app:go(P.themes) end, small = true },
        { "Nieuw rooster", function() app.ws = newGame(st.theme); app.wsLast = nil; Store.set("ws.game", app.ws); app:refresh() end, small = true, primary = done },
    })
    local listW = UI.vgroup(list)
    local infoH = UI.px(104)
    local used = header:getSize().h + listW:getSize().h + infoH + footer:getSize().h + UI.px(UI.TOPPAD) + UI.px(30 + 14 + 8 + 14 + 6)
    local size = math.min(W, UI.H() - used)
    local grid = Grid:new{ size = size, grid = st.grid, found = foundCells, sel = st.sel, onTap = onTap }
    return UI.page(UI.vgroup({ header, UI.center(grid, W, grid:getSize().h), UI.vspace(14), listW, UI.vspace(8), UI.box(info, W, infoH) }), footer)
end

function P.themes(app)
    local d = data()
    local items = { UI.header("Woordzoeker", function() app:back() end, "Kies een thema. Bij elk gevonden woord lees je wat erachter zit.") }
    UI.rowPad = 20
    for i, th in ipairs(d.themes) do
        table.insert(items, UI.row(th.name, #th.words .. " woorden", "›", function()
            app.ws = newGame(i); app.wsLast = nil; Store.set("ws.game", app.ws)
            app:replace(P.wordsearch)
        end))
    end
    UI.rowPad = nil
    return UI.page(UI.vgroup(items))
end

-- Tijdlijn ---------------------------------------------------------------------------

local function yearText(y) return y < 0 and (-y .. " v.Chr.") or tostring(y) end
P.yearText = yearText

local ERAS = {
    { "Oudheid", -3000, 499, "Oud" }, { "Middeleeuwen", 500, 1499, "MA" }, { "Vroegmoderne tijd", 1500, 1799, "1500" },
    { "19e eeuw", 1800, 1899, "1800" }, { "1900 tot 1945", 1900, 1945, "1900" }, { "1946 tot 2000", 1946, 1999, "1946" },
    { "21e eeuw", 2000, 2100, "2000" },
}

function P.timeline(app)
    local W = UI.INNER()
    local d = data()
    local era = app.tlEra or 6
    local e = ERAS[era]
    local items = { UI.header("Tijdlijn", function() app.tlEra = nil; app:back() end, e[1]) }
    local names = {}
    for i, x in ipairs(ERAS) do names[i] = x[4] end
    table.insert(items, UI.segmented(names, era, function(i) app.tlEra = i; app:refresh() end))
    table.insert(items, UI.vspace(16))
    local yearW = UI.px(110)
    for _, ev in ipairs(d.events) do
        if ev[1] >= e[2] and ev[1] <= e[3] then
            table.insert(items, UI.hgroup({
                UI.box(UI.text(yearText(ev[1]), { font = "display", size = 20 }), yearW),
                UI.vgroup({ UI.text(ev[2], { size = 19, font = "medium", width = W - yearW }), UI.text(ev[3], { size = 16, color = UI.INK2, width = W - yearW }) }),
            }, "top"))
            table.insert(items, UI.vspace(12))
        end
    end
    local footer = UI.button("Speel: zet ze op volgorde", function() app.tlGame = nil; app:go(P.order) end, { width = W, primary = true, icon = "play" })
    return UI.page(UI.vgroup(items), footer)
end

--- Tijdlijnspel: vijf gebeurtenissen, tik ze aan van oud naar nieuw.
function P.order(app)
    local W = UI.INNER()
    local d = data()
    local g = app.tlGame
    if not g then
        math.randomseed(os.time())
        local pick, used = {}, {}
        while #pick < 5 do
            local ev = d.events[math.random(#d.events)]
            if not used[ev[1]] then used[ev[1]] = true; table.insert(pick, ev) end
        end
        g = { pick = pick, chosen = {}, wrong = 0 }
        app.tlGame = g
    end
    local sorted = {}
    for i, ev in ipairs(g.pick) do sorted[i] = ev end
    table.sort(sorted, function(a, b) return a[1] < b[1] end)
    local nextIdx = #g.chosen + 1
    local done = nextIdx > #g.pick
    local items = { UI.header("Zet ze op volgorde", function() app:back() end, done and (g.wrong == 0 and "Foutloos!" or (g.wrong .. " keer mis getikt")) or "Tik de gebeurtenissen aan van oud naar nieuw.") }
    for _, ev in ipairs(g.pick) do
        local pos
        for k, c in ipairs(g.chosen) do if c == ev then pos = k end end
        local isWrong = g.lastWrong == ev
        local content = UI.vgroup({
            UI.hgroup({
                UI.text(pos and (pos .. ".") or "·", { font = "display", size = 24, color = pos and UI.BLACK or UI.INK3, bg = pos and UI.FILL or nil }), UI.hspace(14),
                UI.vgroup({
                    UI.text(ev[2], { size = 20, font = "medium", width = W - UI.px(100), bg = pos and UI.FILL or nil }),
                    (pos or done) and UI.text(yearText(ev[1]) .. " · " .. ev[3], { size = 16, color = UI.INK2, width = W - UI.px(100), bg = pos and UI.FILL or nil }) or (isWrong and UI.text("Nog niet: er is iets eerder.", { size = 16, font = "bold", width = W - UI.px(100) }) or nil),
                }),
            }, "top"),
        })
        table.insert(items, UI.Tap:new{ label = ev[2], callback = function()
            if pos or done then return end
            if ev == sorted[nextIdx] then
                table.insert(g.chosen, ev)
                g.lastWrong = nil
                if #g.chosen == #g.pick then
                    local best = Store.get("tl.best", { played = 0, perfect = 0 })
                    best.played = best.played + 1
                    if g.wrong == 0 then best.perfect = best.perfect + 1 end
                    Store.set("tl.best", best)
                end
            else
                g.wrong = g.wrong + 1
                g.lastWrong = ev
            end
            app:refresh()
        end, UI.card(content, { fill = pos ~= nil, border = pos and 0 or nil }) })
        table.insert(items, UI.vspace(10))
    end
    local best = Store.get("tl.best", { played = 0, perfect = 0 })
    table.insert(items, UI.text(("Gespeeld: %d, foutloos: %d"):format(best.played, best.perfect), { size = 15, color = UI.INK2 }))
    local footer = UI.button(done and "Nog een ronde" or "Opnieuw", function() app.tlGame = nil; app:refresh() end, { width = W, primary = done })
    return UI.page(UI.vgroup(items), footer)
end

return P
