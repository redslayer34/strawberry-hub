--=============================================================================
-- VOLCANO SMOKE TESTS — volcano.lua, start to finish
--=============================================================================
--  volcano has already run (smokeprelude + volcanoprelude): the engines and
--  its own loop run, the panel exists, the config was read, and Unload
--  releases all of it.
--=============================================================================

local passed, failed = 0, 0
local failures = {}

local function check(name, condition, detail)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = name .. (detail ~= nil and ("  -- " .. tostring(detail)) or "")
    end
end

local function eq(name, actual, expected)
    check(name, actual == expected,
        string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local Loop = require("Core.Loop")
local Settings = require("Core.Settings")
local VolcanoScreen = require("Volcano.Screen")
local player = game:GetService("Players").LocalPlayer
local heartbeat = game:GetService("RunService").Heartbeat

check("volcano returned its table", type(SMOKE_VOLCANO) == "table")
eq("registered globally", getgenv().StrawberryVolcanoHub, SMOKE_VOLCANO)
eq("version", SMOKE_VOLCANO.Version, "1.0.0")
check("no warning during load", #WARNINGS == 0, table.concat(WARNINGS, " | "))
eq("no Fluent downloaded", #FAKE.urls, 0)

eq("config: weapon", SMOKE_VOLCANO.Config.Weapon, "Sword")
eq("config: bones off", SMOKE_VOLCANO.Config.CollectBones, false)
eq("config: other keys kept", SMOKE_VOLCANO.Config.CraftMagnet, true)
eq("config: skill weapons kept", SMOKE_VOLCANO.Config.SkillWeapons.Gun, true)

check("farm loop running", Loop.isRunning("Farm"))
check("attack loop running", Loop.isRunning("Attack"))
check("volcano loop running", Loop.isRunning("Volcano"))
check("no Kaitun loop", not Loop.isRunning("Kaitun"))
check("no island report without a webhook", not Loop.isRunning("Sea"))
eq("fully prehistoric on", Settings.get("VolcanoFully"), true)
eq("golem weapon", Settings.get("VolcanoGolemWeapon"), "Sword")
eq("bones skipped", Settings.get("VolcanoSkipBones"), true)
eq("eggs skipped", Settings.get("VolcanoSkipEggs"), true)
eq("magnet crafted", Settings.get("VolcanoSkipMagnet"), false)
eq("speed", Settings.get("TweenSpeed"), 260)
eq("no level farm", Settings.get("AutoFarmLevel"), false)
check("rejoins reload this script", require("Game.Server").LOADER:find("StrawberryVolcano.lua", 1, true) ~= nil)
check("rejoins keep the config", require("Game.Server").LOADER:find('Weapon = "Sword"', 1, true) ~= nil)
check("screen loop running", Loop.isRunning("VolcanoScreen"))
check("panel built", VolcanoScreen.gui() ~= nil)
eq("panel in CoreGui", VolcanoScreen.gui() and VolcanoScreen.gui().Parent, game:GetService("CoreGui"))
eq("movement and boat on Heartbeat", heartbeat:Count(), 2)

-- A character, so the farm has something to drive.
local character = newInstance("Model", "Tester", workspace.Characters)
local humanoid = newInstance("Humanoid", "Humanoid", character)
humanoid.Health = 100
local root = newInstance("Part", "HumanoidRootPart", character)
root.Position = Vector3.new(0, 10, 0)
root.CFrame = CFrame.new(0, 10, 0)
player.Character = character

local ok, err = pcall(function()
    for _ = 1, 8 do stepTasks() end
end)
check("frames run", ok, err)
local lines = VolcanoScreen.lines()
check("panel step line", type(lines.Step) == "string" and lines.Step ~= "", lines.Step)
check("panel island line", lines.Island:find("Island:", 1, true) ~= nil, lines.Island)
check("panel magnet line", lines.Magnet:find("Volcanic Magnet", 1, true) ~= nil, lines.Magnet)
check("panel has no error", not lines.Last:find("screen error", 1, true), lines.Last)
local panel = VolcanoScreen.gui()
eq("panel lets clicks through", panel.Tint.Active, false)
check("panel title", panel.Tint.Center.Title.Text:find("Strawberry Volcano", 1, true) ~= nil)

SMOKE_VOLCANO.Unload()
check("volcano loop stopped", not Loop.isRunning("Volcano"))
check("farm loop stopped", not Loop.isRunning("Farm"))
check("panel destroyed", VolcanoScreen.gui() == nil)
check("hub loader restored", require("Game.Server").LOADER:find("StrawberryHub.lua", 1, true) ~= nil)
eq("settings back to default", Settings.get("VolcanoFully"), false)
eq("Heartbeat released", heartbeat:Count(), 0)
eq("anti-AFK released", player.Idled:Count(), 0)
eq("unregistered", getgenv().StrawberryVolcanoHub, nil)
check("second Unload is harmless", pcall(SMOKE_VOLCANO.Unload))

print(string.format("smoke-volcano: %d passed, %d failed", passed, failed))
for _, failure in ipairs(failures) do print("  FAIL " .. failure) end
if failed > 0 then os.exit(1) end
