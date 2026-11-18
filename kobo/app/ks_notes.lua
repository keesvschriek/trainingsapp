-- Notities: zelfde lijst als in de app K op je telefoon (tabel "notes").
-- Lezen per map, nieuwe notitie typen, vastzetten of weghalen.

local UI = require("ks_ui")
local Sync = require("ks_sync")

local N = {}

N.FOLDERS = { "Ideeën", "Citaten", "Lezen en kijken", "Werk", "Thuis", "Overig" }

function N.list(folder)
    local l = Sync.list("notes", function(n) return type(n.text) == "string" and n.text ~= "" and (not folder or n.folder == folder) end)
    table.sort(l, function(a, b)
        if (a.pinned and 1 or 0) ~= (b.pinned and 1 or 0) then return a.pinned == true end
        return (a.createdAt or 0) > (b.createdAt or 0)
    end)
    return l
end

local function newId()
    local f = io.open("/dev/urandom", "rb")
    local b = f and f:read(16) or tostring(os.time() .. math.random())
    if f then f:close() end
    local h = b:gsub(".", function(c) return ("%02x"):format(c:byte()) end):sub(1, 32)
    return ("%s-%s-4%s-a%s-%s"):format(h:sub(1, 8), h:sub(9, 12), h:sub(14, 16), h:sub(18, 20), h:sub(21, 32))
end

function N.add(text, folder)
    if not text or text:gsub("%s", "") == "" then return end
    Sync.put("notes", { id = newId(), text = text, folder = folder or "Ideeën", createdAt = os.time() * 1000, from = "kobo" })
    Sync.soon()
end

function N.summary()
    local n = #N.list()
    return n == 0 and "Ideeën, citaten, iets om te lezen of kijken" or (n .. (n == 1 and " notitie" or " notities"))
end

local MON = { "jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec" }
local function when(ms)
    local t = math.floor((ms or 0) / 1000)
    return tonumber(os.date("%d", t)) .. " " .. MON[tonumber(os.date("%m", t))]
end

function N.page(app)
    local W = UI.INNER()
    local folder = app.noteFolder
    local list = N.list(folder)
    local items = { UI.header("Notities", function() app.noteFolder = nil; app:back() end, (folder or "Alle mappen") .. " · " .. #list) }
    -- mappen
    local names, cur = { "Alles" }, 1
    for i, f in ipairs(N.FOLDERS) do names[#names + 1] = f; if f == folder then cur = i + 1 end end
    local short = { "Alles", "Ideeën", "Citaten", "Lezen", "Werk", "Thuis", "Overig" }
    table.insert(items, UI.segmented(short, cur, function(i) app.noteFolder = i > 1 and N.FOLDERS[i - 1] or nil; app.notePg = 1; app:refresh() end))
    table.insert(items, UI.vspace(10))
    local per = 6
    local np = math.max(1, math.ceil(#list / per))
    local pg = math.min(app.notePg or 1, np)
    if #list == 0 then
        table.insert(items, UI.text("Nog niets in deze map. Typ hieronder een notitie, of maak er een in de app K.", { size = 18, color = UI.INK2, width = W }))
    end
    for i = (pg - 1) * per + 1, math.min(#list, pg * per) do
        local n = list[i]
        local txt = n.text
        if #txt > 220 then txt = txt:sub(1, 210):gsub("[\128-\191]*$", ""):gsub("%s%S*$", "") .. " ..." end
        table.insert(items, UI.Tap:new{ label = n.text:sub(1, 30), callback = function() app.note = n; app:go(N.view) end, UI.vgroup({
            UI.vspace(10),
            UI.text((n.pinned and "• " or "") .. txt, { size = 18, width = W }),
            UI.vspace(4),
            UI.text((folder and "" or (n.folder .. " · ")) .. when(n.createdAt) .. (n.from == "kobo" and " · Kobo" or ""), { size = 14, color = UI.INK2 }),
            UI.vspace(10),
            UI.line(W),
        }) })
    end
    local btns = { { "Notitie typen", function()
        require("ks_opvolg").ask("Notitie" .. (folder and (" in " .. folder) or ""), "Wat wil je onthouden?", function(txt)
            N.add(txt, folder or "Ideeën")
            app:refresh()
        end)
    end, primary = true } }
    if np > 1 then table.insert(btns, 1, { pg .. "/" .. np, function() app.notePg = pg % np + 1; app:refresh() end, small = true }) end
    return UI.page(UI.vgroup(items), UI.buttonRow(btns))
end

function N.view(app)
    local W = UI.INNER()
    local n = app.note
    local items = { UI.header(n.folder or "Notitie", function() app:back() end, when(n.createdAt) .. (n.from == "kobo" and " · gemaakt op de Kobo" or " · van je telefoon")) }
    table.insert(items, UI.vspace(6))
    table.insert(items, UI.text(n.text, { font = "serif", size = 22, width = W }))
    return UI.page(UI.vgroup(items), UI.buttonRow({
        { "Weghalen", function() n.deleted = true; Sync.put("notes", n); Sync.soon(); app:back() end, small = true },
        { n.pinned and "Losmaken" or "Vastzetten", function() n.pinned = not n.pinned or nil; Sync.put("notes", n); Sync.soon(); app:refresh() end, small = true },
        { "Andere map", function() app:go(N.move) end, small = true },
    }))
end

function N.move(app)
    local W = UI.INNER()
    local n = app.note
    local items = { UI.header("Naar welke map?", function() app:back() end) }
    local half = math.floor((W - UI.px(14)) / 2)
    for i = 1, #N.FOLDERS, 2 do
        local pair = {}
        for j = i, math.min(i + 1, #N.FOLDERS) do
            local f = N.FOLDERS[j]
            table.insert(pair, { f, function() n.folder = f; Sync.put("notes", n); Sync.soon(); app:back() end, primary = f == n.folder })
        end
        table.insert(items, UI.buttonRow(pair, #pair == 1 and half or nil))
        table.insert(items, UI.vspace(12))
    end
    return UI.page(UI.vgroup(items))
end

return N
