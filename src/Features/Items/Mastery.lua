--=============================================================================
-- ITEMS: WEAPON MASTERY 600 AND BLACKSMITH UPGRADES
--=============================================================================
--    Melee 600   each fighting style in the reference's order, bought when
--                missing, level-farmed until its Level reaches 600
--    Sword 600   the rarest owned sword under 600 mastery, level-farmed
--    Upgrade     the rarest sword or gun never upgraded: the Blacksmith
--                says what it needs (UpgradeItem Check), the missing
--                materials are farmed in their sea, then the craft is
--                confirmed in the game's own window
--=============================================================================

local Common = require("Features.Stack.Common")
local Data = require("Game.Data")
local Fight = require("Features.Fight")
local LevelFarm = require("Features.LevelFarm")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")

local Mastery = {}

Mastery.TARGET = 600
Mastery.MELEES = {
    "Superhuman", "Death Step", "Sharkman Karate", "Electric Claw", "Dragon Talon",
    "Black Leg", "Fishman Karate", "Electro", "Dragon Claw",
}
Mastery.BUY_TRIES = 3

local buyTries, skipped = {}, {}
local search = Fight.newSearch()
local upgradeInfo = {}   -- [kind] = { weapon = name, required = { [material] = count } }
local statusText = ""

---------------------------------------------------------------------------
-- Melee 600
---------------------------------------------------------------------------

function Mastery.nextMelee()
    for _, melee in ipairs(Mastery.MELEES) do
        if not skipped[melee] and Common.masteryOf(melee) < Mastery.TARGET then return melee end
    end
    return nil
end

local function buyMelee(melee)
    if not Common.every("BuyMelee", 3) then return end
    buyTries[melee] = (buyTries[melee] or 0) + 1
    if buyTries[melee] > Mastery.BUY_TRIES then
        skipped[melee] = true
        return
    end
    if melee == "Dragon Claw" then
        Services.invoke("BlackbeardReward", "DragonClaw", "1")
        Services.invoke("BlackbeardReward", "DragonClaw", "2")
    else
        Services.invoke("Buy" .. melee:gsub(" ", ""))
    end
end

local function farmWith(mode, weapon)
    LevelFarm.tick(weapon)
    mode.target = LevelFarm.target
    return tostring(LevelFarm.status)
end

Mastery.melee = Mode({
    name = "Melee Mastery",
    key = "ItemMeleeMastery",
    want = function() return Mastery.nextMelee() ~= nil end,
    idleStatus = "Every melee at 600",
    tick = function(mode)
        local melee = Mastery.nextMelee()
        if not melee then return "Every melee at 600" end
        if not Common.has(melee) then
            Movement.stop()
            buyMelee(melee)
            return "Buying " .. melee
        end
        Common.equip(melee)
        return string.format("%s %d/%d: %s", melee, Common.masteryOf(melee), Mastery.TARGET, farmWith(mode, "Melee"))
    end,
    stop = function() LevelFarm.stop() end,
})

---------------------------------------------------------------------------
-- Sword 600
---------------------------------------------------------------------------

function Mastery.nextSword()
    local best
    for _, item in ipairs(Common.inventory()) do
        if item.type == "Sword" and (item.mastery or 0) < Mastery.TARGET
            and (not best or (item.rarity or 0) > (best.rarity or 0)) then
            best = item
        end
    end
    return best and best.name or nil
end

Mastery.sword = Mode({
    name = "Sword Mastery",
    key = "ItemSwordMastery",
    want = function() return Mastery.nextSword() ~= nil end,
    idleStatus = "Every sword at 600",
    tick = function(mode)
        local sword = Mastery.nextSword()
        if not sword then return "Every sword at 600" end
        if not Common.has(sword) then
            Movement.stop()
            if Common.every("LoadSword", 3) then Services.invoke("LoadItem", sword) end
            return "Taking " .. sword .. " out"
        end
        Common.equip(sword)
        return string.format("%s %d/%d: %s", sword, Common.masteryOf(sword), Mastery.TARGET, farmWith(mode, "Sword"))
    end,
    stop = function() LevelFarm.stop() end,
})

---------------------------------------------------------------------------
-- Blacksmith upgrades
---------------------------------------------------------------------------

-- The rarest weapon of `kind` never upgraded.
function Mastery.upgradeTarget(kind)
    local best
    for _, item in ipairs(Common.inventory()) do
        if item.type == kind and (item.upgrades or 0) == 0
            and (not best or (item.rarity or 0) > (best.rarity or 0)) then
            best = item
        end
    end
    return best and best.name or nil
end

local function blacksmith()
    for _, root in ipairs({ workspace:FindFirstChild("NPCs"), Services.replicated():FindFirstChild("NPCs") }) do
        for _, node in ipairs(root and root:GetDescendants() or {}) do
            local head = node:IsA("Model") and node.Name == "Blacksmith" and node:FindFirstChild("Head")
            if head then return head.CFrame * CFrame.new(0, -2, 2) end
        end
    end
    return nil
end

local function readRequirements(tool)
    local answer = Services.invoke("UpgradeItem", "Check", tool)
    if type(answer) ~= "table" or type(answer.Required) ~= "table" then return nil, answer end
    local required = {}
    for _, entry in pairs(answer.Required) do
        if type(entry) == "table" and entry.Name then required[entry.Name] = tonumber(entry.Required) or 0 end
    end
    return required, answer
end

-- The first missing material (those of the current sea first).
function Mastery.missingMaterial(required)
    local fallback
    for material, count in pairs(required) do
        if Common.itemCount(material) < count then
            local info = Data.MATERIALS[material]
            if info and info.sea == Player.sea() then return material end
            fallback = fallback or material
        end
    end
    return fallback
end

local function press(button)
    if not button or not getconnections then return false end
    local ok, connections = pcall(getconnections, button.Activated)
    for _, connection in ipairs(ok and connections or {}) do pcall(function() connection.Function() end) end
    return ok
end

local function confirmCraft(tool)
    local player = Services.player()
    local craft = player and Services.find(player, "PlayerGui.Main.Craft")
    if craft and craft.Visible then
        local confirm = Services.find(craft, "Main.Bottom.Confirm")
        if confirm and confirm.Visible then
            press(confirm)
        else
            press(Services.find(craft, "Main.Bottom.Close"))
        end
        return "Confirming the upgrade"
    end
    local _, answer = readRequirements(tool)
    local controller = player and Services.find(player, "PlayerGui.Main.UIController.Craft")
    if controller and type(answer) == "table" then
        pcall(function() require(controller)(answer.Required, answer.Result, answer.ResultStats) end)
    end
    return "Opening the upgrade window"
end

local function upgrade(mode, kind)
    local target = Mastery.upgradeTarget(kind)
    if not target then return "Nothing left to upgrade" end
    local held = Player.findTool(kind)
    if not held or held.Name ~= target then
        Movement.stop()
        if Common.every("UpgradeLoad", 3) then Services.invoke("LoadItem", target) end
        return "Taking " .. target .. " out"
    end
    local smith = blacksmith()
    local info = upgradeInfo[kind]
    if not info or info.weapon ~= target then
        if not smith then
            Movement.stop()
            return "Blacksmith not loaded"
        end
        Common.goTo(smith)
        if Common.near(smith.Position, 10) and Common.every("UpgradeCheck", 2) then
            local required = readRequirements(held)
            if required then upgradeInfo[kind] = { weapon = target, required = required } end
        end
        return "Asking the Blacksmith"
    end
    local material = Mastery.missingMaterial(info.required)
    if material then
        local source = Data.MATERIALS[material]
        if not source then
            Movement.stop()
            return "Material not supported: " .. material
        end
        if not Common.travel(source.sea) then return "Travelling for " .. material end
        return string.format("%s %d/%d: %s", material, Common.itemCount(material), info.required[material],
            Common.farm(mode, source.mobs, search))
    end
    if not smith then
        Movement.stop()
        return "Blacksmith not loaded"
    end
    Common.goTo(smith)
    if not Common.near(smith.Position, 10) then return "Going to the Blacksmith" end
    local status = confirmCraft(held)
    upgradeInfo[kind] = nil
    return status
end

local function upgradeMode(kind, key)
    return Mode({
        name = "Upgrade " .. kind,
        key = key,
        want = function() return Mastery.upgradeTarget(kind) ~= nil end,
        idleStatus = "Nothing left to upgrade",
        tick = function(mode)
            statusText = upgrade(mode, kind)
            return statusText
        end,
        stop = function() search:reset() end,
    })
end

Mastery.upgradeSword = upgradeMode("Sword", "ItemUpgradeSword")
Mastery.upgradeGun = upgradeMode("Gun", "ItemUpgradeGun")

function Mastery.upgradeStatus()
    return statusText
end

function Mastery.reset()
    buyTries, skipped, upgradeInfo, statusText = {}, {}, {}, ""
    search:reset()
end

return Mastery
