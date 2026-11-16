-- Van telefoon naar Kobo: links en tekst uit de app K (tabel "inbox").
-- Na elke synchronisatie zet de Kobo ze bij Te lezen en meldt terug dat ze er staan.

local Sync = require("ks_sync")

local I = {}

local ENT = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ", ["#39"] = "'", rsquo = "'", lsquo = "'", ldquo = '"', rdquo = '"', hellip = "...", ndash = "-", mdash = "-" }
local function clean(s)
    s = s:gsub("<br%s*/?>", " "):gsub("<[^>]+>", "")
    s = s:gsub("&(#?%w+);", function(e)
        if ENT[e] then return ENT[e] end
        local n = e:match("^#(%d+)$")
        if n then
            n = tonumber(n)
            if n < 128 then return string.char(n) end
            if n < 2048 then return string.char(192 + math.floor(n / 64), 128 + n % 64) end
            return string.char(224 + math.floor(n / 4096), 128 + math.floor(n / 64) % 64, 128 + n % 64)
        end
        return " "
    end)
    return (s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

--- Leesbare tekst uit een willekeurige webpagina: alleen kopjes en alinea's uit het artikel.
function I.extract(html)
    local title = clean(html:match('<meta%s+property="og:title"%s+content="([^"]*)"') or html:match("<h1[^>]*>(.-)</h1>") or html:match("<title[^>]*>(.-)</title>") or "Zonder titel")
    -- rommel eruit
    local h = html:gsub("<!%-%-.-%-%->", "")
    for _, tag in ipairs({ "script", "style", "noscript", "nav", "header", "footer", "aside", "form", "figure", "svg", "button" }) do
        h = h:gsub("<" .. tag .. "[%s>].-</" .. tag .. ">", "")
    end
    local body = h:match("<article[^>]*>(.*)</article>") or h:match("<main[^>]*>(.*)</main>") or h:match("<body[^>]*>(.*)</body>") or h
    -- p, h2 en h3 los zoeken (ook als ze in divs zitten) en op volgorde zetten
    local found = {}
    for _, tag in ipairs({ "p", "h2", "h3" }) do
        local pos = 1
        while true do
            local a, b, inner = body:find("<" .. tag .. "[%s>].-</" .. tag .. ">", pos)
            if not a then break end
            inner = body:sub(a, b):gsub("^<" .. tag .. "[^>]*>", ""):gsub("</" .. tag .. ">$", "")
            table.insert(found, { at = a, tag = tag, inner = inner })
            pos = b + 1
        end
    end
    table.sort(found, function(x, y) return x.at < y.at end)
    local blocks = {}
    for _, f in ipairs(found) do
        local tag, inner = f.tag, f.inner
        local t = clean(inner)
        if tag == "p" then
            if #t >= 60 then table.insert(blocks, { k = "p", t = t }) end
        elseif #t > 0 and #t < 160 then
            table.insert(blocks, { k = tag == "h2" and "h2" or "h3", t = t })
        end
    end
    -- losse kopjes aan het eind weg
    while #blocks > 0 and blocks[#blocks].k ~= "p" do table.remove(blocks) end
    return title, blocks
end

local function textBlocks(text)
    local blocks = {}
    for para in (text .. "\n\n"):gmatch("(.-)\n%s*\n") do
        local t = para:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
        if t ~= "" then table.insert(blocks, { k = "p", t = t }) end
    end
    return blocks
end

local function done(r, note)
    r.done = true
    r.note = note
    Sync.put("inbox", r)
end

--- Eén binnengekomen item verwerken. Geeft true als het bij Te lezen staat.
function I.handle(r)
    local R = require("ks_reading")
    local name = "inbox-" .. tostring(r.id):gsub("[^%w%-]", ""):sub(1, 40) .. ".json"
    if type(r.url) == "string" and r.url ~= "" then
        local wiki = r.url:match("^https?://nl%.m?%.?wikipedia%.org/wiki/([^#?]+)") or r.url:match("^https?://nl%.wikipedia%.org/wiki/([^#?]+)")
        if wiki then
            local title = wiki:gsub("_", " "):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
            local ok, _, err = R.wikiNow(title)
            if ok then done(r, "Staat op de Kobo (Wikipedia)"); return true end
            done(r, "Wikipedia-artikel niet gevonden: " .. tostring(err))
            return false
        end
        local ok, html = require("ks_net").get(r.url, { ["User-Agent"] = "Mozilla/5.0 (Kobo; KeesPersonal) AppleWebKit Safari" })
        if not ok then done(r, "Pagina niet bereikbaar"); return false end
        local title, blocks = I.extract(html)
        if #blocks < 2 then done(r, "Pagina niet leesbaar (misschien achter een betaalmuur)"); return false end
        local host = r.url:match("^https?://([^/]+)") or ""
        R.saveDoc(name, { id = name, title = (r.title and r.title ~= "") and r.title or title, sub = host:gsub("^www%.", ""), kind = "Van je telefoon", blocks = blocks, url = r.url },
            { title = (r.title and r.title ~= "") and r.title or title, sub = host:gsub("^www%.", ""), src = "phone", new = true, date = os.date("%Y-%m-%d") })
        done(r, "Staat op de Kobo")
        return true
    end
    if type(r.text) == "string" and r.text ~= "" then
        local blocks = textBlocks(r.text)
        local title = (r.title and r.title ~= "") and r.title or (blocks[1] and blocks[1].t:sub(1, 60) or "Tekst")
        R.saveDoc(name, { id = name, title = title, sub = "Van je telefoon", kind = "Van je telefoon", blocks = blocks },
            { title = title, sub = "Van je telefoon", src = "phone", new = true, date = os.date("%Y-%m-%d") })
        done(r, "Staat op de Kobo")
        return true
    end
    done(r, "Leeg")
    return false
end

--- Alles wat nog wacht verwerken. Geeft het aantal nieuwe stukken.
function I.process()
    local n = 0
    for _, r in ipairs(Sync.list("inbox", function(x) return not x.done end)) do
        local ok, got = pcall(I.handle, r)
        if ok and got then n = n + 1 end
    end
    return n
end

return I
