-- Opvolgen: kleine punten die je niet wilt vergeten. Zelfde lijst als in de telefoon-app
-- (tabel "opvolg" in Supabase). Geen leerlingnamen, hooguit initialen of een rol.

local UIManager = require("ui/uimanager")
local UI = require("ks_ui")
local Sync = require("ks_sync")

local O = {}

O.GROUPS = { "Mentoraat", "Tutoren", "Burgerschap", "Digitale geletterdheid", "Sectie", "Defensie", "Thuis" }
local DAY_SHORT = { "ma", "di", "wo", "do", "vr", "za", "zo" }
local DAY_FULL = { "maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag", "zondag" }
local MON = { "jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec" }

-- Datums -------------------------------------------------------------------------------

local function t(iso) local y, m, d = iso:match("(%d+)-(%d+)-(%d+)"); return os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 } end
function O.today() return os.date("%Y-%m-%d") end
function O.addDays(iso, n) return os.date("%Y-%m-%d", t(iso) + n * 86400) end
-- maandag = 1 ... zondag = 7
function O.weekday(iso) local w = tonumber(os.date("%w", t(iso))); return w == 0 and 7 or w end
--- Eerstvolgende dag met weekdag wd (1 = maandag), nooit vandaag zelf.
function O.nextWeekday(from, wd)
    local n = (wd - O.weekday(from)) % 7
    if n == 0 then n = 7 end
    return O.addDays(from, n)
end
local function diff(a, b) return math.floor((t(a) - t(b)) / 86400 + 0.5) end

--- Datum van het eind van een regel halen: "verslag rondsturen vr", "AB bellen morgen".
function O.parseLine(line, from, fallback)
    local s = (line or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    local due = fallback
    local low = s:lower()
    local function cut(n) s = s:sub(1, #s - n):gsub(" $", "") end
    local num, unit = low:match(" over (%d+) (%a+)$")
    if num and (unit == "dag" or unit == "dagen" or unit == "week" or unit == "weken") then
        due = O.addDays(from, tonumber(num) * (unit:sub(1, 2) == "we" and 7 or 1))
        cut(#(" over " .. num .. " " .. unit))
    elseif low:match(" volgende week$") then
        due = O.nextWeekday(from, 1); cut(#" volgende week")
    else
        local w = low:match(" (%a+)$")
        if w == "vandaag" then due = from; cut(#w + 1)
        elseif w == "morgen" then due = O.addDays(from, 1); cut(#w + 1)
        elseif w == "overmorgen" then due = O.addDays(from, 2); cut(#w + 1)
        elseif w then
            for i = 1, 7 do
                if w == DAY_SHORT[i] or w == DAY_FULL[i] then due = O.nextWeekday(from, i); cut(#w + 1); break end
            end
        end
    end
    -- eerste letter hoofdletter (ook bij é e.d. laten we het zoals het is)
    s = s:gsub("^%l", string.upper)
    return s, due
end

function O.dueText(due, from)
    local d = diff(due, from)
    if d < -1 then return (-d) .. " dagen te laat" end
    if d == -1 then return "gisteren" end
    if d == 0 then return "vandaag" end
    if d == 1 then return "morgen" end
    local tt = t(due)
    return DAY_SHORT[O.weekday(due)] .. " " .. tonumber(os.date("%d", tt)) .. " " .. MON[tonumber(os.date("%m", tt))]
end

-- Gegevens -----------------------------------------------------------------------------

local function newId()
    local f = io.open("/dev/urandom", "rb")
    local b = f and f:read(16) or tostring(os.time() .. math.random())
    if f then f:close() end
    local h = b:gsub(".", function(c) return ("%02x"):format(c:byte()) end):sub(1, 32)
    return ("%s-%s-4%s-a%s-%s"):format(h:sub(1, 8), h:sub(9, 12), h:sub(14, 16), h:sub(18, 20), h:sub(21, 32))
end

function O.open()
    local l = Sync.list("opvolg", function(r) return not r.done and type(r.title) == "string" and type(r.due) == "string" end)
    table.sort(l, function(a, b)
        if a.due ~= b.due then return a.due < b.due end
        return (a.createdAt or 0) < (b.createdAt or 0)
    end)
    return l
end

function O.dueNow(day)
    day = day or O.today()
    local out = {}
    for _, r in ipairs(O.open()) do if r.due <= day then table.insert(out, r) end end
    return out
end

function O.add(title, due, group)
    if not title or title == "" then return end
    Sync.put("opvolg", { id = newId(), title = title, due = due, group = group, done = false, createdAt = os.time() * 1000, from = "kobo" })
    Sync.soon()
end

function O.toggle(r)
    r.done = not r.done
    r.doneAt = r.done and os.time() * 1000 or nil
    Sync.put("opvolg", r)
    Sync.soon()
end

--- Regel voor het beginscherm, of nil als er niets is.
function O.homeLine()
    local now = O.dueNow()
    if #now == 0 then
        local open = O.open()
        if #open == 0 then return "Opvolgen: niets open" end
        return "Opvolgen: " .. #open .. " open, eerste " .. O.dueText(open[1].due, O.today())
    end
    local late = 0
    local day = O.today()
    for _, r in ipairs(now) do if r.due < day then late = late + 1 end end
    local s = #now == 1 and ("Opvolgen: " .. now[1].title) or (#now .. " punten om op te volgen")
    if late > 0 and #now > 1 then s = s .. " (" .. late .. " te laat)" end
    return s
end

-- Invoer -------------------------------------------------------------------------------

--- Toetsenbord voor één regel. onText(text) krijgt de getypte tekst.
local function ask(title, hint, onText, opts)
    local InputDialog = require("ui/widget/inputdialog")
    local dlg
    dlg = require("ks_ui").inputDialog{
        title = title,
        input = "",
        input_hint = hint,
        buttons = { {
            { text = (opts and opts.cancel) or "Annuleren", id = "close", callback = function() UIManager:close(dlg); if opts and opts.onCancel then opts.onCancel() end end },
            { text = (opts and opts.ok) or "Bewaren", is_enter_default = true, callback = function()
                local txt = dlg:getInputText()
                UIManager:close(dlg)
                onText(txt)
            end },
        } },
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end
O.ask = ask

local function row(app, r, day, W)
    local late = r.due < day
    local sub = O.dueText(r.due, day) .. (r.group and (" · " .. r.group) or "")
    local textW = W - UI.px(56)
    local content = UI.vgroup({
        UI.vspace(12),
        UI.hgroup({
            UI.checkbox(r.done), UI.hspace(16),
            UI.vgroup({
                UI.text(r.title, { size = 19, width = textW }),
                UI.vspace(3),
                UI.text(sub, { size = 15, color = late and UI.BLACK or UI.INK2, font = late and "medium" or nil }),
            }),
        }, "top"),
        UI.vspace(12),
        UI.line(W),
    })
    return UI.Tap:new{ label = r.title, callback = function() O.toggle(r); app.ovLast = r; app:refresh() end, content }
end

-- Schermen -----------------------------------------------------------------------------

function O.page(app)
    local day = O.today()
    local W = UI.INNER()
    local open = O.open()
    local items = { UI.header("Opvolgen", function() app:back() end, #open == 0 and "Niets open" or (#open .. " open · tik om af te ronden")) }
    local parts = {
        { "Te laat", function(r) return r.due < day end },
        { "Vandaag", function(r) return r.due == day end },
        { "Komende 7 dagen", function(r) return r.due > day and r.due <= O.addDays(day, 6) end },
        { "Later", function(r) return r.due > O.addDays(day, 6) end },
    }
    local last = app.ovLast
    if last and last.done then
        table.insert(items, UI.vspace(6))
        table.insert(items, UI.Tap:new{ label = "Ongedaan", callback = function() O.toggle(last); app.ovLast = nil; app:refresh() end,
            UI.card(UI.text("Afgerond: " .. last.title .. ". Tik om terug te zetten.", { size = 15, color = UI.INK2, width = W - UI.px(40) }), { pad = UI.px(12) }) })
    end
    -- paginering: zoveel rijen als passen
    local per = UI.compact and 6 or 7
    local pg = app.ovPg or 1
    local all = {}
    for _, p in ipairs(parts) do
        local first = true
        for _, r in ipairs(open) do
            if p[2](r) then
                table.insert(all, { head = first and p[1] or nil, r = r })
                first = false
            end
        end
    end
    local np = math.max(1, math.ceil(#all / per))
    if pg > np then pg = np end
    for i = (pg - 1) * per + 1, math.min(#all, pg * per) do
        local e = all[i]
        if e.head or i == (pg - 1) * per + 1 then
            table.insert(items, UI.vspace(10))
            table.insert(items, UI.section(e.head or "Vervolg", W))
        end
        table.insert(items, row(app, e.r, day, W))
    end
    if #open == 0 then
        table.insert(items, UI.vspace(10))
        table.insert(items, UI.text("Alles is opgevolgd. Nieuwe punten zet je hier of in de app op je telefoon.", { size = 18, width = W, color = UI.INK2 }))
    end
    local btns = {
        { "Punt", function() O.addFlow(app) end, primary = true },
        { "Overleg", function() app:go(O.meetingPick) end },
    }
    if np > 1 then
        table.insert(btns, 1, { pg .. "/" .. np, function() app.ovPg = pg % np + 1; app:refresh() end, small = true })
    end
    return UI.page(UI.vgroup(items), UI.buttonRow(btns))
end

function O.addFlow(app, group)
    local day = O.today()
    ask("Nieuw punt", "Bijv. verslag rondsturen vr", function(txt)
        local title, due = O.parseLine(txt, day, O.addDays(day, 1))
        if title ~= "" then O.add(title, due, group) end
        app:refresh()
    end)
end

function O.meetingPick(app)
    local W = UI.INNER()
    local items = { UI.header("Overleg", function() app:back() end, "Kies het overleg. Daarna tik je de actiepunten achter elkaar in.") }
    table.insert(items, UI.vspace(8))
    local half = math.floor((W - UI.px(14)) / 2)
    for i = 1, #O.GROUPS, 2 do
        local pair = {}
        for j = i, math.min(i + 1, #O.GROUPS) do
            local g = O.GROUPS[j]
            table.insert(pair, { g, function() app.ovMeeting = { group = g, added = {}, dueDays = 7 }; app:go(O.meeting) end })
        end
        table.insert(items, UI.buttonRow(pair, #pair == 1 and half or nil))
        table.insert(items, UI.vspace(12))
    end
    return UI.page(UI.vgroup(items))
end

local DUE_OPTS = { { "Morgen", 1 }, { "Over 3 dagen", 3 }, { "1 week", 7 }, { "2 weken", 14 } }

function O.meeting(app)
    local m = app.ovMeeting or { group = "Overleg", added = {}, dueDays = 7 }
    app.ovMeeting = m
    local day = O.today()
    local W = UI.INNER()
    local items = { UI.header("Overleg " .. m.group, function() app:back() end, #m.added .. " actiepunten · eindig een regel met morgen of vr voor een andere datum") }
    table.insert(items, UI.section("Standaard klaar op", W))
    local names, cur = {}, 3
    for i, o in ipairs(DUE_OPTS) do names[i] = o[1]; if o[2] == m.dueDays then cur = i end end
    table.insert(items, UI.segmented(names, cur, function(i) m.dueDays = DUE_OPTS[i][2]; app:refresh() end))
    table.insert(items, UI.vspace(14))
    for i = #m.added, math.max(1, #m.added - 7), -1 do
        local a = m.added[i]
        table.insert(items, UI.text(a.title, { size = 18, width = W }))
        table.insert(items, UI.text(O.dueText(a.due, day), { size = 15, color = UI.INK2 }))
        table.insert(items, UI.vspace(10))
    end
    local function next()
        ask("Actiepunt " .. (#m.added + 1), "Typ het punt, Volgende voor het volgende", function(txt)
            local title, due = O.parseLine(txt, day, O.addDays(day, m.dueDays))
            if title ~= "" then
                O.add(title, due, m.group)
                table.insert(m.added, { title = title, due = due })
                app:refresh()
                -- meteen door naar het volgende punt
                UIManager:nextTick(next)
            else
                app:refresh()
            end
        end, { ok = "Volgende", cancel = "Klaar" })
    end
    return UI.page(UI.vgroup(items), UI.buttonRow({
        { "Actiepunt typen", next, primary = true },
        { "Klaar", function() app.ovMeeting = nil; app:back() end },
    }))
end

return O
