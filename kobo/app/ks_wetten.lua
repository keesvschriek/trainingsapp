-- Wat verandert er: wetten en besluiten die de afgelopen week in het Staatsblad verschenen,
-- uit de open data van de overheid (repository.overheid.nl, SRU). Ingedeeld in: gaat in,
-- nieuwe wetten, besluiten en begrotingswijzigingen (samengevat).

local DataStorage = require("datastorage")
local UI = require("ks_ui")

local W = {}

W.BASE = os.getenv("KEES_STUDY_SRU_URL") or "https://repository.overheid.nl/sru"
W.OB = os.getenv("KEES_STUDY_OB_URL") or "https://zoek.officielebekendmakingen.nl/"

local function file() return DataStorage:getSettingsDir() .. "/keesstudy-wetten.json" end
local cache
function W.data()
    if cache then return cache end
    local f = io.open(file(), "rb")
    if f then
        local ok, d = pcall(require("json").decode, f:read("*a"))
        f:close()
        if ok and type(d) == "table" then cache = d end
    end
    cache = cache or {}
    return cache
end
local function save(d)
    cache = d
    local f = io.open(file() .. ".tmp", "wb")
    if not f then return end
    f:write(require("json").encode(d))
    f:close()
    os.rename(file() .. ".tmp", file())
end

local function enc(s) return (s:gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end)) end
local function str(v) return type(v) == "string" and v or (type(v) == "table" and type(v["$"]) == "string" and v["$"]) or nil end
local function list(v) if type(v) ~= "table" then return {} end if v[1] then return v end return { v } end

--- "Wet van 4 november 2026 tot wijziging van ..." wordt "Wijziging van ...".
function W.clean(t)
    t = t or ""
    t = t:gsub("^Wet van %d+ %a+ %d+,? ?", ""):gsub("^Besluit van %d+ %a+ %d+,? ?", "")
    t = t:gsub("^houdende ", ""):gsub("^tot ", "")
    t = t:gsub("%s+", " ")
    return (t:gsub("^%l", string.upper))
end

function W.kind(r)
    local t = (r.title or ""):lower()
    if t:find("inwerkingtreding") then return "in" end
    if t:find("begrotingsstaten") or (r.subject or ""):find("Begroting") then return "begroting" end
    if r.type == "Wet" then return "wet" end
    return "besluit"
end

local MINE = { "Onderwijs", "Defensie", "Internationaal", "Sport" }
function W.mine(r)
    for _, m in ipairs(MINE) do if (r.subject or ""):find(m) then return true end end
    return false
end

function W.fetchNow()
    local since = os.date("%Y-%m-%d", os.time() - 7 * 86400)
    local q = "c.product-area==officielepublicaties AND w.publicatienaam==Staatsblad AND dt.available>=" .. since
    local url = W.BASE .. "?query=" .. enc(q) .. "&maximumRecords=100&httpAccept=application/json"
    local ok, body = require("ks_net").get(url)
    if not ok then return false, "Ophalen mislukt: " .. tostring(body) end
    local good, j = pcall(require("json").decode, body)
    if not good or type(j) ~= "table" or type(j.searchRetrieveResponse) ~= "table" then return false, "Onverwacht antwoord." end
    local recs = list(type(j.searchRetrieveResponse.records) == "table" and j.searchRetrieveResponse.records.record)
    local items = {}
    for _, r in ipairs(recs) do
        local m = type(r.recordData) == "table" and r.recordData.gzd and r.recordData.gzd.originalData and r.recordData.gzd.originalData.meta
        if type(m) == "table" then
            local k, mm = m.owmskern or {}, m.owmsmantel or {}
            local subj = {}
            for _, s in ipairs(list(mm.subject)) do local v = str(s); if v then subj[#subj + 1] = v end end
            local it = { id = str(k.identifier), title = str(k.title), type = str(k.type), date = str(mm.available) or str(mm.issued),
                subject = table.concat(subj, "; "), ministry = str(k.creator) }
            if it.id and it.title then items[#items + 1] = it end
        end
    end
    table.sort(items, function(a, b) return (a.date or "") > (b.date or "") end)
    save({ at = os.time(), items = items })
    return true
end

function W.due() local d = W.data(); return not d.at or os.time() - d.at > 20 * 3600 end

function W.summary()
    local d = W.data()
    if not d.items then return "Wetten en besluiten van de afgelopen week" end
    local n, inN = 0, 0
    for _, r in ipairs(d.items) do
        local k = W.kind(r)
        if k ~= "begroting" then n = n + 1 end
        if k == "in" then inN = inN + 1 end
    end
    return n .. " nieuw in het Staatsblad" .. (inN > 0 and (", waarvan " .. inN .. " over wanneer iets ingaat") or "")
end

local MON = { "jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec" }
local function short(d)
    local y, m, dd = (d or ""):match("(%d+)-(%d+)-(%d+)")
    if not y then return "" end
    return tonumber(dd) .. " " .. MON[tonumber(m)]
end

function W.page(app)
    local Wd = UI.INNER()
    local d = W.data()
    local items = { UI.header("Wat verandert er", function() app:back() end, "Staatsblad, afgelopen 7 dagen" .. (d.at and (" · opgehaald " .. os.date("%d-%m %H:%M", d.at)) or "")) }
    if not d.items then
        table.insert(items, UI.text("Nog niets opgehaald.", { size = 18, color = UI.INK2 }))
    else
        local groups = { { "in", "Gaat in" }, { "wet", "Nieuwe wetten" }, { "besluit", "Besluiten (AMvB en KB)" } }
        local rows = {}
        local begr = 0
        for _, g in ipairs(groups) do
            local first = true
            for _, r in ipairs(d.items) do
                local k = W.kind(r)
                if k == "begroting" and g[1] == "in" then begr = begr + 1 end
                if k == g[1] then
                    rows[#rows + 1] = { head = first and g[2] or nil, r = r }
                    first = false
                end
            end
        end
        local per = 5
        local np = math.max(1, math.ceil(#rows / per))
        local pg = math.min(app.wtPg or 1, np)
        app.wtPg = pg
        for i = (pg - 1) * per + 1, math.min(#rows, pg * per) do
            local e = rows[i]
            if e.head then table.insert(items, UI.vspace(6)); table.insert(items, UI.section(e.head, Wd)) end
            local r = e.r
            local t = W.clean(r.title)
            if #t > 170 then t = t:sub(1, 160):gsub("[\128-\191]*$", ""):gsub("%s%S*$", "") .. " ..." end
            table.insert(items, UI.Tap:new{ label = r.id, callback = function() app.wt = r; app:go(W.detail) end, UI.vgroup({
                UI.vspace(8),
                UI.text(t, { size = 17, width = Wd, font = W.mine(r) and "medium" or nil }),
                UI.vspace(3),
                UI.text(short(r.date) .. " · " .. (r.subject ~= "" and r.subject or (r.type or "")), { size = 14, color = UI.INK2, width = Wd }),
                UI.vspace(8),
                UI.line(Wd),
            }) })
        end
        if begr > 0 and pg == np then
            table.insert(items, UI.vspace(10))
            table.insert(items, UI.text("Verder " .. begr .. " wijzigingen van begrotingen (suppletoire begrotingen).", { size = 15, color = UI.INK2, width = Wd }))
        end
        if np > 1 then
            return UI.page(UI.vgroup(items), UI.buttonRow({
                { "Vorige", function() app.wtPg = math.max(1, pg - 1); app:refresh() end, small = true, disabled = pg <= 1 },
                { pg .. " / " .. np, function() end, small = true, disabled = true },
                { "Verder", function() app.wtPg = math.min(np, pg + 1); app:refresh() end, small = true, primary = true, disabled = pg >= np },
            }))
        end
    end
    return UI.page(UI.vgroup(items), UI.button("Nu ophalen", function()
        require("ks_net").online(function() W.fetchNow(); app:refresh() end)
    end, { width = Wd }))
end

function W.detail(app)
    local Wd = UI.INNER()
    local r = app.wt
    local items = { UI.header(({ ["in"] = "Gaat in", wet = "Wet", besluit = "Besluit", begroting = "Begroting" })[W.kind(r)] or "Staatsblad", function() app:back() end,
        (r.id or "") .. " · " .. short(r.date)) }
    table.insert(items, UI.text(r.title or "", { font = "serif", size = 21, width = Wd }))
    table.insert(items, UI.vspace(12))
    if r.subject and r.subject ~= "" then table.insert(items, UI.text("Onderwerp: " .. r.subject, { size = 16, color = UI.INK2, width = Wd })) end
    if r.ministry then table.insert(items, UI.text("Van: " .. r.ministry, { size = 16, color = UI.INK2, width = Wd })) end
    if app.wtMsg then table.insert(items, UI.vspace(10)); table.insert(items, UI.text(app.wtMsg, { size = 17, font = "medium", width = Wd })) end
    return UI.page(UI.vgroup(items), UI.button("Hele tekst bij Te lezen zetten", function()
        require("ks_net").online(function()
            local ok, html = require("ks_net").get(W.OB .. r.id .. ".html")
            if not ok then app.wtMsg = "Ophalen lukte niet."; app:refresh(); return end
            local _, blocks = require("ks_inbox").extract(html)
            if #blocks < 1 then app.wtMsg = "De tekst kon niet gelezen worden."; app:refresh(); return end
            local name = "stb-" .. r.id:gsub("[^%w%-]", "") .. ".json"
            require("ks_reading").saveDoc(name, { id = name, title = W.clean(r.title), sub = "Staatsblad", kind = "Staatsblad", blocks = blocks },
                { title = W.clean(r.title), sub = "Staatsblad " .. r.id, src = "stb", new = true, date = os.date("%Y-%m-%d") })
            app.wtMsg = "Staat bij Lezen, Te lezen."
            app:refresh()
        end)
    end, { width = Wd }))
end

return W
