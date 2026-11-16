-- Volgende Defensie-module: aftellen en paklijst. Zelfde gegevens als de telefoon-app
-- (blokken van het soort "defensie" en de tabel "pack").

local UI = require("ks_ui")
local Sync = require("ks_sync")

local M = {}

M.START = { "Defensiepas", "Uniform en kistjes", "Sportkleding en loopschoenen", "Toiletspullen en handdoek", "Oplader en powerbank", "Notitieboek en pen", "Medicijnen", "Snacks en drinkfles" }
local MON = { "jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec" }
local DAYS = { "zo", "ma", "di", "wo", "do", "vr", "za" }

local function t(iso) local y, m, d = iso:match("(%d+)-(%d+)-(%d+)"); return os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 } end
local function today() return os.date("%Y-%m-%d") end
local function short(iso) local x = t(iso); return DAYS[tonumber(os.date("%w", x)) + 1] .. " " .. tonumber(os.date("%d", x)) .. " " .. MON[tonumber(os.date("%m", x))] end
function M.daysTo(iso) return math.floor((t(iso) - t(today())) / 86400 + 0.5) end

function M.next()
    local day = today()
    local l = Sync.list("blocks", function(b) return b.kind == "defensie" and type(b.start) == "string" and type(b["end"]) == "string" and b["end"] >= day end)
    table.sort(l, function(a, b) return a.start < b.start end)
    return l[1]
end

function M.pack()
    local l = Sync.list("pack", function(p) return type(p.text) == "string" end)
    local raw = Sync.data().rows.pack
    local pulled = not Sync.connected() or Sync.data().lastPull ~= "1970-01-01T00:00:00Z"
    if #l == 0 and (raw == nil or next(raw) == nil) and pulled then
        -- zelfde startlijst en ids als de telefoon-app, dus geen dubbelingen
        for i, txt in ipairs(M.START) do Sync.put("pack", { id = "pack-" .. i, text = txt, order = i - 1 }) end
        Sync.soon()
        l = Sync.list("pack")
    end
    table.sort(l, function(a, b) return (a.order or 0) < (b.order or 0) end)
    return l
end

local function packedSet(m)
    local s = {}
    for _, id in ipairs(type(m.packed) == "table" and m.packed or {}) do s[id] = true end
    return s
end

function M.homeLine()
    local m = M.next()
    if not m then return nil end
    local d = M.daysTo(m.start)
    if d > 28 then return nil end
    local s = packedSet(m)
    local got, all = 0, 0
    for _, p in ipairs(Sync.list("pack")) do all = all + 1; if s[p.id] then got = got + 1 end end
    local when = d <= 0 and "nu bezig" or d == 1 and "morgen" or ("over " .. d .. " dagen")
    return (m.label ~= "" and m.label or "Defensie") .. " " .. when .. (all > 0 and (" · paklijst " .. got .. "/" .. all) or "")
end

function M.page(app)
    local W = UI.INNER()
    local m = M.next()
    if not m then
        return UI.page(UI.vgroup({ UI.header("Module", function() app:back() end),
            UI.text("Geen module gepland. Zet je modules in de app op je telefoon: Meer, Schema, Blokken, soort Defensie.", { size = 18, width = W, color = UI.INK2 }) }))
    end
    local d = M.daysTo(m.start)
    local items = { UI.header(m.label ~= "" and m.label or "Defensie", function() app:back() end, short(m.start) .. " t/m " .. short(m["end"])) }
    table.insert(items, UI.card(UI.hgroup({
        UI.text(d > 0 and tostring(d) or "Nu", { font = "display", size = 48 }), UI.hspace(14),
        UI.text(d > 0 and (d == 1 and "dag te gaan" or "dagen te gaan") or "module is bezig", { size = 18, color = UI.INK2 }),
    }, "center"), { pad = UI.px(16) }))
    table.insert(items, UI.vspace(16))
    table.insert(items, UI.section("Paklijst", W))
    local s = packedSet(m)
    for _, p in ipairs(M.pack()) do
        local on = s[p.id] == true
        table.insert(items, UI.Tap:new{ label = p.text, callback = function()
            local list = {}
            s[p.id] = not on or nil
            for id in pairs(s) do table.insert(list, id) end
            m.packed = list
            Sync.put("blocks", m)
            Sync.soon()
            app:refresh()
        end, UI.vgroup({
            UI.vspace(10),
            UI.hgroup({ UI.checkbox(on), UI.hspace(16), UI.text(p.text, { size = 19, width = W - UI.px(56) }) }),
            UI.vspace(10),
            UI.line(W),
        }) })
    end
    table.insert(items, UI.vspace(10))
    table.insert(items, UI.text("De lijst pas je aan in de app op je telefoon. Afvinken telt per module.", { size = 15, color = UI.INK2, width = W }))
    return UI.page(UI.vgroup(items))
end

return M
