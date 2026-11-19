-- Quizlogica: vragen laden, kiezen, records bijhouden en nieuwe pakketten ophalen.

local DataStorage = require("datastorage")
local json = require("ks_json")
local Store = require("ks_store")

local Q = {}
Q.PACKS_URL = os.getenv("KEES_STUDY_PACKS_URL") or "https://raw.githubusercontent.com/keesvschriek/trainingsapp/main/quiz-packs/index.json"

local data -- { cats, groups, questions, countries }

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function packsPath() return DataStorage:getSettingsDir() .. "/keesstudy-packs.json" end

local function packId(pid, q) return "p:" .. pid .. ":" .. #q.q .. ":" .. q.q:sub(1, 24) end

function Q.load(dir)
    if data then return data end
    local ok, d = pcall(json.decode, readFile(dir .. "/data/quiz.json") or "{}")
    data = ok and d or { cats = {}, groups = {}, questions = {}, countries = {} }
    data.catByKey = {}
    for _, c in ipairs(data.cats or {}) do data.catByKey[c.key] = c end
    -- eerder opgehaalde pakketten erbij
    local have = {}
    for _, q in ipairs(data.questions) do have[q.id] = true end
    local ok2, packs = pcall(json.decode, readFile(packsPath()) or "{}")
    if ok2 and packs and packs.packs then
        for _, p in ipairs(packs.packs) do
            for _, q in ipairs(p.questions or {}) do
                local id = packId(p.id, q)
                if not have[id] and data.catByKey[q.cat] and type(q.a) == "table" and #q.a == 4 then
                    have[id] = true
                    table.insert(data.questions, { id = id, cat = q.cat, q = q.q, a = q.a, why = q.why or "", asOf = q.asOf or "" })
                end
            end
        end
    end
    return data
end

function Q.catName(key) return data and data.catByKey[key] and data.catByKey[key].name or key end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end
Q.shuffle = shuffle

function Q.visible()
    local removed = Store.get("quiz.removed", {})
    local out = {}
    for _, q in ipairs(data.questions) do if not removed[q.id] then out[#out + 1] = q end end
    return out
end

function Q.counts()
    local c = {}
    for _, q in ipairs(Q.visible()) do c[q.cat] = (c[q.cat] or 0) + 1 end
    return c
end

--- n vragen uit de categorieën (leeg = alles), liefst nog niet gezien.
function Q.pick(cats, n)
    local want = {}
    for _, k in ipairs(cats or {}) do want[k] = true end
    local seen = Store.get("quiz.seen", {})
    local fresh, old = {}, {}
    for _, q in ipairs(Q.visible()) do
        if not next(want) or want[q.cat] then
            if seen[q.id] then old[#old + 1] = q else fresh[#fresh + 1] = q end
        end
    end
    shuffle(fresh)
    table.sort(old, function(a, b) return seen[a.id] < seen[b.id] end) -- langst geleden eerst
    -- eerst nieuwe vragen, dan vragen die je langer dan een week niet zag, pas dan recentere
    local week = os.time() - 7 * 86400
    local older, recent = {}, {}
    for _, q in ipairs(old) do if (tonumber(seen[q.id]) or 0) < week then older[#older + 1] = q else recent[#recent + 1] = q end end
    local out, answers = {}, {}
    local function add(q)
        -- hetzelfde antwoord maar één keer per ronde (zelfde feit, andere vraag)
        local key = type(q.a) == "table" and type(q.a[1]) == "string" and q.a[1]:lower() or q.id
        if #out >= n or answers[key] then return end
        answers[key] = true
        out[#out + 1] = q
    end
    for _, q in ipairs(fresh) do add(q) end
    for _, q in ipairs(older) do add(q) end
    for _, q in ipairs(recent) do add(q) end
    return out
end

function Q.wrongList(n)
    local wrong = Store.get("quiz.wrong", {})
    local out = {}
    for _, q in ipairs(Q.visible()) do if wrong[q.id] then out[#out + 1] = q end end
    shuffle(out)
    while #out > n do table.remove(out) end
    return out
end

--- Hoofdsteden: gegenereerde vragen. dir = "cap" (land -> hoofdstad) of "land".
function Q.capitals(region, n, dir)
    local pool = {}
    for _, c in ipairs(data.countries) do if not region or c.region == region then pool[#pool + 1] = c end end
    shuffle(pool)
    local out = {}
    for i = 1, math.min(n, #pool) do
        local c = pool[i]
        local others, used = {}, { [c] = true }
        local tries = 0
        while #others < 3 and tries < 200 do
            tries = tries + 1
            local o = pool[math.random(#pool)]
            if not used[o] and o.cap ~= c.cap then used[o] = true; others[#others + 1] = o end
        end
        if #others < 3 then break end
        if dir == "land" then
            out[#out + 1] = { id = "gen:land:" .. c.name, cat = "aardrijkskunde", q = c.cap .. " is de hoofdstad van:", a = { c.name, others[1].name, others[2].name, others[3].name }, why = "" }
        else
            out[#out + 1] = { id = "gen:cap:" .. c.name, cat = "aardrijkskunde", q = "Wat is de hoofdstad van " .. c.name .. "?", a = { c.cap, others[1].cap, others[2].cap, others[3].cap },
                why = #c.capAll > 1 and (c.name .. " heeft meer dan één hoofdstad of naam: " .. table.concat(c.capAll, ", ") .. ".") or "" }
        end
    end
    return out
end

function Q.answered(q, right)
    local stats = Store.get("quiz.stats", { answered = 0, correct = 0, days = {} })
    stats.answered = stats.answered + 1
    if right then stats.correct = stats.correct + 1 end
    stats.days[os.date("%Y-%m-%d")] = true
    Store.set("quiz.stats", stats)
    if q.id:sub(1, 4) == "gen:" then return end
    local seen = Store.get("quiz.seen", {})
    seen[q.id] = os.time()
    Store.set("quiz.seen", seen)
    local wrong = Store.get("quiz.wrong", {})
    wrong[q.id] = (not right) or nil
    Store.set("quiz.wrong", wrong)
end

function Q.hide(q)
    local removed = Store.get("quiz.removed", {})
    removed[q.id] = true
    Store.set("quiz.removed", removed)
end

function Q.stats() return Store.get("quiz.stats", { answered = 0, correct = 0, days = {} }) end

function Q.streak()
    local days = Q.stats().days
    local t = os.time()
    if not days[os.date("%Y-%m-%d", t)] then t = t - 86400 end
    local n = 0
    while days[os.date("%Y-%m-%d", t)] do
        n = n + 1
        t = t - 86400
    end
    return n
end

--- Sla een uitslag op. Geeft (isRecord, vorigRecord) terug.
function Q.saveResult(key, score)
    local recs = Store.get("quiz.records", {})
    local prev = recs[key]
    local isRecord = not prev or score > prev.best
    recs[key] = { best = isRecord and score or prev.best, plays = (prev and prev.plays or 0) + 1 }
    Store.set("quiz.records", recs)
    Store.flush()
    return isRecord and prev ~= nil, prev and prev.best
end

function Q.record(key)
    local r = Store.get("quiz.records", {})[key]
    return r and r.best
end

--- Haal pakketten op via wifi. callback(ok, bericht)
function Q.updatePacks(callback)
    local Net = require("ks_net")
    Net.online(function()
        local ok, body = Net.get(Q.PACKS_URL .. "?t=" .. os.time())
        if not ok then return callback(false, body) end
        local good, d = pcall(json.decode, body)
        if not good or type(d) ~= "table" or type(d.packs) ~= "table" then return callback(false, "Onverwacht bestand ontvangen.") end
        Q.load(require("ks_main").dir)
        local before = #data.questions
        local f = io.open(packsPath(), "wb")
        if f then f:write(body); f:close() end
        data = nil
        Q.load(require("ks_main").dir)
        local added = #data.questions - before
        callback(true, added > 0 and (added .. " nieuwe vragen binnen.") or "Geen nieuwe vragen: je bent bij.")
    end, { onFail = function(msg) callback(false, msg) end })
end

return Q
