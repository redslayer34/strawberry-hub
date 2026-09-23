--=============================================================================
-- ROUTER — picks the fastest way to a far goal
--=============================================================================
--  Movement asks the Router every frame. Each possible route is priced in
--  seconds and the cheapest wins:
--
--    direct      fly all the way (distance / current speed)
--    entrance    requestEntrance to a portal point, then fly the rest
--    submarine   Sea 3: the only way in and out of the Submerged Island
--    respawn     opt-in: move the spawn point near the goal, then reset
--
--  A shortcut is only taken when it saves MIN_SAVING seconds. A portal that
--  does not move the player is locked for the rest of the session; one that
--  works is confirmed. The chosen route is kept while the goal stays put, so
--  a moving mob does not cause a re-plan every frame, and two shortcuts are
--  never chained without flying in between.
--=============================================================================

local Entrances = require("Game.Entrances")
local Player = require("Core.Player")
local Services = require("Core.Services")
local Settings = require("Core.Settings")

local Router = {}

Router.SNAP = 150            -- studs: closer goals are simply set
Router.OVERHEAD = 1.5        -- seconds a teleport request costs
Router.MIN_SAVING = 5        -- seconds a shortcut must save
Router.REPLAN_MOVE = 300     -- studs the goal may move before re-planning
Router.COOLDOWN = 4          -- seconds before the same portal is used again
Router.VERIFY_STEPS = 10     -- x 0.25 s to see a jump happen
Router.ARRIVED = 150         -- studs from the portal that count as a jump
Router.RESPAWN_COST = 6      -- seconds a respawn costs
Router.RESPAWN_STEPS = 60    -- x 0.25 s to wait for the new character

-- Sea 3 Submerged Island (reference): the island, the worker who sends you
-- there, the dock to leave from, and where leaving lands.
Router.ISLAND = Vector3.new(11538.6, -2154.7, 9827.3)
Router.ISLAND_RADIUS = 3000
Router.WORKER = Vector3.new(-16269.4, 24.0, 1371.7)
Router.DOCK = Vector3.new(11427.9, -2156.4, 9726.2)
Router.TIKI = Vector3.new(-16456.5, 530.3, 436.2)
Router.AT_DOCK = 30

local route, note
local busy, justJumped = false, false
local blocked, confirmed, lastUsed = {}, {}, {}

local function onIsland(position)
    return Player.sea() == 3 and (position - Router.ISLAND).Magnitude <= Router.ISLAND_RADIUS
end

local function spawnPoints()
    local points = {}
    local origin = workspace:FindFirstChild("_WorldOrigin")
    local spawns = origin and origin:FindFirstChild("PlayerSpawns")
    if not spawns then return points end
    for _, group in ipairs(spawns:GetChildren()) do
        for _, model in ipairs(group:GetChildren()) do
            if model:IsA("Model") then
                local ok, pivot = pcall(function() return model:GetPivot() end)
                if ok and pivot then points[#points + 1] = { name = model.Name, position = pivot.Position } end
            end
        end
    end
    return points
end

-- The cheapest route from `here` to `goal` at `speed` studs/s.
function Router.plan(here, goal, speed)
    speed = math.max(speed or 1, 1)
    local direct = (goal - here).Magnitude / speed
    local best = { kind = "direct", cost = direct, goal = goal }

    local function consider(option)
        option.goal = goal
        if option.cost < best.cost then best = option end
    end

    -- The Submerged Island is only reachable by submarine, both ways.
    local fromIsland, toIsland = onIsland(here), onIsland(goal)
    if toIsland and not fromIsland then
        return {
            kind = "submarine", name = "Submarine", goal = goal, dock = Router.WORKER, enter = true,
            cost = (here - Router.WORKER).Magnitude / speed + Router.OVERHEAD,
            saving = 0,
        }
    elseif fromIsland and not toIsland then
        best = {
            kind = "submarine", name = "Submarine", goal = goal, dock = Router.DOCK, enter = false,
            cost = (here - Router.DOCK).Magnitude / speed + Router.OVERHEAD + (Router.TIKI - goal).Magnitude / speed,
        }
        direct = math.huge
    end

    local now = os.clock()
    for _, point in ipairs(Entrances.available()) do
        if not blocked[point.name] and now - (lastUsed[point.name] or -math.huge) >= Router.COOLDOWN
            and (here - point.position).Magnitude > Router.ARRIVED then
            consider({
                kind = "entrance", name = point.name, point = point,
                cost = Router.OVERHEAD + (point.position - goal).Magnitude / speed,
            })
        end
    end

    if Settings.get("RespawnShortcut") then
        for _, spawn in ipairs(spawnPoints()) do
            consider({
                kind = "respawn", name = "respawn at " .. spawn.name, spawn = spawn,
                cost = Router.RESPAWN_COST + (spawn.position - goal).Magnitude / speed,
            })
        end
    end

    best.saving = direct - best.cost
    if best.kind ~= "direct" and best.kind ~= "submarine" and best.saving < Router.MIN_SAVING then
        return { kind = "direct", cost = direct, goal = goal, saving = 0 }
    end
    return best
end

---------------------------------------------------------------------------
-- Running a shortcut
---------------------------------------------------------------------------

local function waitUntil(steps, test)
    for _ = 1, steps do
        task.wait(0.25)
        if test() then return true end
    end
    return false
end

local function near(position, radius)
    local here = Player.position()
    return here ~= nil and (here - position).Magnitude <= radius
end

local function netInvoke(name, ...)
    local remote = Services.find(Services.replicated(), "Modules.Net")
    remote = remote and remote:FindFirstChild(name)
    if not remote then return nil end
    local args = { ... }
    local ok, result = pcall(function() return remote:InvokeServer((table.unpack or unpack)(args)) end)
    return ok and result or nil
end

local actions = {}

function actions.entrance(plan)
    Entrances.use(plan.point)
    local ok = waitUntil(Router.VERIFY_STEPS, function() return near(plan.point.position, Router.ARRIVED) end)
    if ok then confirmed[plan.name] = true else blocked[plan.name] = true end
end

function actions.submarine(plan)
    if plan.enter then
        netInvoke("RF/SubmarineWorkerSpeak", "TravelToSubmergedIsland")
        Services.invoke("SetLastSpawnPoint", "SubmergedIsland")
        waitUntil(Router.VERIFY_STEPS * 2, function() return near(Router.ISLAND, Router.ISLAND_RADIUS) end)
    else
        netInvoke("RF/SubmarineTransportation", "GetAvailableLocations")
        netInvoke("RF/SubmarineTransportation", "InitiateTeleport", "Tiki Outpost")
        waitUntil(Router.VERIFY_STEPS * 2, function() return near(Router.TIKI, 1000) end)
    end
end

function actions.respawn(plan)
    Services.invoke("SetLastSpawnPoint", plan.spawn.name)
    if Player.data("LastSpawnPoint") ~= plan.spawn.name then
        blocked[plan.name] = true
        return
    end
    local old = Player.character()
    local humanoid = Player.humanoid()
    if humanoid then humanoid.Health = 0 end
    waitUntil(Router.RESPAWN_STEPS, function()
        return Player.character() ~= old and Player.alive()
    end)
end

local function run(plan)
    busy = true
    lastUsed[plan.name] = os.clock()
    task.spawn(function()
        local ok, err = pcall(actions[plan.kind], plan)
        if not ok then warn("[Strawberry Hub] " .. plan.name .. ": " .. tostring(err)) end
        route = nil
        busy = false
        justJumped = true
    end)
end

-- Called by Movement each frame. Returns handled (true: a shortcut is
-- running, do not move this frame) and an optional Vector3 to fly to
-- instead of the goal (the submarine dock, for instance).
function Router.update(here, goal, speed)
    if busy then return true end
    if not Settings.get("SmartTravel") then
        route, note = nil, nil
        return false
    end
    if (goal - here).Magnitude < Router.SNAP then
        route, note = nil, nil
        return false
    end
    if justJumped then
        -- Fly at least one frame between two shortcuts.
        justJumped = false
        route = nil
        return false
    end

    if not route or (route.goal - goal).Magnitude > Router.REPLAN_MOVE then
        route = Router.plan(here, goal, speed)
    end

    if route.kind == "direct" then
        note = nil
        return false
    end

    if route.saving and route.saving > 0 and route.saving < math.huge then
        note = string.format("via %s (saves %d s)", route.name, math.floor(route.saving))
    else
        note = "via " .. route.name
    end

    if route.dock and (here - route.dock).Magnitude > Router.AT_DOCK then
        return false, route.dock
    end

    run(route)
    return true
end

function Router.busy() return busy end
function Router.note() return note end

-- Portals of this sea and what is known about them, for the Settings tab.
function Router.describe()
    local lines = {}
    local known = Entrances.unlocks() ~= nil
    for _, point in ipairs(Entrances.POINTS[Player.sea() or 0] or {}) do
        local state
        if blocked[point.name] then state = "locked"
        elseif confirmed[point.name] then state = "works"
        elseif point.unlock and known and not Entrances.unlocks()[point.unlock] then state = "not unlocked"
        else state = "untested" end
        lines[#lines + 1] = point.name .. ": " .. state
    end
    if #lines == 0 then return "No portal known in this sea." end
    if not known then lines[#lines + 1] = "(unlocks not read yet)" end
    return table.concat(lines, "\n")
end

-- Test hook.
function Router.reset()
    route, note = nil, nil
    busy, justJumped = false, false
    blocked, confirmed, lastUsed = {}, {}, {}
end

return Router
