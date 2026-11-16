-- Koppeling met de telefoon-app (Kees Study) via Supabase: dezelfde tabel "records" als de app.
--
-- Eén keer koppelen: vanaf je telefoon stuur je het Supabase-adres, de openbare sleutel, je e-mail
-- en wachtwoord (versleuteld, via ks_relay). De Kobo logt in en bewaart alleen een sleutel om
-- ingelogd te blijven, nooit het wachtwoord. Daarna gaan wijzigingen heen en weer;
-- de nieuwste wijziging wint, net als in de app.

local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local Store = require("ks_store")
local UI = require("ks_ui")

local S = {}

-- Welke tabellen van de app de Kobo bijhoudt
S.TABLES = { workouts = true, checks = true, checkins = true, metrics = true, blocks = true }

local function cfg() local c = Store.get("sync.cfg"); return type(c) == "table" and c or nil end
function S.connected() local c = cfg(); return c ~= nil and type(c.refresh) == "string" end

local function file() return DataStorage:getSettingsDir() .. "/keesstudy-sync.json" end
local data
local function scrub(v)
    if type(v) == "function" then return nil end
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = scrub(x) end
    return out
end
function S.data()
    if data then return data end
    local f = io.open(file(), "rb")
    if f then
        local ok, d = pcall(require("json").decode, f:read("*a"))
        f:close()
        if ok and type(d) == "table" then data = scrub(d) end
    end
    data = data or {}
    data.rows = type(data.rows) == "table" and data.rows or {}
    data.dirty = type(data.dirty) == "table" and data.dirty or {}
    data.pending = type(data.pending) == "table" and data.pending or {}
    data.lastPull = type(data.lastPull) == "string" and data.lastPull or "1970-01-01T00:00:00Z"
    return data
end
local function save()
    local f = io.open(file() .. ".tmp", "wb")
    if not f then return end
    f:write(require("json").encode(S.data()))
    f:close()
    os.rename(file() .. ".tmp", file())
end

local function nowMs() return os.time() * 1000 end

-- Records -------------------------------------------------------------------------------

function S.get(tbl, id) local t = S.data().rows[tbl]; return t and t[id] or nil end

function S.list(tbl, pred)
    local out = {}
    for _, r in pairs(S.data().rows[tbl] or {}) do
        if not r.deleted and (not pred or pred(r)) then table.insert(out, r) end
    end
    return out
end

--- Lokaal opslaan en klaarzetten om te versturen.
function S.put(tbl, row)
    local d = S.data()
    row.updatedAt = nowMs()
    d.rows[tbl] = d.rows[tbl] or {}
    d.rows[tbl][row.id] = row
    d.dirty[tbl .. "|" .. row.id] = true
    save()
end

-- Netwerk -------------------------------------------------------------------------------

local token, tokenUntil
local function json(v) return require("json").encode(v) end
local function decode(s) local ok, v = pcall(require("json").decode, s); return ok and scrub(v) or nil end

local function auth(grant, body, c)
    local Net = require("ks_net")
    local ok, res = Net.request("POST", c.url .. "/auth/v1/token?grant_type=" .. grant,
        { apikey = c.key, ["Content-Type"] = "application/json" }, json(body))
    if not ok then
        local j = decode(res or "")
        return nil, j and (j.error_description or j.msg or j.error) or res
    end
    local j = decode(res)
    if not j or type(j.access_token) ~= "string" then return nil, "Onverwacht antwoord bij inloggen." end
    return j
end

--- Inloggen met e-mail en wachtwoord (alleen bij koppelen).
function S.link(url, key, email, password)
    url = url:gsub("%s", ""):gsub("/+$", "")
    key = key:gsub("%s", "")
    local c = { url = url, key = key }
    local j, err = auth("password", { email = email, password = password }, c)
    if not j then return false, err end
    c.email = email
    c.uid = type(j.user) == "table" and j.user.id or nil
    c.refresh = j.refresh_token
    Store.set("sync.cfg", c)
    Store.flush()
    token, tokenUntil = j.access_token, os.time() + (tonumber(j.expires_in) or 3600) - 60
    -- verse start: alles opnieuw ophalen
    data = { rows = {}, dirty = {}, pending = {}, lastPull = "1970-01-01T00:00:00Z" }
    save()
    return true
end

function S.unlink()
    Store.set("sync.cfg", nil)
    Store.flush()
    token, tokenUntil = nil, nil
    data = { rows = {}, dirty = {}, pending = {}, lastPull = "1970-01-01T00:00:00Z" }
    save()
end

local function ensureToken()
    local c = cfg()
    if not c then return nil, "Niet gekoppeld." end
    if token and os.time() < (tokenUntil or 0) then return token, c end
    local j, err = auth("refresh_token", { refresh_token = c.refresh }, c)
    if not j then return nil, "Opnieuw koppelen nodig (" .. tostring(err) .. ")." end
    -- de sleutel om ingelogd te blijven verandert elke keer: meteen bewaren
    c.refresh = j.refresh_token or c.refresh
    if type(j.user) == "table" and j.user.id then c.uid = j.user.id end
    Store.set("sync.cfg", c)
    Store.flush()
    token, tokenUntil = j.access_token, os.time() + (tonumber(j.expires_in) or 3600) - 60
    return token, c
end

local function enc(s) return (s:gsub("[^%w%-%._~]", function(ch) return ("%%%02X"):format(ch:byte()) end)) end

--- Heen en weer. Geeft ok, bericht.
function S.syncNow()
    local tok, c = ensureToken()
    if not tok then return false, c end
    local Net = require("ks_net")
    local d = S.data()
    local H = { apikey = c.key, Authorization = "Bearer " .. tok, ["Content-Type"] = "application/json" }
    -- eerst eventueel wachtende zwaarte/notities aan trainingen hangen
    S.attachPending()
    -- 1. omhoog
    local batch, keys = {}, {}
    for k in pairs(d.dirty) do
        local tbl, id = k:match("^([^|]+)|(.+)$")
        local row = tbl and S.get(tbl, id)
        if row then
            table.insert(batch, { user_id = c.uid, tbl = tbl, id = id, data = row, updated_at = row.updatedAt, deleted = row.deleted == true })
            table.insert(keys, k)
        else
            d.dirty[k] = nil
        end
    end
    local pushed = 0
    if #batch > 0 then
        local hp = {}
        for k, v in pairs(H) do hp[k] = v end
        hp.Prefer = "resolution=merge-duplicates,return=minimal"
        local ok, err = Net.request("POST", c.url .. "/rest/v1/records?on_conflict=user_id,tbl,id", hp, json(batch))
        if not ok then return false, "Versturen mislukt: " .. tostring(err) end
        for _, k in ipairs(keys) do d.dirty[k] = nil end
        pushed = #batch
    end
    -- 2. omlaag
    local pulled = 0
    for _ = 1, 40 do
        local ok, body = Net.request("GET", c.url .. "/rest/v1/records?select=tbl,id,data,updated_at,deleted,server_ts&server_ts=gt." .. enc(d.lastPull)
            .. "&order=server_ts.asc&limit=500", H)
        if not ok then save(); return false, "Ophalen mislukt: " .. tostring(body) end
        local rows = decode(body) or {}
        for _, r in ipairs(rows) do
            if S.TABLES[r.tbl] and type(r.id) == "string" and type(r.data) == "table" then
                d.rows[r.tbl] = d.rows[r.tbl] or {}
                local loc = d.rows[r.tbl][r.id]
                local up = tonumber(r.updated_at) or 0
                if not loc or (tonumber(loc.updatedAt) or 0) < up then
                    local row = r.data
                    row.updatedAt = up
                    row.deleted = r.deleted == true or nil
                    d.rows[r.tbl][r.id] = row
                    d.dirty[r.tbl .. "|" .. r.id] = nil
                    pulled = pulled + 1
                end
            end
            if type(r.server_ts) == "string" then d.lastPull = r.server_ts end
        end
        if #rows < 500 then break end
    end
    -- wat net binnenkwam kan wachtende notities alsnog laten passen
    S.attachPending()
    if next(d.dirty) and pushed == 0 then
        -- door attachPending nieuw klaargezet: meteen meesturen bij de volgende keer
    end
    d.at = os.time()
    save()
    return true, ("%d verstuurd, %d opgehaald"):format(pushed, pulled)
end

function S.due()
    if not S.connected() then return false end
    local d = S.data()
    return next(d.dirty) ~= nil or not d.at or os.time() - d.at > 30 * 60
end

function S.refresh(done)
    require("ks_net").online(function() done(S.syncNow()) end, { onFail = function(m) done(false, m) end })
end

--- Na een wijziging op de Kobo: versturen als er toch al wifi is, anders bij de volgende ronde.
function S.soon()
    if not S.connected() then return end
    if require("ks_net").isOn() then
        UIManager:scheduleIn(1, function() pcall(S.syncNow) end)
    end
end

-- Training en check-in ------------------------------------------------------------------

local function today() return os.date("%Y-%m-%d") end

function S.checkin(date) return S.get("checkins", "checkin-" .. (date or today())) end

function S.saveCheckin(v)
    local date = today()
    S.put("checkins", { id = "checkin-" .. date, date = date, sleep = v.sleep, legs = v.legs, energy = v.energy, calm = v.calm })
    S.soon()
end

--- slotId uit het intervals-event dat de telefoon-app zelf heeft aangemaakt.
function S.slotOf(ev)
    return type(ev) == "table" and type(ev.ext) == "string" and ev.ext:match("^trainingsapp%-%d%d%d%d%-%d%d%-%d%d%-(.+)$") or nil
end

local function kindOf(slotId, ev)
    if slotId == "test-cooper" or slotId == "test-10k" then return "run" end
    local t = (ev and ev.type or ""):lower()
    if t:find("run") then return "run" end
    if slotId:find("^run") or slotId:find("race") then return "run" end
    if slotId:find("strength") or slotId:find("kracht") or t:find("weight") or t == "kracht" then return "strength" end
    return "other"
end

function S.isDone(date, slotId)
    local c = S.get("checks", date .. ":" .. slotId)
    if c and c.done and not c.deleted then return true end
    for _, w in ipairs(S.list("workouts", function(w) return w.date == date and w.slotId == slotId end)) do
        if w then return true end
    end
    return false
end

--- Training afvinken. rpe (1-10) en notitie zijn optioneel.
function S.markDone(date, ev, rpe, notes)
    local slotId = S.slotOf(ev)
    if not slotId then return false end
    S.put("checks", { id = date .. ":" .. slotId, date = date, slotId = slotId, done = true })
    if rpe or (notes and notes ~= "") then
        local d = S.data()
        table.insert(d.pending, { date = date, slotId = slotId, kind = kindOf(slotId, ev), title = ev.name or "Training",
            rpe = rpe, notes = notes ~= "" and notes or nil, at = os.time() })
        save()
        S.attachPending()
    end
    S.soon()
    return true
end

function S.undo(date, ev)
    local slotId = S.slotOf(ev)
    if not slotId then return end
    S.put("checks", { id = date .. ":" .. slotId, date = date, slotId = slotId, done = false })
    S.soon()
end

--- Zwaarte en notitie aan de echte training hangen zodra die (via Garmin en intervals) in de app staat.
--- Na drie dagen zonder training maakt de Kobo zelf een training aan, zoals handmatig loggen in de app.
function S.attachPending()
    local d = S.data()
    local keep = {}
    for _, p in ipairs(d.pending) do
        local cands = S.list("workouts", function(w) return w.date == p.date and (w.slotId == p.slotId or (not w.slotId and w.kind == p.kind)) end)
        table.sort(cands, function(a, b) return (a.slotId == p.slotId and 0 or 1) < (b.slotId == p.slotId and 0 or 1) end)
        local w = cands[1]
        if w then
            w.rpe = w.rpe or p.rpe
            if p.notes then w.notes = (w.notes and w.notes ~= "" and (w.notes .. "\n") or "") .. p.notes end
            w.slotId = w.slotId or p.slotId
            S.put("workouts", w)
        elseif os.time() - (p.at or 0) > 3 * 86400 or p.kind == "strength" or p.kind == "other" then
            S.put("workouts", { id = "kobo-" .. p.date .. "-" .. p.slotId, date = p.date, kind = p.kind, slotId = p.slotId, title = p.title,
                rpe = p.rpe, notes = p.notes, source = "manual" })
        else
            table.insert(keep, p)
        end
    end
    d.pending = keep
    save()
end

-- Schermen ------------------------------------------------------------------------------

local function sendOpts(app)
    return {
        title = "Telefoon-app koppelen",
        mode = "koppel",
        onSubmit = function(text)
            local ok, j = pcall(require("json").decode, text)
            if not ok or type(j) ~= "table" or j.t ~= "koppel" then return false, "Dit is geen koppelbericht. Gebruik de koppelpagina." end
            local good, err = S.link(tostring(j.url or ""), tostring(j.key or ""), tostring(j.email or ""), tostring(j.pw or ""))
            if not good then return false, "Inloggen lukte niet: " .. tostring(err) end
            UIManager:scheduleIn(0.5, function() S.refresh(function() app:refresh() end) end)
            return true, "Gekoppeld als " .. tostring(j.email) .. ". De gegevens worden nu opgehaald."
        end,
    }
end

function S.settings(app)
    local W = UI.INNER()
    local c = cfg()
    local items = { UI.header("Telefoon-app", function() app.syncMsg = nil; app:back() end, "Training en check-in delen met Kees Study op je telefoon") }
    if S.connected() then
        local d = S.data()
        local n = 0
        for _, t in pairs(d.rows) do for _ in pairs(t) do n = n + 1 end end
        local waiting = 0
        for _ in pairs(d.dirty) do waiting = waiting + 1 end
        table.insert(items, UI.card(UI.vgroup({
            UI.text("Gekoppeld", { font = "medium", size = 21 }),
            UI.text(tostring(c.email or ""), { size = 16, color = UI.INK2 }),
            UI.vspace(8),
            UI.text((d.at and ("Laatst gelijkgezet: " .. require("ks_main").dateText(d.at) .. " " .. os.date("%H:%M", d.at)) or "Nog niet gelijkgezet")
                .. "\n" .. n .. " gegevens op de Kobo" .. (waiting > 0 and (", " .. waiting .. " wachten op versturen") or ""), { size = 16, color = UI.INK2, width = W - UI.px(40) }),
        })))
        table.insert(items, UI.vspace(14))
        if app.syncMsg then table.insert(items, UI.text(app.syncMsg, { size = 17, font = "bold", width = W })); table.insert(items, UI.vspace(10)) end
        table.insert(items, UI.button("Nu gelijkzetten", function()
            app.syncMsg = "Bezig..."
            app:refresh()
            UIManager:scheduleIn(0.2, function()
                S.refresh(function(ok, msg) app.syncMsg = ok and ("Klaar: " .. msg) or msg; app:refresh() end)
            end)
        end, { width = W, primary = true }))
        table.insert(items, UI.vspace(10))
        table.insert(items, UI.buttonRow({
            { "Opnieuw koppelen", function()
                require("ks_relay").open(app, sendOpts(app), function(err) app.syncMsg = err; app:refresh() end)
            end, small = true },
            { "Ontkoppelen", function() S.unlink(); app.syncMsg = "Ontkoppeld. Je gegevens in de app op je telefoon blijven gewoon staan."; app:refresh() end, small = true },
        }))
    else
        table.insert(items, UI.text("Koppel de Kobo één keer met de app op je telefoon. Daarna zie je op de Kobo of je trainingen gedaan zijn, vink je ze af met zwaarte en notitie, en doe je de ochtend-check-in. Alles komt ook in de app.", { size = 18, width = W }))
        table.insert(items, UI.vspace(14))
        table.insert(items, UI.card(UI.text("Je hebt nodig: het Supabase-adres en de openbare sleutel (staan in de app bij Instellingen, Synchroniseren), en je e-mail en wachtwoord. Die stuur je versleuteld vanaf je telefoon. De Kobo bewaart je wachtwoord niet.",
            { size = 16, color = UI.INK2, width = W - UI.px(40) })))
        table.insert(items, UI.vspace(16))
        if app.syncMsg then table.insert(items, UI.text(app.syncMsg, { size = 17, font = "bold", width = W })); table.insert(items, UI.vspace(10)) end
        table.insert(items, UI.button("Koppelen vanaf je telefoon", function()
            app.syncMsg = "Even wifi aanzetten..."
            app:refresh()
            require("ks_relay").open(app, sendOpts(app), function(err) app.syncMsg = err; app:refresh() end)
        end, { width = W, primary = true, icon = "wifi" }))
    end
    return UI.page(UI.vgroup(items))
end

local QUESTIONS = {
    { key = "sleep", q = "Hoe heb je geslapen?", lo = "slecht", hi = "goed" },
    { key = "legs", q = "Hoe voelen je benen?", lo = "zwaar", hi = "fris" },
    { key = "energy", q = "Hoeveel energie heb je?", lo = "weinig", hi = "veel" },
    { key = "calm", q = "Hoe rustig voel je je?", lo = "onrustig", hi = "rustig" },
}

function S.checkinPage(app)
    local W = UI.INNER()
    app.ci = app.ci or {}
    local old = S.checkin()
    if old and not app.ciInit then
        for _, q in ipairs(QUESTIONS) do app.ci[q.key] = app.ci[q.key] or old[q.key] end
        app.ciInit = true
    end
    local items = { UI.header("Ochtend-check-in", function() app.ci = nil; app.ciInit = nil; app:back() end,
        old and "Al gedaan vandaag. Je kunt het nog aanpassen." or "Vier vragen, 1 tot 5. Komt ook in de app.") }
    for _, q in ipairs(QUESTIONS) do
        table.insert(items, UI.text(q.q, { font = "medium", size = 19 }))
        table.insert(items, UI.vspace(6))
        table.insert(items, UI.segmented({ "1", "2", "3", "4", "5" }, app.ci[q.key] or 0, function(i) app.ci[q.key] = i; app:refresh() end))
        table.insert(items, UI.vspace(2))
        table.insert(items, UI.hgroup({ UI.text(q.lo, { size = 14, color = UI.INK3 }), UI.hspan(W - UI.text(q.lo, { size = 14 }):getSize().w - UI.text(q.hi, { size = 14 }):getSize().w), UI.text(q.hi, { size = 14, color = UI.INK3 }) }))
        table.insert(items, UI.vspace(14))
    end
    local complete = true
    for _, q in ipairs(QUESTIONS) do if not app.ci[q.key] then complete = false end end
    local footer = UI.buttonRow({
        { "Opslaan", function()
            S.saveCheckin(app.ci)
            app.ci = nil; app.ciInit = nil
            app:back()
        end, primary = true, disabled = not complete },
    })
    return UI.page(UI.vgroup(items), footer)
end

--- Afvinken met zwaarte en notitie. app.doneEv = { date, ev }
function S.donePage(app)
    local W = UI.INNER()
    local x = app.doneEv
    local items = { UI.header("Gedaan", function() app.doneEv = nil; app.doneRpe = nil; app.doneNote = nil; app:back() end, x.ev.name .. " · " .. require("ks_main").dateText(os.time())) }
    table.insert(items, UI.text("Hoe zwaar was het? (1 = heel licht, 10 = alles gegeven)", { size = 18, width = W }))
    table.insert(items, UI.vspace(8))
    table.insert(items, UI.segmented({ "1", "2", "3", "4", "5" }, (app.doneRpe and app.doneRpe <= 5) and app.doneRpe or 0, function(i) app.doneRpe = i; app:refresh() end))
    table.insert(items, UI.vspace(6))
    table.insert(items, UI.segmented({ "6", "7", "8", "9", "10" }, (app.doneRpe and app.doneRpe > 5) and (app.doneRpe - 5) or 0, function(i) app.doneRpe = i + 5; app:refresh() end))
    table.insert(items, UI.vspace(18))
    table.insert(items, UI.text("Notitie (mag leeg blijven)", { size = 16, color = UI.INK2 }))
    table.insert(items, UI.vspace(6))
    table.insert(items, UI.Tap:new{ label = "Notitie", callback = function()
        local InputDialog = require("ui/widget/inputdialog")
        local dlg
        dlg = InputDialog:new{ title = "Notitie bij de training", input = app.doneNote or "", allow_newline = true,
            buttons = { { { text = "Annuleren", id = "close", callback = function() UIManager:close(dlg) end },
                { text = "Klaar", is_enter_default = true, callback = function() app.doneNote = dlg:getInputText(); UIManager:close(dlg); app:refresh() end } } } }
        UIManager:show(dlg)
        dlg:onShowKeyboard()
    end, UI.card(UI.text(app.doneNote and app.doneNote ~= "" and app.doneNote or "Tik om te typen", { size = 17, color = (app.doneNote and app.doneNote ~= "") and UI.BLACK or UI.INK3, width = W - UI.px(40) })) })
    local footer = UI.buttonRow({
        { "Alleen afvinken", function()
            S.markDone(x.date, x.ev)
            app.doneEv = nil; app.doneRpe = nil; app.doneNote = nil
            app:back()
        end },
        { "Opslaan", function()
            S.markDone(x.date, x.ev, app.doneRpe, app.doneNote)
            app.doneEv = nil; app.doneRpe = nil; app.doneNote = nil
            app:back()
        end, primary = true },
    })
    return UI.page(UI.vgroup(items), footer)
end

return S
