-- Gisteren in de Kamer: de besluiten van de laatste stemmingen in de Tweede Kamer,
-- met per motie, amendement of wet de uitslag en welke fracties voor en tegen stemden.
-- Bron: open data van de Tweede Kamer (OData, zonder inloggen, CC-0).

local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local UI = require("ks_ui")

local K = {}

K.BASE = os.getenv("KEES_STUDY_TK_URL") or "https://gegevensmagazijn.tweedekamer.nl/OData/v4/2.0/"

local function str(v) return type(v) == "string" and v or nil end
local function num(v) return type(v) == "number" and v or nil end

local function file() return DataStorage:getSettingsDir() .. "/keesstudy-kamer.json" end
local cache
function K.data()
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

local function enc(s) return (s:gsub("[^%w%-%._~%(%)%$=&/,:;%?]", function(c) return ("%%%02X"):format(c:byte()) end)) end

local function get(path)
    local ok, body, code = require("ks_net").get(K.BASE .. enc(path), { Accept = "application/json;odata.metadata=none" })
    if not ok then return nil, body end
    local good, j = pcall(require("json").decode, body)
    if not good or type(j) ~= "table" then return nil, "Onverwacht antwoord van de Tweede Kamer." end
    return j
end

--- Zet de ruwe besluiten om in een korte lijst.
function K.digest(act)
    local out = {}
    local agenda = type(act.Agendapunt) == "table" and act.Agendapunt or {}
    table.sort(agenda, function(a, b) return (num(a.Volgorde) or 0) < (num(b.Volgorde) or 0) end)
    for _, ap in ipairs(agenda) do
        if ap.Verwijderd ~= true then
            local besluiten = type(ap.Besluit) == "table" and ap.Besluit or {}
            table.sort(besluiten, function(a, b) return (num(a.AgendapuntZaakBesluitVolgorde) or 0) < (num(b.AgendapuntZaakBesluitVolgorde) or 0) end)
            for _, b in ipairs(besluiten) do
                local tekst = str(b.BesluitTekst) or ""
                if b.Verwijderd ~= true and tekst ~= "" then
                    local zaak = type(b.Zaak) == "table" and b.Zaak[1] or nil
                    local soort = zaak and str(zaak.Soort) or nil
                    local titel = zaak and (str(zaak.Onderwerp) or str(zaak.Titel)) or str(ap.Onderwerp) or "Besluit"
                    local voor, tegen = {}, {}
                    local nv, nt = 0, 0
                    for _, s in ipairs(type(b.Stemming) == "table" and b.Stemming or {}) do
                        if s.Verwijderd ~= true and s.Vergissing ~= true then
                            local fr = str(s.ActorFractie) or str(s.ActorNaam) or "?"
                            local n = num(s.FractieGrootte) or 1
                            if s.Soort == "Voor" then voor[fr] = (voor[fr] or 0) + n; nv = nv + n
                            elseif s.Soort == "Tegen" then tegen[fr] = (tegen[fr] or 0) + n; nt = nt + n end
                        end
                    end
                    local function list(t)
                        local l = {}
                        for k, v in pairs(t) do table.insert(l, { k, v }) end
                        table.sort(l, function(x, y) return x[2] > y[2] or (x[2] == y[2] and x[1] < y[1]) end)
                        local names = {}
                        for _, x in ipairs(l) do table.insert(names, x[1]) end
                        return table.concat(names, ", ")
                    end
                    -- alleen echte uitslagen, geen procedurebesluiten zonder zaak
                    if soort or nv + nt > 0 then
                        table.insert(out, {
                            soort = soort, titel = titel, uitslag = tekst:gsub("%.$", ""),
                            voor = list(voor), tegen = list(tegen), nv = nv, nt = nt,
                            nummer = zaak and str(zaak.Nummer) or nil,
                        })
                    end
                end
            end
        end
    end
    return out
end

local SEL = "$expand=Agendapunt($select=Id,Onderwerp,Volgorde,Verwijderd;$expand=Besluit($select=BesluitTekst,AgendapuntZaakBesluitVolgorde,Verwijderd;$expand=Stemming($select=Soort,ActorNaam,ActorFractie,FractieGrootte,Vergissing,Verwijderd),Zaak($select=Soort,Onderwerp,Titel,Nummer)))"
local PLAIN = "$expand=Agendapunt($expand=Besluit($expand=Stemming,Zaak))"

local PRIO = { Wetgeving = 1, Initiatiefwetgeving = 1, Begroting = 2, Amendement = 3 }

function K.fetchNow()
    local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local q1, err = get("Activiteit?$filter=Verwijderd eq false and Soort eq 'Stemmingen' and Datum le " .. now .. "&$orderby=Datum desc&$top=3&$select=Id,Datum")
    if not q1 then return false, err end
    local acts = type(q1.value) == "table" and q1.value or {}
    if #acts == 0 then return false, "Geen stemmingen gevonden." end
    -- de laatste stemmingen kunnen nog leeg zijn (gepland, nog niet verwerkt): neem de eerste met besluiten
    for _, act in ipairs(acts) do
        if str(act.Id) then
            local full = get("Activiteit(" .. act.Id .. ")?" .. SEL)
            if not full then full, err = get("Activiteit(" .. act.Id .. ")?" .. PLAIN) end
            if not full then return false, err end
            local items = K.digest(full)
            if #items > 0 then
                for i, it in ipairs(items) do it.i = i end
                table.sort(items, function(a, b)
                    local pa, pb = PRIO[a.soort or ""] or 9, PRIO[b.soort or ""] or 9
                    if pa ~= pb then return pa < pb end
                    return a.i < b.i
                end)
                save({ at = os.time(), datum = str(act.Datum) and act.Datum:sub(1, 10) or nil, items = items })
                return true
            end
        end
    end
    save({ at = os.time(), datum = str(acts[1].Datum) and acts[1].Datum:sub(1, 10) or nil, items = {} })
    return true
end

--- Elke zes uur hooguit één keer, als onderdeel van de krantenronde.
function K.due()
    if not require("ks_store").get("kamer.on", true) then return false end
    local at = K.data().at
    return not at or os.time() - at > 6 * 3600
end

function K.refresh(done)
    require("ks_net").online(function()
        local ok, err = K.fetchNow()
        done(ok, err)
    end, { onFail = function(msg) done(false, msg) end })
end

local MONTHS = { "januari", "februari", "maart", "april", "mei", "juni", "juli", "augustus", "september", "oktober", "november", "december" }
local DAYS = { "zondag", "maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag" }
function K.dateText(d)
    if not d then return "" end
    local y, m, dd = d:match("(%d+)-(%d+)-(%d+)")
    if not y then return d end
    local ts = os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12 }
    return DAYS[tonumber(os.date("%w", ts)) + 1] .. " " .. tonumber(dd) .. " " .. MONTHS[tonumber(m)]
end

function K.summary()
    local d = K.data()
    if not d.items then return "Nog niet opgehaald" end
    local aan = 0
    for _, it in ipairs(d.items) do if it.uitslag:lower():find("aangenomen") then aan = aan + 1 end end
    return ("%s · %d besluiten, %d aangenomen"):format(K.dateText(d.datum), #d.items, aan)
end

function K.page(app)
    local W = UI.INNER()
    local d = K.data()
    local items = { UI.header("In de Kamer", function() app.kamerPg = nil; app.kamerMsg = nil; app:back() end,
        d.items and ("Stemmingen van " .. K.dateText(d.datum) .. " · Tweede Kamer") or "De laatste stemmingen in de Tweede Kamer") }
    local blocks = {}
    for _, it in ipairs(d.items or {}) do
        local aangenomen = it.uitslag:lower():find("aangenomen") ~= nil
        local g = {
            UI.hgroup({
                aangenomen and require("ui/widget/container/framecontainer"):new{ background = UI.BLACK, bordersize = 0, radius = UI.px(6),
                    padding = 0, padding_left = UI.px(8), padding_right = UI.px(8), padding_top = UI.px(2), padding_bottom = UI.px(2),
                    UI.text(it.uitslag, { font = "bold", size = 16, color = UI.WHITE, bg = UI.BLACK }) }
                    or UI.text(it.uitslag, { font = "bold", size = 16 }),
                UI.hspace(10),
                UI.text((it.soort or "Besluit") .. ((it.nv + it.nt) > 0 and ("  ·  " .. it.nv .. " voor, " .. it.nt .. " tegen") or ""), { size = 15, color = UI.INK2 }),
            }),
            UI.vspace(4),
            UI.text(it.titel, { size = 19, font = "medium", width = W, height = UI.px(80) }),
        }
        if it.voor ~= "" then table.insert(g, UI.text("Voor: " .. it.voor, { size = 15, color = UI.INK2, width = W, height = UI.px(42) })) end
        if it.tegen ~= "" then table.insert(g, UI.text("Tegen: " .. it.tegen, { size = 15, color = UI.INK2, width = W, height = UI.px(42) })) end
        table.insert(g, UI.vspace(12))
        table.insert(g, UI.line(W))
        table.insert(g, UI.vspace(12))
        table.insert(blocks, UI.vgroup(g))
    end
    if #blocks == 0 then
        table.insert(items, UI.text(d.items and "Bij de laatste stemmingen zijn geen besluiten gevonden." or "Nog niets opgehaald. Tik op Ophalen.", { size = 19, width = W }))
    end
    if app.kamerMsg then table.insert(items, UI.text(app.kamerMsg, { size = 17, font = "bold", width = W })) end
    -- bladzijden
    local head = UI.vgroup(items)
    local avail = UI.H() - UI.px(UI.TOPPAD) - head:getSize().h - UI.px(60 + 50)
    local pages, cur, used = {}, {}, 0
    for _, bl in ipairs(blocks) do
        local h = bl:getSize().h
        if used + h > avail and #cur > 0 then table.insert(pages, cur); cur, used = {}, 0 end
        table.insert(cur, bl); used = used + h
    end
    if #cur > 0 then table.insert(pages, cur) end
    local pg = math.max(1, math.min(app.kamerPg or 1, #pages))
    for _, bl in ipairs(pages[pg] or {}) do table.insert(items, bl) end
    local np = math.max(1, #pages)
    local footer = UI.buttonRow({
        { "Ophalen", function()
            app.kamerMsg = "Bezig met ophalen..."
            app:refresh()
            UIManager:scheduleIn(0.2, function()
                K.refresh(function(ok, err)
                    if ok then app.kamerMsg = nil else app.kamerMsg = "Ophalen mislukt: " .. tostring(err) end
                    app.kamerPg = 1
                    app:refresh()
                end)
            end)
        end, small = true },
        { "Vorige", function() app.kamerPg = pg - 1; app:refresh() end, small = true, disabled = pg <= 1 },
        { np > 1 and ("Verder " .. pg .. "/" .. np) or "Verder", function() app.kamerPg = pg + 1; app:refresh() end, small = true, primary = pg < np, disabled = pg >= np },
    })
    return UI.page(UI.vgroup(items), footer)
end

return K
