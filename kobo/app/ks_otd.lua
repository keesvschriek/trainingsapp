-- Vandaag in de geschiedenis: de datumpagina van de Nederlandse Wikipedia (bijv. "16 november"),
-- met gebeurtenissen, geboren en overleden. Gebeurtenissen kun je bewaren als leerkaart.

local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local Store = require("ks_store")
local UI = require("ks_ui")

local O = {}

O.BASE = os.getenv("KEES_STUDY_WIKI_URL") or "https://nl.wikipedia.org/w/index.php?action=raw&title="
local MONTHS = { "januari", "februari", "maart", "april", "mei", "juni", "juli", "augustus", "september", "oktober", "november", "december" }

local function file() return DataStorage:getSettingsDir() .. "/keesstudy-otd.json" end
local cache
function O.data()
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

function O.title(ts)
    local t = os.date("*t", ts or os.time())
    return t.day .. " " .. MONTHS[t.month]
end

--- Wikitekst opschonen tot leesbare tekst.
function O.clean(s)
    s = s:gsub("<ref[^>]-/>", ""):gsub("<ref.-</ref>", ""):gsub("<!%-%-.-%-%->", ""):gsub("<[^>]+>", "")
    -- sjablonen weg (twee keer voor geneste)
    for _ = 1, 2 do s = s:gsub("{{[^{}]*}}", "") end
    s = s:gsub("%[%[[^%]|]-|([^%]]-)%]%]", "%1"):gsub("%[%[([^%]]-)%]%]", "%1")
    s = s:gsub("%[https?://%S+%s*([^%]]*)%]", "%1")
    s = s:gsub("'''", ""):gsub("''", ""):gsub("&nbsp;", " ")
    s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function yearOf(s)
    local y = s:match("^(%d+)%s*v%.?%s*Chr%.?")
    if y then return -tonumber(y), s:gsub("^%d+%s*v%.?%s*Chr%.?", "", 1) end
    y = s:match("^(%d%d?%d?%d?)")
    if y then return tonumber(y), s:sub(#y + 1) end
    return nil, s
end

--- Haal de lijsten uit de wikitekst. Geeft { {y, t, sec, sub} }.
function O.parse(text)
    local out = {}
    local sec, sub, curYear
    local keep = { gebeurtenissen = "Gebeurtenissen", geboren = "Geboren", overleden = "Overleden" }
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local lvl, head = line:match("^(==+)%s*(.-)%s*==+%s*$")
        if head then
            local h = O.clean(head)
            if #lvl == 2 then
                sec = keep[h:lower()]
                sub, curYear = nil, nil
            elseif sec then
                sub = h
            end
        elseif sec then
            local bold = line:match("^'''([^']+)'''%s*:?%s*$") or line:match("^;%s*(.+)$")
            if bold then
                sub = O.clean(bold)
            else
                local stars, rest = line:match("^(%*+)%s*(.*)$")
                if stars then
                    local txt = O.clean(rest)
                    if #stars == 1 then
                        local y, after = yearOf(txt)
                        if y then
                            after = after:gsub("^%s*[%-–—:]%s*", "")
                            curYear = y
                            if after ~= "" then table.insert(out, { y = y, t = after, sec = sec, sub = sub }) end
                        end
                    elseif curYear and txt ~= "" then
                        table.insert(out, { y = curYear, t = txt, sec = sec, sub = sub })
                    end
                end
            end
        end
    end
    return out
end

function O.fetchNow()
    local title = O.title()
    local ok, body = require("ks_net").get(O.BASE .. title:gsub(" ", "_"), { ["User-Agent"] = "KeesStudy/1.0 (Kobo e-reader, persoonlijk gebruik)" })
    if not ok then return false, body end
    local items = O.parse(body)
    if #items == 0 then return false, "Kon de pagina " .. title .. " niet lezen." end
    save({ day = os.date("%Y%m%d"), title = title, items = items })
    return true
end

function O.due() return O.data().day ~= os.date("%Y%m%d") end

function O.refresh(done)
    require("ks_net").online(function()
        local ok, err = O.fetchNow()
        done(ok, err)
    end, { onFail = function(msg) done(false, msg) end })
end

function O.yearText(y) return y < 0 and (-y .. " v.Chr.") or tostring(y) end

function O.summary()
    local d = O.data()
    if d.day ~= os.date("%Y%m%d") or not d.items then return "Nog niet opgehaald vandaag" end
    -- een gebeurtenis die bij het jaar past: liefst eentje uit de politiek of oorlog
    local pick
    for _, it in ipairs(d.items) do
        if it.sec == "Gebeurtenissen" then
            local s = (it.sub or ""):lower()
            if s:find("politiek") or s:find("oorlog") or s:find("militair") then pick = it; break end
            pick = pick or it
        end
    end
    return pick and (O.yearText(pick.y) .. ": " .. pick.t) or ""
end

-- Bewaren als leerkaart -------------------------------------------------------------------

function O.saved() return Store.get("otd.saved", {}) end
local function key(it) return it.sec .. ":" .. it.y .. ":" .. it.t:sub(1, 40) end
function O.isSaved(it) for _, s in ipairs(O.saved()) do if s.id == key(it) then return true end end return false end
function O.toggle(it)
    local list, k, found = O.saved(), key(it), nil
    for i, s in ipairs(list) do if s.id == k then found = i end end
    if found then table.remove(list, found)
    else
        local front = it.sec == "Geboren" and ("In welk jaar geboren? " .. it.t) or (it.sec == "Overleden" and ("In welk jaar overleden? " .. it.t) or ("Wanneer? " .. it.t))
        table.insert(list, { id = k, front = front, back = O.yearText(it.y), why = (O.data().title or "") .. " " .. O.yearText(it.y) })
    end
    Store.set("otd.saved", list)
end

-- Scherm ----------------------------------------------------------------------------------

local TABS = { "Gebeurtenissen", "Geboren", "Overleden" }

function O.page(app)
    local W = UI.INNER()
    local d = O.data()
    local today = d.day == os.date("%Y%m%d")
    local tab = app.otdTab or 1
    local items = { UI.header("Op deze dag", function() app.otdTab = nil; app.otdPg = nil; app.otdMsg = nil; app:back() end,
        (d.title or O.title()) .. " · Wikipedia" .. (today and "" or " · nog niet opgehaald vandaag")) }
    table.insert(items, UI.segmented(TABS, tab, function(i) app.otdTab = i; app.otdPg = 1; app:refresh() end))
    table.insert(items, UI.vspace(8))
    table.insert(items, UI.text("Tik op een regel om hem als leerkaart te bewaren.", { size = 15, color = UI.INK3 }))
    table.insert(items, UI.vspace(6))
    local blocks, lastSub = {}, nil
    for _, it in ipairs(today and d.items or {}) do
        if it.sec == TABS[tab] then
            local saved = O.isSaved(it)
            local row = UI.Tap:new{ label = it.t, callback = function() O.toggle(it); app:refresh() end,
                UI.vgroup({
                    UI.vspace(8),
                    UI.hgroup({
                        UI.text(O.yearText(it.y), { size = 18, font = "bold", width = UI.px(110) }),
                        UI.text(it.t, { size = 18, width = W - UI.px(110 + 40), height = UI.px(80) }),
                        saved and UI.icon("star", 24) or UI.hspace(24),
                    }, "top"),
                    UI.vspace(8),
                    UI.line(W),
                }) }
            if it.sub and it.sub ~= lastSub then
                lastSub = it.sub
                table.insert(blocks, UI.vgroup({ UI.section(it.sub), row }))
            else
                table.insert(blocks, row)
            end
        end
    end
    if #blocks == 0 then
        table.insert(items, UI.vspace(20))
        table.insert(items, UI.text(today and "Niets gevonden in dit deel." or "Tik op Ophalen om de pagina van vandaag te laden.", { size = 19, color = UI.INK2, width = W }))
    end
    if app.otdMsg then table.insert(items, UI.text(app.otdMsg, { size = 17, font = "bold", width = W })) end
    local head = UI.vgroup(items)
    local avail = UI.H() - UI.px(UI.TOPPAD) - head:getSize().h - UI.px(60 + 50)
    local pages, cur, used = {}, {}, 0
    for _, bl in ipairs(blocks) do
        local h = bl:getSize().h
        if used + h > avail and #cur > 0 then table.insert(pages, cur); cur, used = {}, 0 end
        table.insert(cur, bl); used = used + h
    end
    if #cur > 0 then table.insert(pages, cur) end
    local np = math.max(1, #pages)
    local pg = math.max(1, math.min(app.otdPg or 1, np))
    for _, bl in ipairs(pages[pg] or {}) do table.insert(items, bl) end
    local footer = UI.buttonRow({
        { "Ophalen", function()
            app.otdMsg = "Bezig met ophalen..."
            app:refresh()
            UIManager:scheduleIn(0.2, function()
                O.refresh(function(ok, err)
                    app.otdMsg = (not ok) and ("Ophalen mislukt: " .. tostring(err)) or nil
                    app.otdPg = 1
                    app:refresh()
                end)
            end)
        end, small = true },
        { "Vorige", function() app.otdPg = pg - 1; app:refresh() end, small = true, disabled = pg <= 1 },
        { np > 1 and ("Verder " .. pg .. "/" .. np) or "Verder", function() app.otdPg = pg + 1; app:refresh() end, small = true, primary = pg < np, disabled = pg >= np },
    })
    return UI.page(UI.vgroup(items), footer)
end

return O
