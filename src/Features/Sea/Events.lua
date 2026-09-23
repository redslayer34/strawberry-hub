--=============================================================================
-- SEA EVENTS — sea beasts, ships, sharks, Terrorshark, piranhas
--=============================================================================
--  Auto Sea Event: with no event around, buy / board your boat and sail to
--  the chosen zone (Sea 3) or the Sea 2 spot; with one within 2000 studs,
--  leave the boat and fight it. Events are looked for in the reference's
--  order: sea beast (90k HP and more), Terrorshark, ship, shark, piranha.
--
--  Mobs with a Humanoid (sharks, Terrorshark) are hit by the attack loop;
--  sea beasts and ships have none, so every weapon's skills are fired at
--  them (Mastery.fireAt), from the reference's positions.
--
--  Also here: Destroy IDK (clears sea events while the spy has no answer)
--  and the drives to Tiki Outpost and Hydra Island.
--=============================================================================

local Boat = require("Game.Boat")
local Common = require("Features.Stack.Common")
local Enemies = require("Game.Enemies")
local Mastery = require("Game.Mastery")
local Mode = require("Features.Other.Mode")
local Movement = require("Game.Movement")
local Player = require("Core.Player")
local PlayerTweaks = require("Features.PlayerTweaks")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local Webhook = require("Features.Webhook")

local Events = {}

Events.KINDS = { "SeaBeast", "Terrorshark", "Ship", "Shark", "Piranha" }
Events.ALL = { SeaBeast = true, Terrorshark = true, Ship = true, Shark = true, Piranha = true }
Events.BRIGADES = { PirateBrigade = true, PirateGrandBrigade = true }
Events.SHARKS = { "Fish Crew Member", "Shark" }
Events.SEA_BEAST_HP = 90000
Events.RADIUS = 2000
Events.SKILL_RANGE = 400
Events.AT_ZONE = 200

Events.TIKI_ROUTE = {
    Vector3.new(7415.83251953125, 24.0008487701416, -6664.6826171875),
    Vector3.new(-4703.16015625, 24.000019073486328, -7.822202682495117),
    Vector3.new(-8762.3310546875, 23.99974822998047, -452.2586669921875),
    Vector3.new(-15018.0634765625, 23.999053955078125, 199.0315399169922),
    Vector3.new(-16065.728515625, 23.9991512298584, 421.8982238769531),
}
Events.HYDRA_ROUTE = {
    Vector3.new(7415.83251953125, 24.0008487701416, -6664.6826171875),
    Vector3.new(1162.8353271484375, 24.00018882751465, -1825.8121337890625),
    Vector3.new(2517.887451171875, 24.000118255615234, 5109.43115234375),
    Vector3.new(5172.72607421875, 23.999813079833984, 3893.62451171875),
    Vector3.new(5203.80908203125, 24.001039505004883, 2013.0904541015625),
}

---------------------------------------------------------------------------
-- Finding
---------------------------------------------------------------------------

-- A sea beast's max health, from its "12,000/90,000" health label.
function Events.maxHealth(beast)
    local label = Services.find(beast, "HealthBBG.Frame.TextLabel")
    local text = label and tostring(label.Text) or ""
    local max = text:match("/%s*([%d,]+)")
    return max and tonumber((max:gsub(",", ""))) or 0
end

local function within(part, radius)
    return part ~= nil and Player.distanceTo(part.Position) < radius
end

function Events.alive(target)
    if not target or not target.Parent then return false end
    local humanoid = target:FindFirstChildOfClass("Humanoid")
    if humanoid then return humanoid.Health > 0 end
    local health = target:FindFirstChild("Health")
    return health == nil or (tonumber(health.Value) or 0) > 0
end

local function seaBeast(radius, minHealth)
    local beasts = workspace:FindFirstChild("SeaBeasts")
    for _, beast in ipairs(beasts and beasts:GetChildren() or {}) do
        if beast.Name == "SeaBeast1" and Events.alive(beast)
            and within(beast:FindFirstChild("HumanoidRootPart"), radius)
            and Events.maxHealth(beast) >= minHealth then
            return beast
        end
    end
    return nil
end

local function ship(radius, brigadeOnly)
    local enemies = workspace:FindFirstChild("Enemies")
    for _, model in ipairs(enemies and enemies:GetChildren() or {}) do
        local health = model:FindFirstChild("Health")
        if model:FindFirstChild("Engine") and health and (tonumber(health.Value) or 0) > 0
            and within(model.Engine, radius) and (not brigadeOnly or Events.BRIGADES[model.Name]) then
            return model
        end
    end
    return nil
end

local function mob(names, radius)
    local found, distance = Enemies.nearest(names)
    if found and distance and distance < radius then return found end
    return nil
end

-- The first sea event of `kinds` (a set, default every kind) within
-- `radius` studs.
function Events.find(kinds, radius, brigadeOnly)
    kinds = kinds or Events.ALL
    radius = radius or Events.RADIUS
    if kinds.SeaBeast then
        local beast = seaBeast(radius, Events.SEA_BEAST_HP)
        if beast then return beast end
    end
    if kinds.Terrorshark then
        local shark, inWorld = Enemies.findBoss("Terrorshark")
        if shark and inWorld and within(shark:FindFirstChild("HumanoidRootPart"), radius) then return shark end
    end
    if kinds.Ship then
        local boat = ship(radius, brigadeOnly)
        if boat then return boat end
    end
    if kinds.Shark then
        local shark = mob(Events.SHARKS, radius)
        if shark then return shark end
    end
    if kinds.Piranha then
        local piranha = mob("Piranha", radius)
        if piranha then return piranha end
    end
    return nil
end

-- Any sea beast within `radius` (the Fishman V3 quest takes any).
function Events.anySeaBeast(radius)
    return seaBeast(radius or Events.RADIUS, 0)
end

---------------------------------------------------------------------------
-- Fighting
---------------------------------------------------------------------------

-- The weapons chosen for skills, in Mastery's order (all when none chosen).
function Events.weapons()
    local chosen = Settings.get("SeaSkillWeapons") or {}
    local list = {}
    for _, weapon in ipairs(Mastery.WEAPONS) do
        if chosen[weapon] then list[#list + 1] = weapon end
    end
    return list
end

-- One step against `target`. Returns the status.
function Events.fight(mode, target)
    Boat.stop()
    local engine = target:FindFirstChild("Engine")
    if engine then
        Common.goTo(engine.CFrame * CFrame.new(0, -15, 0))
        local root = Player.hrp()
        if root and Player.distanceTo(engine.Position) < Events.SKILL_RANGE then
            Mastery.fireAt(CFrame.new(root.Position.X, -58, root.Position.Z), Events.weapons())
        end
        return "Sinking " .. target.Name
    end
    local root = target:FindFirstChild("HumanoidRootPart")
    if not root then return "Waiting for " .. target.Name end
    if not target:FindFirstChildOfClass("Humanoid") then
        -- A sea beast: above it, or at 140 when it dives deep.
        if math.abs(root.Position.Y + 60) <= 175 then
            Common.goTo(root.CFrame * CFrame.new(0, 200, 50))
        else
            Common.goTo(CFrame.new(root.Position.X, 140, root.Position.Z))
        end
        if Player.distanceTo(root.Position) < Events.SKILL_RANGE then
            Mastery.fireAt(CFrame.new(root.Position.X, 40, root.Position.Z), Events.weapons())
        end
        return "Fighting a sea beast"
    end
    local height = target.Name == "Terrorshark" and 60 or 20
    Common.goTo(root.CFrame * CFrame.new(0, height, 0))
    mode.target = target
    PlayerTweaks.ensureBuso()
    Player.equip(Settings.get("Weapon"))
    return "Fighting " .. target.Name
end

---------------------------------------------------------------------------
-- Sailing
---------------------------------------------------------------------------

-- Where to wait for sea events in this sea.
function Events.spot()
    if Player.sea() == 2 then return Boat.SEA2_SPOT end
    return Boat.ZONES[Settings.get("SeaZone")] or Boat.ZONES["Zone 1"]
end

-- Boards the boat and sails to `spot` (default Events.spot()). Returns the
-- status. `label` names the place in the status.
function Events.patrol(spot, label, boatName)
    local boat, status = Boat.get(boatName)
    if not boat then return status end
    if Settings.get("SeaRepair") then
        local repairing = Boat.repair(boat)
        if repairing then return repairing end
    end
    spot = spot or Events.spot()
    label = label or (Player.sea() == 2 and "the sea" or tostring(Settings.get("SeaZone")))
    if Boat.sail(boat, spot) > Events.AT_ZONE then return "Sailing to " .. label end
    return "Waiting for a sea event at " .. label
end

local function selectedKinds()
    local chosen = Settings.get("SeaEventKinds") or {}
    local kinds, any = {}, false
    for _, kind in ipairs(Events.KINDS) do
        if chosen[kind] then kinds[kind], any = true, true end
    end
    return any and kinds or nil
end

Events.auto = Mode({
    name = "Sea Events",
    key = "SeaAuto",
    tick = function(mode)
        if Player.sea() == 1 then
            Movement.stop()
            return "Only in Sea 2 and Sea 3"
        end
        local kinds = selectedKinds()
        if not kinds then
            Movement.stop()
            return "Select the sea events to farm"
        end
        local target = Events.find(kinds, Events.RADIUS, Settings.get("SeaBrigadeOnly"))
        if target then return Events.fight(mode, target) end
        return Events.patrol()
    end,
    stop = Boat.stop,
})

---------------------------------------------------------------------------
-- Destroy IDK: the spy has no answer while a sea event blocks him
---------------------------------------------------------------------------

local idkSeen = false

function Events.spyUnsure()
    return Common.invoke("InfoLeviathan", "1") == -1
end

Events.idk = Mode({
    name = "Destroy IDK",
    key = "SeaDestroyIdk",
    sea = 3,
    want = Events.spyUnsure,
    idle = function()
        if idkSeen then
            idkSeen = false
            Webhook.notify("WebhookIdk", "Destroy IDK", "The spy knows again")
        end
    end,
    idleStatus = "The spy has an answer",
    tick = function(mode)
        idkSeen = true
        local target = Events.find(Events.ALL)
        if target then return "IDK: " .. Events.fight(mode, target) end
        return "IDK: " .. Events.patrol()
    end,
    stop = Boat.stop,
})

---------------------------------------------------------------------------
-- Drive to Tiki Outpost / Hydra Island
---------------------------------------------------------------------------

local routes = {}

local function driveMode(name, key, route)
    routes[key] = { index = 1 }
    return Mode({
        name = name,
        key = key,
        sea = 3,
        want = function() return routes[key].index <= #route end,
        idleStatus = "Arrived (turn it off and on to drive again)",
        tick = function()
            local boat, status = Boat.get()
            if not boat then return status end
            local state = routes[key]
            local point = route[state.index]
            if Boat.sail(boat, point) < 10 then state.index = state.index + 1 end
            return string.format("Driving (%d/%d)", math.min(state.index, #route), #route)
        end,
        stop = Boat.stop,
    })
end

Events.driveTiki = driveMode("Drive To Tiki", "SeaDriveTiki", Events.TIKI_ROUTE)
Events.driveHydra = driveMode("Drive To Hydra", "SeaDriveHydra", Events.HYDRA_ROUTE)

-- A drive starts over when its toggle changes.
function Events.onSetting(key)
    if routes[key] then routes[key].index = 1 end
end

-- Drives start over when their toggle changes. Returns the listener's remover.
function Events.start()
    return Settings.onChanged(function(key) Events.onSetting(key) end)
end

function Events.reset()
    idkSeen = false
    for _, state in pairs(routes) do state.index = 1 end
end

return Events
