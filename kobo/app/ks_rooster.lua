-- Rooster uit Zermelo, via je eigen iCal-link (alleen lezen).
--
-- Privacy: de link staat alleen op deze Kobo. Van elke afspraak bewaren we alleen
-- begin, eind, de korte titel (vak en klas) en het lokaal, voor de komende 7 dagen.
-- Beschrijvingen, opmerkingen en deelnemers worden niet bewaard.

local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local Store = require("ks_store")
local UI = require("ks_ui")

local R = {}

R.DAYS = 9 -- ook zondag nog de hele volgende week

local function file() return DataStorage:getSettingsDir() .. "/keesstudy-rooster.json" end
local cache
function R.data()
    if cache then return cache end
    local f = io.open(file(), "rb")
    if f then
        local ok, d = pcall(require("json").decode, f:read("*a"))
        f:close()
        if ok and type(d) == "table" then cache = d end
    end
    cache = cache or {}
    if type(cache.events) ~= "table" then cache.events = {} end
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

function R.url() local u = Store.get("rooster.url"); return type(u) == "string" and u ~= "" and u or nil end
function R.connected() return R.url() ~= nil end

-- iCal ------------------------------------------------------------------------------------

local function unescape(s)
    return (s:gsub("\\n", " "):gsub("\\N", " "):gsub("\\,", ","):gsub("\\;", ";"):gsub("\\\\", "\\"))
end

-- os.time leest velden als lokale wintertijd; dit is het verschil met UTC
local function stdOffset(g) return g - os.time(os.date("!*t", g)) end

--- "20261116T081500Z", "20261116T081500" of "20261116" -> tijdstip (lokaal)
function R.parseTime(v)
    local y, mo, d, h, mi, s, z = v:match("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)(Z?)")
    if not y then
        y, mo, d = v:match("^(%d%d%d%d)(%d%d)(%d%d)")
        if not y then return nil end
        return os.time{ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 0 }, true
    end
    local t = { year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) }
    if z == "Z" then
        t.isdst = false
        local guess = os.time(t)
        return guess + stdOffset(guess)
    end
    t.isdst = nil
    return os.time(t)
end

--- Alleen wat we nodig hebben. from/to: tijdvenster.
function R.parse(text, from, to)
    text = text:gsub("\r\n", "\n"):gsub("\n[ \t]", "")
    local out = {}
    for block in text:gmatch("BEGIN:VEVENT\n(.-)END:VEVENT") do
        local ev = {}
        for line in block:gmatch("[^\n]+") do
            local key, params, val = line:match("^([A-Z%-]+)([^:]*):(.*)$")
            if key == "DTSTART" then ev.s, ev.allday = R.parseTime(val)
            elseif key == "DTEND" then ev.e = R.parseTime(val)
            elseif key == "SUMMARY" then ev.what = unescape(val)
            elseif key == "LOCATION" then ev.where = unescape(val)
            elseif key == "STATUS" and val:upper():find("CANCEL") then ev.cancelled = true end
        end
        if ev.s and ev.s >= from and ev.s < to then
            ev.what = (ev.what or "Afspraak"):sub(1, 80)
            if ev.where then ev.where = ev.where:sub(1, 40) end
            if ev.what:lower():find("vervallen") or ev.what:lower():find("uitval") then ev.cancelled = true end
            table.insert(out, { s = ev.s, e = ev.e or ev.s, what = ev.what, where = ev.where ~= "" and ev.where or nil, x = ev.cancelled or nil, d = ev.allday or nil })
        end
    end
    table.sort(out, function(a, b) return a.s < b.s end)
    return out
end

local function dayStart(ts)
    local t = os.date("*t", ts)
    return os.time{ year = t.year, month = t.month, day = t.day, hour = 0 }
end

function R.fetchNow()
    local url = R.url()
    if not url then return false, "Nog geen link ingesteld." end
    url = url:gsub("^webcal://", "https://")
    local ok, body = require("ks_net").get(url)
    if not ok then return false, body end
    if not body:find("BEGIN:VCALENDAR") then return false, "Dit lijkt geen agenda-link." end
    local from = dayStart(os.time())
    local events = R.parse(body, from, from + R.DAYS * 86400)
    save({ at = os.time(), events = events })
    return true
end

function R.refresh(done)
    require("ks_net").online(function()
        local ok, err = R.fetchNow()
        done(ok, err)
    end, { onFail = function(msg) done(false, msg) end })
end

--- Eens per 3 uur mee met de krantenronde.
function R.due()
    if not R.connected() then return false end
    local at = R.data().at
    return not at or os.time() - at > 3 * 3600 or os.date("%Y%m%d", at) ~= os.date("%Y%m%d")
end

function R.forDay(ts)
    local a = dayStart(ts)
    local out = {}
    for _, ev in ipairs(R.data().events) do
        if type(ev.s) == "number" and ev.s >= a and ev.s < a + 86400 then table.insert(out, ev) end
    end
    return out
end

local function hm(ts) return os.date("%H:%M", ts) end

--- Korte regel voor het startscherm: wat is nu of hierna.
function R.next()
    if not R.connected() then return nil end
    local now = os.time()
    for _, ev in ipairs(R.data().events) do
        if not ev.d and not ev.x and type(ev.e) == "number" and ev.e > now then
            local where = ev.where and (", " .. ev.where) or ""
            if ev.s <= now then return "Nu: " .. ev.what .. where .. " tot " .. hm(ev.e) end
            local day = os.date("%Y%m%d", ev.s) == os.date("%Y%m%d", now) and "" or
                (os.date("%Y%m%d", ev.s) == os.date("%Y%m%d", now + 86400) and "morgen " or (require("ks_main").dateText(ev.s):match("^(%S+)") .. " "))
            return "Hierna: " .. day .. hm(ev.s) .. " " .. ev.what .. where
        end
    end
    return R.data().at and "Geen lessen meer deze week" or nil
end

-- Schermen --------------------------------------------------------------------------------

function R.page(app)
    local W = UI.INNER()
    local d = R.data()
    local off = app.roosterDay or 0
    local ts = os.time() + off * 86400
    local title = off == 0 and "Vandaag" or (off == 1 and "Morgen" or require("ks_main").dateText(ts))
    local items = { UI.header("Rooster", function() app.roosterDay = nil; app.roosterMsg = nil; app:back() end,
        title .. (d.at and (" · bijgewerkt " .. os.date("%H:%M", d.at)) or "")) }
    if off <= 1 then table.insert(items, UI.text(require("ks_main").dateText(ts), { size = 19, font = "medium", color = UI.INK2 })) end
    table.insert(items, UI.vspace(10))
    local list = R.forDay(ts)
    if not R.connected() then
        table.insert(items, UI.text("Nog geen rooster gekoppeld. Ga naar Instellingen, Rooster.", { size = 19, width = W }))
    elseif #list == 0 then
        table.insert(items, UI.text(d.at and "Geen lessen of afspraken." or "Nog niet opgehaald. Tik op Ophalen.", { size = 19, color = UI.INK2, width = W }))
    end
    local now = os.time()
    for _, ev in ipairs(list) do
        local isNow = ev.s <= now and ev.e > now
        local timeW = UI.px(130)
        local left = UI.text(ev.d and "Hele dag" or (hm(ev.s) .. "\n" .. hm(ev.e)), { size = 17, font = isNow and "bold" or "medium", color = (ev.e < now) and UI.INK3 or UI.BLACK, width = timeW })
        local right = UI.vgroup({
            UI.text(ev.what .. (ev.x and "  (vervalt)" or ""), { size = 21, font = "medium", color = (ev.x or ev.e < now) and UI.INK3 or UI.BLACK, width = W - timeW, height = UI.px(60) }),
            ev.where and UI.text(ev.where, { size = 16, color = UI.INK2 }) or UI.vspace(0),
        })
        table.insert(items, UI.hgroup({ left, right }, "top"))
        table.insert(items, UI.vspace(10))
        table.insert(items, UI.line(W, isNow and UI.BLACK or nil, isNow and UI.px(2) or nil))
        table.insert(items, UI.vspace(10))
    end
    if app.roosterMsg then table.insert(items, UI.text(app.roosterMsg, { size = 17, font = "bold", width = W })) end
    local footer = UI.buttonRow({
        { "Ophalen", function()
            app.roosterMsg = "Bezig met ophalen..."
            app:refresh()
            UIManager:scheduleIn(0.2, function()
                R.refresh(function(ok, err)
                    app.roosterMsg = (not ok) and ("Ophalen mislukt: " .. tostring(err)) or nil
                    app:refresh()
                end)
            end)
        end, small = true, disabled = not R.connected() },
        { "Vorige", function() app.roosterDay = off - 1; app:refresh() end, small = true, disabled = off <= 0 },
        { "Volgende", function() app.roosterDay = off + 1; app:refresh() end, small = true, primary = true, disabled = off >= R.DAYS - 1 },
    })
    return UI.page(UI.vgroup(items), footer)
end

-- Een lange link typen op e-ink is lastig. Daarom kan hij ook uit een tekstbestand komen dat je
-- via USB in de hoofdmap van de Kobo zet. Na het inlezen wordt het bestand gewist.
R.LINKFILE = os.getenv("KEES_STUDY_LINKFILE") or "/mnt/onboard/rooster-link.txt"

function R.importFile()
    local f = io.open(R.LINKFILE, "rb")
    if not f then return false, "Geen bestand rooster-link.txt gevonden in de hoofdmap van de Kobo." end
    local t = (f:read("*a") or ""):gsub("^\239\187\191", ""):gsub("%s", "")
    f:close()
    os.remove(R.LINKFILE)
    if not (t:match("^https://") or t:match("^webcal://") or (os.getenv("KS_TEST") and t:match("^http://"))) then return false, "In het bestand staat geen geldige link. Het bestand is gewist." end
    Store.set("rooster.url", t)
    save({ events = {} })
    return true
end

local function askLink(app)
    local InputDialog = require("ui/widget/inputdialog")
    local dlg
    dlg = InputDialog:new{
        title = "Plak of typ je iCal-link uit Zermelo",
        input = "",
        buttons = { {
            { text = "Annuleren", id = "close", callback = function() UIManager:close(dlg) end },
            { text = "Bewaren", is_enter_default = true, callback = function()
                local t = (dlg:getInputText() or ""):gsub("%s", "")
                UIManager:close(dlg)
                if t:match("^https://") or t:match("^webcal://") then
                    Store.set("rooster.url", t)
                    save({ events = {} })
                    app.roosterMsg = "Link bewaard. Tik op Nu ophalen."
                else
                    app.roosterMsg = "Dat is geen geldige link (hij moet beginnen met https:// of webcal://)."
                end
                app:refresh()
            end },
        } },
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function R.settings(app)
    local W = UI.INNER()
    local items = { UI.header("Rooster", function() app.roosterMsg = nil; app:back() end, "Je lesrooster uit Zermelo, alleen lezen") }
    local on = R.connected()
    table.insert(items, UI.text(on and "Gekoppeld. De link staat alleen op deze Kobo." or "Nog niet gekoppeld.", { size = 20, font = "medium", width = W }))
    table.insert(items, UI.vspace(12))
    table.insert(items, UI.text("Zo koppel je: maak in de Zermelo WebApp onder Instellingen een iCal-link. Tik op Vanaf je telefoon, scan de QR-code en plak de link. Via USB (bestand rooster-link.txt in de hoofdmap) of overtypen kan ook.", { size = 17, color = UI.INK2, width = W }))
    table.insert(items, UI.vspace(12))
    table.insert(items, UI.card(UI.text("Van elke les bewaart de Kobo alleen de tijd, de titel en het lokaal, voor de komende 7 dagen. Opmerkingen en deelnemers worden weggegooid. Staat er een naam in de titel van een afspraak, dan zie je die wel. Lekt de link uit, maak dan in Zermelo een nieuwe en wis deze.",
        { size = 16, width = W - UI.px(44), bg = UI.FILL }), { fill = true, border = 0 }))
    table.insert(items, UI.vspace(16))
    if app.roosterMsg then
        table.insert(items, UI.text(app.roosterMsg, { size = 17, font = "bold", width = W }))
        table.insert(items, UI.vspace(10))
    end
    table.insert(items, UI.button("Vanaf je telefoon", function()
        app.roosterMsg = "Even wifi aanzetten..."
        app:refresh()
        require("ks_relay").open(app, {
            title = "Roosterlink voor de Kobo",
            hint = "Plak hier je iCal-link uit de Zermelo WebApp (Instellingen).",
            label = "iCal-link",
            onSubmit = function(t)
                t = t:gsub("%s", "")
                if not (t:match("^https://") or t:match("^webcal://") or (os.getenv("KS_TEST") and t:match("^http://"))) then
                    return false, "Dit is geen geldige link. Hij moet beginnen met https:// of webcal://."
                end
                Store.set("rooster.url", t)
                save({ events = {} })
                app.roosterMsg = nil
                return true, "De roosterlink is bewaard. Tik op de Kobo op Klaar en daarna op Nu ophalen."
            end,
        }, function(err) app.roosterMsg = err; app:refresh() end)
    end, { width = W, primary = not on, icon = "wifi" }))
    table.insert(items, UI.vspace(12))
    table.insert(items, UI.buttonRow({
        { "Link uit bestand", function()
            local ok, err = R.importFile()
            app.roosterMsg = ok and "Link bewaard en bestand gewist. Tik op Nu ophalen." or err
            app:refresh()
        end },
        { "Overtypen", function() askLink(app) end },
    }))
    table.insert(items, UI.vspace(12))
    table.insert(items, UI.buttonRow({
        { "Nu ophalen", function()
            app.roosterMsg = "Bezig met ophalen..."
            app:refresh()
            UIManager:scheduleIn(0.2, function()
                R.refresh(function(ok, err)
                    local n = #R.data().events
                    app.roosterMsg = ok and ("Opgehaald: " .. n .. " lessen en afspraken deze week.") or ("Ophalen mislukt: " .. tostring(err))
                    app:refresh()
                end)
            end)
        end, disabled = not on },
    }))
    table.insert(items, UI.vspace(12))
    table.insert(items, UI.buttonRow({
        { "Link en rooster wissen", function()
            Store.set("rooster.url", nil)
            save({ events = {} })
            app.roosterMsg = "Gewist."
            app:refresh()
        end, small = true, disabled = not on },
    }))
    return UI.page(UI.vgroup(items))
end

return R
