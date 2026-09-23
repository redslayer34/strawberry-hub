--=============================================================================
-- ITEMS: SABER (Sea 1, level 200)
--=============================================================================
--  The reference's steps, with its exact positions:
--    1  press the jungle plates until the plate door opens
--    2  take the jungle torch and burn the desert gate
--    3  take the cup, fill it at the fountain, give it to the Sick Man
--    4  Rich Son: kill the Mob Leader, then carry the Relic to the jungle
--    5  the final door opens: kill the Saber Expert
--=============================================================================

local Common = require("Features.Stack.Common")
local Enemies = require("Game.Enemies")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")

local Saber = {}

Saber.MIN_LEVEL = 200
Saber.CUP_SPOT = Vector3.new(1112.46521, 4.92147732, 4364.55469)
Saber.CUP_TAKE = Vector3.new(1113.66992, 7.5484705, 4365.27832)
Saber.FOUNTAIN = Vector3.new(1395.77307, 37.4733238, -1324.34631)
Saber.SICK_MAN = Vector3.new(1457.8768310547, 88.377502441406, -1390.6892089844)
Saber.RICH_SON = Vector3.new(-1404.07996, 29.8520069, 5.26677656)
Saber.RELIC_SPOT = Vector3.new(-1405.3677978516, 29.977333068848, 4.5685839653015)
Saber.FIRE_SPOT = Vector3.new(1115.23499, 4.92147732, 4349.36963)
Saber.FIRE_TOUCH = Vector3.new(1114.59863, 4.92147732, 4350.64258)

local function anyOpen(folderPath)
    local folder = Services.find(workspace, folderPath)
    for _, part in ipairs(folder and folder:GetChildren() or {}) do
        if part:IsA("Part") and not part.CanCollide then return true end
    end
    return false
end

local function platePressable()
    local plates = Services.find(workspace, "Map.Jungle.QuestPlates")
    for _, plate in ipairs(plates and plates:GetChildren() or {}) do
        local button = plate:IsA("Model") and plate:FindFirstChild("Button")
        if button and button:FindFirstChild("TouchInterest") then return button end
    end
    return nil
end

local function cupStep()
    local cup = Common.tool("Cup")
    if not cup then
        if Common.near(Saber.CUP_SPOT, 5) then
            Common.goTo(Saber.CUP_TAKE)
            Common.touch(Services.find(workspace, "Map.Desert.Cup"))
            return "Taking the cup"
        end
        Common.goTo(Saber.CUP_SPOT)
        return "Going to the cup"
    end
    Common.equip("Cup")
    local handle = cup:FindFirstChild("Handle")
    if handle and handle:FindFirstChild("TouchInterest") then
        Common.goTo(Saber.FOUNTAIN)
        return "Filling the cup"
    end
    Common.goTo(Saber.SICK_MAN)
    if Common.near(Saber.SICK_MAN, 8) and Common.every("SickMan", 3) then
        Services.invoke("ProQuestProgress", "SickMan")
        Common.forget()
    end
    return "Giving the cup to the Sick Man"
end

local function richSon(mode, progress)
    if progress == 0 then
        local leader, inWorld = Enemies.findBoss("Mob Leader")
        if leader then return Common.fight(mode, leader, inWorld) end
        Movement.stop()
        return "Waiting for the Mob Leader"
    end
    if not Common.has("Relic") then
        Common.goTo(Saber.RICH_SON)
        if Common.near(Saber.RICH_SON, 8) and Common.every("RichSon", 3) then
            Services.invoke("ProQuestProgress", "RichSon")
            Common.forget()
        end
        return "Taking the Relic"
    end
    Common.equip("Relic")
    Common.goTo(Saber.RELIC_SPOT)
    return "Carrying the Relic"
end

local function torchStep()
    local torch = Common.tool("Torch")
    if not torch then
        local lying = Services.find(workspace, "Map.Jungle.Torch")
        if lying then Common.goTo(lying.CFrame) else Movement.stop() end
        return "Taking the jungle torch"
    end
    Common.equip("Torch")
    if Common.near(Saber.FIRE_SPOT, 5) then
        Common.goTo(Saber.FIRE_TOUCH)
        Common.touch(Services.find(workspace, "Map.Desert.Burn.Fire"), torch)
        return "Burning the gate"
    end
    Common.goTo(Saber.FIRE_SPOT)
    return "Carrying the torch"
end

Saber.mode = Mode({
    name = "Saber",
    key = "ItemSaber",
    sea = 1,
    want = function()
        return Player.level() >= Saber.MIN_LEVEL and not Common.has("Saber") and Common.itemCount("Saber") == 0
    end,
    idleStatus = "Owned, or level 200 needed",
    tick = function(mode)
        if anyOpen("Map.Jungle.Final") then
            local expert, inWorld = Enemies.findBoss("Saber Expert")
            if expert then return Common.fight(mode, expert, inWorld) end
            Movement.stop()
            return "Waiting for the Saber Expert"
        end
        local door = Services.find(workspace, "Map.Jungle.QuestPlates.Door")
        if door and door.CanCollide then
            local button = platePressable()
            if button then
                Common.goTo(button.CFrame)
                return "Pressing the jungle plates"
            end
        end
        if anyOpen("Map.Desert.Burn") then
            local progress = Common.invoke("ProQuestProgress", "RichSon")
            if progress == 0 or progress == 1 then return richSon(mode, progress) end
            return cupStep()
        end
        return torchStep()
    end,
})

return Saber
