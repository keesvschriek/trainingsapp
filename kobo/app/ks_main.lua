-- Kees Study voor de Kobo: beginscherm en navigatie.
-- Wordt gestart door de user patch 2-kees-study.lua als KEES_STUDY=1.

local Device = require("device")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local UI = require("ks_ui")
local Store = require("ks_store")

local M = {}

local App = InputContainer:extend{ name = "keesstudy", covers_fullscreen = true, is_always_active = true }

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
    UI.painted = {}
    local ok, w = pcall(builder, self)
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
    Store.flush()
    UIManager:quit(85)
end

function App:quit()
    Store.flush()
    UIManager:close(self, "full")
end

-- Beginscherm ------------------------------------------------------------------

local MONTHS = { "januari", "februari", "maart", "april", "mei", "juni", "juli", "augustus", "september", "oktober", "november", "december" }
local DAYS = { "zondag", "maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag" }

local function homePage(app)
    local ChessUI = require("ks_chessui")
    local QuizUI = require("ks_quizui")
    local t = os.date("*t")
    local body = UI.vgroup({
        UI.text("Kees Study", { font = "serif", size = 44 }),
        UI.vspace(4),
        UI.text(DAYS[t.wday] .. " " .. t.day .. " " .. MONTHS[t.month], { size = 18, color = UI.INK2 }),
        UI.vspace(22),
        UI.line(UI.INNER(), UI.BLACK, UI.px(2)),
        UI.row("Schaken leren", ChessUI.summary(), "›", function() app:go(ChessUI.lessonList) end),
        UI.row("Tegen de computer", require("ks_play").summary(), "›", function()
            local g = require("ks_store").get("play.game")
            app:go((g and not g.over) and require("ks_play").game or require("ks_play").menu)
        end),
        UI.row("Quiz", QuizUI.summary(), "›", function() app:go(QuizUI.home) end),
        UI.row("Topografie op de kaart", "Landen aanwijzen en herkennen, per werelddeel", "›", function() app:go(require("ks_mapui").menu) end),
        UI.row("Bijwerken via wifi", "App en vragen bijwerken · versie " .. require("ks_update").localVersion(), "›", function() app:go(M.updatePage) end),
    })
    local footer = UI.vgroup({
        UI.text("Afsluiten brengt je terug naar je Kobo-bibliotheek. Scherm verversen haalt vage restjes weg (met één flits).", { size = 15, color = UI.INK2, width = UI.INNER() }),
        UI.vspace(10),
        UI.buttonRow({
            { "Scherm verversen", function() app:cleanScreen() end, small = true },
            { "Afsluiten", function() app:quit() end },
        }),
    })
    return UI.page(body, footer)
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
        table.insert(items, UI.vspace(10))
        table.insert(items, UI.button("Nu bijwerken", function()
            say("Bezig met downloaden...")
            later(function()
                U.apply(S.info, function(ok, res)
                    if ok then S.done = true; say("Klaar. Herstart de app om de nieuwe versie te gebruiken.")
                    else say("Bijwerken mislukt: " .. res) end
                end)
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
    local app = App:new{}
    app.stack = { homePage }
    app[1] = homePage(app)
    UIManager:show(app, "full")
    M.app = app
    return app
end

M.App = App
return M
