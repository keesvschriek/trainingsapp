-- Avond op de Kobo: dag afsluiten, verder lezen, kort leren.
-- Dag afsluiten: wat ging goed, wat moet morgen (wordt een opvolgpunt) en je energie.

local UI = require("ks_ui")
local Store = require("ks_store")

local A = {}

function A.isEvening()
    local h = tonumber(os.date("%H"))
    return h >= 20 or h < 4
end

-- Na middernacht hoort de avond nog bij gisteren
local function dayKey()
    local tm = os.time()
    if tonumber(os.date("%H", tm)) < 4 then tm = tm - 86400 end
    return os.date("%Y-%m-%d", tm)
end

function A.log() return Store.get("avond.log", {}) end
function A.entry() return A.log()[dayKey()] end

local function saveEntry(e)
    local l = A.log()
    l[dayKey()] = e
    -- hooguit 120 dagen bewaren
    local keys = {}
    for k in pairs(l) do table.insert(keys, k) end
    table.sort(keys)
    for i = 1, #keys - 120 do l[keys[i]] = nil end
    Store.set("avond.log", l)
end

function A.summary()
    local e = A.entry()
    if e and e.done then return "Afgesloten" .. (e.energy and (" · energie " .. e.energy) or "") end
    return "Drie korte vragen, dan klaar"
end

--- Laatst gelezen stuk onthouden, voor Verder lezen.
function A.setLastRead(v) Store.set("last.read", v) end
function A.lastRead() local v = Store.get("last.read"); return type(v) == "table" and v or nil end

function A.continueReading(app)
    local v = A.lastRead()
    if v and v.kind == "doc" and v.name then
        require("ks_reading").open(app, { name = v.name, title = v.title })
    elseif v and v.kind == "frag" then
        app.fragBook = v.book
        app:go(require("ks_fragment").page)
    else
        app:go(require("ks_main").readFolder)
    end
end

function A.page(app)
    local O = require("ks_opvolg")
    local W = UI.INNER()
    local e = A.entry() or {}
    app.avond = e
    local items = { UI.header("Dag afsluiten", function() app:back() end, require("ks_main").dateText()) }

    local function block(title, value, empty, onTap)
        table.insert(items, UI.vspace(14))
        table.insert(items, UI.section(title, W))
        table.insert(items, UI.Tap:new{ label = title, callback = onTap,
            UI.card(UI.text(value or empty, { size = 19, width = W - UI.px(40), color = value and UI.BLACK or UI.INK2 }), { pad = UI.px(16) }) })
    end

    block("Wat ging goed vandaag?", e.goed, "Tik om te typen", function()
        O.ask("Wat ging goed vandaag?", "Eén zin is genoeg", function(txt)
            if txt and txt ~= "" then e.goed = txt; saveEntry(e) end
            app:refresh()
        end)
    end)

    local morgen = e.morgen or {}
    block("Wat moet morgen?", #morgen > 0 and ("• " .. table.concat(morgen, "\n• ")) or nil, "Tik om een punt te typen. Het komt bij Opvolgen, ook op je telefoon.", function()
        local tomorrow = O.addDays(O.today(), 1)
        O.ask("Wat moet morgen?", "Bijv. kopieën ophalen voor 3H", function(txt)
            local title, due = O.parseLine(txt, O.today(), tomorrow)
            if title ~= "" then
                O.add(title, due)
                table.insert(morgen, title)
                e.morgen = morgen
                saveEntry(e)
            end
            app:refresh()
        end, { ok = "Toevoegen" })
    end)

    table.insert(items, UI.vspace(14))
    table.insert(items, UI.section("Energie vandaag", W))
    table.insert(items, UI.segmented({ "1", "2", "3", "4", "5" }, e.energy or 0, function(i) e.energy = i; saveEntry(e); app:refresh() end))
    table.insert(items, UI.vspace(6))
    table.insert(items, UI.text("1 is op, 5 is vol energie.", { size = 15, color = UI.INK2 }))

    -- laatste 7 avonden, als je wilt terugkijken
    local l, row = A.log(), {}
    for i = 6, 0, -1 do
        local d = os.date("%Y-%m-%d", os.time() - i * 86400)
        local x = l[d]
        table.insert(row, UI.vgroup({
            UI.text(({ "zo", "ma", "di", "wo", "do", "vr", "za" })[tonumber(os.date("%w", os.time() - i * 86400)) + 1], { size = 14, color = UI.INK2 }),
            UI.text(x and x.energy and tostring(x.energy) or "·", { size = 19, font = "medium" }),
        }, "center"))
        table.insert(row, UI.hspace(22))
    end
    table.insert(items, UI.vspace(18))
    table.insert(items, UI.section("Energie, laatste 7 dagen", W))
    table.insert(items, UI.hgroup(row))

    return UI.page(UI.vgroup(items), UI.button(e.done and "Afgesloten" or "Dag afsluiten", function()
        e.done = true
        saveEntry(e)
        app:home()
    end, { width = W, primary = not e.done }))
end

return A
