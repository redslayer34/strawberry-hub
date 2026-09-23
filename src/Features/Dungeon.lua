--=============================================================================
-- DUNGEON — join (solo or with other accounts), clear floors, pick cards
--=============================================================================
--  Join: the Simulation Hub has pads. The leader stands on a free pad (the
--  queue menu opens), sets the difficulty and starts once enough players
--  are on it; the other accounts fly onto the leader to share the pad.
--
--  Inside, the player's "ExplorerGUID" attribute points to its dungeon
--  info: FloorId is the floor the player is on, CurrentExploredLevel the
--  highest one opened. Behind -> take the previous floor's exit teleporter;
--  otherwise kill the floor's mobs, the prop placeholder first.
--
--  Cards: the buff offers are GUIs with a DisplayName; the buff keys come
--  from DungeonShared.ExplorerBuffs. The chosen priorities win, otherwise a
--  random card is taken.
--=============================================================================

local Common = require("Features.Stack.Common")
local Enemies = require("Game.Enemies")
local Loop = require("Core.Loop")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Dungeon = {}

Dungeon.DIFFICULTIES = { "Normal", "Hard", "Challenge" }
Dungeon.WEAPONS = { "Melee", "Sword", "Blox Fruit" }
Dungeon.CORE_BUFFS = {
    "Lifesteal", "AllCooldown", "AttackSpeedMultiplier", "FruitTAPCooldown", "Armor", "Sniper",
    "Overflow", "Gun", "Sword", "Melee", "Fruit", "Defense",
}
Dungeon.PLACEHOLDER = "PropHitboxPlaceholder"
Dungeon.IGNORED_MOB = "Blank Buddy"

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local function objects()
    return Services.replicated():FindFirstChild("DungeonReplicationObjects")
end

function Dungeon.inside()
    local folder = objects()
    return folder ~= nil and folder:FindFirstChildWhichIsA("Folder") ~= nil
end

-- The floor the player is on and the highest floor opened.
function Dungeon.floors()
    local player = Services.player()
    local guid = player and player:GetAttribute("ExplorerGUID")
    local folder = objects()
    local info = guid and folder and folder:FindFirstChild(guid, true)
    if not info then return nil end
    local owner = info.Parent and info.Parent.Parent
    return info:GetAttribute("FloorId"), owner and owner:GetAttribute("CurrentExploredLevel")
end

local function floorModel(level)
    return level and Services.find(workspace, "Map.Dungeon." .. tostring(level))
end

-- Is `position` inside the floor's bounding box? (Far from its pivot when
-- the box cannot be read.)
function Dungeon.within(model, position)
    local ok, inside = pcall(function()
        local cframe, size = model:GetBoundingBox()
        local localPoint = cframe:PointToObjectSpace(position)
        return math.abs(localPoint.X) <= size.X / 2 and math.abs(localPoint.Y) <= size.Y / 2
            and math.abs(localPoint.Z) <= size.Z / 2
    end)
    if ok then return inside end
    local pivot = Common.pivot(model)
    return pivot ~= nil and (pivot.Position - position).Magnitude <= 600
end

-- The mob to fight on `level`: the placeholder first, then the nearest.
function Dungeon.target(level)
    local model = floorModel(level)
    local enemies = workspace:FindFirstChild("Enemies")
    local hrp = Player.hrp()
    if not model or not enemies or not hrp then return nil end
    local best, bestDistance, placeholder
    for _, mob in ipairs(enemies:GetChildren()) do
        if mob.Name ~= Dungeon.IGNORED_MOB and Enemies.isAlive(mob)
            and Dungeon.within(model, mob.HumanoidRootPart.Position) then
            if mob.Name == Dungeon.PLACEHOLDER then
                placeholder = placeholder or mob
            else
                local distance = (mob.HumanoidRootPart.Position - hrp.Position).Magnitude
                if not bestDistance or distance < bestDistance then best, bestDistance = mob, distance end
            end
        end
    end
    return placeholder or best
end

---------------------------------------------------------------------------
-- Join
---------------------------------------------------------------------------

local function pads()
    local folder = Services.find(workspace, "Map.Simulation Hub.Pads")
    return folder and folder:GetChildren() or nil
end

local function queueMenuOpen()
    local player = Services.player()
    local menu = player and Services.find(player, "PlayerGui.DungeonQueueSettingsMenu")
    return menu ~= nil and menu.Enabled == true
end

local function padOf(list, mine)
    local player = Services.player()
    for _, pad in ipairs(list) do
        if mine and pad:GetAttribute("Initiator") == (player and player.UserId) then return pad end
        if not mine and (pad:GetAttribute("NumPlayersOnPad") or 0) == 0 then return pad end
    end
    return nil
end

local function settingsRemote(pad)
    return pad:FindFirstChild("DungeonSettingsChanged")
end

local function lead()
    local list = pads()
    if not list then
        Movement.stop()
        return "Go to the Simulation Hub (dungeon pads not loaded)"
    end
    if not queueMenuOpen() then
        local pad = padOf(list, false)
        if not pad then return "Every pad is taken" end
        local base = pad.PrimaryPart or pad:FindFirstChildWhichIsA("BasePart")
        if base then Common.goTo(base.CFrame * CFrame.new(0, 5, 0)) end
        return "Going to a dungeon pad"
    end
    Movement.stop()
    local pad = padOf(list, true)
    local remote = pad and settingsRemote(pad)
    if not remote then return "Waiting for the pad" end
    local difficulty = Settings.get("DungeonDifficulty")
    if pad:GetAttribute("Difficulty") ~= difficulty and Common.every("DungeonDifficulty", 1) then
        pcall(function() remote:FireServer("Difficulty", difficulty) end)
    end
    local count = pad:GetAttribute("NumPlayersOnPad") or 0
    local needed = Settings.get("DungeonMinPlayers")
    if count >= needed and Common.every("DungeonStart", 2) then
        pcall(function() remote:FireServer("Start") end)
        return "Starting the dungeon"
    end
    return string.format("Waiting for players (%d/%d)", count, needed)
end

local function follow()
    local leader = Services.get("Players"):FindFirstChild(Settings.get("DungeonLeaderName") or "")
    local root = leader and leader.Character and leader.Character:FindFirstChild("HumanoidRootPart")
    if not root then
        Movement.stop()
        return "Choose the leader account"
    end
    if queueMenuOpen() then
        Movement.stop()
        return "On the leader's pad"
    end
    Common.goTo(root.CFrame)
    return "Joining " .. leader.Name
end

Dungeon.join = Mode({
    name = "Dungeon Join",
    key = "DungeonJoin",
    want = function() return not Dungeon.inside() end,
    idleStatus = "In a dungeon",
    tick = function()
        if Settings.get("DungeonLeader") then return lead() end
        return follow()
    end,
})

---------------------------------------------------------------------------
-- Attack
---------------------------------------------------------------------------

Dungeon.attack = Mode({
    name = "Dungeon",
    key = "DungeonAttack",
    want = function()
        local current, highest = Dungeon.floors()
        return current ~= nil and highest ~= nil
    end,
    idleStatus = "Not in a dungeon",
    tick = function(mode)
        local current, highest = Dungeon.floors()
        if current ~= highest then
            local previous = floorModel(highest - 1)
            local root = previous and Services.find(previous, "ExitTeleporter.Root")
            if not root then
                Movement.stop()
                return "Waiting for the exit teleporter"
            end
            Common.goTo(root.CFrame * CFrame.new(0, 5, 0))
            if Common.near(root.Position, 15) then Common.touch(root) end
            return "Going to floor " .. tostring(highest)
        end
        local mob = Dungeon.target(highest)
        if not mob then
            Movement.stop()
            return "Floor " .. tostring(highest) .. ": waiting for mobs"
        end
        return "Floor " .. tostring(highest) .. ": "
            .. Common.fight(mode, mob, true, Settings.get("DungeonWeapon"))
    end,
})

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------

local function stripFont(text)
    return (tostring(text):gsub("<.->", ""))
end

local function buffs()
    local module = Services.module("DungeonShared.ExplorerBuffs")
    return type(module) == "table" and type(module.ExplorerBuffs) == "table" and module.ExplorerBuffs or {}
end

-- Display name -> buff key.
local function keysByName()
    local map = {}
    for key, buff in pairs(buffs()) do
        if type(buff) == "table" and buff.DisplayName then map[stripFont(buff.DisplayName)] = key end
    end
    return map
end

-- The core buffs' display names, for the priority lists.
function Dungeon.cardNames()
    local names, all = {}, buffs()
    for _, key in ipairs(Dungeon.CORE_BUFFS) do
        local buff = all[key]
        names[#names + 1] = type(buff) == "table" and buff.DisplayName and stripFont(buff.DisplayName) or key
    end
    return names
end

local function skillCooldown(key)
    return key:find("Cooldown", 1, true) ~= nil and (key:find("ZCooldown", 1, true) or key:find("XCooldown", 1, true)
        or key:find("CCooldown", 1, true) or key:find("VCooldown", 1, true)) ~= nil
end

-- The offered cards: { key, button }.
function Dungeon.offers()
    local player = Services.player()
    local gui = player and player:FindFirstChild("PlayerGui")
    local map, offers = keysByName(), {}
    for _, screen in ipairs(gui and gui:GetChildren() or {}) do
        local name = screen:FindFirstChild("DisplayName", true)
        local description = screen:FindFirstChild("BuffDescription", true)
        local button = screen:FindFirstChildWhichIsA("TextButton", true)
        if name and description and button and name:IsA("TextLabel") then
            local key = map[stripFont(name.Text)] or stripFont(name.Text)
            if not skillCooldown(key) then offers[#offers + 1] = { key = key, name = stripFont(name.Text), button = button } end
        end
    end
    return offers
end

local function click(button)
    if getconnections then
        local ok, connections = pcall(getconnections, button.Activated)
        if ok and type(connections) == "table" and #connections > 0 then
            for _, connection in ipairs(connections) do pcall(function() connection.Function() end) end
            return true
        end
    end
    if firesignal then return pcall(firesignal, button.Activated) end
    return false
end

-- Picks one card: the best priority offered, else a random one.
function Dungeon.pickCard()
    local offers = Dungeon.offers()
    if #offers == 0 then return nil end
    for _, setting in ipairs({ "DungeonCard1", "DungeonCard2", "DungeonCard3" }) do
        local wanted = Settings.get(setting)
        for _, offer in ipairs(offers) do
            if wanted ~= "" and offer.name == wanted then
                click(offer.button)
                return offer
            end
        end
    end
    local offer = offers[math.random(1, #offers)]
    click(offer.button)
    return offer
end

function Dungeon.start()
    Loop.start("DungeonCards", 0.5, function()
        if Settings.get("DungeonCards") and Common.every("DungeonCard", 1) then Dungeon.pickCard() end
    end)
end

return Dungeon
