--=============================================================================
-- ITEMS: SABER (Sea 1, level 200)
--=============================================================================
--  The step comes from the server, as in the Teddy Kaitun: ProQuestProgress
--  (no argument) answers { Plates = {true, ...}, UsedTorch, UsedCup,
--  TalkedSon, KilledMob, UsedRelic, KilledShanks }. Reading the map instead
--  (which doors look open) sent the character to the Saber Expert before
--  the puzzle was done, or left it waiting for him. One step at a time:
--
--    1  the 5 jungle plates
--    2  the jungle torch, DestroyTorch at the desert gate
--    3  GetCup, FillCup at the fountain, SickMan
--    4  RichSon (talk), kill the Mob Leader
--    5  RichSon again for the Relic, PlaceRelic in the jungle
--    6  kill the Saber Expert (Shanks)
--=============================================================================

local Common = require("Features.Stack.Common")
local Enemies = require("Game.Enemies")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")

local Saber = {}

Saber.MIN_LEVEL = 200
Saber.ACT_EVERY = 1.5
-- Teddy's positions.
Saber.TORCH = Vector3.new(-1679.2634, 20.4901, 170.7659)
Saber.BURN = Vector3.new(1121.07, 4, 4389.22)
Saber.CUP = Vector3.new(1109.47, 4, 4402.89)
Saber.FOUNTAIN = Vector3.new(1398, -152, -1520)
Saber.SICK_MAN = Vector3.new(1503.4, 77.35, -1297.55)
Saber.RICH_SON = Vector3.new(-939.34, 26.03, 4114.77)
Saber.MOB_LEADER = Vector3.new(-2880.716, 10, 5430.853)
Saber.RELIC_SPOT = Vector3.new(-1405.31445, 29.8519974, 4.34172916)

-- The server's progress table, or nil (cached by Common.invoke).
function Saber.progress()
    local answer = Common.invoke("ProQuestProgress")
    return type(answer) == "table" and answer or nil
end

-- Plates pressed (the true values of the Plates table).
function Saber.plates(progress)
    local count = 0
    for _, value in pairs(type(progress) == "table" and type(progress.Plates) == "table" and progress.Plates or {}) do
        if value == true then count = count + 1 end
    end
    return count
end

local function act(key)
    return Common.every("Saber" .. key, Saber.ACT_EVERY)
end

local function call(...)
    Services.invoke("ProQuestProgress", ...)
    Common.forget()
end

-- Flies to `where`; true once there.
local function at(where, radius)
    Common.goTo(where)
    return Common.near(where, radius or 10)
end

local function plates()
    local folder = Services.find(workspace, "Map.Jungle.QuestPlates")
    for index = 1, 5 do
        local plate = folder and folder:FindFirstChild("Plate" .. index)
        local button = plate and plate:FindFirstChild("Button")
        if button and button:FindFirstChild("TouchInterest") then
            Common.goTo(button.CFrame)
            if Common.near(button.Position, 6) then Common.touch(button) end
            return "Pressing jungle plate " .. index
        end
    end
    -- Not loaded yet: the jungle first.
    Common.goTo(Saber.TORCH)
    return "Going to the jungle plates"
end

local function torch()
    if not Common.has("Torch") then
        local lying = Services.find(workspace, "Map.Jungle.Torch")
        local where = lying and lying.Position or Saber.TORCH
        Common.goTo(where)
        if lying and Common.near(where, 8) then Common.touch(lying) end
        return "Taking the jungle torch"
    end
    Common.equip("Torch")
    if not at(Saber.BURN, 12) then return "Carrying the torch to the desert gate" end
    if act("Torch") then call("DestroyTorch") end
    return "Burning the desert gate"
end

-- The cup, Teddy's way: FillCup and SickMan are asked from wherever the
-- character stands first (the server does not check the distance), then
-- next to the Sick Man. The fountain lies under the sea (y -152): the
-- character got stuck in the water going there, so it is only tried last,
-- for a short while, before the remote way again.
Saber.CUP_TRIES = 3        -- remote tries per place
Saber.FOUNTAIN_TIME = 25   -- seconds at most towards the fountain
local cupTries, fountainSince = 0, nil

local function giveCup(held)
    if not act("Cup") then return end
    cupTries = cupTries + 1
    Services.invoke("ProQuestProgress", "FillCup", held)
    call("SickMan")
end

local function cup()
    local held = Common.tool("Cup")
    if not held then
        cupTries, fountainSince = 0, nil
        if act("GetCup") then call("GetCup") end
        Common.goTo(Saber.CUP)
        return "Taking the cup"
    end
    Common.equip("Cup")
    if cupTries < Saber.CUP_TRIES then
        Movement.stop()
        giveCup(held)
        return "Filling the cup and giving it to the Sick Man"
    end
    if cupTries < Saber.CUP_TRIES * 2 then
        if at(Saber.SICK_MAN, 10) then giveCup(held) end
        return "Taking the cup to the Sick Man"
    end
    fountainSince = fountainSince or os.clock()
    if os.clock() - fountainSince > Saber.FOUNTAIN_TIME then
        -- Not reached (the water): back up, and the remote way again.
        cupTries, fountainSince = 0, nil
        Common.goTo(Saber.SICK_MAN + Vector3.new(0, 30, 0))
        return "Leaving the water"
    end
    if at(Saber.FOUNTAIN, 15) then giveCup(held) end
    return "Taking the cup to the fountain"
end

local function richSon(why)
    if at(Saber.RICH_SON, 10) and act("RichSon") then call("RichSon") end
    return why
end

local function fightAt(mode, name, where)
    local boss, inWorld = Enemies.findBoss(name)
    if boss then return Common.fight(mode, boss, inWorld) end
    mode.target = nil
    Common.goTo(where + Vector3.new(0, 25, 0))
    return "Looking for the " .. name
end

local function relic()
    if not Common.has("Relic") then return richSon("Taking the Relic from the Rich Son") end
    Common.equip("Relic")
    if not at(Saber.RELIC_SPOT, 8) then return "Carrying the Relic to the jungle" end
    pcall(function()
        local invisible = Services.find(workspace, "Map.Jungle.Final.Invis")
        if invisible then invisible.CanCollide = false end
    end)
    if act("PlaceRelic") then call("PlaceRelic") end
    return "Placing the Relic"
end

-- The step the server says is next: "plates", "torch", "cup", "talk",
-- "mob", "relic", "shanks", or nil (done, or no answer yet).
function Saber.step(progress)
    if not progress or progress.KilledShanks then return nil end
    if Saber.plates(progress) < 5 then return "plates" end
    if not progress.UsedTorch then return "torch" end
    if not progress.UsedCup then return "cup" end
    if not progress.TalkedSon then return "talk" end
    if not progress.KilledMob then return "mob" end
    if not progress.UsedRelic then return "relic" end
    return "shanks"
end

Saber.mode = Mode({
    name = "Saber",
    key = "ItemSaber",
    sea = 1,
    want = function()
        if Player.level() < Saber.MIN_LEVEL or Common.owns("Saber") then return false end
        local progress = Saber.progress()
        return progress == nil or Saber.step(progress) ~= nil
    end,
    idleStatus = "Owned, or level 200 needed",
    tick = function(mode)
        mode.target = nil
        local progress = Saber.progress()
        local step = Saber.step(progress)
        if not progress then
            Movement.stop()
            return "Reading the Saber quest"
        end
        if step == "plates" then return "1/6 " .. plates() end
        if step == "torch" then return "2/6 " .. torch() end
        if step == "cup" then return "3/6 " .. cup() end
        if step == "talk" then return "4/6 " .. richSon("Talking to the Rich Son") end
        if step == "mob" then return "4/6 " .. fightAt(mode, "Mob Leader", Saber.MOB_LEADER) end
        if step == "relic" then return "5/6 " .. relic() end
        if step == "shanks" then return "6/6 " .. fightAt(mode, "Saber Expert", Saber.RELIC_SPOT) end
        Movement.stop()
        return "Done"
    end,
    stop = function() cupTries, fountainSince = 0, nil end,
})

return Saber
