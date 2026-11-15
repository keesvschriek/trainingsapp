-- Kees Study: start de eigen app als KOReader is opgestart met KEES_STUDY=1.
-- Zonder die variabele doet dit bestand niets en start KOReader gewoon.
if os.getenv("KEES_STUDY") ~= "1" then return end

local dir = os.getenv("KEES_STUDY_DIR") or "/mnt/onboard/.adds/keesstudy/app"
package.path = dir .. "/?.lua;" .. package.path

local UIManager = require("ui/uimanager")
local Device = require("device")
local logger = require("logger")

math.randomseed(os.time())
local ok, err = pcall(function() require("ks_main").run(dir) end)
if not ok then
    logger.err("Kees Study kon niet starten:", err)
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = "Kees Study kon niet starten:\n" .. tostring(err) })
    return -- KOReader start daarna op de gewone manier
end

local code = UIManager:run()
pcall(function() require("ks_store").flush() end)

-- Netjes afsluiten, zoals KOReader dat zelf ook doet
local userpatch = require("userpatch")
userpatch.applyPatches(userpatch.before_exit)
Device:exit()
userpatch.applyPatches(userpatch.on_exit)
os.exit(type(code) == "number" and code or 0, true)
