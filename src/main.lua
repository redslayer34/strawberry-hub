--=============================================================================
-- MAIN — bundle entry point
--=============================================================================
--  Stages, each guarded so a failure leaves the previous ones working:
--
--      game ready      wait for the player data, pick a team, anti-AFK
--      engine          movement driver + farm and attack loops
--      interface       Fluent window (downloaded from GitHub)
--
--  If Fluent cannot be downloaded the engine still runs; there is just no
--  window to drive it from.
--=============================================================================

local AimHook = require("Game.AimHook")
local Boat = require("Game.Boat")
local Entrances = require("Game.Entrances")
local Esp = require("Features.Esp")
local Dungeon = require("Features.Dungeon")
local Farm = require("Features.Farm")
local Fishing = require("Features.Other.Fishing")
local Fruits = require("Features.Fruits")
local Items = require("Features.Items")
local RaceV4 = require("Features.Races.V4")
local SeaEvents = require("Features.Sea.Events")
local SeaIslands = require("Features.Sea.Islands")
local IslandLoader = require("Game.IslandLoader")
local Pvp = require("Features.Pvp")
local Screen = require("Features.Screen")
local Webhook = require("Features.Webhook")
local FluentLoader = require("UI.Fluent")
local Interface = require("UI.Interface")
local Loop = require("Core.Loop")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local PlayerTweaks = require("Features.PlayerTweaks")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local Stats = require("Features.Stats")

local VERSION = "2.0.0"

local env = (getgenv and getgenv()) or _G

-- Running the loader twice must not leave two hubs fighting over the
-- character: the previous one is unloaded first.
if type(env.StrawberryHub) == "table" and type(env.StrawberryHub.Unload) == "function" then
    pcall(env.StrawberryHub.Unload)
end

local hub = { Version = VERSION, Settings = Settings }
env.StrawberryHub = hub

local function guard(label, fn, ...)
    local ok, result, second, third = xpcall(fn, function(err)
        return tostring(err) .. "\n" .. debug.traceback("", 2)
    end, ...)
    if not ok then
        warn("[Strawberry Hub] " .. label .. " failed: " .. tostring(result))
        return nil
    end
    return result, second, third
end

local function notify(text)
    pcall(function()
        Services.get("StarterGui"):SetCore("SendNotification", {
            Title = "Strawberry Hub",
            Text = text,
            Duration = 10,
        })
    end)
end

---------------------------------------------------------------------------
-- Game ready
---------------------------------------------------------------------------

local connections = {}

guard("waiting for the game", Player.waitUntilLoaded, 60)

-- Team selection runs aside: it waits on a screen that may never show up
-- (the team is already chosen when the script is re-run).
task.spawn(function()
    guard("team selection", Player.chooseTeam, env.StrawberryTeam, 30)
end)

local afk = guard("anti-AFK", Player.antiAfk)
if afk then connections[#connections + 1] = afk end

---------------------------------------------------------------------------
-- Engine
---------------------------------------------------------------------------

guard("movement", Movement.start)
guard("portal unlocks", Entrances.refresh)
local stopIslands = guard("island loader", IslandLoader.start)
if stopIslands then connections[#connections + 1] = { Disconnect = stopIslands } end
guard("farm", Farm.start)
guard("auto stats", Stats.start)
guard("player tweaks", PlayerTweaks.start)
guard("fishing extras", Fishing.start)
guard("fruits", Fruits.start)
guard("items", Items.start)
guard("dungeon cards", Dungeon.start)
guard("race v4", RaceV4.start)
guard("boat", Boat.start)
guard("sea islands", SeaIslands.start)
local stopDrives = guard("sea drives", SeaEvents.start)
if stopDrives then connections[#connections + 1] = { Disconnect = stopDrives } end
guard("esp", Esp.start)
guard("pvp", Pvp.start)
guard("screen", Screen.start)
guard("webhook", Webhook.start)

---------------------------------------------------------------------------
-- Unload
---------------------------------------------------------------------------

local library
local unloaded = false

function hub.Unload()
    if unloaded then return end
    unloaded = true

    pcall(Farm.stop)
    pcall(AimHook.disable)
    pcall(Loop.stopAll)
    pcall(Movement.destroy)
    pcall(Boat.destroy)
    pcall(IslandLoader.destroy)
    pcall(require("Game.TeleportTag").clear)
    pcall(Fishing.destroy)
    pcall(Esp.destroy)
    pcall(Pvp.destroy)
    pcall(Screen.destroy)
    pcall(require("Game.Hook").disable)
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    pcall(Interface.destroy)
    if library then pcall(function() library:Destroy() end) end

    if env.StrawberryHub == hub then env.StrawberryHub = nil end
end

---------------------------------------------------------------------------
-- Interface
---------------------------------------------------------------------------

local saveManager, interfaceManager
library, saveManager, interfaceManager = guard("Fluent download", FluentLoader.load)

if library then
    local window = guard("interface", Interface.build, library, saveManager, interfaceManager, {
        version = VERSION,
        unload = hub.Unload,
    })
    hub.Window = window
    hub.Fluent = library
    if not window then notify("The window failed to build -- check the console (F9).") end
else
    notify("Fluent could not be downloaded. The hub is loaded without a window.")
end

return hub
