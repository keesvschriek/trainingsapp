-- Te lezen: achtergrondstukken (van Claude, met literatuurlijst) en Wikipedia-artikelen.
-- Alles opent in het leesscherm van de app zelf (ks_reader), niet in KOReader.

local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local Store = require("ks_store")
local UI = require("ks_ui")

local R = {}

R.BASE = os.getenv("KEES_STUDY_READING_URL") or "https://keesvschriek.github.io/trainingsapp/kobo/reading/"

-- Stukken staan als kleine JSON-bestanden in de instellingenmap van de app (niet in je bibliotheek).
-- Oude map "Te lezen" in de bibliotheek (van de vorige versie) eenmalig opruimen.
local function cleanOld()
    if Store.get("read.oldclean") then return end
    Store.set("read.oldclean", true)
    pcall(function()
        local home = G_reader_settings and G_reader_settings:readSetting("home_dir") or "/mnt/onboard"
        local old = home .. "/Te lezen"
        if lfs.attributes(old, "mode") ~= "directory" then return end
        for name in lfs.dir(old) do
            if name:match("%.html$") or name:match("%.epub$") then os.remove(old .. "/" .. name) end
            if name:match("%.sdr$") then pcall(function() require("ffi/util").purgeDir(old .. "/" .. name) end) end
        end
        lfs.rmdir(old)
    end)
end

function R.dir()
    if not os.getenv("KEES_STUDY_READING_DIR") then cleanOld() end
    local d = os.getenv("KEES_STUDY_READING_DIR") or (require("datastorage"):getSettingsDir() .. "/keesstudy-lezen")
    if lfs.attributes(d, "mode") ~= "directory" then lfs.mkdir(d) end
    return d
end

local function meta() return Store.get("read.meta", {}) end
local function setMeta(name, m) local all = meta(); all[name] = m; Store.set("read.meta", all) end

local function safeName(s) return (s:gsub("[^%w%-_ ]", ""):gsub("%s+", "-"):sub(1, 60)) end

local ENT = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ", ["#39"] = "'" }
local function text(s)
    s = s:gsub("<br%s*/?>", " "):gsub("<[^>]+>", "")
    s = s:gsub("&(#?%w+);", function(e)
        if ENT[e] then return ENT[e] end
        local n = e:match("^#(%d+)$")
        if n then n = tonumber(n); if n < 128 then return string.char(n) end end
        return "&" .. e .. ";"
    end)
    return (s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

--- Ons eigen eenvoudige HTML omzetten naar blokken (kopjes, alinea's, opsommingen).
function R.fromHTML(html)
    local title = text(html:match("<h1[^>]*>(.-)</h1>") or html:match("<title>(.-)</title>") or "Zonder titel")
    local blocks = {}
    local body = html:match("<body[^>]*>(.*)</body>") or html
    for tag, attrs, inner in body:gmatch("<(%w+)([^>]*)>(.-)</%1>") do
        local t = text(inner)
        if t ~= "" then
            if tag == "h2" then table.insert(blocks, { k = "h2", t = t })
            elseif tag == "h3" then table.insert(blocks, { k = "h3", t = t })
            elseif tag == "p" and attrs:find("sub") then table.insert(blocks, { k = "sub", t = t })
            elseif tag == "p" and inner:find("<small>") then table.insert(blocks, { k = "small", t = t })
            elseif tag == "p" then table.insert(blocks, { k = "p", t = t })
            elseif tag == "ul" or tag == "ol" then
                for li in inner:gmatch("<li[^>]*>(.-)</li>") do table.insert(blocks, { k = "li", t = text(li) }) end
            end
        end
    end
    return title, blocks
end

--- Platte tekst van Wikipedia ("== Kop ==" en alinea's) omzetten naar blokken.
local STOP = { ["zie ook"] = true, ["externe links"] = true, ["externe link"] = true, ["bronnen"] = true, ["bron"] = true,
    ["referenties"] = true, ["noten"] = true, ["voetnoten"] = true, ["bronnen, noten en/of referenties"] = true }
function R.fromWikiText(t)
    local blocks = {}
    for line in (t .. "\n"):gmatch("([^\n]*)\n") do
        local lvl, head = line:match("^(==+)%s*(.-)%s*==+%s*$")
        if head then
            if STOP[head:lower()] then break end
            table.insert(blocks, { k = #lvl <= 2 and "h2" or "h3", t = head })
        elseif line:match("%S") then
            table.insert(blocks, { k = "p", t = (line:gsub("%s+", " ")) })
        end
    end
    -- kopjes zonder tekst eronder weg
    local out = {}
    for i, b in ipairs(blocks) do
        local nxt = blocks[i + 1]
        if not ((b.k == "h2" or b.k == "h3") and (not nxt or nxt.k == "h2" or (b.k == "h3" and nxt.k == "h3"))) then table.insert(out, b) end
    end
    return out
end

local function saveDoc(name, doc)
    local f = io.open(R.dir() .. "/" .. name .. ".tmp", "wb")
    if not f then return false end
    f:write(require("json").encode(doc))
    f:close()
    os.rename(R.dir() .. "/" .. name .. ".tmp", R.dir() .. "/" .. name)
    return true
end
function R.load(name)
    local f = io.open(R.dir() .. "/" .. name, "rb")
    if not f then return nil end
    local ok, d = pcall(require("json").decode, f:read("*a"))
    f:close()
    return ok and type(d) == "table" and d or nil
end

--- Nieuwe stukken ophalen uit de lijst op GitHub Pages.
function R.fetchNow()
    local Net = require("ks_net")
    local ok, body = Net.get(R.BASE .. "index.json?t=" .. os.time())
    if not ok then return false, body end
    local good, idx = pcall(require("json").decode, body)
    if not good or type(idx) ~= "table" or type(idx.items) ~= "table" then return false, "Onverwachte lijst." end
    local got = 0
    for _, it in ipairs(idx.items) do
        if type(it.file) == "string" and it.file:match("^[%w%-_]+%.html$") then
            local name = it.file:gsub("%.html$", ".json")
            local m = meta()[name]
            local removed = Store.get("read.removed", {})[name]
            if not removed and (lfs.attributes(R.dir() .. "/" .. name, "mode") ~= "file" or not m or m.v ~= it.v) then
                local ok2, html = Net.get(R.BASE .. it.file .. "?v=" .. tostring(it.v or 1))
                if ok2 and html:find("<html") then
                    local title, blocks = R.fromHTML(html)
                    if #blocks > 0 and saveDoc(name, { id = name, title = it.title or title, sub = it.sub, kind = "Te lezen", blocks = blocks }) then
                        setMeta(name, { title = it.title or title, sub = it.sub, date = it.date, v = it.v, src = "claude", words = it.words, new = true })
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

--- Alles wat er te lezen is, nieuwste eerst.
function R.list()
    local dir, out = R.dir(), {}
    local all = meta()
    for name in lfs.dir(dir) do
        if name:match("%.json$") then
            local m = all[name] or {}
            table.insert(out, { name = name, title = m.title or name, sub = m.sub or "", date = m.date, words = m.words,
                new = m.new, done = m.done, wiki = m.src == "wiki", mtime = lfs.attributes(dir .. "/" .. name, "modification") or 0 })
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

--- Openen in het leesscherm van de app.
function R.open(app, it)
    local doc = R.load(it.name)
    if not doc then app.readMsg = "Dit stuk kon niet worden geopend."; app:refresh(); return end
    local m = meta()[it.name] or { title = it.title, sub = it.sub }
    m.new = nil
    m.done = true
    setMeta(it.name, m)
    app.readMsg = nil
    pcall(function() require("ks_avond").setLastRead({ kind = "doc", name = it.name, title = m.title or it.title }) end)
    app.rdDoc = doc
    app.rdPages = nil
    app:go(require("ks_reader").page)
end

function R.remove(it)
    os.remove(R.dir() .. "/" .. it.name)
    local all = meta()
    if all[it.name] and all[it.name].src == "claude" then
        local rm = Store.get("read.removed", {})
        rm[it.name] = true
        Store.set("read.removed", rm)
    end
    all[it.name] = nil
    Store.set("read.meta", all)
end

R.WIKI = os.getenv("KEES_STUDY_WIKIAPI_URL") or "https://nl.wikipedia.org/w/api.php"

local function urlenc(s) return (s:gsub("[^%w%-_%.~]", function(c) return ("%%%02X"):format(c:byte()) end)) end

--- Wikipedia-artikel ophalen en bewaren als stuk om te lezen. onDone(ok, item, err)
function R.saveWikipedia(app, title, onDone)
    require("ks_net").online(function()
        local url = R.WIKI .. "?action=query&format=json&formatversion=2&prop=extracts&explaintext=1&exsectionformat=wiki&redirects=1&titles=" .. urlenc(title)
        local ok, body = require("ks_net").get(url, { ["User-Agent"] = "KeesStudy/1.0 (Kobo e-reader, persoonlijk gebruik)" })
        if not ok then return onDone(false, nil, body) end
        local good, j = pcall(require("json").decode, body)
        local page = good and type(j) == "table" and type(j.query) == "table" and type(j.query.pages) == "table" and j.query.pages[1]
        local extract = page and type(page.extract) == "string" and page.extract or nil
        if not extract or extract == "" then return onDone(false, nil, "Artikel niet gevonden.") end
        local realTitle = type(page.title) == "string" and page.title or title
        local name = "wiki-" .. safeName(realTitle) .. ".json"
        local intro, rest = extract:match("^(.-)\n(==.*)$")
        local blocks = R.fromWikiText(extract)
        if not saveDoc(name, { id = name, title = realTitle, sub = "Wikipedia", kind = "Wikipedia", blocks = blocks }) then
            return onDone(false, nil, "Kon niet opslaan.")
        end
        setMeta(name, { title = realTitle, sub = "Wikipedia", src = "wiki", new = true, date = os.date("%Y-%m-%d"),
            words = select(2, extract:gsub("%S+", "")) })
        onDone(true, { name = name, title = realTitle })
    end, { onFail = function(m) onDone(false, nil, m) end })
end

-- Scherm -------------------------------------------------------------------------------

function R.page(app)
    local W = UI.INNER()
    local items = { UI.header("Te lezen", function() app.readPg = nil; app.readMsg = nil; app.readEdit = nil; app:back() end,
        "Achtergrondstukken en Wikipedia-artikelen") }
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
        end, W, it.wiki and "book" or "news"))
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
