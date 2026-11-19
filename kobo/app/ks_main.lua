-- Kees Personal voor de Kobo (met Kees Study als map): beginscherm en navigatie.
-- Wordt gestart door de user patch 2-kees-study.lua als KEES_STUDY=1.

local Device = require("device")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local UI = require("ks_ui")
local Store = require("ks_store")

local M = {}

local App = InputContainer:extend{ name = "keesstudy", covers_fullscreen = true, is_always_active = true }

function App:handleEvent(ev)
    if ev.handler == "onGesture" then pcall(function() require("ks_system").touch() end) end
    return InputContainer.handleEvent(self, ev)
end

--- Bij elk tekenen opnieuw bijhouden welke tikvlakken er staan (anders groeit de lijst elke minuut met de klok).
function App:paintTo(bb, x, y)
    UI.painted = {}
    InputContainer.paintTo(self, bb, x, y)
end

function App:onSuspend() pcall(function() require("ks_system").onSuspend() end) end
function App:onResume() pcall(function() require("ks_system").onResume() end) end

function App:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = UI.W(), h = UI.H() }
    self.stack = {}
    self.navs = 0
    self.ges_events = { SwipePage = { require("ui/gesturerange"):new{ ges = "swipe", range = self.dimen } } }
end

--- Vegen, overal in de app: naar links = verder, naar rechts = vorige (of terug als er geen vorige is).
--- Werkt via de knoppen die op het scherm staan, dus elk scherm met Vorige/Verder doet automatisch mee.
local NEXT = { "^Verder", "^Volgende", "^Volgend" }
local PREV = { "^Vorige", "^Vorig" }
local function findTap(patterns)
    for i = #UI.painted, 1, -1 do
        local t = UI.painted[i]
        for _, p in ipairs(patterns) do
            if type(t.label) == "string" and t.label:find(p) and t.callback then return t end
        end
    end
end
function App:onSwipePage(_, ges)
    if ges.direction == "west" then
        local t = findTap(NEXT)
        if t then UI.run(t.callback) return true end
    elseif ges.direction == "east" then
        local t = findTap(PREV)
        if t then UI.run(t.callback) return true end
        if #self.stack > 1 then self:back() return true end
    end
end

--- Ga naar een nieuw scherm. builder(app) geeft een widget terug en mag later opnieuw worden aangeroepen.
function App:go(builder)
    table.insert(self.stack, builder)
    self:render("page")
end

function App:replace(builder)
    self.stack[#self.stack] = builder
    self:render("page")
end

function App:back()
    if #self.stack > 1 then table.remove(self.stack) end
    self:render("page")
end

function App:home()
    while #self.stack > 1 do table.remove(self.stack) end
    self:render("page")
end

--- Per scherm onthouden bij welke poging het paste. Dan hoeft een vol scherm de volgende keer
--- niet eerst groot, dan compact en dan steeds kleiner gebouwd te worden (scheelt op de Kobo veel tijd).
local fit = setmetatable({}, { __mode = "k" })

--- Bouw het huidige scherm opnieuw zonder het al naar het scherm te sturen.
function App:rebuild()
    local builder = self.stack[#self.stack]
    if not builder then return end
    -- Bouwen; past het scherm niet met de gekozen lettergrootte, dan stapje kleiner (alleen voor dit scherm).
    -- Poging 1 normaal, 2 compactere lijstregels, 3 en verder elke keer 6% kleinere letters.
    local base = UI.scale
    local known = fit[builder]
    local first = (known and known.scale == base) and known.attempt or 1
    local ok, w
    for attempt = first, 7 do
        UI.painted = {}
        UI.overflow = false
        UI.noShrink = false
        UI.need = nil
        UI.compact = attempt >= 2
        UI.scale = base * 0.94 ^ math.max(0, attempt - 2)
        ok, w = pcall(builder, self)
        if not ok or not UI.overflow or UI.noShrink or UI.scale < 0.75 then
            if ok then
                -- ruim over (minder dan 85% gebruikt)? volgende keer een maat groter proberen
                local roomy = UI.need and UI.need < UI.H() * 0.85
                fit[builder] = { scale = base, attempt = (roomy and attempt > 1) and attempt - 1 or attempt }
            end
            break
        end
    end
    UI.scale = base
    UI.compact = false
    if not ok then
        local err = tostring(w)
        require("logger").warn("Kees Personal fout:", err)
        local onHome = #self.stack <= 1
        w = UI.page(UI.vgroup({
            UI.header("Er ging iets mis", (not onHome) and function() self:back() end or nil),
            UI.text(err, { width = UI.INNER(), size = 16 }),
            UI.vspace(20),
            UI.text("Je voortgang is veilig. Kijk of er een nieuwe versie is, die lost dit vaak op.", { width = UI.INNER(), size = 18 }),
        }), UI.buttonRow({
            { "Bijwerken", function() self:go(M.updatePage) end, primary = true },
            { "Instellingen", function() self:go(require("ks_system").settingsPage) end },
            { "Afsluiten", function() self:quit() end },
        }))
    end
    self[1] = w
end

--- Teken het huidige scherm opnieuw (na een tik). mode "page" = nieuw scherm.
function App:render(mode)
    -- KOReader zet de teller voor flitsende verversingen terug bij licht/donker
    -- wisselen (ToggleNightMode). Daarom hier elke keer weer uit.
    UIManager.FULL_REFRESH_COUNT = 0
    self:rebuild()
    -- Om de zoveel nieuwe schermen één keer volledig verversen (tegen vage restjes).
    if mode == "page" then
        self.navs = (self.navs or 0) + 1
        local every = Store.get("set.fullevery2", 0)
        -- in donker blijven er sneller restjes staan: dan twee keer zo vaak
        if every > 0 and require("ks_light").isDark() then every = math.max(2, math.floor(every / 2)) end
        if every > 0 and self.navs >= every then
            self.navs = 0
            UIManager:setDirty(self, "full")
            return
        end
    end
    -- Altijd "partial": op de Elipsa 2E is dat de modus zonder knipperen (REAGL).
    -- "ui" laat het scherm zelf kiezen en dat knippert bij grijstinten; "full" geeft een zwarte flits.
    UIManager:setDirty(self, "partial")
end

function App:refresh() self:render("ui") end

--- Eén keer volledig verversen (met flits) om restjes van eerdere schermen weg te halen.
function App:cleanScreen() UIManager:setDirty(self, "full") end

--- Herstarten, bijvoorbeeld na een update. KOReader start dan opnieuw en daarmee deze app.
function App:restart()
    pcall(function() require("ks_system").stop() end)
    Store.flush()
    UIManager:quit(85)
end

function App:quit()
    pcall(function() require("ks_system").stop() end)
    Store.flush()
    UIManager:close(self, "full")
end

--- Naar de gewone Kobo (bibliotheek en winkel). KOReader sluit af; de Kobo gaat verder waar hij was.
function App:toKobo()
    pcall(function() require("ks_system").stop() end)
    Store.flush()
    UIManager:quit(0)
end

-- Beginscherm ------------------------------------------------------------------

local MONTHS = { "januari", "februari", "maart", "april", "mei", "juni", "juli", "augustus", "september", "oktober", "november", "december" }
local DAYS = { "zondag", "maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag" }

function M.dateText(ts)
    local t = os.date("*t", ts)
    return DAYS[t.wday] .. " " .. t.day .. " " .. MONTHS[t.month]
end

--- Een module veilig laden: als er iets mis is met één onderdeel, blijft de rest werken.
local function safe(fn, fallback)
    local r = { pcall(fn) }
    if r[1] then return unpack(r, 2, 4) end
    require("logger").warn("Kees Personal:", r[2])
    return fallback, nil
end

local function remember(name) Store.set("last.module", name) end

--- Map "Kees Study": leren en spelen. Schaken en puzzels hebben elk een eigen mapje, zodat alles op één scherm past.
function M.studyFolder(app)
    local QuizUI = require("ks_quizui")
    local items = {
        UI.header("Kees Study", function() app:back() end, "Leren, schaken, kaarten en puzzels"),
        UI.row("Leerlijnen", safe(require("ks_leer").summary, "NAVO, Defensie, Geschiedenis, Topografie"), "›", function() remember("Leerlijnen"); app:go(require("ks_leer").home) end, nil, "school"),
        UI.row("Leerkaarten", safe(require("ks_cards").summary, ""), "›", function() remember("Leerkaarten"); app:go(require("ks_cards").home) end, nil, "brain"),
        UI.row("Quiz", safe(QuizUI.summary, ""), "›", function() remember("Quiz"); app:go(QuizUI.home) end, nil, "help"),
        UI.row("Schaken", "Lessen, tegen de computer en de puzzel van de dag", "›", function() app:go(M.chessFolder) end, nil, "chess"),
        UI.row("Topografie op de kaart", "Landen aanwijzen en herkennen, per werelddeel", "›", function() remember("Topografie"); app:go(require("ks_mapui").menu) end, nil, "earth"),
        UI.row("Tijdreis", safe(require("ks_tijdreis").summary, ""), "›", function() remember("Tijdreis"); app.trMap = nil; app:go(require("ks_tijdreis").page) end, nil, "map"),
        UI.row("Wikirace", safe(require("ks_wikirace").summary, ""), "›", function() remember("Wikirace"); require("ks_wikirace").start(app) end, nil, "web"),
        UI.row("Puzzels", "Woordzoeker en tijdlijn", "›", function() app:go(M.puzzleFolder) end, nil, "list_checks"),
    }
    return UI.page(UI.vgroup(items))
end

--- Mapje Schaken.
function M.chessFolder(app)
    local ChessUI = require("ks_chessui")
    return UI.page(UI.vgroup({
        UI.header("Schaken", function() app:back() end),
        UI.row("Schaken leren", safe(ChessUI.summary, ""), "›", function() remember("Schaken leren"); app:go(ChessUI.lessonList) end, nil, "chess"),
        UI.row("Tegen de computer", safe(require("ks_play").summary, ""), "›", function()
            remember("Tegen de computer")
            local g = Store.get("play.game")
            app:go((g and not g.over) and require("ks_play").game or require("ks_play").menu)
        end, nil, "chess"),
        UI.row("Puzzel van de dag", "Van Lichess, ook zonder wifi op te lossen", "›", function() app:go(require("ks_lichess").page) end, nil, "target"),
    }))
end

--- Mapje Puzzels.
function M.puzzleFolder(app)
    return UI.page(UI.vgroup({
        UI.header("Puzzels", function() app:back() end),
        UI.row("Woordzoeker", "Willekeurige woorden of een geschiedenisthema", "›", function()
            local g = Store.get("ws.game")
            app:go(g and g.grid and require("ks_puzzles").wordsearch or require("ks_puzzles").themes)
        end, nil, "list_checks"),
        UI.row("Tijdlijn", "Grote gebeurtenissen, en zet ze op volgorde", "›", function() app:go(require("ks_puzzles").timeline) end, nil, "history"),
    }))
end

--- Map "Lezen": fragmenten, te lezen, en je eigen boeken.
function M.readFolder(app)
    local items = {
        UI.header("Lezen", function() app:back() end, "Rustig lezen, zonder scrollen"),
        UI.row("Fragment van de dag", safe(require("ks_fragment").summary, ""), "›", function() app:go(require("ks_fragment").page) end, nil, "feather"),
        UI.row("Te lezen", safe(require("ks_reading").summary, ""), "›", function() app.readPg = 1; app:go(require("ks_reading").page) end, nil, "news"),
        UI.row("Op deze dag", safe(require("ks_otd").summary, ""), "›", function() app.otdPg = 1; app:go(require("ks_otd").page) end, nil, "history"),
        UI.row("Radionieuws van deze dag", safe(require("ks_radio").summary, ""), "›", function() require("ks_radio").start(app) end, nil, "news"),
        UI.vspace(20),
        UI.row("Naar je boeken", "Sluit de app en ga naar de Kobo-bibliotheek", "›", function() app:toKobo() end, nil, "book"),
    }
    return UI.page(UI.vgroup(items))
end

--- Map "Ontwikkeling": dagtekst en gewoontes.
function M.growFolder(app)
    local D = require("ks_dagtekst")
    local H = require("ks_habits")
    local who = safe(D.summary, "")
    local done, total = safe(H.summary, 0)
    local items = {
        UI.header("Ontwikkeling", function() app:back() end, "Elke dag een beetje"),
        UI.row("Opvolgen", safe(require("ks_opvolg").homeLine, ""), "›", function() app.ovPg = 1; app.ovLast = nil; app:go(require("ks_opvolg").page) end, nil, "list_checks"),
        UI.row("Notities", safe(require("ks_notes").summary, ""), "›", function() app.noteFolder = nil; app.notePg = 1; app:go(require("ks_notes").page) end, nil, "pencil"),
        UI.row("Je week", "Rooster, training en punten per dag", "›", function() app.weekMon = nil; app:go(require("ks_week").page) end, nil, "calendar"),
        UI.row("Defensie-module", safe(require("ks_module").homeLine, nil) or "Aftellen en paklijst", "›", function() app:go(require("ks_module").page) end, nil, "flag"),
        UI.row("Dag afsluiten", safe(require("ks_avond").summary, ""), "›", function() app:go(require("ks_avond").page) end, nil, "moon"),
        UI.row("Dagtekst", "Vandaag: " .. tostring(who), "›", function() remember("Dagtekst"); app:go(D.page) end, nil, "quote"),
        UI.row("Gewoontes", ("%d van %d gedaan vandaag"):format(done or 0, total or 0), "›", function() remember("Gewoontes"); app:go(H.page) end, nil, "list_checks"),
    }
    return UI.page(UI.vgroup(items))
end

local function greeting()
    local h = tonumber(os.date("%H"))
    if h < 6 then return "Goedenacht" end
    if h < 12 then return "Goedemorgen" end
    if h < 18 then return "Goedemiddag" end
    return "Goedenavond"
end

local function homePage(app)
    local D = require("ks_dagtekst")
    local H = require("ks_habits")
    local Sport = require("ks_sport")
    local News = require("ks_news")
    local Sys = require("ks_system")
    local W = UI.INNER()
    local gap = UI.px(16)
    local half = math.floor((W - gap) / 2)
    local space = UI.H() - UI.px(UI.TOPPAD) - UI.MARGIN()

    local function build(level)
        local items = {}
        -- Begroeting
        table.insert(items, UI.text(M.dateText(), { size = 17, color = UI.INK2 }))
        table.insert(items, UI.vspace(2))
        table.insert(items, UI.text(greeting() .. ", Kees", { font = "display", size = 34, width = W }))
        local nextLes = safe(require("ks_rooster").next)
        if nextLes then
            table.insert(items, UI.vspace(6))
            table.insert(items, UI.Tap:new{ label = "Rooster", callback = function() app.roosterDay = 0; app:go(require("ks_rooster").page) end,
                UI.hgroup({ UI.icon("calendar", 19, UI.INK2), UI.hspace(8), UI.text(nextLes, { size = 16, color = UI.INK2, max_width = W - UI.px(40) }) }) })
        end
        local ovLine = safe(require("ks_opvolg").homeLine)
        if ovLine then
            table.insert(items, UI.vspace(6))
            table.insert(items, UI.Tap:new{ label = "Opvolgen", callback = function() app.ovPg = 1; app.ovLast = nil; app:go(require("ks_opvolg").page) end,
                UI.hgroup({ UI.icon("list_checks", 19, UI.INK2), UI.hspace(8), UI.text(ovLine, { size = 16, color = UI.INK2, max_width = W - UI.px(60) }), UI.icon("chevron_right", 18, UI.INK3) }) })
        end
        if os.date("%w") == "0" and tonumber(os.date("%H")) >= 12 and not require("ks_avond").isEvening() then
            table.insert(items, UI.vspace(6))
            table.insert(items, UI.Tap:new{ label = "Je week", callback = function() app.weekMon = nil; app:go(require("ks_week").page) end,
                UI.hgroup({ UI.icon("calendar", 19, UI.INK2), UI.hspace(8), UI.text("Je week bekijken en doorschuiven", { size = 16, color = UI.INK2 }), UI.icon("chevron_right", 18, UI.INK3) }) })
        end
        local modLine = safe(require("ks_module").homeLine)
        if modLine then
            table.insert(items, UI.vspace(6))
            table.insert(items, UI.Tap:new{ label = "Module", callback = function() app:go(require("ks_module").page) end,
                UI.hgroup({ UI.icon("flag", 19, UI.INK2), UI.hspace(8), UI.text(modLine, { size = 16, color = UI.INK2, max_width = W - UI.px(60) }), UI.icon("chevron_right", 18, UI.INK3) }) })
        end
        local Sync = require("ks_sync")
        if Sync.connected() and tonumber(os.date("%H")) < 12 and not safe(Sync.checkin) then
            table.insert(items, UI.vspace(6))
            table.insert(items, UI.Tap:new{ label = "Check-in", callback = function() app:go(Sync.checkinPage) end,
                UI.hgroup({ UI.icon("sun", 19, UI.INK2), UI.hspace(8), UI.text("Ochtend-check-in nog niet gedaan", { size = 16, color = UI.INK2 }), UI.icon("chevron_right", 18, UI.INK3) }) })
        end
        table.insert(items, UI.vspace(level >= 2 and 14 or 22))

        -- Dagtekst: grijze kaart met citaat
        local who, first = safe(D.summary, "Dagtekst")
        local quote = UI.vgroup({
            UI.text(first or "", { font = "serif", size = 21, width = W - UI.px(40), line_height = 0.35, height = level >= 1 and UI.px(84) or UI.px(118) }),
            UI.vspace(6),
            UI.text((D.isEvening() and "Terugblik · " or "") .. tostring(who), { size = 15, color = UI.INK2 }),
        })
        table.insert(items, UI.Tap:new{ label = "Dagtekst", callback = function() remember("Dagtekst"); app:go(D.page) end,
            UI.card(quote, { pad = UI.px(18) }) })
        table.insert(items, UI.vspan(gap))

        -- Avond: dag afsluiten, verder lezen, 10 kaarten
        local A = require("ks_avond")
        if A.isEvening() then
            local function half_card(icon, label, title, sub, cb)
                local v = UI.vgroup({
                    UI.hgroup({ UI.icon(icon, 20, UI.INK2), UI.hspace(8), UI.text(label, { size = 15, color = UI.INK2 }) }),
                    UI.vspace(6),
                    UI.text(title, { font = "medium", size = 21, width = half - UI.px(40), height = UI.px(56) }),
                    UI.vspace(2),
                    UI.text(sub or "", { size = 15, color = UI.INK2, width = half - UI.px(40), height = UI.px(42) }),
                })
                return { v = v, cb = cb, label = label }
            end
            local e = safe(A.entry)
            local lr = safe(A.lastRead)
            local C = require("ks_cards")
            local row1 = {
                half_card("moon", "Dag afsluiten", (e and e.done) and "Afgesloten" or "Hoe was je dag?", safe(A.summary, ""), function() app:go(A.page) end),
                half_card("book", "Verder lezen", lr and lr.title or "Iets om te lezen", lr and (lr.kind == "frag" and "Fragment van de dag" or "Te lezen") or "Fragment, stukken, Op deze dag", function() A.continueReading(app) end),
            }
            local row2 = {
                half_card("brain", "Kort leren", "10 leerkaarten", safe(C.summary, ""), function() C.ten(app) end),
                os.date("%w") == "0"
                    and half_card("calendar", "Zondag", "Je week", "Rooster, training, module en punten", function() app.weekMon = nil; app:go(require("ks_week").page) end)
                    or half_card("list_checks", "Opvolgen", (#safe(require("ks_opvolg").open, {}) .. " open"), "Tik voor je lijst", function() app.ovPg = 1; app.ovLast = nil; app:go(require("ks_opvolg").page) end),
            }
            for _, r in ipairs({ row1, row2 }) do
                local h = math.max(r[1].v:getSize().h, r[2].v:getSize().h) + UI.px(36)
                table.insert(items, UI.hgroup({
                    UI.Tap:new{ label = r[1].label, callback = r[1].cb, UI.card(r[1].v, { width = half, height = h }) },
                    UI.hspan(gap),
                    UI.Tap:new{ label = r[2].label, callback = r[2].cb, UI.card(r[2].v, { width = half, height = h }) },
                }, "top"))
                table.insert(items, UI.vspan(gap))
            end
        end

        -- Training en gewoontes naast elkaar
        local name, sub, icon = safe(Sport.today, "Sport")
        local tr = UI.vgroup({
            UI.hgroup({ UI.icon(icon or "run", 20, UI.INK2), UI.hspace(8), UI.text("Training", { size = 15, color = UI.INK2 }) }),
            UI.vspace(6),
            UI.text(name or "Sport", { font = "medium", size = 21, width = half - UI.px(40), height = UI.px(56) }),
            UI.vspace(2),
            UI.text(sub or "", { size = 15, color = UI.INK2, width = half - UI.px(40), height = UI.px(42) }),
        })
        local done, total = safe(H.summary, 0)
        done, total = done or 0, total or 0
        local dots = {}
        for i = 1, math.max(total, 1) do
            table.insert(dots, UI.dot(i <= done and total > 0, 15))
            table.insert(dots, UI.hspace(6))
        end
        local hb = UI.vgroup({
            UI.hgroup({ UI.icon("list_checks", 20, UI.INK2), UI.hspace(8), UI.text("Gewoontes", { size = 15, color = UI.INK2 }) }),
            UI.vspace(6),
            UI.text(done .. " van " .. total, { font = "medium", size = 21 }),
            UI.vspace(8),
            UI.hgroup(dots),
        })
        local sunday = os.date("%w") == "0"
        if sunday then
            hb = UI.vgroup({
                UI.hgroup({ UI.icon("calendar", 20, UI.INK2), UI.hspace(8), UI.text("Je week", { size = 15, color = UI.INK2 }) }),
                UI.vspace(6),
                UI.text("Weekoverzicht", { font = "medium", size = 21 }),
                UI.vspace(2),
                UI.text(("Gewoontes vandaag %d van %d. Tik voor je hele week."):format(done, total), { size = 15, color = UI.INK2, width = half - UI.px(44) }),
            })
        end
        local rowH = math.max(tr:getSize().h, hb:getSize().h) + UI.px(36)
        table.insert(items, UI.hgroup({
            UI.Tap:new{ label = "Training", callback = function() app:go(Sport.page) end, UI.card(tr, { width = half, height = rowH }) },
            UI.hspan(gap),
            UI.Tap:new{ label = sunday and "Je week" or "Gewoontes", callback = function()
                if sunday then app:go(require("ks_week").page) else remember("Gewoontes"); app:go(H.page) end
            end, UI.card(hb, { width = half, height = rowH }) },
        }, "top"))
        table.insert(items, UI.vspan(gap))

        -- Nieuws (niet 's avonds: dan is het rustig)
        if not require("ks_avond").isEvening() then
        local nd = News.data()
        local edName = nd.edition or (News.edition())
        local nv = { UI.hgroup({ UI.icon("news", 20, UI.INK2), UI.hspace(8),
            UI.text(edName .. (nd.at and (" · " .. os.date("%H:%M", nd.at)) or "") .. " · NOS", { size = 15, color = UI.INK2 }) }) }
        table.insert(nv, UI.vspace(8))
        local nHead = level >= 1 and 2 or 3
        local shown = 0
        for _, it in ipairs(nd.items or {}) do
            if shown >= nHead then break end
            if it.feed == "algemeen" or shown < nHead then
                table.insert(nv, UI.text(it.title, { size = 18, width = W - UI.px(40), height = UI.px(26) }))
                table.insert(nv, UI.vspace(6))
                shown = shown + 1
            end
        end
        if shown == 0 then table.insert(nv, UI.text("Nog niet opgehaald. Tik om de krant te openen.", { size = 17, color = UI.INK2, width = W - UI.px(44) })) end
        table.insert(items, UI.Tap:new{ label = "Nieuws", callback = function() app:go(News.page) end, UI.card(UI.vgroup(nv)) })
        end
        table.insert(items, UI.vspace(level >= 2 and 18 or 26))

        local top = UI.vgroup(items)
        local topH = top:getSize().h

        -- Apps naast elkaar, als een dock. Kobo = terug naar de gewone Kobo (Nickel).
        local icon = UI.px(level >= 3 and 54 or 60)
        local apps = {
            { "chess", "Kees Study", function() app:go(M.studyFolder) end, true },
            { "run", "Sport", function() app:go(Sport.page) end },
            { "leaf", "Groei", function() app:go(M.growFolder) end },
            { "wrench", "Tools", function() app:go(require("ks_tools").menu) end },
            { "book", "Lezen", function() app:go(M.readFolder) end },
            { "cog", "Instellingen", function() app:go(Sys.settingsPage) end },
            { "home_outline", "Kobo", function() app:toKobo() end },
        }
        local col = math.floor(W / #apps)
        local row = {}
        for _, a in ipairs(apps) do table.insert(row, UI.appIcon(a[1], a[2], icon, a[3], a[4], col)) end
        local grid = { UI.hgroup(row, "top") }
        local g = UI.vgroup(grid)
        -- het dock onderaan het scherm
        local fill = math.max(0, space - topH - g:getSize().h - UI.px(6))
        return UI.vgroup({ top, UI.vspan(fill), g }), topH + g:getSize().h
    end

    -- begin bij de compactheid die de vorige keer paste (scheelt bouwen), met ruimte over een stap terug
    local body
    for level = M.homeLevel or 0, 3 do
        local h
        body, h = build(level)
        if h <= space or level == 3 then
            M.homeLevel = (h < space * 0.9 and level > 0) and level - 1 or level
            break
        end
    end
    return UI.page(body)
end

--- Scherm om de app en de vragen via wifi bij te werken.
function M.updatePage(app)
    local U = require("ks_update")
    local S = app.updateState or {}
    app.updateState = S
    local items = { UI.header("Bijwerken via wifi", function() app.updateState = nil; app:back() end, "Je versie: " .. U.localVersion()) }
    local function say(msg) S.msg = msg; app:refresh() end
    local function later(fn) UIManager:scheduleIn(0.2, fn) end

    table.insert(items, UI.text("De app", { font = "serif", size = 24 }))
    table.insert(items, UI.vspace(8))
    if S.info and #S.info.files > 0 and not S.done then
        table.insert(items, UI.text(("Er is een nieuwe versie: %d bestand%s, %d kB."):format(#S.info.files, #S.info.files == 1 and "" or "en", math.ceil(S.info.bytes / 1024)), { size = 19, width = UI.INNER() }))
        if S.info.changes and #S.info.changes > 0 then
            table.insert(items, UI.vspace(10))
            table.insert(items, UI.text("Wat is er nieuw", { font = "bold", size = 18 }))
            for _, c in ipairs(S.info.changes) do
                table.insert(items, UI.text("· " .. c, { size = 17, width = UI.INNER() }))
            end
        end
        table.insert(items, UI.vspace(10))
        table.insert(items, UI.button("Nu bijwerken", function()
            say("Bezig met downloaden...")
            later(function()
                U.apply(S.info, function(ok, res)
                    if ok then S.done = true; say("Klaar. Herstart de app om de nieuwe versie te gebruiken.")
                    else say("Bijwerken mislukt: " .. res) end
                end, function(i, n) say(("Bezig met downloaden: bestand %d van %d"):format(i, n)) end)
            end)
        end, { width = UI.INNER(), primary = true }))
    elseif S.done then
        table.insert(items, UI.button("Nu herstarten", function() app:restart() end, { width = UI.INNER(), primary = true }))
    else
        table.insert(items, UI.button("Controleren op een nieuwe versie", function()
            say("Bezig met controleren...")
            later(function()
                U.check(function(ok, info)
                    if not ok then return say("Controleren mislukt: " .. info) end
                    S.info = info
                    say(#info.files == 0 and "Je hebt de nieuwste versie." or nil)
                end)
            end)
        end, { width = UI.INNER() }))
    end

    if U.hasBackup() and not S.done then
        table.insert(items, UI.vspace(12))
        table.insert(items, UI.button(S.confirmRollback and ("Zeker? Terug naar " .. U.backupVersion()) or "Vorige versie terugzetten", function()
            if not S.confirmRollback then S.confirmRollback = true; return app:refresh() end
            S.confirmRollback = nil
            local ok, err = U.rollback()
            if ok then S.done = true; say("Vorige versie teruggezet. Herstart de app.") else say(err) end
        end, { width = UI.INNER(), small = true }))
    end

    table.insert(items, UI.vspace(26))
    table.insert(items, UI.text("Quizvragen", { font = "serif", size = 24 }))
    table.insert(items, UI.vspace(8))
    table.insert(items, UI.button("Nieuwe vragen ophalen", function()
        say("Bezig met ophalen...")
        later(function() require("ks_quiz").updatePacks(function(_, msg) say(msg) end) end)
    end, { width = UI.INNER() }))
    if S.msg then
        table.insert(items, UI.vspace(18))
        table.insert(items, UI.text(S.msg, { size = 19, width = UI.INNER(), font = "bold" }))
    end
    table.insert(items, UI.vspace(18))
    table.insert(items, UI.text("Wifi gaat vanzelf aan als dat nodig is. Je voortgang blijft bewaard.", { size = 16, color = UI.INK2, width = UI.INNER() }))
    table.insert(items, UI.vspace(18))
    table.insert(items, UI.row("Back-ups op de Kobo", "Elke dag een kopie, 7 dagen bewaard", "›", function() app:go(require("ks_system").backupPage) end, nil, "history"))
    do
        local l = safe(require("ks_backup").last)
        table.insert(items, UI.row("Back-up in de cloud", l and ("Laatste: " .. os.date("%d-%m %H:%M", l.at)) or "Nog geen back-up", "›", function() app.bkMsg = nil; app:go(require("ks_backup").page) end, nil, "download"))
    end
    return UI.page(UI.vgroup(items))
end

function M.run(dir)
    -- Geen automatische flitsende verversing na een aantal schermen
    UIManager.FULL_REFRESH_COUNT = 0
    M.dir = dir
    pcall(Store.backup)
    local Sys = require("ks_system")
    Sys.applyFont()
    local app = App:new{}
    app.stack = { homePage }
    app[1] = homePage(app)
    UI.onRefresh = function() require("ks_system").quickSync(app) end
    -- fout in een knop: melden in de statusbalk en het scherm opnieuw tekenen in plaats van afsluiten
    UI.onError = function()
        local Sys = require("ks_system")
        Sys.note, Sys.noteUntil = "Dat ging mis. Je voortgang is veilig.", os.time() + 8
        app:render("ui")
    end
    UI.onHome = function() app:home() end
    UI.onLight = function() require("ks_light").showPanel(app) end
    UIManager:show(app, "full")
    M.app = app
    Sys.start(app)
    return app
end

M.App = App
return M
