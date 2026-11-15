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

function App:onSuspend() pcall(function() require("ks_system").onSuspend() end) end
function App:onResume() pcall(function() require("ks_system").onResume() end) end

function App:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = UI.W(), h = UI.H() }
    self.stack = {}
    self.navs = 0
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

--- Teken het huidige scherm opnieuw (na een tik). mode "page" = nieuw scherm.
function App:render(mode)
    local builder = self.stack[#self.stack]
    if not builder then return end
    -- Bouwen; past het scherm niet met de gekozen lettergrootte, dan stapje kleiner (alleen voor dit scherm)
    local base = UI.scale
    local ok, w
    -- eerst lijstregels compacter, daarna pas kleinere letters
    for attempt = 1, 7 do
        UI.painted = {}
        UI.overflow = false
        ok, w = pcall(builder, self)
        if not ok or not UI.overflow or UI.scale < 0.75 then break end
        if attempt == 1 then UI.compact = true else UI.scale = UI.scale * 0.94 end
    end
    UI.scale = base
    UI.compact = false
    if not ok then
        w = UI.page(UI.vgroup({ UI.header("Er ging iets mis", function() self:home() end), UI.text(tostring(w), { width = UI.INNER(), size = 16 }) }))
    end
    self[1] = w
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

-- Beginscherm ------------------------------------------------------------------

local MONTHS = { "januari", "februari", "maart", "april", "mei", "juni", "juli", "augustus", "september", "oktober", "november", "december" }
local DAYS = { "zondag", "maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag" }

function M.dateText()
    local t = os.date("*t")
    return DAYS[t.wday] .. " " .. t.day .. " " .. MONTHS[t.month]
end

--- Een module veilig laden: als er iets mis is met één onderdeel, blijft de rest werken.
local function safe(fn, fallback)
    local ok, a, b = pcall(fn)
    if ok then return a, b end
    require("logger").warn("Kees Personal:", a)
    return fallback, nil
end

local function remember(name) Store.set("last.module", name) end

--- Map "Kees Study": de leeronderdelen die er al waren.
function M.studyFolder(app)
    local ChessUI = require("ks_chessui")
    local QuizUI = require("ks_quizui")
    local items = {
        UI.header("Kees Study", function() app:back() end, "Schaken, quiz en topografie"),
        UI.row("Schaken leren", safe(ChessUI.summary, ""), "›", function() remember("Schaken leren"); app:go(ChessUI.lessonList) end),
        UI.row("Tegen de computer", safe(require("ks_play").summary, ""), "›", function()
            remember("Tegen de computer")
            local g = Store.get("play.game")
            app:go((g and not g.over) and require("ks_play").game or require("ks_play").menu)
        end),
        UI.row("Quiz", safe(QuizUI.summary, ""), "›", function() remember("Quiz"); app:go(QuizUI.home) end),
        UI.row("Topografie op de kaart", "Landen aanwijzen en herkennen, per werelddeel", "›", function() remember("Topografie"); app:go(require("ks_mapui").menu) end),
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
        UI.row("Dagtekst", "Vandaag: " .. tostring(who), "›", function() remember("Dagtekst"); app:go(D.page) end),
        UI.row("Gewoontes", ("%d van %d gedaan vandaag"):format(done or 0, total or 0), "›", function() remember("Gewoontes"); app:go(H.page) end),
    }
    return UI.page(UI.vgroup(items))
end

local function homePage(app)
    local D = require("ks_dagtekst")
    local H = require("ks_habits")
    local Sys = require("ks_system")
    local W = UI.INNER()
    local gap = UI.px(16)
    local tw = math.floor((W - gap) / 2)
    local space = UI.H() - UI.px(UI.TOPPAD) - UI.MARGIN()

    -- level 0: alles; 1: zonder "Verder met"; 2: ook de dagtekst ingekort
    local function build(level)
        local items = {
            UI.text("Kees Personal", { font = "serif", size = 40 }),
            UI.vspace(2),
            UI.text(M.dateText(), { size = 18, color = UI.INK2 }),
            UI.vspace(20),
            UI.line(W, UI.BLACK, UI.px(2)),
        }
        -- Dagtekst: kort stukje, tik voor de hele tekst
        local who, first = safe(D.summary, "Dagtekst")
        first = first or ""
        if level >= 2 and #first > 90 then first = first:sub(1, 87):gsub("%s+%S*$", "") .. "..." end
        local label = D.isEvening() and "Dagtekst · terugblik" or "Dagtekst"
        table.insert(items, UI.Tap:new{ label = "Dagtekst", callback = function() remember("Dagtekst"); app:go(D.page) end, UI.vgroup({
            UI.vspace(16),
            UI.text(label .. " · " .. tostring(who), { size = 16, color = UI.INK2, width = W }),
            UI.vspace(6),
            UI.text(first, { font = "serif", size = 21, width = W, line_height = 0.35 }),
            UI.vspace(16),
            UI.line(W),
        }) })
        -- Kleine regels: gewoontes, laatst geopend
        local done, total = safe(H.summary, 0)
        UI.rowPad = 26
        table.insert(items, UI.row("Gewoontes vandaag", nil, ("%d van %d"):format(done or 0, total or 0), function() remember("Gewoontes"); app:go(H.page) end))
        local last = Store.get("last.module")
        if last and level < 1 then
            local open = {
                ["Schaken leren"] = function() app:go(require("ks_chessui").lessonList) end,
                ["Tegen de computer"] = function()
                    local g = Store.get("play.game")
                    app:go((g and not g.over) and require("ks_play").game or require("ks_play").menu)
                end,
                ["Quiz"] = function() app:go(require("ks_quizui").home) end,
                ["Topografie"] = function() app:go(require("ks_mapui").menu) end,
                ["Dagtekst"] = function() app:go(D.page) end,
                ["Gewoontes"] = function() app:go(H.page) end,
            }
            if open[last] then table.insert(items, UI.row("Verder met " .. last, nil, "›", open[last])) end
        end
        UI.rowPad = nil
        table.insert(items, UI.vspace(24))
        local top = UI.vgroup(items)
        local topH = top:getSize().h

        -- Mappen als tegels, twee per rij; hoogte past zich aan de ruimte aan
        local th = math.min(UI.px(170), math.floor((space - topH - 2 * gap) / 2))
        local tiles = {
            { "Kees Study", "Schaken, quiz en topografie", function() app:go(M.studyFolder) end },
            { "Ontwikkeling", "Dagtekst en gewoontes", function() app:go(M.growFolder) end },
            { "Lezen", "Terug naar je boeken", function() app:quit() end },
            { "Instellingen", "Letters, schermtijd, bijwerken", function() app:go(Sys.settingsPage) end },
        }
        local HSpan = require("ui/widget/horizontalspan")
        local VSpan = require("ui/widget/verticalspan")
        local grid = {}
        for r = 0, 1 do
            table.insert(grid, UI.hgroup({
                UI.tile(tiles[r * 2 + 1][1], tiles[r * 2 + 1][2], tw, th, tiles[r * 2 + 1][3]),
                HSpan:new{ width = gap },
                UI.tile(tiles[r * 2 + 2][1], tiles[r * 2 + 2][2], tw, th, tiles[r * 2 + 2][3]),
            }, "top"))
            table.insert(grid, VSpan:new{ width = gap })
        end
        local g = UI.vgroup(grid)
        return UI.vgroup({ top, g }), topH + g:getSize().h
    end

    local body
    for level = 0, 2 do
        local h
        body, h = build(level)
        if h <= space then break end
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
    UIManager:show(app, "full")
    M.app = app
    Sys.start(app)
    return app
end

M.App = App
return M
