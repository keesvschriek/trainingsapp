-- Kees Study voor de Kobo: beginscherm en navigatie.
-- Wordt gestart door de user patch 2-kees-study.lua als KEES_STUDY=1.

local Device = require("device")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local UI = require("ks_ui")
local Store = require("ks_store")

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
    if mode == "page" then
        self.navs = self.navs + 1
        -- Om de zoveel schermen helemaal verversen tegen inbranden (ghosting)
        UIManager:setDirty(self, self.navs % 6 == 0 and "full" or "partial")
    else
        UIManager:setDirty(self, "ui")
    end
end

function App:refresh() self:render("ui") end

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
    })
    local footer = UI.vgroup({
        UI.text("Afsluiten brengt je terug naar je Kobo-bibliotheek.", { size = 15, color = UI.INK2, width = UI.INNER() }),
        UI.vspace(10),
        UI.button("Afsluiten", function() app:quit() end, { width = UI.INNER() }),
    })
    return UI.page(body, footer)
end

local M = {}

function M.run(dir)
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
