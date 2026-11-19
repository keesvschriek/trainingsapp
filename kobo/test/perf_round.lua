-- Meet hoe lang de krantenronde de Kobo laat haperen: de langste pauze tussen twee tikken van een klokje.
local UIManager = require("ui/uimanager")
local T = require("ui/time")
local function now() return T.to_ms(T.now()) end
local steps = {}
local state = { done = false, maxGap = 0, gaps = 0, last = nil, t0 = nil }
local function beat()
    if state.done then return end
    local t = now()
    if state.last then
        local g = t - state.last
        if g > state.maxGap then state.maxGap = g end
        if g > 500 then state.gaps = state.gaps + 1 end
    end
    state.last = t
    UIManager:scheduleIn(0.05, beat)
end
local function wait()
    if state.news and not state.done and not require("ks_net").busy() then state.done = true; state.t1 = now() end
    if not state.done then table.insert(steps, wait) return end
    print(("KSTEST nieuws na %.1f s"):format((state.news - state.t0) / 1000))
    print(("KSTEST ronde klaar in %.1f s, langste hapering %.0f ms, %d keer langer dan 0,5 s"):format((state.t1 - state.t0) / 1000, state.maxGap, state.gaps))
end
steps[1] = function()
    local Store = require("ks_store")
    -- alles als 'nog niet opgehaald' markeren
    local N = require("ks_news"); local d = N.data(); d.key = nil
    Store.set("jk.pool", {}); Store.set("jk.votes", Store.get("jk.votes", {}))
    require("ks_radio").data().date = nil
    local K = require("ks_kamer"); K.data().at = nil
    Store.set("read.at", nil)
    state.t0 = now()
    beat()
    N.refresh(function() state.news = now() end, true)
end
steps[2] = wait
return steps
