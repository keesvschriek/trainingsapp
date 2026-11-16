-- Fragment van de dag: korte stukken uit klassiekers over geschiedenis, oorlog en filosofie.
-- Bron: Project Gutenberg (rechtenvrij). De Kobo haalt een boek één keer op, knipt er
-- fragmenten uit en bewaart alleen die fragmenten, niet het hele boek.

local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local Store = require("ks_store")
local UI = require("ks_ui")

local F = {}

-- Eerst de kant-en-klare fragmenten van onze eigen GitHub Pages (klein en betrouwbaar),
-- anders zelf knippen uit de tekst van Project Gutenberg.
F.PAGES = os.getenv("KEES_STUDY_FRAG_URL") or "https://keesvschriek.github.io/trainingsapp/kobo/fragments/"
F.BASE = os.getenv("KEES_STUDY_GUTENBERG_URL") or "https://www.gutenberg.org/cache/epub/"
F.KEEP = 250

-- Alleen werken waarvan schrijver en vertaler al lang overleden zijn.
F.BOOKS = {
    { id = 7142, author = "Thucydides", title = "History of the Peloponnesian War", note = "vertaling Richard Crawley", lang = "en" },
    { id = 1946, author = "Carl von Clausewitz", title = "On War", note = "vertaling J. J. Graham", lang = "en" },
    { id = 2680, author = "Marcus Aurelius", title = "Meditations", note = "Engelse vertaling", lang = "en" },
    { id = 132, author = "Sun Tzu", title = "The Art of War", note = "vertaling Lionel Giles", lang = "en" },
    { id = 1232, author = "Niccolò Machiavelli", title = "The Prince", note = "vertaling W. K. Marriott", lang = "en" },
    { id = 11024, author = "Multatuli", title = "Max Havelaar", note = "oorspronkelijke tekst, 1860", lang = "nl" },
}

local function file(id) return DataStorage:getSettingsDir() .. "/keesstudy-frag-" .. id .. ".json" end
local loaded = {}
function F.frags(id)
    if loaded[id] then return loaded[id] end
    local f = io.open(file(id), "rb")
    if not f then return nil end
    local ok, d = pcall(require("json").decode, f:read("*a"))
    f:close()
    if ok and type(d) == "table" and type(d.frags) == "table" then loaded[id] = d.frags; return d.frags end
    return nil
end

local function words(s) local n = 0; for _ in s:gmatch("%S+") do n = n + 1 end; return n end

local function isHeading(l)
    if #l == 0 or #l > 70 then return false end
    local up = l:upper()
    return l == up and l:find("%a") ~= nil or l:match("^CHAPTER") or l:match("^BOOK") or l:match("^Chapter") or l:match("^Book")
end

--- Knip een Gutenberg-tekst in losse fragmenten. Geeft { {t, w, p} } met t = tekst, w = waar, p = procent.
function F.cut(text)
    text = text:gsub("\r\n", "\n")
    local a = text:find("%*%*%* ?START OF[^\n]*\n")
    if a then text = text:sub((text:find("\n", a) or a) + 1) end
    local b = text:find("%*%*%* ?END OF")
    if b then text = text:sub(1, b - 1) end
    local all, where = {}, nil
    local total = #text
    local pos = 1
    for block in (text .. "\n\n"):gmatch("(.-)\n%s*\n") do
        pos = pos + #block + 2
        local lines = {}
        for l in block:gmatch("[^\n]+") do table.insert(lines, (l:gsub("^%s+", ""):gsub("%s+$", ""))) end
        while #lines > 1 and isHeading(lines[1]) do where = table.remove(lines, 1):sub(1, 60) end
        local joined = table.concat(lines, " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
        if #lines <= 2 and isHeading(joined) then
            where = joined:sub(1, 60)
        else
            local n = words(joined)
            if n >= 60 and n <= 230 and not joined:find("Gutenberg") and not joined:match("^%[") and not joined:find("http") then
                -- voetnootcijfers en rare tekens weg
                joined = joined:gsub("%[%d+%]", ""):gsub("_", "")
                table.insert(all, { t = joined, w = where, p = math.floor(pos / total * 100) })
            end
        end
    end
    -- gelijkmatig verspreid over het boek, in volgorde
    if #all <= F.KEEP then return all end
    local out = {}
    for i = 1, F.KEEP do table.insert(out, all[math.floor((i - 1) * #all / F.KEEP) + 1]) end
    return out
end

local function store(book, frags)
    local f = io.open(file(book.id) .. ".tmp", "wb")
    if not f then return false, "Kon niet opslaan." end
    f:write(require("json").encode({ frags = frags }))
    f:close()
    os.rename(file(book.id) .. ".tmp", file(book.id))
    loaded[book.id] = frags
    return true
end

function F.fetch(book)
    local Net = require("ks_net")
    local ok, body = Net.get(F.PAGES .. book.id .. ".json")
    if ok then
        local good, d = pcall(require("json").decode, body)
        if good and type(d) == "table" and type(d.frags) == "table" and #d.frags >= 5 then return store(book, d.frags) end
    end
    local url = F.BASE .. book.id .. "/pg" .. book.id .. ".txt"
    ok, body = Net.get(url, { ["User-Agent"] = "KeesStudy/1.0 (Kobo e-reader, persoonlijk gebruik)" })
    if not ok then
        local msg = tostring(body)
        if msg:find("503") then msg = "Project Gutenberg is even niet bereikbaar (503). Probeer het later nog eens." end
        return false, msg
    end
    local frags = F.cut(body)
    body = nil
    collectgarbage()
    if #frags < 5 then return false, "Kon geen fragmenten uit dit boek halen." end
    return store(book, frags)
end

local function dayNum() local t = os.date("*t"); return math.floor(os.time{ year = t.year, month = t.month, day = t.day, hour = 12 } / 86400) end

--- Boek van vandaag (draait elke dag door) of het boek dat je zelf koos.
function F.bookIndex(app)
    if app and app.fragBook then return app.fragBook end
    return dayNum() % #F.BOOKS + 1
end

--- Elke dag één stap verder in het boek; "Volgend fragment" gaat ook verder.
local function current(book)
    local pos = Store.get("frag.pos", {})
    local p = pos[tostring(book.id)] or { i = 1, d = dayNum() }
    if p.d ~= dayNum() then p = { i = p.i + 1, d = dayNum() }; pos[tostring(book.id)] = p; Store.set("frag.pos", pos) end
    return p.i
end
local function setPos(book, i)
    local pos = Store.get("frag.pos", {})
    pos[tostring(book.id)] = { i = i, d = dayNum() }
    Store.set("frag.pos", pos)
end

function F.today()
    local book = F.BOOKS[F.bookIndex()]
    local frags = F.frags(book.id)
    if not frags then return nil, book end
    local i = (current(book) - 1) % #frags + 1
    return frags[i], book, i, #frags
end

--- Hooguit één ontbrekend boek per ronde ophalen (eerst dat van vandaag).
function F.due()
    local book = F.BOOKS[F.bookIndex()]
    if not F.frags(book.id) then return book end
    return nil
end
function F.autoFetch()
    local b = F.due()
    if b then return F.fetch(b) end
    return true
end

function F.summary()
    local fr, book = F.today()
    if not fr then return book.author .. " · nog niet opgehaald" end
    return book.author .. ", " .. book.title
end

function F.page(app)
    local W = UI.INNER()
    local bi = F.bookIndex(app)
    local book = F.BOOKS[bi]
    local frags = F.frags(book.id)
    local items = { UI.header("Fragment", function() app.fragBook = nil; app.fragMsg = nil; app:back() end, book.author .. ", " .. book.title .. " (" .. book.note .. ")") }
    table.insert(items, UI.vspace(10))
    local footer
    if not frags then
        table.insert(items, UI.text("Dit boek is nog niet opgehaald. De Kobo haalt het één keer op en bewaart alleen fragmenten.", { size = 19, width = W }))
        if app.fragMsg then table.insert(items, UI.vspace(10)); table.insert(items, UI.text(app.fragMsg, { size = 17, font = "bold", width = W })) end
        footer = UI.buttonRow({
            { "Ophalen", function()
                app.fragMsg = "Bezig met ophalen..."
                app:refresh()
                UIManager:scheduleIn(0.2, function()
                    require("ks_net").online(function()
                        local ok, err = F.fetch(book)
                        app.fragMsg = (not ok) and ("Ophalen mislukt: " .. tostring(err)) or nil
                        app:refresh()
                    end, { onFail = function(m) app.fragMsg = m; app:refresh() end })
                end)
            end, primary = true },
            { "Ander boek", function() app.fragBook = bi % #F.BOOKS + 1; app.fragMsg = nil; app:refresh() end },
        })
        return UI.page(UI.vgroup(items), footer)
    end
    local i = (current(book) - 1) % #frags + 1
    local fr = frags[i]
    if fr.w then
        table.insert(items, UI.text(fr.w, { size = 15, font = "bold", color = UI.INK3, width = W }))
        table.insert(items, UI.vspace(10))
    end
    table.insert(items, UI.text(fr.t, { font = "serif", size = 22, width = W, line_height = 0.45 }))
    table.insert(items, UI.vspace(14))
    table.insert(items, UI.text(("Fragment %d van %d · ongeveer %d%% in het boek"):format(i, #frags, fr.p or 0), { size = 15, color = UI.INK3 }))
    footer = UI.buttonRow({
        { "Vorige", function() setPos(book, math.max(1, i - 1)); app:refresh() end, small = true, disabled = i <= 1 },
        { "Ander boek", function() app.fragBook = bi % #F.BOOKS + 1; app:refresh() end, small = true },
        { "Volgende", function() setPos(book, i + 1); app:refresh() end, small = true, primary = true },
    })
    return UI.page(UI.vgroup(items), footer)
end

return F
