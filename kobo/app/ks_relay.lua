-- Vanaf je telefoon, via internet: werkt overal (thuis, op school, via een hotspot).
--
-- De Kobo toont een QR-code en een code. Op je telefoon open je de verstuurpagina (via de QR-code),
-- plakt de tekst en verstuurt. De telefoon versleutelt de tekst met de code en zet hem kort neer
-- bij ntfy.sh, een gratis doorgeefdienst. De Kobo haalt hem daar op en ontsleutelt hem.
-- ntfy.sh ziet alleen onleesbare tekst; de code staat alleen op het scherm van de Kobo.

local UIManager = require("ui/uimanager")
local UI = require("ks_ui")

local R = {}

R.PAGE = os.getenv("KEES_STUDY_SEND_URL") or "https://keesvschriek.github.io/trainingsapp/kobo/stuur.html"
R.NTFY = os.getenv("KEES_STUDY_NTFY_URL") or "https://ntfy.sh/"
R.MINUTES = 10
local ALPHA = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

local function sha() return require("ffi/sha2") end

local function randomCode()
    local bytes
    local f = io.open("/dev/urandom", "rb")
    if f then bytes = f:read(8); f:close() end
    if not bytes or #bytes < 8 then
        math.randomseed(os.time() + math.floor(os.clock() * 1e6))
        local t = {}
        for i = 1, 8 do t[i] = string.char(math.random(0, 255)) end
        bytes = table.concat(t)
    end
    local out = {}
    for i = 1, 8 do
        local n = bytes:byte(i) % #ALPHA + 1
        out[i] = ALPHA:sub(n, n)
    end
    return table.concat(out)
end

function R.topic(code) return "ks-" .. sha().sha256("kees-topic:" .. code):sub(1, 24) end

local function keystream(code, len)
    local parts, i = {}, 0
    while #table.concat(parts) < len do
        table.insert(parts, sha().hex2bin(sha().sha256("kees-key:" .. code .. ":" .. i)))
        i = i + 1
    end
    return table.concat(parts):sub(1, len)
end

local function xor(a, b)
    local bit = require("bit")
    local out = {}
    for i = 1, #a do out[i] = string.char(bit.bxor(a:byte(i), b:byte(i))) end
    return table.concat(out)
end

function R.encrypt(code, text)
    local c = xor(text, keystream(code, #text))
    return "v1." .. sha().bin2base64(c) .. "." .. sha().sha256("kees-mac:" .. code .. text):sub(1, 16)
end

function R.decrypt(code, msg)
    local b64, mac = msg:match("^v1%.([%w%+/=]+)%.(%x+)$")
    if not b64 then return nil end
    local ok, c = pcall(sha().base642bin, b64)
    if not ok or not c then return nil end
    local text = xor(c, keystream(code, #c))
    if sha().sha256("kees-mac:" .. code .. text):sub(1, 16) ~= mac then return nil end
    return text
end

--- opts: { title, hint, label, onSubmit = function(text) -> ok, msg }
function R.start(opts)
    R.stop()
    local code = randomCode()
    local sess = { code = code, topic = R.topic(code), opts = opts, since = os.time() - 5, ends = os.time() + R.MINUTES * 60 }
    R.sess = sess
    local function poll()
        if R.sess ~= sess or sess.result or sess.fail then return end
        if os.time() > sess.ends then
            sess.fail = "De tijd is om. Start opnieuw als je nog iets wilt sturen."
            if sess.onChange then sess.onChange() end
            return
        end
        pcall(function() require("ks_net").touch() end)
        local ok, body = require("ks_net").get(R.NTFY .. sess.topic .. "/json?poll=1&since=" .. sess.since)
        if ok and type(body) == "string" then
            for line in body:gmatch("[^\n]+") do
                local good, m = pcall(require("ks_json").decode, line)
                if good and type(m) == "table" and m.event == "message" and type(m.message) == "string" then
                    local text = R.decrypt(code, m.message)
                    if text then
                        local okSubmit, msg = opts.onSubmit((text:gsub("^%s+", ""):gsub("%s+$", "")))
                        if okSubmit then
                            sess.result = msg or "Ontvangen."
                        else
                            sess.warn = msg or "Dat ging niet goed. Probeer het nog eens."
                        end
                        if type(m.time) == "number" then sess.since = m.time + 1 end
                        if sess.onChange then sess.onChange() end
                        if sess.result then return end
                    end
                end
            end
        end
        UIManager:scheduleIn(3, poll)
    end
    UIManager:scheduleIn(1, poll)
    return sess
end

function R.stop() R.sess = nil end

function R.url(sess) return R.PAGE .. "#c=" .. sess.code .. (sess.opts.mode and ("&m=" .. sess.opts.mode) or "") end

function R.screen(app)
    local W = UI.INNER()
    local sess = R.sess
    local function done() R.stop(); app:back() end
    local items = { UI.header("Vanaf je telefoon", done, sess and sess.opts.title or "") }
    if not sess then
        table.insert(items, UI.text("Er staat niets open.", { size = 19, width = W }))
        return UI.page(UI.vgroup(items))
    end
    sess.onChange = function() app:refresh() end
    if sess.result then
        table.insert(items, UI.text("Gelukt", { font = "display", size = 28 }))
        table.insert(items, UI.vspace(8))
        table.insert(items, UI.text(sess.result, { size = 19, width = W }))
        table.insert(items, UI.vspace(24))
        table.insert(items, UI.button("Klaar", done, { width = W, primary = true }))
        return UI.page(UI.vgroup(items))
    end
    if sess.fail then
        table.insert(items, UI.text(sess.fail, { size = 19, width = W }))
        table.insert(items, UI.vspace(24))
        table.insert(items, UI.button("Terug", done, { width = W }))
        return UI.page(UI.vgroup(items))
    end
    local codeText = sess.code:sub(1, 4) .. " " .. sess.code:sub(5, 8)
    local ok, QR = pcall(require, "ui/widget/qrwidget")
    if sess.opts.mode == "koppel" then
        -- makkelijkst: in de app op je telefoon de code overtypen
        table.insert(items, UI.text("Open de app K op je telefoon, tik rechtsboven op het tandwiel, kies Kobo koppelen en typ deze code met je wachtwoord:", { size = 18, width = W }))
        table.insert(items, UI.vspace(14))
        table.insert(items, UI.card(UI.center(UI.text(codeText, { font = "display", size = 48 }), W - UI.px(40))))
        table.insert(items, UI.vspace(18))
        if ok then
            local q = UI.px(170)
            table.insert(items, UI.hgroup({
                QR:new{ text = R.url(sess), width = q, height = q }, UI.hspace(16),
                UI.text("Andere telefoon of geen app bij de hand? Scan deze code; dan vul je alles in de browser in.", { size = 15, color = UI.INK2, width = W - q - UI.px(16) }),
            }, "center"))
        end
    else
        table.insert(items, UI.text("Scan de code met de camera van je telefoon, plak de tekst en tik op Versturen.", { size = 18, width = W }))
        table.insert(items, UI.vspace(16))
        local qrSize = math.min(W, UI.px(300))
        if ok then
            table.insert(items, UI.center(QR:new{ text = R.url(sess), width = qrSize, height = qrSize }, W, qrSize))
            table.insert(items, UI.vspace(16))
        end
        table.insert(items, UI.card(UI.vgroup({
            UI.text("Geen camera? Ga naar", { size = 15, color = UI.INK2 }),
            UI.text(R.PAGE:gsub("^https://", ""), { size = 15, width = W - UI.px(40) }),
            UI.vspace(8),
            UI.text("en vul deze code in:", { size = 15, color = UI.INK2 }),
            UI.text(codeText, { font = "display", size = 34 }),
        })))
    end
    table.insert(items, UI.vspace(12))
    if sess.warn then
        table.insert(items, UI.text(sess.warn, { size = 16, font = "bold", width = W }))
        table.insert(items, UI.vspace(8))
    end
    table.insert(items, UI.text(("Wacht op je telefoon, tot %s. De tekst gaat versleuteld via ntfy.sh."):format(os.date("%H:%M", sess.ends)), { size = 15, color = UI.INK2, width = W }))
    table.insert(items, UI.vspace(16))
    table.insert(items, UI.button("Stoppen", done, { width = W }))
    return UI.page(UI.vgroup(items))
end

--- Kort: wifi aan, starten en het scherm tonen.
function R.open(app, opts, onError)
    require("ks_net").online(function()
        R.start(opts)
        app:go(R.screen)
    end, { onFail = function(msg) onError(msg) end })
end

return R
