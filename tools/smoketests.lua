--=============================================================================
-- SMOKE TESTS — main.lua, start to finish
--=============================================================================
--  main has already run when this file starts (see smokeprelude.lua). This
--  checks that every stage is wired: the loops run, the window exists, the
--  hub is registered, and Unload releases all of it.
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
local player = game:GetService("Players").LocalPlayer
local heartbeat = game:GetService("RunService").Heartbeat

check("main returned the hub", type(SMOKE_HUB) == "table")
eq("hub registered globally", getgenv().StrawberryHub, SMOKE_HUB)
eq("version", SMOKE_HUB.Version, "2.0.0")
check("window built", SMOKE_HUB.Window ~= nil)
eq("Fluent kept on the hub", SMOKE_HUB.Fluent, FAKE.library)
check("no warning during load", #WARNINGS == 0, table.concat(WARNINGS, " | "))

eq("library and both addons downloaded", #FAKE.urls, 3)
eq("library URL", FAKE.urls[1], "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua")
eq("tabs built", #FAKE.record.tabs, 6)
eq("autoload applied", FAKE.record.autoloadCalls, 1)

check("farm loop running", Loop.isRunning("Farm"))
check("attack loop running", Loop.isRunning("Attack"))
check("status loop running", Loop.isRunning("StatusPanel"))
eq("movement driver on Heartbeat", heartbeat:Count(), 1)
eq("anti-AFK connected", player.Idled:Count(), 1)

-- A few frames with the farm switched on must not throw.
FAKE.library.Options.AutoFarmLevel:SetValue(true)
local ok, err = pcall(function()
    for _ = 1, 5 do stepTasks() end
end)
check("frames run with the farm on", ok, err)

SMOKE_HUB.Unload()
check("farm loop stopped", not Loop.isRunning("Farm"))
check("attack loop stopped", not Loop.isRunning("Attack"))
check("status loop stopped", not Loop.isRunning("StatusPanel"))
eq("Heartbeat released", heartbeat:Count(), 0)
eq("anti-AFK released", player.Idled:Count(), 0)
check("Fluent destroyed", FAKE.record.destroyed == true)
eq("hub unregistered", getgenv().StrawberryHub, nil)
check("second Unload is harmless", pcall(SMOKE_HUB.Unload))

print(string.format("smoke: %d passed, %d failed", passed, failed))
for _, failure in ipairs(failures) do print("  FAIL " .. failure) end
if failed > 0 then os.exit(1) end
