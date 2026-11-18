-- Wikirace: elke dag een nieuwe opdracht. Kom van het ene Wikipedia-artikel bij het andere,
-- alleen via links in de artikelen. Hoe minder stappen, hoe beter.

local UI = require("ks_ui")
local Store = require("ks_store")

local WR = {}

WR.API = os.getenv("KEES_STUDY_WIKIAPI_URL") or "https://nl.wikipedia.org/w/api.php"

-- Bekende artikelen als begin en doel (geschiedenis, politiek, sport, natuur, techniek, plaatsen).
WR.TITLES = {
    "Johan Rudolph Thorbecke", "Napoleon Bonaparte", "Willem van Oranje", "Tweede Wereldoorlog", "Slag om Arnhem", "Romeinse Rijk",
    "Verenigde Oost-Indische Compagnie", "Karel de Grote", "Julius Caesar", "Rembrandt van Rijn", "Vincent van Gogh", "Afsluitdijk",
    "Deltawerken", "Watersnood van 1953", "Tour de France", "Johan Cruijff", "Olympische Spelen", "Elfstedentocht", "NAVO",
    "Europese Unie", "Verenigde Naties", "Koude Oorlog", "Berlijnse Muur", "Apollo 11", "Albert Einstein", "Isaac Newton",
    "Charles Darwin", "Penicilline", "Stoommachine", "Industriële revolutie", "Franse Revolutie", "Tachtigjarige Oorlog",
    "Amsterdam", "Nijmegen", "Rijn", "Mount Everest", "Sahara", "Chocolade", "Koffie", "Tulpenmanie", "Fiets", "Eiffeltoren",
    "Piramides van Gizeh", "Chinese Muur", "Titanic (schip, 1912)", "Anne Frank", "Desiderius Erasmus", "Baruch Spinoza",
    "Michiel de Ruyter", "Abel Tasman", "Christoffel Columbus", "Atoombom", "Internet", "Alan Turing", "Schaken", "Zwarte Dood",
    "Pompeii", "Vesuvius", "Grondwet (Nederland)", "Tweede Kamer der Staten-Generaal", "Koninklijke Landmacht", "Eerste Wereldoorlog",
    "Maan", "Zon", "Melkweg", "Dinosauriërs", "Wolf (dier)", "Olifanten", "Ijstijd", "Vikingen", "Middeleeuwen", "Oude Egypte",
    "Atheense democratie", "Marathon (atletiek)", "Voetbal", "Wielrennen", "Schaatsen", "Rusland", "Verenigde Staten", "China",
    "Japan", "Brazilië", "Australië", "Antarctica", "Kernenergie", "Windmolen", "Kaas", "Bier", "Muziek", "Mozart", "Beatles",
}

local function today() return os.date("%Y-%m-%d") end
local function enc(s) return (s:gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end)) end

local function api(params)
    local ok, body = require("ks_net").get(WR.API .. "?format=json&formatversion=2&redirects=1&" .. params,
        { ["User-Agent"] = "KeesStudy/1.0 (Kobo e-reader, persoonlijk gebruik)" })
    if not ok then return nil, body end
    local good, j = pcall(require("json").decode, body)
    if not good or type(j) ~= "table" then return nil, "Onverwacht antwoord van Wikipedia." end
    return j
end

--- Korte uitleg en echte titel (na doorverwijzing). Geeft {title, intro} of nil.
function WR.info(title)
    local j, err = api("action=query&prop=extracts&exintro=1&explaintext=1&exsentences=2&titles=" .. enc(title))
    local p = j and type(j.query) == "table" and type(j.query.pages) == "table" and j.query.pages[1]
    if not p or p.missing then return nil, err or "Artikel niet gevonden." end
    return { title = p.title, intro = type(p.extract) == "string" and p.extract or "" }
end

--- Alle links naar andere artikelen. Geeft gesorteerde lijst titels.
function WR.links(title)
    local out, cont = {}, nil
    for _ = 1, 5 do
        local j = api("action=query&prop=links&plnamespace=0&pllimit=max&titles=" .. enc(title) .. (cont and ("&plcontinue=" .. enc(cont)) or ""))
        if not j then break end
        local p = type(j.query) == "table" and type(j.query.pages) == "table" and j.query.pages[1]
        for _, l in ipairs(p and type(p.links) == "table" and p.links or {}) do
            if type(l.title) == "string" then out[#out + 1] = l.title end
        end
        cont = type(j.continue) == "table" and j.continue.plcontinue or nil
        if not cont then break end
    end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

--- Opdracht van vandaag (vast per datum).
function WR.pair(shift)
    local n = #WR.TITLES
    local t = os.date("*t")
    local day = math.floor(os.time{ year = t.year, month = t.month, day = t.day, hour = 12 } / 86400) + (shift or 0)
    local a = (day * 7) % n + 1
    local b = (day * 13 + 5) % n + 1
    if b == a then b = b % n + 1 end
    return WR.TITLES[a], WR.TITLES[b]
end

function WR.state() return Store.get("wr.day") end

--- Opdracht van vandaag klaarzetten (met wifi). Slaat artikelen over die niet bestaan.
function WR.prepare()
    local s = WR.state()
    if s and s.date == today() and s.start then return true end
    for shift = 0, 6 do
        local a, b = WR.pair(shift * 101)
        local ia = WR.info(a)
        local ib = ia and WR.info(b)
        if ia and ib then
            Store.set("wr.day", { date = today(), start = ia.title, startIntro = ia.intro, target = ib.title, targetIntro = ib.intro, path = { ia.title }, done = false })
            return true
        end
    end
    return false, "Wikipedia is nu niet bereikbaar."
end

function WR.summary()
    local s = WR.state()
    if s and s.date == today() and s.start then
        if s.done then return "Vandaag gehaald in " .. (#s.path - 1) .. " stappen" end
        return "Van " .. s.start .. " naar " .. s.target
    end
    return "Elke dag een nieuwe opdracht"
end

-- Schermen -------------------------------------------------------------------------------------------

function WR.start(app)
    app.wrLetter, app.wrPg = nil, 1
    app:go(WR.page)
end

local LETTERS = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "#" }
local function letterOf(t)
    local c = t:sub(1, 1):upper()
    local b = t:byte(1)
    if b and b >= 0xC3 then c = ({ ["Á"] = "A", ["É"] = "E", ["Ö"] = "O", ["Ü"] = "U" })[t:sub(1, 2)] or "#" end
    if not c:match("%a") then return "#" end
    return c
end

function WR.page(app)
    local W = UI.INNER()
    local s = WR.state()
    if not s or s.date ~= today() or not s.start then
        local items = { UI.header("Wikirace", function() app:back() end, "Elke dag een nieuwe opdracht") }
        table.insert(items, UI.text(app.wrMsg or "De opdracht van vandaag wordt opgehaald zodra er wifi is.", { size = 19, width = W }))
        return UI.page(UI.vgroup(items), UI.button("Opdracht ophalen", function()
            require("ks_net").online(function()
                local ok, err = WR.prepare()
                app.wrMsg = ok and nil or err
                app:refresh()
            end)
        end, { width = W, primary = true }))
    end

    local cur = s.path[#s.path]
    local steps = #s.path - 1
    local items = { UI.header("Wikirace", function() app:back() end, "Van " .. s.start .. " naar " .. s.target) }

    if s.done then
        table.insert(items, UI.text("Gehaald in " .. steps .. (steps == 1 and " stap." or " stappen."), { font = "medium", size = 24 }))
        table.insert(items, UI.vspace(10))
        table.insert(items, UI.text(table.concat(s.path, "  ›  "), { size = 17, width = W }))
        local st = Store.get("wr.stats", {})
        table.insert(items, UI.vspace(14))
        table.insert(items, UI.text(("Gespeeld: %d · gehaald: %d · beste: %s stappen"):format(st.played or 0, st.won or 0, st.best and tostring(st.best) or "-"), { size = 16, color = UI.INK2, width = W }))
        table.insert(items, UI.vspace(10))
        table.insert(items, UI.text("Morgen staat er een nieuwe opdracht klaar.", { size = 16, color = UI.INK2 }))
        return UI.page(UI.vgroup(items))
    end

    -- waar je nu bent
    table.insert(items, UI.card(UI.vgroup({
        UI.text("Stap " .. steps .. " · je bent bij", { size = 14, color = UI.INK2 }),
        UI.text(cur, { font = "medium", size = 22, width = W - UI.px(40) }),
        UI.vspace(6),
        UI.text("Doel: " .. s.target .. (s.targetIntro ~= "" and (". " .. s.targetIntro:sub(1, 160):gsub("%s%S*$", "") .. " ...") or ""), { size = 15, color = UI.INK2, width = W - UI.px(40) }),
    }), { pad = UI.px(16) }))
    table.insert(items, UI.vspace(10))

    -- links van dit artikel (één keer ophalen per artikel)
    if not app.wrLinks or app.wrLinks.title ~= cur then
        app.wrLinks = { title = cur, list = nil }
    end
    local L = app.wrLinks.list
    if not L then
        table.insert(items, UI.text(app.wrMsg or "Links ophalen...", { size = 18, color = UI.INK2 }))
        require("ui/uimanager"):nextTick(function()
            require("ks_net").online(function()
                local list = WR.links(cur)
                app.wrLinks.list = list
                app.wrMsg = #list == 0 and "Geen links gevonden. Ga een stap terug." or nil
                app:refresh()
            end)
        end)
        return UI.page(UI.vgroup(items))
    end

    -- doel staat erbij? dan zie je dat meteen
    local hasTarget = false
    for _, t in ipairs(L) do if t == s.target then hasTarget = true break end end

    if not app.wrLetter then
        local counts = {}
        for _, t in ipairs(L) do local c = letterOf(t); counts[c] = (counts[c] or 0) + 1 end
        table.insert(items, UI.text(#L .. " links. Kies een beginletter" .. (hasTarget and ". Het doel staat ertussen!" or "."), { size = 17, width = W, font = hasTarget and "medium" or nil }))
        table.insert(items, UI.vspace(10))
        local per, bw = 7, math.floor((W - UI.px(6 * 8)) / 7)
        local row = {}
        for _, c in ipairs(LETTERS) do
            local n = counts[c] or 0
            table.insert(row, UI.button(c, function() if n > 0 then app.wrLetter = c; app.wrPg = 1; app:refresh() end end, { width = bw, small = true, disabled = n == 0 }))
            table.insert(row, UI.hspace(8))
            if #row >= per * 2 then
                table.insert(items, UI.hgroup(row)); table.insert(items, UI.vspace(8)); row = {}
            end
        end
        if #row > 0 then table.insert(items, UI.hgroup(row)) end
    else
        local list = {}
        for _, t in ipairs(L) do if letterOf(t) == app.wrLetter then list[#list + 1] = t end end
        local per = 9
        local np = math.max(1, math.ceil(#list / per))
        local pg = math.min(app.wrPg or 1, np)
        table.insert(items, UI.text("Letter " .. app.wrLetter .. " · " .. #list .. (#list == 1 and " link" or " links") .. (np > 1 and (" · " .. pg .. "/" .. np) or ""), { size = 15, color = UI.INK2 }))
        for i = (pg - 1) * per + 1, math.min(#list, pg * per) do
            local t = list[i]
            table.insert(items, UI.Tap:new{ label = t, callback = function()
                table.insert(s.path, t)
                app.wrLetter, app.wrPg, app.wrMsg = nil, 1, nil
                if t == s.target then
                    s.done = true
                    local st = Store.get("wr.stats", {})
                    st.played, st.won = (st.played or 0) + 1, (st.won or 0) + 1
                    local n = #s.path - 1
                    if not st.best or n < st.best then st.best = n end
                    Store.set("wr.stats", st)
                end
                Store.set("wr.day", s)
                app:refresh()
            end, UI.vgroup({
                UI.vspace(9),
                UI.text(t, { size = 19, width = W, font = t == s.target and "bold" or nil }),
                UI.vspace(9),
                UI.line(W),
            }) })
        end
        return UI.page(UI.vgroup(items), UI.buttonRow({
            { "Letters", function() app.wrLetter = nil; app:refresh() end, small = true },
            { "Vorige", function() app.wrPg = math.max(1, pg - 1); app:refresh() end, small = true, disabled = pg <= 1 },
            { "Verder", function() app.wrPg = math.min(np, pg + 1); app:refresh() end, small = true, primary = true, disabled = pg >= np },
        }))
    end
    return UI.page(UI.vgroup(items), UI.buttonRow({
        { "Stap terug", function()
            if #s.path > 1 then table.remove(s.path); Store.set("wr.day", s); app.wrLetter = nil; app:refresh() end
        end, small = true, disabled = #s.path <= 1 },
        { "Lees dit artikel", function()
            require("ks_reading").saveWikipedia(app, cur, function(ok, item)
                if ok and item then require("ks_reading").open(app, item) end
            end)
        end, small = true },
    }))
end

return WR
