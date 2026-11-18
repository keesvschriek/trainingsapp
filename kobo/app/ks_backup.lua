-- Back-up van de hele Kobo in je eigen Supabase: leerlijnen, schaken, quiz, gewoontes,
-- dag afsluiten, instellingen. Eén keer per dag, mee met de synchronisatie.
-- Geheimen gaan er niet in: de sleutel van intervals.icu, je roosterlink en de koppeling zelf.
-- Na een reset of op een nieuwe Kobo: koppelen, dan Terugzetten.

local Store = require("ks_store")
local Sync = require("ks_sync")

local B = {}

-- nooit naar de cloud, en bij terugzetten nooit overschrijven
B.SECRET = { ["sync.cfg"] = true, ["sport.key"] = true, ["rooster.url"] = true }
-- buffers die toch opnieuw worden opgehaald
B.SKIP = { ["sport.cache"] = true, ["lichess.puzzle"] = true, ["read.meta"] = true, ["read.at"] = true, ["backup.cloud"] = true, ["ws.game"] = true }

function B.snapshot()
    local data = Store.open().data or {}
    local out = {}
    for k, v in pairs(data) do
        if not B.SECRET[k] and not B.SKIP[k] and not tostring(k):find("cache") then out[k] = v end
    end
    return out
end

local function serialize(t) return require("dump")(t) end

--- Back-up maken en versturen. Geeft ok, bericht.
function B.push()
    local snap = B.snapshot()
    local lua = serialize(snap)
    local now = os.time()
    local row = { user_id = Sync.uid(), tbl = "kobo", id = "backup", updated_at = now * 1000, deleted = false,
        data = { v = 1, at = now, size = #lua, keys = 0, store = lua } }
    for _ in pairs(snap) do row.data.keys = row.data.keys + 1 end
    local ok, err = Sync.request("POST", "/rest/v1/records?on_conflict=user_id,tbl,id", Sync.json({ row }), "resolution=merge-duplicates,return=minimal")
    if not ok then return false, "Back-up mislukt: " .. tostring(err) end
    Store.set("backup.cloud", { at = now, size = #lua, keys = row.data.keys })
    return true, "Back-up gemaakt (" .. math.floor(#lua / 1024) .. " kB)"
end

function B.last() return Store.get("backup.cloud") end

function B.daily()
    if not Sync.connected() then return end
    local l = B.last()
    if l and os.date("%Y-%m-%d", l.at) == os.date("%Y-%m-%d") then return end
    B.push()
end

--- Back-up ophalen. Geeft tabel {at, keys, store} of nil, bericht.
function B.fetch()
    local ok, body = Sync.request("GET", "/rest/v1/records?select=data,updated_at&tbl=eq.kobo&id=eq.backup")
    if not ok then return nil, "Ophalen mislukt: " .. tostring(body) end
    local rows = Sync.decode(body)
    local d = type(rows) == "table" and rows[1] and rows[1].data
    if type(d) ~= "table" or type(d.store) ~= "string" then return nil, "Er is nog geen back-up in de cloud." end
    return d
end

--- Terugzetten: alles uit de back-up over de huidige gegevens heen, behalve de geheimen.
function B.restore(d)
    local fn = loadstring("return " .. d.store)
    if not fn then return false, "Back-up is niet leesbaar." end
    setfenv(fn, {})
    local ok, t = pcall(fn)
    if not ok or type(t) ~= "table" then return false, "Back-up is niet leesbaar." end
    local n = 0
    for k, v in pairs(t) do
        if not B.SECRET[k] then Store.set(k, v); n = n + 1 end
    end
    Store.flush()
    return true, n .. " onderdelen teruggezet"
end

-- Scherm ------------------------------------------------------------------------------------

function B.page(app)
    local UI = require("ks_ui")
    local W = UI.INNER()
    local items = { UI.header("Back-up in de cloud", function() app:back() end, "In je eigen Supabase, één keer per dag") }
    local l = B.last()
    table.insert(items, UI.card(UI.text(l and ("Laatste back-up: " .. os.date("%d-%m %H:%M", l.at) .. ", " .. (l.keys or 0) .. " onderdelen, " .. math.floor((l.size or 0) / 1024) .. " kB")
        or "Nog geen back-up gemaakt. Dat gebeurt vanzelf bij de eerstvolgende synchronisatie.", { size = 18, width = W - UI.px(40) })))
    table.insert(items, UI.vspace(14))
    table.insert(items, UI.text("Mee: leerlijnen, leerkaarten, quiz, schaken, gewoontes, dag afsluiten, opgeslagen leesposities en instellingen. Niet mee: de sleutel van intervals.icu, je roosterlink en de koppeling met de telefoon. Die zet je na een reset opnieuw.", { size = 16, color = UI.INK2, width = W }))
    if app.bkMsg then
        table.insert(items, UI.vspace(14))
        table.insert(items, UI.text(app.bkMsg, { size = 18, font = "medium", width = W }))
    end
    if not Sync.connected() then
        table.insert(items, UI.vspace(14))
        table.insert(items, UI.text("Koppel eerst de telefoon-app (Instellingen, Telefoon-app).", { size = 18, width = W }))
        return UI.page(UI.vgroup(items))
    end
    return UI.page(UI.vgroup(items), UI.buttonRow({
        { "Terugzetten", function()
            require("ks_net").online(function()
                local d, err = B.fetch()
                if not d then app.bkMsg = err; app:refresh(); return end
                app.bkFound = d
                app:go(B.confirm)
            end)
        end },
        { "Nu back-up maken", function()
            require("ks_net").online(function()
                local ok, msg = B.push()
                app.bkMsg = msg
                app:refresh()
            end)
        end, primary = true },
    }))
end

function B.confirm(app)
    local UI = require("ks_ui")
    local W = UI.INNER()
    local d = app.bkFound
    local items = { UI.header("Terugzetten?", function() app:back() end) }
    table.insert(items, UI.text(("Back-up van %s, %d onderdelen. Wat nu op deze Kobo staat aan voortgang wordt vervangen door de back-up. Daarna start de app opnieuw."):format(os.date("%d-%m-%Y %H:%M", d.at or 0), d.keys or 0), { size = 19, width = W }))
    return UI.page(UI.vgroup(items), UI.buttonRow({
        { "Annuleren", function() app:back() end },
        { "Terugzetten", function()
            local ok, msg = B.restore(d)
            if ok then app:restart() else app.bkMsg = msg; app:back() end
        end, primary = true },
    }))
end

return B
