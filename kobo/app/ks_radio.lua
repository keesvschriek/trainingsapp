-- Radionieuws van deze dag: de ANP-berichten zoals ze op deze datum op de radio werden voorgelezen,
-- uit de collectie Radiobulletins van de KB (Delpher). Standaard 80 jaar geleden; ontbreekt die dag,
-- dan 75 of 70 jaar geleden. Alleen voor eigen gebruik: de tekst wordt op de Kobo opgehaald en niet gedeeld.

local DataStorage = require("datastorage")
local UI = require("ks_ui")

local R = {}

R.BASE = os.getenv("KEES_STUDY_KB_URL") or "https://resolver.kb.nl/resolve?urn="
R.MAX = 40 -- berichten per dag

local MONTHS = { "januari", "februari", "maart", "april", "mei", "juni", "juli", "augustus", "september", "oktober", "november", "december" }

local function file() return DataStorage:getSettingsDir() .. "/keesstudy-radio.json" end
local cache
function R.data()
    if cache then return cache end
    local f = io.open(file(), "rb")
    if f then
        local ok, d = pcall(require("ks_json").decode, f:read("*a"))
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
    f:write(require("ks_json").encode(d))
    f:close()
    os.rename(file() .. ".tmp", file())
end

local ENT = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }

--- OCR-tekst van één bericht netjes maken: kopregels weg, afgebroken woorden aan elkaar.
function R.clean(xml)
    local lines = {}
    for p in xml:gmatch("<p>(.-)</p>") do
        p = p:gsub("&(%w+);", function(e) return ENT[e] or " " end):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
        local low = p:lower()
        local skip = p == "" or low:match("^red%.?") or low:match("^datum") or low:match("^tijd") or low:match("derwerp")
            or low:match("^bron") or low:match("^regels") or p:match("^[%d%s%.%-,:]+$") or #p <= 3
        if not skip then lines[#lines + 1] = p end
    end
    -- korte kopregels bovenaan (dienst, tijd, "Headlines") overslaan tot de eerste echte zin
    while #lines > 0 and #lines[1] < 35 do table.remove(lines, 1) end
    -- regels samenvoegen tot alinea's: een regel die eindigt op een punt sluit een alinea af
    local paras, cur = {}, ""
    for _, l in ipairs(lines) do
        if cur:match("%-$") then cur = cur:sub(1, -2) .. l
        elseif cur == "" then cur = l
        else cur = cur .. " " .. l end
        if l:match("[%.!?]$") and #cur > 60 then paras[#paras + 1] = cur; cur = "" end
    end
    if #cur > 40 then paras[#paras + 1] = cur end
    -- de eerste regel is vaak de dienst en de tijd ("Bunte. 18-11-51 8.30 Headlines"): alleen bewaren als het echte tekst is
    if paras[1] and #paras[1] < 50 then table.remove(paras, 1) end
    return paras
end

local function urn(y, m, d, n) return ("anp:%04d:%02d:%02d:%d:mpeg21:ocr"):format(y, m, d, n) end

local UA = { ["User-Agent"] = "KeesStudy/1.0 (Kobo e-reader, persoonlijk gebruik)" }
local BACK = { 80, 75, 70, 85, 60 }

--- Vandaag ophalen in stappen: één bericht per stap. 80 jaar geleden, of 75, 70, 85 of 60 als die dag ontbreekt.
--- Geeft een functie die true teruggeeft zolang er nog een bericht komt (zie ks_net.background).
function R.stepper()
    local Net = require("ks_net")
    local t = os.date("*t")
    local today = os.date("%Y-%m-%d")
    local bi, n, misses, items = 1, 1, 0, {}
    local finished = not R.due()
    return function()
        if finished then return false end
        local y = t.year - BACK[bi]
        local ok, body, code = Net.get(R.BASE .. urn(y, t.month, t.day, n), UA)
        -- geen verbinding (geen antwoord van de server): stoppen zonder iets op te slaan, de volgende ronde probeert het opnieuw
        if not ok and not code then finished = true; return false end
        if ok and body:find("<text") then
            misses = 0
            local paras = R.clean(body)
            if #paras > 0 then items[#items + 1] = { n = n, paras = paras } end
        else
            misses = misses + 1
        end
        n = n + 1
        if misses < 2 and n <= R.MAX then return true end
        -- deze dag klaar
        if #items > 0 then
            save({ date = today, year = y, back = BACK[bi], items = items, at = os.time() })
            finished = true
            return false
        end
        bi, n, misses = bi + 1, 1, 0
        if bi > #BACK then
            save({ date = today, items = {}, at = os.time() })
            finished = true
            return false
        end
        return true
    end
end

--- In één keer (als je zelf op Ophalen tikt).
function R.fetchNow()
    local step = R.stepper()
    while step() do end
    local d = R.data()
    if d.items and #d.items > 0 then return true end
    return false, "Geen radioberichten gevonden voor deze dag."
end

function R.due() local d = R.data(); return d.date ~= os.date("%Y-%m-%d") end

function R.summary()
    local d = R.data()
    if d.date == os.date("%Y-%m-%d") and d.items and #d.items > 0 then
        return #d.items .. " berichten van " .. os.date("%d", os.time()):gsub("^0", "") .. " " .. MONTHS[tonumber(os.date("%m"))] .. " " .. d.year
    end
    return "ANP-berichten van precies 80 jaar geleden"
end

--- Als stuk in de eigen lezer openen.
function R.open(app)
    local d = R.data()
    local t = os.date("*t")
    local blocks = {}
    for _, it in ipairs(d.items or {}) do
        blocks[#blocks + 1] = { k = "h3", t = "Bericht " .. it.n }
        for _, p in ipairs(it.paras) do blocks[#blocks + 1] = { k = "p", t = p } end
    end
    blocks[#blocks + 1] = { k = "p", t = "Bron: ANP Radiobulletins, Koninklijke Bibliotheek (Delpher). De tekst is automatisch van de typoscripten gelezen, dus er zitten leesfouten in." }
    app.rdDoc = { id = "radio-" .. (d.year or 0) .. "-" .. t.month .. "-" .. t.day, title = "Radionieuws van " .. t.day .. " " .. MONTHS[t.month] .. " " .. (d.year or ""),
        kind = "Radionieuws", blocks = blocks }
    app.rdPages = nil
    app:go(require("ks_reader").page)
end

--- Vanuit het menu: meteen lezen als het er al is, anders eerst ophalen.
function R.start(app)
    local d = R.data()
    if d.date == os.date("%Y-%m-%d") and d.items and #d.items > 0 then return R.open(app) end
    app.radioMsg = nil
    app:go(R.page)
end

function R.page(app)
    local W = UI.INNER()
    local items = { UI.header("Radionieuws van deze dag", function() app:back() end, "ANP, precies 80 jaar geleden") }
    table.insert(items, UI.text(app.radioMsg or "De berichten van vandaag worden opgehaald zodra er wifi is.", { size = 19, width = W }))
    return UI.page(UI.vgroup(items), UI.button("Nu ophalen", function()
        app.radioMsg = "Even geduld, dit zijn tot 40 losse berichten..."
        app:refresh()
        require("ks_net").online(function()
            local ok, err = R.fetchNow()
            app.radioMsg = ok and nil or err
            if ok then app:back(); R.open(app) else app:refresh() end
        end)
    end, { width = W, primary = true }))
end

return R
