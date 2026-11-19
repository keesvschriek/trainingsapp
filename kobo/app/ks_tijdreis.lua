-- Tijdreis: je eigen plek op de historische topografische kaarten van het Kadaster,
-- van 1815 tot nu (de kaarten van topotijdreis.nl, Kadaster en Esri Nederland).
-- Kies een plek en een jaar; de kaartstukjes worden op de Kobo bewaard.

local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local UI = require("ks_ui")
local Store = require("ks_store")

local T = {}

T.TILES = os.getenv("KEES_STUDY_TOPO_URL") or "https://tiles.arcgis.com/tiles/nSZVuSZjHpEZZbRo/arcgis/rest/services/Historische_tijdreis_%d/MapServer/tile/%d/%d/%d"
T.PDOK = os.getenv("KEES_STUDY_PDOK_URL") or "https://api.pdok.nl/bzk/locatieserver/search/v3_1/free"
T.YEARS = { 1815, 1850, 1870, 1900, 1925, 1945, 1960, 1980, 2000, 2024 }
T.ZOOM = { { "Straat", 11 }, { "Dorp", 10 }, { "Omgeving", 9 }, { "Streek", 8 } }
local ORIGIN_X, ORIGIN_Y, RES0 = -30515500.0, 31112399.999999993, 3251.206502413005

--- WGS84 naar Rijksdriehoek (benaderingsformules van Schreutelkamp en Strang van Hees).
function T.toRD(lat, lon)
    local dp, dl = 0.36 * (lat - 52.15517440), 0.36 * (lon - 5.38720621)
    local X = { { 0, 1, 190094.945 }, { 1, 1, -11832.228 }, { 2, 1, -114.221 }, { 0, 3, -32.391 }, { 1, 0, -0.705 }, { 3, 1, -2.340 }, { 1, 3, -0.608 }, { 0, 2, -0.008 }, { 2, 3, 0.148 } }
    local Y = { { 1, 0, 309056.544 }, { 0, 2, 3638.893 }, { 2, 0, 73.077 }, { 1, 2, -157.984 }, { 3, 0, 59.788 }, { 0, 1, 0.433 }, { 2, 2, -6.439 }, { 1, 1, -0.032 }, { 0, 4, 0.092 }, { 1, 4, -0.054 } }
    local x, y = 155000, 463000
    for _, c in ipairs(X) do x = x + c[3] * dp ^ c[1] * dl ^ c[2] end
    for _, c in ipairs(Y) do y = y + c[3] * dp ^ c[1] * dl ^ c[2] end
    return x, y
end

local function preset(name, lat, lon) local x, y = T.toRD(lat, lon); return { name = name, x = x, y = y } end
T.PRESETS = { preset("Elst", 51.9197, 5.8481), preset("Nijmegen", 51.8475, 5.8640), preset("Vliegbasis Woensdrecht", 51.4492, 4.3420) }

function T.places()
    local own = Store.get("tr.places", {})
    local out = {}
    for _, p in ipairs(T.PRESETS) do out[#out + 1] = p end
    for _, p in ipairs(own) do out[#out + 1] = p end
    return out
end

--- Plek zoeken bij PDOK (adres, straat of plaats). Geeft {name, x, y} of nil, bericht.
function T.search(q)
    local function enc(s) return (s:gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end)) end
    local ok, body = require("ks_net").get(T.PDOK .. "?rows=1&fl=weergavenaam,centroide_rd&q=" .. enc(q))
    if not ok then return nil, "Zoeken lukte niet." end
    local good, j = pcall(require("ks_json").decode, body)
    local doc = good and type(j) == "table" and type(j.response) == "table" and type(j.response.docs) == "table" and j.response.docs[1]
    if not doc or type(doc.centroide_rd) ~= "string" then return nil, "Niets gevonden voor \"" .. q .. "\"." end
    local x, y = doc.centroide_rd:match("POINT%(([%d%.%-]+) ([%d%.%-]+)%)")
    if not x then return nil, "Niets gevonden." end
    return { name = type(doc.weergavenaam) == "string" and doc.weergavenaam or q, x = tonumber(x), y = tonumber(y) }
end

-- Kaartstukjes ----------------------------------------------------------------------------------

local function dir() return DataStorage:getSettingsDir() .. "/keesstudy-tiles" end
local function tilePath(year, z, row, col) return ("%s/%d_%d_%d_%d.jpg"):format(dir(), year, z, row, col) end

--- Welke stukjes zijn nodig voor een kaart van w x h pixels rond (x, y)?
function T.layout(x, y, z, w, h)
    local res = RES0 / 2 ^ z
    local px, py = (x - ORIGIN_X) / res, (ORIGIN_Y - y) / res
    local left, top = math.floor(px - w / 2), math.floor(py - h / 2)
    local tiles = {}
    for row = math.floor(top / 256), math.floor((top + h - 1) / 256) do
        for col = math.floor(left / 256), math.floor((left + w - 1) / 256) do
            tiles[#tiles + 1] = { row = row, col = col, dx = col * 256 - left, dy = row * 256 - top }
        end
    end
    return tiles
end

function T.missing(year, z, tiles)
    local lfs = require("libs/libkoreader-lfs")
    local n = 0
    for _, t in ipairs(tiles) do if not lfs.attributes(tilePath(year, z, t.row, t.col), "mode") then n = n + 1 end end
    return n
end

function T.fetch(year, z, tiles)
    local lfs = require("libs/libkoreader-lfs")
    lfs.mkdir(dir())
    local Net = require("ks_net")
    local bad = 0
    for _, t in ipairs(tiles) do
        local p = tilePath(year, z, t.row, t.col)
        if not lfs.attributes(p, "mode") then
            local ok, body = Net.get(T.TILES:format(year, z, t.row, t.col))
            if ok and body:byte(1) == 0xFF then
                local f = io.open(p, "wb"); if f then f:write(body); f:close() end
            else
                bad = bad + 1
                -- leeg stukje onthouden zodat we het niet steeds opnieuw vragen
                local f = io.open(p, "wb"); if f then f:close() end
            end
        end
    end
    return bad
end

--- Kaart samenstellen tot één beeld.
function T.compose(year, z, tiles, w, h)
    local Blitbuffer = require("ffi/blitbuffer")
    local RenderImage = require("ui/renderimage")
    local bb = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
    bb:fill(Blitbuffer.COLOR_WHITE)
    for _, t in ipairs(tiles) do
        local f = io.open(tilePath(year, z, t.row, t.col), "rb")
        local data = f and f:read("*a")
        if f then f:close() end
        if data and #data > 100 then
            local img = RenderImage:renderImageData(data, #data)
            if img then
                local sx, sy = math.max(0, -t.dx), math.max(0, -t.dy)
                local dx, dy = math.max(0, t.dx), math.max(0, t.dy)
                local cw, ch = math.min(256 - sx, w - dx), math.min(256 - sy, h - dy)
                if cw > 0 and ch > 0 then bb:blitFrom(img, dx, dy, sx, sy, cw, ch) end
                img:free()
            end
        end
    end
    return bb
end

-- Scherm ---------------------------------------------------------------------------------------

function T.summary()
    local s = Store.get("tr.view", {})
    return (s.place or "Elst") .. ", van 1815 tot nu"
end

function T.page(app)
    local W = UI.INNER()
    local v = Store.get("tr.view", {})
    local places = T.places()
    local place
    for _, p in ipairs(places) do if p.name == v.place then place = p end end
    place = place or places[1]
    local yi = v.yi or 4
    local zi = v.zi or 2
    local year, z = T.YEARS[yi], T.ZOOM[zi][2]
    local function set(k, val) local s = Store.get("tr.view", {}); s[k] = val; Store.set("tr.view", s); app.trMap = nil; app:refresh() end

    local header = UI.header("Tijdreis: " .. place.name, function() if app.trMap then app.trMap.bb:free() end app.trMap = nil; app:back() end,
        year .. " · " .. T.ZOOM[zi][1]:lower())
    local names = {}
    for i, zz in ipairs(T.ZOOM) do names[i] = zz[1] end
    local seg = UI.segmented(names, zi, function(i) set("zi", i) end)
    local footer = UI.buttonRow({
        { yi > 1 and ("‹ " .. T.YEARS[yi - 1]) or "‹", function() if yi > 1 then set("yi", yi - 1) end end, small = true, disabled = yi <= 1 },
        { "Plek", function() app:go(T.placePage) end, small = true },
        { yi < #T.YEARS and (T.YEARS[yi + 1] .. " ›") or "›", function() if yi < #T.YEARS then set("yi", yi + 1) end end, small = true, primary = true, disabled = yi >= #T.YEARS },
    })
    local credit = UI.text("Kaart: Kadaster, Esri Nederland (topotijdreis.nl)", { size = 13, color = UI.INK2 })
    local used = header:getSize().h + seg:getSize().h + footer:getSize().h + credit:getSize().h + UI.px(UI.TOPPAD + 70)
    local mw, mh = W, math.max(UI.px(300), UI.H() - used)
    local key = table.concat({ year, z, place.name, mw, mh }, "|")
    local tiles = T.layout(place.x, place.y, z, mw, mh)

    local body
    if app.trMap and app.trMap.key == key then
        body = require("ui/widget/imagewidget"):new{ image = app.trMap.bb, image_disposable = false, width = mw, height = mh }
    elseif T.missing(year, z, tiles) == 0 then
        if app.trMap then app.trMap.bb:free() end
        app.trMap = { key = key, bb = T.compose(year, z, tiles, mw, mh) }
        body = require("ui/widget/imagewidget"):new{ image = app.trMap.bb, image_disposable = false, width = mw, height = mh }
    else
        body = UI.center(UI.text(app.trMsg or ("Kaart van " .. year .. " ophalen..."), { size = 18, color = UI.INK2 }), mw, mh)
        UIManager:nextTick(function()
            require("ks_net").online(function()
                local bad = T.fetch(year, z, tiles)
                app.trMsg = bad == #tiles and ("Voor " .. year .. " is hier geen kaart.") or nil
                app:refresh()
            end)
        end)
    end
    return UI.page(UI.vgroup({ header, seg, UI.vspace(8), body, UI.vspace(4), credit }), footer)
end

function T.placePage(app)
    local W = UI.INNER()
    local items = { UI.header("Welke plek?", function() app:back() end, "Of zoek een adres, straat of plaats") }
    for _, p in ipairs(T.places()) do
        table.insert(items, UI.row(p.name, nil, "›", function()
            local s = Store.get("tr.view", {}); s.place = p.name; Store.set("tr.view", s)
            app.trMap = nil; app:back()
        end))
    end
    if app.trMsg2 then table.insert(items, UI.vspace(10)); table.insert(items, UI.text(app.trMsg2, { size = 17, width = W })) end
    return UI.page(UI.vgroup(items), UI.button("Andere plek zoeken", function()
        require("ks_opvolg").ask("Plek zoeken", "Bijv. Markt Elst of Grote Markt Nijmegen", function(q)
            if not q or q == "" then return end
            require("ks_net").online(function()
                local p, err = T.search(q)
                if p then
                    local own = Store.get("tr.places", {})
                    table.insert(own, p)
                    while #own > 8 do table.remove(own, 1) end
                    Store.set("tr.places", own)
                    local s = Store.get("tr.view", {}); s.place = p.name; Store.set("tr.view", s)
                    app.trMap, app.trMsg2 = nil, nil
                    app:back()
                else
                    app.trMsg2 = err; app:refresh()
                end
            end)
        end, { ok = "Zoeken" })
    end, { width = W }))
end

return T
