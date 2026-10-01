--=============================================================================
-- KAITUN SMOKE TESTS — kaitun.lua, start to finish
--=============================================================================
--  kaitun has already run (smokeprelude + kaitunprelude): the engines and
--  the Kaitun's own loops run, the panel exists, the config was read, and
--  Unload releases all of it.
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
local KaitunScreen = require("Kaitun.Screen")
local player = game:GetService("Players").LocalPlayer
local heartbeat = game:GetService("RunService").Heartbeat

check("kaitun returned its table", type(SMOKE_KAITUN) == "table")
eq("registered globally", getgenv().StrawberryKaitunHub, SMOKE_KAITUN)
eq("version", SMOKE_KAITUN.Version, "1.0.0")
check("no warning during load", #WARNINGS == 0, table.concat(WARNINGS, " | "))
eq("no Fluent downloaded", #FAKE.urls, 0)

eq("config: team", SMOKE_KAITUN.Config.Team, "Marines")
eq("config: speed", SMOKE_KAITUN.Config.Speed, 250)
eq("config: skip merged", SMOKE_KAITUN.Config.Skip.CDK, true)
eq("config: other skips kept", SMOKE_KAITUN.Config.Skip.Yama, false)

check("farm loop running", Loop.isRunning("Farm"))
check("attack loop running", Loop.isRunning("Attack"))
check("kaitun loop running", Loop.isRunning("Kaitun"))
check("hops reload the Kaitun", require("Game.Server").LOADER:find("StrawberryKaitun.lua", 1, true) ~= nil)
check("hops keep the config", require("Game.Server").LOADER:find('Team = "Marines"', 1, true) ~= nil)
check("screen loop running", Loop.isRunning("KaitunScreen"))
check("panel built", KaitunScreen.gui() ~= nil)
eq("panel in CoreGui", KaitunScreen.gui() and KaitunScreen.gui().Parent, game:GetService("CoreGui"))
eq("movement on Heartbeat", heartbeat:Count(), 1)

-- A character, so the engine has something to drive.
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
eq("engine switched the level farm on", Settings.get("AutoFarmLevel"), true)
eq("engine set the speed", Settings.get("TweenSpeed"), 250)
check("panel text filled", KaitunScreen.lines().Level:find("Level", 1, true) ~= nil)
local panel = KaitunScreen.gui()
check("panel covers the whole screen", panel.IgnoreGuiInset == true and panel.Tint ~= nil)
eq("panel lets clicks through", panel.Tint.Active, false)
check("panel lists the tasks and why", KaitunScreen.lines().Resting:find(":", 1, true) ~= nil, KaitunScreen.lines().Resting)
check("panel shows the total time", KaitunScreen.lines().Time:find("Total", 1, true) ~= nil)
check("panel title", panel.Tint.Center.Title.Text:find("Strawberry Kaitun", 1, true) ~= nil)

SMOKE_KAITUN.Unload()
check("kaitun loop stopped", not Loop.isRunning("Kaitun"))
check("farm loop stopped", not Loop.isRunning("Farm"))
check("panel destroyed", KaitunScreen.gui() == nil)
check("hub loader restored", require("Game.Server").LOADER:find("StrawberryHub.lua", 1, true) ~= nil)
eq("settings back to default", Settings.get("AutoFarmLevel"), false)
eq("Heartbeat released", heartbeat:Count(), 0)
eq("anti-AFK released", player.Idled:Count(), 0)
eq("unregistered", getgenv().StrawberryKaitunHub, nil)
check("second Unload is harmless", pcall(SMOKE_KAITUN.Unload))

print(string.format("smoke-kaitun: %d passed, %d failed", passed, failed))
for _, failure in ipairs(failures) do print("  FAIL " .. failure) end
if failed > 0 then os.exit(1) end
