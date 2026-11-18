-- Nieuws: een rustige krant in edities (ochtend, middag, avond) uit de RSS-feeds van de NOS.
-- Ophalen gaat automatisch één keer per ochtend- en avondeditie als je de app opent,
-- of wanneer je zelf op Nu ophalen tikt. Daarna is alles offline te lezen.
-- Gebruik volgens de voorwaarden van de NOS: persoonlijk, met bronvermelding, tekst niet bewerkt.

local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local UI = require("ks_ui")
local Store = require("ks_store")

local N = {}

N.FEEDS = {
    { id = "algemeen", name = "Voorpagina", url = "https://feeds.nos.nl/nosnieuwsalgemeen" },
    { id = "politiek", name = "Politiek", url = "https://feeds.nos.nl/nosnieuwspolitiek" },
    { id = "binnenland", name = "Binnenland", url = "https://feeds.nos.nl/nosnieuwsbinnenland" },
    { id = "buitenland", name = "Buitenland", url = "https://feeds.nos.nl/nosnieuwsbuitenland" },
    { id = "economie", name = "Economie", url = "https://feeds.nos.nl/nosnieuwseconomie" },
    { id = "sport", name = "Sport", url = "https://feeds.nos.nl/nossportalgemeen" },
}
N.DEFAULT = { algemeen = true, politiek = true, buitenland = true, sport = true }
N.PER_FEED = 8

-- in tests: feeds van een eigen servertje
local testBase = os.getenv("KEES_STUDY_NEWS_URL")
if testBase then
    for _, f in ipairs(N.FEEDS) do f.url = testBase .. f.id .. ".xml" end
end

function N.enabled()
    local e = Store.get("news.feeds")
    if not e then return N.DEFAULT end
    return e
end

--- Welke editie is het nu? (naam, sleutel voor vandaag)
function N.edition(t)
    t = t or os.time()
    local h = tonumber(os.date("%H", t))
    local d = os.date("%Y-%m-%d", t)
    if h >= 5 and h < 12 then return "Ochtendeditie", d .. "-o" end
    if h >= 12 and h < 17 then return "Middageditie", d .. "-m" end
    if h < 5 then d = os.date("%Y-%m-%d", t - 6 * 3600) end
    return "Avondeditie", d .. "-a"
end

-- Opslag in een eigen bestand, zodat de krant de back-ups niet groot maakt.
local function file() return DataStorage:getSettingsDir() .. "/keesstudy-news.json" end
local cache
function N.data()
    if cache then return cache end
    local f = io.open(file(), "rb")
    if f then
        local ok, d = pcall(require("json").decode, f:read("*a"))
        f:close()
        if ok and type(d) == "table" then cache = d end
    end
    cache = cache or { items = {} }
    return cache
end
local function save()
    local f = io.open(file() .. ".tmp", "wb")
    if not f then return end
    f:write(require("json").encode(cache))
    f:close()
    os.rename(file() .. ".tmp", file())
end

-- RSS lezen ---------------------------------------------------------------------

local ENT = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ", euro = "€", hellip = "...", ndash = "-", mdash = "-", lsquo = "'", rsquo = "'", ldquo = '"', rdquo = '"' }
local function decode(s)
    s = s:gsub("&#x(%x+);", function(h) return require("util").unicodeCodepointToUtf8(tonumber(h, 16)) end)
    s = s:gsub("&#(%d+);", function(n) return require("util").unicodeCodepointToUtf8(tonumber(n)) end)
    s = s:gsub("&(%a+);", function(n) return ENT[n] or ("&" .. n .. ";") end)
    return s
end
local function cdata(s)
    if not s then return nil end
    local inner = s:match("^%s*<!%[CDATA%[(.-)%]%]>%s*$")
    if inner then return inner end
    return decode(s)
end

--- HTML naar platte alinea's (koppen en lijsten blijven leesbaar).
function N.toText(html)
    if not html or html == "" then return "" end
    local s = html
    s = s:gsub("<script.-</script>", ""):gsub("<style.-</style>", ""):gsub("<figure.-</figure>", "")
    s = s:gsub("<br%s*/?>", "\n")
    s = s:gsub("</p>", "\n\n"):gsub("</h%d>", "\n\n"):gsub("<li[^>]*>", "\n· "):gsub("</li>", "")
    s = s:gsub("<[^>]+>", "")
    s = decode(s)
    s = s:gsub("[ \t\r]+", " "):gsub(" *\n *", "\n"):gsub("\n\n\n+", "\n\n")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local MON = { Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6, Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12 }
local function rfc822(s)
    if not s then return nil end
    local d, mon, y, h, mi, sec, zone = s:match("(%d+)%s+(%a+)%s+(%d+)%s+(%d+):(%d+):?(%d*)%s*([%+%-]?%d*)")
    if not d or not MON[mon] then return nil end
    local t = os.time{ year = tonumber(y), month = MON[mon], day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(sec) or 0 }
    -- omrekenen naar lokale tijd: eerst naar UTC via de opgegeven zone, dan het lokale verschil erbij
    local off = 0
    if zone and zone ~= "" then
        local sign, zh, zm = zone:match("([%+%-])(%d%d)(%d%d)")
        if sign then off = (tonumber(zh) * 3600 + tonumber(zm) * 60) * (sign == "-" and -1 or 1) end
    end
    local localOff = os.time() - os.time(os.date("!*t"))
    return t - off + localOff
end

function N.parse(xml, feed)
    local list = {}
    for item in xml:gmatch("<item[%s>].-</item>") do
        local function tag(name) return item:match("<" .. name .. "[^>]*>(.-)</" .. name .. ">") end
        local title = cdata(tag("title"))
        local link = cdata(tag("link")) or cdata(tag("guid"))
        local desc = tag("content:encoded") or tag("description")
        if title and title ~= "" then
            table.insert(list, {
                title = (title:gsub("%s+", " ")),
                link = link,
                text = N.toText(cdata(desc) or ""),
                t = rfc822(tag("pubDate")) or os.time(),
                feed = feed.id,
            })
        end
        if #list >= N.PER_FEED then break end
    end
    return list
end

--- Haal alle gekozen rubrieken op. Moet al online zijn.
function N.fetchNow()
    local Net = require("ks_net")
    local en = N.enabled()
    local items, seen, errs, got = {}, {}, {}, 0
    for _, f in ipairs(N.FEEDS) do
        if en[f.id] then
            local ok, body = Net.get(f.url)
            if ok then
                got = got + 1
                for _, it in ipairs(N.parse(body, f)) do
                    local key = it.link or it.title
                    if not seen[key] then seen[key] = true; table.insert(items, it) end
                end
            else
                table.insert(errs, f.name)
            end
        end
    end
    if got == 0 then return false, "Kon het nieuws niet ophalen." end
    local d = N.data()
    local name, key = N.edition()
    d.items, d.at, d.edition, d.key = items, os.time(), name, key
    d.read = {}
    save()
    return true, #errs > 0 and ("Niet gelukt: " .. table.concat(errs, ", ")) or nil
end

function N.refresh(done, quiet)
    require("ks_net").online(function()
        local ok, err = N.fetchNow()
        -- in dezelfde wifi-sessie ook de sporttraining bijwerken
        if require("ks_sport").connected() then pcall(require("ks_sport").fetchNow) end
        -- en de laatste stemmingen in de Tweede Kamer
        local K = require("ks_kamer")
        if K.due() then pcall(K.fetchAll) end
        -- Jouw Kamer: de eerste keer een paar stemmingsdagen terug ophalen
        pcall(function() local J = require("ks_jouwkamer"); if #require("ks_store").get("jk.pool", {}) < 5 then J.fill() end; J.prefetch(5) end)
        -- radionieuws van 80 jaar geleden (ANP, KB)
        pcall(function() local Radio = require("ks_radio"); if Radio.due() then Radio.fetchNow() end end)
        -- Staatsblad van de afgelopen week en de Wikirace van vandaag
        pcall(function() local Wt = require("ks_wetten"); if Wt.due() then Wt.fetchNow() end end)
        pcall(function() require("ks_wikirace").prepare() end)
        -- vandaag in de geschiedenis en je rooster
        local O = require("ks_otd")
        if O.due() then pcall(O.fetchNow) end
        local R = require("ks_rooster")
        if R.due() then pcall(R.fetchNow) end
        -- te lezen en het fragment van de dag (hooguit één boek per keer)
        local Sync = require("ks_sync")
        if Sync.due() then pcall(Sync.syncNow) end
        local RD = require("ks_reading")
        if RD.due() then pcall(RD.fetchNow) end
        pcall(require("ks_fragment").autoFetch)
        done(ok, err)
    end, { quiet = quiet, onFail = function(msg) done(false, msg) end })
end

--- Moet de editie van nu nog opgehaald worden? (alleen ochtend en avond automatisch)
function N.due()
    if not Store.get("news.auto", true) then return false end
    local name, key = N.edition()
    if name == "Middageditie" then return false end
    return N.data().key ~= key
end

function N.unreadCount()
    local d = N.data()
    local n = 0
    for _, it in ipairs(d.items or {}) do if not (d.read or {})[it.link or it.title] then n = n + 1 end end
    return n
end

-- Schermen ----------------------------------------------------------------------

local function ago(t)
    local m = math.floor((os.time() - t) / 60)
    if m < 1 then return "zojuist" end
    if m < 60 then return m .. " min geleden" end
    if m < 24 * 60 then return math.floor(m / 60) .. " uur geleden" end
    return os.date("%d-%m %H:%M", t)
end
N.ago = ago

local function feedName(id)
    for _, f in ipairs(N.FEEDS) do if f.id == id then return f.name end end
    return id
end

--- Tekst opdelen in bladzijden die op het scherm passen.
local function paginate(text, width, height, opts)
    local pages, cur = {}, ""
    local function fits(s) local w = UI.text(s, opts); local h = w:getSize().h; w:free(); return h <= height end
    for para in (text .. "\n\n"):gmatch("(.-)\n\n") do
        if para ~= "" then
            local try = cur == "" and para or (cur .. "\n\n" .. para)
            if fits(try) then
                cur = try
            else
                if cur ~= "" then table.insert(pages, cur); cur = "" end
                if fits(para) then cur = para
                else
                    -- te lange alinea: per zin
                    for sent in (para .. " "):gmatch("(.-[%.%?!]%s)") do
                        local t2 = cur == "" and sent or (cur .. sent)
                        if fits(t2) then cur = t2 else table.insert(pages, cur); cur = sent end
                    end
                end
            end
        end
    end
    if cur ~= "" then table.insert(pages, cur) end
    if #pages == 0 then pages = { "" } end
    return pages
end

function N.article(app)
    local d = N.data()
    local list = app.newsList or {}
    local idx = app.newsIdx or 1
    local it = list[idx]
    if not it then return N.page(app) end
    d.read = d.read or {}
    if not d.read[it.link or it.title] then d.read[it.link or it.title] = true; save() end
    local W = UI.INNER()
    local head = UI.vgroup({
        UI.header(feedName(it.feed), function() app.newsPage = nil; app:back() end, ago(it.t) .. " · NOS"),
        UI.text(it.title, { font = "display", size = 30, width = W }),
        UI.vspace(16),
    })
    local footerH = UI.px(80)
    local avail = UI.H() - UI.px(UI.TOPPAD) - head:getSize().h - footerH - UI.px(60)
    local opts = { font = "serif", size = 20, width = W, line_height = 0.45 }
    app.newsPages = app.newsPages or {}
    local keyP = (it.link or it.title) .. "|" .. UI.scale
    if not app.newsPages[keyP] then app.newsPages[keyP] = paginate(it.text ~= "" and it.text or "Deze rubriek geeft alleen de kop.", W, avail, opts) end
    local pages = app.newsPages[keyP]
    local p = math.min(app.newsPage or 1, #pages)
    local body = UI.vgroup({ head, UI.text(pages[p], opts) })
    local nav = {}
    if p > 1 then table.insert(nav, { "Vorige bladzijde", function() app.newsPage = p - 1; app:refresh() end, small = true, icon = "chevron_left" })
    elseif idx > 1 then table.insert(nav, { "Vorig bericht", function() app.newsIdx = idx - 1; app.newsPage = 1; app:refresh() end, small = true, icon = "chevron_left" }) end
    if p < #pages then table.insert(nav, { ("Verder (%d/%d)"):format(p, #pages), function() app.newsPage = p + 1; app:refresh() end, small = true, primary = true })
    elseif idx < #list then table.insert(nav, { "Volgend bericht", function() app.newsIdx = idx + 1; app.newsPage = 1; app:refresh() end, small = true, primary = true }) end
    if #nav == 0 then table.insert(nav, { "Terug naar de krant", function() app:back() end, small = true }) end
    return UI.page(body, UI.buttonRow(nav))
end

function N.page(app)
    local d = N.data()
    local W = UI.INNER()
    local name = d.edition or N.edition()
    local extra = d.at and (require("ks_main").dateText(d.at) .. " · opgehaald " .. os.date("%H:%M", d.at) .. " · NOS") or "Nog niet opgehaald"
    local items = { UI.header(name, function() app.newsMsg = nil; app.newsPg = nil; app:back() end, extra) }
    local nowName, nowKey = N.edition()
    if d.key and d.key ~= nowKey then
        table.insert(items, UI.card(UI.hgroup({ UI.icon("info", 22, UI.INK2, { bg = UI.FILL }), UI.hspace(10),
            UI.text("Dit is een oudere editie. De " .. nowName:lower() .. " staat klaar om op te halen.", { size = 16, width = W - UI.px(80), bg = UI.FILL }) }), { fill = true, pad = UI.px(14) }))
        table.insert(items, UI.vspace(12))
    end
    -- per rubriek, gelezen berichten in grijs; verdeeld over bladzijden die passen
    local byFeed = {}
    for i, it in ipairs(d.items or {}) do
        byFeed[it.feed] = byFeed[it.feed] or {}
        table.insert(byFeed[it.feed], i)
    end
    local flat, blocks = {}, {}
    local en = N.enabled()
    for _, f in ipairs(N.FEEDS) do
        local ids = byFeed[f.id]
        if ids and en[f.id] then
            for n, i in ipairs(ids) do
                local it = d.items[i]
                table.insert(flat, it)
                local pos = #flat
                local read = (d.read or {})[it.link or it.title]
                local row = UI.Tap:new{ label = it.title, callback = function() app.newsList = flat; app.newsIdx = pos; app.newsPage = 1; app:go(N.article) end,
                    UI.vgroup({
                        UI.text(it.title, { size = 20, font = read and "sans" or "medium", color = read and UI.INK2 or UI.BLACK, width = W }),
                        UI.vspace(2),
                        UI.text(ago(it.t), { size = 15, color = UI.INK3 }),
                        UI.vspace(14),
                    }) }
                -- de kop van een rubriek blijft bij zijn eerste bericht
                table.insert(blocks, n == 1 and UI.vgroup({ UI.section(f.name), row }) or row)
            end
        end
    end
    if Store.get("kamer.on", true) then
        local K = require("ks_kamer")
        table.insert(items, UI.row("Gisteren in de Kamer", K.summary(), "›", function() app.kamerPg = 1; app:go(K.page) end, W, "scale"))
        table.insert(items, UI.row("Jouw Kamer", require("ks_jouwkamer").summary(), "›", function() app.jk = nil; app:go(require("ks_jouwkamer").page) end, W, "check"))
        table.insert(items, UI.row("Op deze dag", require("ks_otd").summary(), "›", function() app.otdPg = 1; app:go(require("ks_otd").page) end, W, "history"))
        table.insert(items, UI.row("Radionieuws van deze dag", require("ks_radio").summary(), "›", function() require("ks_radio").start(app) end, W, "news"))
        table.insert(items, UI.row("Wat verandert er", require("ks_wetten").summary(), "›", function() app.wtPg = 1; app:go(require("ks_wetten").page) end, W, "list_checks"))
        table.insert(items, UI.vspace(6))
    end
    local head = UI.vgroup(items)
    local footerH = UI.px(60)
    local avail = UI.H() - UI.px(UI.TOPPAD) - head:getSize().h - footerH - UI.px(70) - (app.newsMsg and UI.px(40) or 0)
    local pages, cur, used = {}, {}, 0
    for _, bl in ipairs(blocks) do
        local h = bl:getSize().h
        if used + h > avail and #cur > 0 then table.insert(pages, cur); cur, used = {}, 0 end
        table.insert(cur, bl); used = used + h
    end
    if #cur > 0 then table.insert(pages, cur) end
    local pg = math.max(1, math.min(app.newsPg or 1, #pages))
    app.newsPg = pg
    for _, bl in ipairs(pages[pg] or {}) do table.insert(items, bl) end
    if #(d.items or {}) == 0 then
        table.insert(items, UI.vspace(30))
        table.insert(items, UI.center(UI.icon("news", 60, UI.INK3), W))
        table.insert(items, UI.vspace(12))
        table.insert(items, UI.center(UI.text("Nog geen nieuws. Tik op Ophalen.", { size = 19, color = UI.INK2 }), W))
    end
    if app.newsMsg then
        table.insert(items, UI.vspace(8))
        table.insert(items, UI.text(app.newsMsg, { size = 17, font = "bold", width = W }))
    end
    local npages = math.max(1, #pages)
    local footer = UI.buttonRow({
        { "Ophalen", function()
            app.newsMsg = "Bezig met ophalen..."
            app.newsPg = 1
            app:refresh()
            UIManager:scheduleIn(0.2, function()
                N.refresh(function(ok, err)
                    if ok then app.newsMsg = err else app.newsMsg = "Ophalen mislukt: " .. tostring(err) end
                    app:refresh()
                end)
            end)
        end, small = true },
        { "Vorige", function() app.newsPg = pg - 1; app:refresh() end, small = true, disabled = pg <= 1 },
        { npages > 1 and ("Verder " .. pg .. "/" .. npages) or "Verder", function() app.newsPg = pg + 1; app:refresh() end, small = true, primary = pg < npages, disabled = pg >= npages },
        { "Rubrieken", function() app:go(N.settings) end, small = true },
    })
    return UI.page(UI.vgroup(items), footer)
end

function N.settings(app)
    local en = N.enabled()
    local items = { UI.header("Rubrieken", function() app:back() end, "Kies wat er in je krant komt.") }
    for _, f in ipairs(N.FEEDS) do
        table.insert(items, UI.Tap:new{ label = f.name, callback = function()
            local e = {}
            for k, v in pairs(en) do e[k] = v end
            e[f.id] = (not e[f.id]) or nil
            Store.set("news.feeds", e)
            app:refresh()
        end, UI.vgroup({ UI.vspace(12), UI.hgroup({ UI.checkbox(en[f.id]), UI.hspace(16), UI.text(f.name, { size = 21, font = "medium" }) }), UI.vspace(12), UI.line(UI.INNER()) }) })
    end
    local kon = Store.get("kamer.on", true)
    table.insert(items, UI.Tap:new{ label = "Kamer", callback = function() Store.set("kamer.on", not kon); app:refresh() end,
        UI.vgroup({ UI.vspace(12), UI.hgroup({ UI.checkbox(kon), UI.hspace(16), UI.text("Gisteren in de Kamer", { size = 21, font = "medium" }) }), UI.vspace(12), UI.line(UI.INNER()) }) })
    table.insert(items, UI.vspace(24))
    table.insert(items, UI.section("Automatisch ophalen"))
    local auto = Store.get("news.auto", true)
    table.insert(items, UI.segmented({ "Ochtend en avond", "Alleen zelf" }, auto and 1 or 2, function(i) Store.set("news.auto", i == 1); app:refresh() end))
    table.insert(items, UI.vspace(10))
    table.insert(items, UI.text("Bij Ochtend en avond haalt de app de krant op als je hem opent tussen 5 en 12 uur of na 17 uur, één keer per editie. Wifi gaat daarna weer uit. Je sporttraining wordt meteen mee bijgewerkt.", { size = 16, color = UI.INK2, width = UI.INNER() }))
    return UI.page(UI.vgroup(items))
end

return N
