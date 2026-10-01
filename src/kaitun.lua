--=============================================================================
-- KAITUN — entry point of StrawberryKaitun.lua
--=============================================================================
--  The hub's engines without the window: the Kaitun engine switches the
--  hub's settings itself (Kaitun/Engine) and a small panel shows what it is
--  doing (Kaitun/Screen). Configure it before the loader:
--
--      getgenv().StrawberryKaitun = { Team = "Pirates", Skip = { CDK = true } }
--
--  It shares every module with the hub, so a fix in the hub fixes the
--  Kaitun too. Running it unloads a hub or a Kaitun already running: two of
--  them would fight over the character.
--=============================================================================

local AimHook = require("Game.AimHook")
local Codes = require("Features.Codes")
local Config = require("Kaitun.Config")
local Engine = require("Kaitun.Engine")
local Farm = require("Features.Farm")
local Electric = require("Features.Items.Electric")
local Fruits = require("Features.Fruits")
local Helpers = require("Features.Helpers")
local IslandLoader = require("Game.IslandLoader")
local Items = require("Features.Items")
local KaitunScreen = require("Kaitun.Screen")
local Loop = require("Core.Loop")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local PlayerTweaks = require("Features.PlayerTweaks")
local RaceV4 = require("Features.Races.V4")
local Screen = require("Features.Screen")
local Server = require("Game.Server")
local Settings = require("Core.Settings")
local Stats = require("Features.Stats")
local Webhook = require("Features.Webhook")

local VERSION = "1.0.0"

local env = (getgenv and getgenv()) or _G

for _, name in ipairs({ "StrawberryKaitunHub", "StrawberryHub" }) do
    local previous = env[name]
    if type(previous) == "table" and type(previous.Unload) == "function" then pcall(previous.Unload) end
end

local config = Config.load(env.StrawberryKaitun)
-- A server hop starts the Kaitun again (not the hub), with this config.
local hubLoader = Server.LOADER
Server.LOADER = Config.loader()
local kaitun = { Version = VERSION, Settings = Settings, Config = config, Engine = Engine }
env.StrawberryKaitunHub = kaitun

local function guard(label, fn, ...)
    local ok, result = xpcall(fn, function(err)
        return tostring(err) .. "\n" .. debug.traceback("", 2)
    end, ...)
    if not ok then
        warn("[Strawberry Kaitun] " .. label .. " failed: " .. tostring(result))
        return nil
    end
    return result
end

local connections = {}

guard("waiting for the game", Player.waitUntilLoaded, 60)
task.spawn(function()
    guard("team selection", Player.chooseTeam, config.Team, 30)
end)
local afk = guard("anti-AFK", Player.antiAfk)
if afk then connections[#connections + 1] = afk end

guard("movement", Movement.start)
local stopIslands = guard("island loader", IslandLoader.start)
if stopIslands then connections[#connections + 1] = { Disconnect = stopIslands } end
guard("farm", Farm.start)
guard("auto stats", Stats.start)
guard("player tweaks", PlayerTweaks.start)
guard("farm helpers", Helpers.start)
guard("lightning bolt clouds", Electric.start)
guard("fruits", Fruits.start)
guard("items", Items.start)
guard("race v4", RaceV4.start)
guard("screen", Screen.start)
guard("webhook", Webhook.start)
-- The 2x experience codes, as the Teddy Kaitun does at start: only while
-- there are levels to gain (the boost runs on a timer once redeemed).
if config.RedeemCodes ~= false and (Player.level() or 0) < Engine.MAX_LEVEL then
    task.spawn(function() guard("codes", Codes.redeemAll) end)
end
guard("kaitun engine", Engine.start)
if config.ShowScreen ~= false then guard("kaitun screen", KaitunScreen.start) end

local unloaded = false

function kaitun.Unload()
    if unloaded then return end
    unloaded = true
    Server.LOADER = hubLoader
    pcall(Engine.stop)
    pcall(KaitunScreen.destroy)
    pcall(Farm.stop)
    pcall(Electric.destroy)
    pcall(AimHook.disable)
    pcall(Loop.stopAll)
    pcall(Movement.destroy)
    pcall(IslandLoader.destroy)
    pcall(Helpers.destroy)
    pcall(require("Game.TeleportTag").clear)
    pcall(Screen.destroy)
    pcall(require("Game.Hook").disable)
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    if env.StrawberryKaitunHub == kaitun then env.StrawberryKaitunHub = nil end
end

return kaitun
