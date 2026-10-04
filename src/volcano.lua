--=============================================================================
-- VOLCANO — entry point of StrawberryVolcano.lua
--=============================================================================
--  The Prehistoric Island on its own, round after round: Volcanic Magnet
--  (Scrap Metal, Blaze Ember, craft), sail out until the island spawns, the
--  volcano event (golems, erupting rocks), dragon eggs and dino bones, a
--  reset, and again. It is the hub's Volcano.fully mode (Banana's "Fully
--  Event Prehistoric Island") without the window: Volcano/Engine sets the
--  settings it needs and Volcano/Screen shows what it is doing. Configure
--  it before the loader:
--
--      getgenv().StrawberryVolcano = { Weapon = "Sword", CollectBones = false }
--
--  It shares every module with the hub. Running it unloads a hub, a Kaitun
--  or a Volcano script already running: two of them would fight over the
--  character.
--=============================================================================

local AimHook = require("Game.AimHook")
local Boat = require("Game.Boat")
local Config = require("Volcano.Config")
local Engine = require("Volcano.Engine")
local Farm = require("Features.Farm")
local Helpers = require("Features.Helpers")
local IslandLoader = require("Game.IslandLoader")
local Islands = require("Features.Sea.Islands")
local Loop = require("Core.Loop")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local PlayerTweaks = require("Features.PlayerTweaks")
local Pvp = require("Features.Pvp")
local Screen = require("Features.Screen")
local Server = require("Game.Server")
local Settings = require("Core.Settings")
local VolcanoScreen = require("Volcano.Screen")

local VERSION = "1.0.0"

local env = (getgenv and getgenv()) or _G

for _, name in ipairs({ "StrawberryVolcanoHub", "StrawberryKaitunHub", "StrawberryHub" }) do
    local previous = env[name]
    if type(previous) == "table" and type(previous.Unload) == "function" then pcall(previous.Unload) end
end

local config = Config.load(env.StrawberryVolcano)
-- A rejoin or hop starts this script again (not the hub), with this config.
local hubLoader = Server.LOADER
Server.LOADER = Config.loader()
local volcano = { Version = VERSION, Settings = Settings, Config = config, Engine = Engine, Require = require }
env.StrawberryVolcanoHub = volcano

local function guard(label, fn, ...)
    local ok, result = xpcall(fn, function(err)
        return tostring(err) .. "\n" .. debug.traceback("", 2)
    end, ...)
    if not ok then
        warn("[Strawberry Volcano] " .. label .. " failed: " .. tostring(result))
        return nil
    end
    return result
end

local connections = {}

-- The team first (SetTeam every second, aside): the game finishes loading
-- once the player has one.
task.spawn(function()
    guard("team selection", Player.chooseTeam, config.Team, 60)
end)
guard("waiting for the game", Player.waitUntilLoaded, 60)
local afk = guard("anti-AFK", Player.antiAfk)
if afk then connections[#connections + 1] = afk end

guard("movement", Movement.start)
local stopIslands = guard("island loader", IslandLoader.start)
if stopIslands then connections[#connections + 1] = { Disconnect = stopIslands } end
guard("farm", Farm.start)
guard("player tweaks", PlayerTweaks.start)
guard("walk on water", Pvp.startWaterWalk)
guard("farm helpers", Helpers.start)
-- The boat driver: without it the boat is bought, boarded, and never moves.
guard("boat", Boat.start)
guard("screen", Screen.start)
-- The island's spawn message, only to the user's own webhook.
local webhook = type(config.WebhookUrl) == "string" and config.WebhookUrl ~= ""
if webhook then guard("island report", Islands.start) end
guard("volcano engine", Engine.start)
-- Aside: nothing the panel does may hold up the rest.
if config.ShowScreen ~= false then task.spawn(function() guard("volcano screen", VolcanoScreen.start) end) end

local unloaded = false

function volcano.Unload()
    if unloaded then return end
    unloaded = true
    Server.LOADER = hubLoader
    pcall(Engine.stop)
    pcall(VolcanoScreen.destroy)
    pcall(Farm.stop)
    pcall(AimHook.disable)
    pcall(Loop.stopAll)
    pcall(Movement.destroy)
    pcall(Boat.destroy)
    pcall(Pvp.destroy)
    pcall(IslandLoader.destroy)
    pcall(Helpers.destroy)
    pcall(require("Game.TeleportTag").clear)
    pcall(Screen.destroy)
    pcall(require("Game.Hook").disable)
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    if env.StrawberryVolcanoHub == volcano then env.StrawberryVolcanoHub = nil end
end

return volcano
