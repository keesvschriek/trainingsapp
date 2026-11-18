-- Jouw Kamer: stem zelf op echte moties waarover de Tweede Kamer stemde.
-- Pas na jouw stem zie je de uitslag en hoe de fracties stemden.
-- Na een paar moties zie je met welke fracties je het vaakst eens was, op basis van echt stemgedrag.
-- De indiener staat er bewust niet bij, zodat je op de inhoud stemt.

local UI = require("ks_ui")
local Store = require("ks_store")

local J = {}

local function str(v) return type(v) == "string" and v or nil end

--- "Gewijzigde motie van het lid X c.s. over iets doen" wordt "Iets doen".
function J.clean(titel)
    local t = titel or ""
    t = t:gsub("^%s+", "")
    local rest = t:match("^.-[Mm]otie van .- over (.+)$")
    if rest then t = rest end
    t = t:gsub("%s*%(t%.?v%.?v%..-%)%s*$", ""):gsub("%s+$", "")
    return (t:gsub("^%l", string.upper))
end

local function topics(it)
    local K = require("ks_kamer")
    local tp = K.topicsOf((it.titel or "") .. " " .. (it.ctx or ""), it.ctx)
    local list = {}
    for _, t in ipairs(K.TOPICS) do if tp[t.key] then list[#list + 1] = t.key end end
    return list
end

--- Nieuwe moties toevoegen aan de voorraad (na elke Kamer-ronde).
function J.addPool(items, datum)
    local pool = Store.get("jk.pool", {})
    local votes = Store.get("jk.votes", {})
    local have = {}
    for _, p in ipairs(pool) do have[p.id] = true end
    for id in pairs(votes) do have[id] = true end
    for _, it in ipairs(items or {}) do
        local id = str(it.nummer)
        local isMotie = (it.soort == "Motie") or (it.titel or ""):lower():find("motie", 1, true)
        if id and isMotie and not have[id] and type(it.votes) == "table" and next(it.votes) then
            have[id] = true
            table.insert(pool, { id = id, titel = J.clean(it.titel), ctx = it.ctx, uitslag = it.uitslag, votes = it.votes,
                nv = it.nv, nt = it.nt, datum = datum, topics = topics(it) })
        end
    end
    -- hooguit 150 bewaren, de nieuwste
    while #pool > 150 do table.remove(pool, 1) end
    Store.set("jk.pool", pool)
end

--- Eerste keer: de laatste stemmingsdagen ophalen zodat er genoeg moties zijn.
function J.fill()
    local list = require("ks_kamer").fetchRecent(4)
    for _, d in ipairs(list or {}) do J.addPool(d.items, d.datum) end
end

--- Volgende motie: eerst je onderwerpen (Defensie, Onderwijs, Buitenland, Sport), nieuwste eerst.
function J.next()
    local pool = Store.get("jk.pool", {})
    local best, bestScore
    for i = #pool, 1, -1 do
        local p = pool[i]
        local score = (#(p.topics or {}) > 0 and 1000 or 0) + i
        if not bestScore or score > bestScore then best, bestScore = p, score end
    end
    return best
end

function J.vote(p, mine)
    local votes = Store.get("jk.votes", {})
    votes[p.id] = { titel = p.titel, ctx = p.ctx, datum = p.datum, mine = mine, votes = p.votes, uitslag = p.uitslag, topics = p.topics, at = os.time() }
    Store.set("jk.votes", votes)
    local pool = Store.get("jk.pool", {})
    for i, x in ipairs(pool) do if x.id == p.id then table.remove(pool, i); break end end
    Store.set("jk.pool", pool)
end

--- Overeenkomst per fractie. topic: alleen moties over dat onderwerp. Geeft gesorteerde lijst {fr, eens, n}.
function J.scores(topic)
    local per = {}
    local total = 0
    for _, v in pairs(Store.get("jk.votes", {})) do
        local inTopic = not topic
        for _, t in ipairs(v.topics or {}) do if t == topic then inTopic = true end end
        if v.mine ~= "S" and inTopic then
            total = total + 1
            for fr, s in pairs(v.votes or {}) do
                per[fr] = per[fr] or { fr = fr, eens = 0, n = 0 }
                per[fr].n = per[fr].n + 1
                if s == v.mine then per[fr].eens = per[fr].eens + 1 end
            end
        end
    end
    local list = {}
    for _, x in pairs(per) do list[#list + 1] = x end
    table.sort(list, function(a, b)
        local pa, pb = a.eens / a.n, b.eens / b.n
        if pa ~= pb then return pa > pb end
        return a.fr < b.fr
    end)
    return list, total
end

function J.count()
    local n = 0
    for _, v in pairs(Store.get("jk.votes", {})) do if v.mine ~= "S" then n = n + 1 end end
    return n
end

function J.summary()
    local n = J.count()
    local p = J.next()
    if n == 0 then return "Stem zelf op echte moties en zie wie er net zo stemde" end
    return n .. " keer gestemd" .. (p and " · nieuwe motie klaar" or "")
end

-- Schermen ----------------------------------------------------------------------------------

local function fractions(votes, want)
    local l = {}
    for fr, s in pairs(votes or {}) do if s == want then l[#l + 1] = fr end end
    table.sort(l)
    return table.concat(l, ", ")
end

function J.page(app)
    local W = UI.INNER()
    local items = { UI.header("Jouw Kamer", function() app.jk = nil; app:back() end, J.count() .. " keer gestemd") }
    local s = app.jk or {}
    app.jk = s
    if not s.cur and not s.voted then s.cur = J.next() end
    local p = s.cur
    if not p then
        table.insert(items, UI.text("Er staan nu geen nieuwe moties klaar. Na de volgende stemmingen in de Kamer (meestal dinsdag) komen er nieuwe bij.", { size = 19, width = W }))
        return UI.page(UI.vgroup(items), UI.buttonRow({
            { "Moties ophalen", function()
                require("ks_net").online(function()
                    local ok = pcall(J.fill)
                    s.cur = J.next(); s.msg = (ok and s.cur) and nil or "Ophalen lukte niet."
                    app:refresh()
                end)
            end },
            { "Uitslag", function() app:go(J.result) end, primary = true },
        }))
    end
    table.insert(items, UI.text((p.ctx and (p.ctx:gsub("^Vaststelling van de begrotingsstaten van het ", "Begroting ")) or "Motie") .. (p.datum and (" · gestemd op " .. p.datum) or ""), { size = 15, color = UI.INK2, width = W }))
    table.insert(items, UI.vspace(8))
    table.insert(items, UI.card(UI.vgroup({
        UI.text("De Kamer vraagt de regering:", { size = 15, color = UI.INK2 }),
        UI.vspace(6),
        UI.text(p.titel, { font = "serif", size = 23, width = W - UI.px(56), bg = UI.FILL }),
    }), { fill = true, border = 0, pad = UI.px(22) }))
    table.insert(items, UI.vspace(16))
    if not s.voted then
        table.insert(items, UI.text("Hoe zou jij stemmen?", { font = "medium", size = 20 }))
        return UI.page(UI.vgroup(items), UI.buttonRow({
            { "Overslaan", function() J.vote(p, "S"); s.cur = J.next(); app:refresh() end, small = true },
            { "Tegen", function() J.vote(p, "T"); s.voted = "T"; app:refresh() end },
            { "Voor", function() J.vote(p, "V"); s.voted = "V"; app:refresh() end, primary = true },
        }))
    end
    -- uitslag na jouw stem
    table.insert(items, UI.text("Jij stemde " .. (s.voted == "V" and "voor" or "tegen") .. ". De motie is " .. ((p.uitslag or ""):lower():find("aangenomen") and "aangenomen" or ((p.uitslag or ""):lower():find("verworpen") and "verworpen" or (p.uitslag or "behandeld"))) .. ".", { font = "medium", size = 20, width = W }))
    table.insert(items, UI.vspace(10))
    table.insert(items, UI.text("Voor (" .. (p.nv or 0) .. "): " .. fractions(p.votes, "V"), { size = 16, width = W }))
    table.insert(items, UI.vspace(6))
    table.insert(items, UI.text("Tegen (" .. (p.nt or 0) .. "): " .. fractions(p.votes, "T"), { size = 16, width = W, color = UI.INK2 }))
    return UI.page(UI.vgroup(items), UI.buttonRow({
        { "Uitslag", function() app:go(J.result) end },
        { "Volgende motie", function() s.voted = nil; s.cur = J.next(); app:refresh() end, primary = true },
    }))
end

function J.result(app)
    local W = UI.INNER()
    local K = require("ks_kamer")
    local topic = app.jkTopic
    local list, total = J.scores(topic)
    local items = { UI.header("Met wie stem je mee?", function() app:back() end, total .. " moties" .. (topic and " over dit onderwerp" or "") .. ", op basis van echt stemgedrag") }
    local names, cur, keys = { "Alles" }, 1, { false }
    for _, t in ipairs(K.TOPICS) do names[#names + 1] = t.name; keys[#keys + 1] = t.key; if t.key == topic then cur = #names end end
    table.insert(items, UI.segmented(names, cur, function(i) app.jkTopic = keys[i] or nil; app:refresh() end))
    table.insert(items, UI.vspace(12))
    if total < 5 then
        table.insert(items, UI.text("Stem eerst op een paar moties. Vanaf vijf zegt de uitslag iets.", { size = 18, color = UI.INK2, width = W }))
    end
    local bw = W - UI.px(260)
    for i, x in ipairs(list) do
        if i > 16 then break end
        local frac = x.eens / x.n
        local full = math.floor(bw * frac)
        table.insert(items, UI.hgroup({
            UI.text(x.fr, { size = 16, width = UI.px(170), max_width = UI.px(170) }),
            UI.hgroup({ full > 0 and UI.line(full, UI.BLACK, UI.px(8)) or nil, UI.line(bw - full, UI.LINE, UI.px(8)) }),
            UI.hspace(10),
            UI.text(math.floor(frac * 100 + 0.5) .. "%", { size = 16, font = "medium" }),
        }))
        table.insert(items, UI.vspace(7))
    end
    table.insert(items, UI.vspace(8))
    table.insert(items, UI.text("Een fractie telt alleen mee bij moties waarover ze stemde. Overgeslagen moties tellen niet.", { size = 14, color = UI.INK2, width = W }))
    return UI.page(UI.vgroup(items))
end

return J
