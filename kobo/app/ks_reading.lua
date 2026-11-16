-- Te lezen: achtergrondstukken (van Claude, met literatuurlijst) en Wikipedia-artikelen als boek.
-- Alles staat als bestand in de map "Te lezen" en opent in de lezer van KOReader,
-- met gewone bladzijden, woordenboek en lettergrootte.

local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local Store = require("ks_store")
local UI = require("ks_ui")

local R = {}

R.BASE = os.getenv("KEES_STUDY_READING_URL") or "https://keesvschriek.github.io/trainingsapp/kobo/reading/"

function R.dir()
    local d = os.getenv("KEES_STUDY_READING_DIR")
    if not d then
        local home = G_reader_settings and G_reader_settings:readSetting("home_dir")
        if not home then local ok, dev = pcall(require, "device"); home = ok and dev.home_dir or nil end
        d = (home or "/mnt/onboard") .. "/Te lezen"
    end
    if lfs.attributes(d, "mode") ~= "directory" then lfs.mkdir(d) end
    return d
end

local function meta() return Store.get("read.meta", {}) end
local function setMeta(name, m) local all = meta(); all[name] = m; Store.set("read.meta", all) end

local function safeName(s) return (s:gsub("[/\\:%*%?\"<>|]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end

--- Nieuwe stukken ophalen uit de lijst op GitHub Pages.
function R.fetchNow()
    local Net = require("ks_net")
    local ok, body = Net.get(R.BASE .. "index.json?t=" .. os.time())
    if not ok then return false, body end
    local good, idx = pcall(require("json").decode, body)
    if not good or type(idx) ~= "table" or type(idx.items) ~= "table" then return false, "Onverwachte lijst." end
    local dir, got = R.dir(), 0
    for _, it in ipairs(idx.items) do
        if type(it.file) == "string" and it.file:match("^[%w%-_]+%.html$") then
            local path = dir .. "/" .. it.file
            local m = meta()[it.file]
            local removed = Store.get("read.removed", {})[it.file]
            if not removed and (lfs.attributes(path, "mode") ~= "file" or not m or m.v ~= it.v) then
                local ok2, html = Net.get(R.BASE .. it.file .. "?v=" .. tostring(it.v or 1))
                if ok2 and html:find("<html") then
                    local f = io.open(path, "wb")
                    if f then
                        f:write(html); f:close()
                        setMeta(it.file, { title = it.title, sub = it.sub, date = it.date, v = it.v, src = "claude", words = it.words, new = true })
                        got = got + 1
                    end
                end
            end
        end
    end
    Store.set("read.at", os.time())
    return true, got
end

function R.due() local at = Store.get("read.at"); return not at or os.time() - at > 6 * 3600 end

function R.refresh(done)
    require("ks_net").online(function() done(R.fetchNow()) end, { onFail = function(m) done(false, m) end })
end

--- Alles in de map, nieuwste eerst.
function R.list()
    local dir, out = R.dir(), {}
    local all = meta()
    for name in lfs.dir(dir) do
        if name:match("%.html$") or name:match("%.epub$") then
            local path = dir .. "/" .. name
            local m = all[name] or {}
            local title = m.title or name:gsub("%.%u%u%.epub$", ""):gsub("%.epub$", ""):gsub("%.html$", "")
            table.insert(out, { name = name, path = path, title = title, sub = m.sub or (name:match("%.epub$") and "Wikipedia" or ""),
                date = m.date, words = m.words, new = m.new, done = m.done, mtime = lfs.attributes(path, "modification") or 0 })
        end
    end
    table.sort(out, function(a, b) return a.mtime > b.mtime end)
    return out
end

function R.newCount() local n = 0; for _, it in ipairs(R.list()) do if it.new then n = n + 1 end end; return n end

function R.summary()
    local l = R.list()
    if #l == 0 then return "Nog niets" end
    local n = R.newCount()
    return n > 0 and (n .. " nieuw · " .. l[1].title) or (#l .. " stukken")
end

-- De lezer van KOReader stuurt je bij "naar de bibliotheek" (het huisje of mapje bovenin, of
-- aan het eind van het boek) naar zijn eigen bestandsbeheer. Zolang de app draait, sluiten we
-- dan alleen het boek, zodat je terug bent in de app.
local function keepInApp()
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI._ksPatched then return end
    ReaderUI._ksPatched = true
    local orig = ReaderUI.showFileManager
    ReaderUI.showFileManager = function(self, ...)
        if require("ks_system").app then
            -- onHome heeft het boek al gesloten; als dat nog niet zo is, nu sluiten
            if ReaderUI.instance == self and self.dialog then pcall(function() self:onClose() end) end
            return
        end
        return orig(self, ...)
    end
end

--- Openen in de lezer. Na het sluiten kom je terug in de app.
function R.open(app, it)
    keepInApp()
    local m = meta()[it.name] or { title = it.title, sub = it.sub }
    m.new = nil
    m.done = true
    setMeta(it.name, m)
    Store.flush()
    app.readMsg = nil
    -- het scherm eronder alvast bijwerken, dan klopt het als je de lezer sluit
    app:refresh()
    UIManager:nextTick(function()
        require("apps/reader/readerui"):showReader(it.path)
    end)
end

function R.remove(it)
    os.remove(it.path)
    local all = meta()
    if all[it.name] and all[it.name].src == "claude" then
        local rm = Store.get("read.removed", {})
        rm[it.name] = true
        Store.set("read.removed", rm)
    end
    all[it.name] = nil
    Store.set("read.meta", all)
    -- KOReader bewaart naast een boek een .sdr-map met je leesplek; die mag ook weg
    pcall(function() require("ffi/util").purgeDir(it.path:gsub("%.%w+$", "") .. ".sdr") end)
end

--- Wikipedia-artikel als boek bewaren (gebruikt de functie die KOReader zelf heeft).
function R.saveWikipedia(app, title, onDone)
    local name = safeName(title) .. ".NL.epub"
    local path = R.dir() .. "/" .. name
    require("ks_net").online(function()
        local Wikipedia = require("ui/wikipedia")
        Wikipedia:createEpubWithUI(path, title, "nl", function(ok)
            if ok then setMeta(name, { title = title, sub = "Wikipedia", new = true, date = os.date("%Y-%m-%d") }) end
            onDone(ok, ok and { name = name, path = path, title = title } or nil)
        end)
    end, { onFail = function(m) onDone(false, nil, m) end })
end

-- Scherm -------------------------------------------------------------------------------

function R.page(app)
    local W = UI.INNER()
    local items = { UI.header("Te lezen", function() app.readPg = nil; app.readMsg = nil; app.readEdit = nil; app:back() end,
        "Achtergrondstukken en Wikipedia-artikelen, in de lezer") }
    local list = R.list()
    local rows = {}
    for _, it in ipairs(list) do
        local meta2 = {}
        if it.new then table.insert(meta2, "nieuw") end
        if it.sub and it.sub ~= "" then table.insert(meta2, it.sub) end
        if it.words then table.insert(meta2, math.max(1, math.floor(it.words / 230 + 0.5)) .. " min") end
        if it.done and not it.new then table.insert(meta2, "gelezen") end
        local right = app.readEdit and "Wis" or "›"
        table.insert(rows, UI.row(it.title, table.concat(meta2, " · "), right, function()
            if app.readEdit then R.remove(it); app:refresh() else R.open(app, it) end
        end, W, it.name:match("%.epub$") and "book" or "news"))
    end
    if #rows == 0 then
        table.insert(items, UI.vspace(10))
        table.insert(items, UI.text("Nog niets te lezen. Tik op Ophalen, of bewaar een artikel vanuit Op deze dag.", { size = 19, color = UI.INK2, width = W }))
    end
    if app.readMsg then table.insert(items, UI.text(app.readMsg, { size = 17, font = "bold", width = W })) end
    local head = UI.vgroup(items)
    local per = 1
    if #rows > 0 then
        local avail = UI.H() - UI.px(UI.TOPPAD) - head:getSize().h - UI.px(60 + 50)
        per = math.max(1, math.floor(avail / rows[1]:getSize().h))
    end
    local np = math.max(1, math.ceil(#rows / per))
    local pg = math.max(1, math.min(app.readPg or 1, np))
    for i = (pg - 1) * per + 1, math.min(#rows, pg * per) do table.insert(items, rows[i]) end
    local footer = UI.buttonRow({
        { "Ophalen", function()
            app.readMsg = "Bezig met ophalen..."
            app:refresh()
            UIManager:scheduleIn(0.2, function()
                R.refresh(function(ok, n)
                    app.readMsg = ok and (n > 0 and (n .. " nieuw stuk" .. (n > 1 and "ken" or "")) or "Niets nieuws.") or ("Ophalen mislukt: " .. tostring(n))
                    app:refresh()
                end)
            end)
        end, small = true },
        { app.readEdit and "Klaar" or "Opruimen", function() app.readEdit = not app.readEdit; app:refresh() end, small = true, disabled = #rows == 0 },
        { np > 1 and ("Verder " .. pg .. "/" .. np) or "Verder", function() app.readPg = pg % np + 1; app:refresh() end, small = true, disabled = np <= 1 },
    })
    return UI.page(UI.vgroup(items), footer)
end

return R
