-- Vanaf je telefoon: de Kobo zet even een kleine webpagina open op je eigen wifi.
-- Op je telefoon open je het adres, vult de code in en plakt wat je wilt doorsturen.
-- Alles blijft in je eigen netwerk. Na 5 minuten, of na één keer versturen, gaat de pagina weer dicht.

local UIManager = require("ui/uimanager")
local UI = require("ks_ui")

local S = {}

S.PORT = tonumber(os.getenv("KEES_STUDY_SHARE_PORT") or "") or 8080
S.MINUTES = 5

local function myIP()
    -- truc: een UDP-socket "verbinden" verstuurt niets, maar vertelt wel welk adres we hebben
    local ok, ip = pcall(function()
        local socket = require("socket")
        local u = socket.udp()
        u:setpeername("192.0.2.1", 80)
        local addr = u:getsockname()
        u:close()
        return addr
    end)
    if ok and ip and ip ~= "0.0.0.0" then return ip end
    return nil
end

local function esc(s) return (tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")) end

local function urldecode(s)
    s = s:gsub("+", " ")
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function parseForm(body)
    local t = {}
    for k, v in (body or ""):gmatch("([^&=]+)=([^&]*)") do t[urldecode(k)] = urldecode(v) end
    return t
end

local function page(title, inner)
    return [[<!DOCTYPE html><html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>]] .. esc(title) .. [[</title><style>
body{font-family:-apple-system,system-ui,sans-serif;margin:0;padding:24px;color:#111;background:#fff;max-width:520px}
h1{font-size:22px;margin:0 0 6px}p{color:#555;line-height:1.4}
label{display:block;font-weight:600;margin:18px 0 6px}
input,textarea{width:100%;box-sizing:border-box;font-size:17px;padding:12px;border:1.5px solid #111;border-radius:10px}
textarea{min-height:120px}button{margin-top:22px;width:100%;font-size:18px;padding:14px;border:0;border-radius:12px;background:#111;color:#fff}
.ok{font-size:20px;font-weight:600}</style></head><body>]] .. inner .. "</body></html>"
end

local function send(c, code, html)
    c:send(("HTTP/1.1 %s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n%s"):format(code, #html, html))
end

--- Start de pagina. opts: { title, label, hint, multiline, onSubmit = function(text) -> ok, msg }
--- Geeft een sessie terug met ip, port, code, of nil en een fout.
function S.start(opts)
    S.stop()
    local socket = require("socket")
    local srv = socket.tcp()
    srv:setoption("reuseaddr", true)
    local ok, err = srv:bind("*", S.PORT)
    if not ok then srv:close(); return nil, "Kon de pagina niet openen (" .. tostring(err) .. ")." end
    srv:listen(4)
    srv:settimeout(0)
    local ip = os.getenv("KEES_STUDY_SHARE_IP") or myIP()
    if not ip then srv:close(); return nil, "Geen wifi-verbinding. Zet eerst wifi aan." end
    local sess = { srv = srv, ip = ip, port = S.PORT, code = ("%04d"):format(math.random(0, 9999)), opts = opts,
        ends = os.time() + S.MINUTES * 60, tries = 0, done = false }
    S.sess = sess

    local function form(msg)
        return page(opts.title, "<h1>" .. esc(opts.title) .. "</h1><p>" .. esc(opts.hint or "") .. "</p>" ..
            (msg and ("<p><b>" .. esc(msg) .. "</b></p>") or "") ..
            [[<form method="post" action="/"><label for="c">Code op de Kobo</label>
<input id="c" name="code" inputmode="numeric" autocomplete="off" maxlength="4" required>
<label for="t">]] .. esc(opts.label or "Tekst") .. "</label>" ..
            (opts.multiline and '<textarea id="t" name="text" required></textarea>' or '<input id="t" name="text" autocomplete="off" required>') ..
            "<button>Naar de Kobo</button></form>")
    end

    local function handle(c)
        c:settimeout(2)
        local line = c:receive("*l")
        if not line then return end
        local method = line:match("^(%u+)")
        local len = 0
        while true do
            local h = c:receive("*l")
            if not h or h == "" then break end
            local n = h:lower():match("^content%-length:%s*(%d+)")
            if n then len = tonumber(n) end
        end
        if method == "POST" and len > 0 and len < 20000 then
            local body = c:receive(len)
            local f = parseForm(body)
            if sess.done then return send(c, "200 OK", page("Klaar", '<p class="ok">Dit is al verstuurd. De pagina is dicht.</p>')) end
            if f.code ~= sess.code then
                sess.tries = sess.tries + 1
                if sess.tries >= 5 then
                    send(c, "200 OK", page("Gestopt", '<p class="ok">Te vaak een verkeerde code. De Kobo heeft de pagina gesloten.</p>'))
                    sess.fail = "Te vaak een verkeerde code ingevuld. Gestopt."
                    return S.stop()
                end
                return send(c, "200 OK", form("Die code klopt niet."))
            end
            local okSubmit, msg = opts.onSubmit((f.text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
            if okSubmit then
                sess.done = true
                send(c, "200 OK", page("Gelukt", '<p class="ok">Gelukt, staat op de Kobo.</p><p>' .. esc(msg or "") .. "</p><p>Je kunt dit venster sluiten.</p>"))
                sess.result = msg or "Ontvangen."
                return
            end
            return send(c, "200 OK", form(msg or "Dat ging niet goed."))
        end
        send(c, "200 OK", form())
    end

    local function poll()
        if S.sess ~= sess or not sess.srv then return end
        for _ = 1, 4 do
            local c = sess.srv:accept()
            if not c then break end
            pcall(handle, c)
            pcall(function() c:close() end)
        end
        if sess.done or os.time() > sess.ends then
            if not sess.done then sess.fail = "De tijd is om. De pagina is gesloten." end
            UIManager:scheduleIn(1, function() if S.sess == sess then S.stop(true) end end)
            if sess.onChange then sess.onChange() end
            return
        end
        if sess.result or sess.fail then if sess.onChange then sess.onChange() end end
        UIManager:scheduleIn(0.3, poll)
    end
    UIManager:scheduleIn(0.3, poll)
    return sess
end

function S.stop(keep)
    local sess = S.sess
    if sess and sess.srv then pcall(function() sess.srv:close() end); sess.srv = nil end
    if not keep then S.sess = nil end
    if sess and sess.onChange and keep then sess.onChange() end
end

--- Scherm met adres en code. back: terug naar het vorige scherm.
function S.screen(app)
    local W = UI.INNER()
    local sess = S.sess
    local items = { UI.header("Vanaf je telefoon", function() S.stop(); app:back() end, sess and sess.opts.title or "") }
    if not sess then
        table.insert(items, UI.text("Er staat geen pagina open.", { size = 20, width = W }))
        return UI.page(UI.vgroup(items))
    end
    sess.onChange = function() app:refresh() end
    if sess.result then
        table.insert(items, UI.text("Gelukt", { font = "bold", size = 28 }))
        table.insert(items, UI.vspace(8))
        table.insert(items, UI.text(sess.result, { size = 20, width = W }))
        table.insert(items, UI.vspace(24))
        table.insert(items, UI.button("Klaar", function() S.stop(); app:back() end, { width = W, primary = true }))
        return UI.page(UI.vgroup(items))
    end
    if sess.fail then
        table.insert(items, UI.text(sess.fail, { size = 20, width = W }))
        table.insert(items, UI.vspace(24))
        table.insert(items, UI.button("Terug", function() S.stop(); app:back() end, { width = W }))
        return UI.page(UI.vgroup(items))
    end
    table.insert(items, UI.text("Open op je telefoon (op dezelfde wifi):", { size = 19, color = UI.INK2, width = W }))
    table.insert(items, UI.vspace(10))
    table.insert(items, UI.card(UI.text(sess.ip .. ":" .. sess.port, { font = "bold", size = 34, bg = UI.FILL, width = W - UI.px(44) }), { fill = true, border = 0 }))
    table.insert(items, UI.vspace(20))
    table.insert(items, UI.text("Code", { size = 19, color = UI.INK2 }))
    table.insert(items, UI.text(sess.code:sub(1, 2) .. " " .. sess.code:sub(3, 4), { font = "bold", size = 56 }))
    table.insert(items, UI.vspace(16))
    table.insert(items, UI.text(("De pagina gaat om %s dicht, of zodra je iets hebt verstuurd. Alles blijft op je eigen wifi."):format(os.date("%H:%M", sess.ends)),
        { size = 16, color = UI.INK2, width = W }))
    table.insert(items, UI.vspace(24))
    table.insert(items, UI.button("Stoppen", function() S.stop(); app:back() end, { width = W }))
    return UI.page(UI.vgroup(items))
end

--- Kort: start en toon het scherm, of meld de fout.
function S.open(app, opts, onError)
    local function go()
        local sess, err = S.start(opts)
        if not sess then return onError(err) end
        app:go(S.screen)
    end
    require("ks_net").online(go, { onFail = function(msg) onError(msg) end })
end

return S
