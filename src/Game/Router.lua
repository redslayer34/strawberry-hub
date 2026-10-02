--=============================================================================
-- ROUTER — how far goals are reached
--=============================================================================
--  Movement asks the Router every frame. Some ways are taken whenever they
--  apply:
--
--    temple      Sea 3: out of the Temple of Time, its own way back
--    templeIn    Sea 3: into the temple, through the "Mysterious Force" NPC
--                (race V4 progress Begin / Teleport), as Vxeze Hub does
--    submarine   Sea 3: the only way to and from the Submerged Island
--    entrance    Sea 1 (Teddy Kaitun): into and out of the Underwater City,
--                up to the Sky and the Upper Sky, from wherever the
--                character is: requestEntrance(dest) while standing on dest
--
--  Then every way that fits is given an estimated time and the one that
--  arrives first is taken; flying is a way too:
--
--    pad         the game's portal doors (Game/Pads, from Vxeze Hub): fly to
--                the door, stand on it and call it until it sends you on;
--                routes of up to PAD_DEPTH doors, only when they save
--                PAD_GAIN studs
--    gateway     opt-in: the Portal fruit's Gateway to the island nearest the
--                goal (fruit level 200+, C skill ready)
--    celestial   Sea 3: the Celestial Domain's own transports
--    mirror      Sea 3: the Cake Loaf's big mirror
--    respawn     "Reset teleport": move the spawn point to the goal's island,
--                then reset the character; never while holding something
--                death would lose (Router.PROTECTED)
--    direct      fly
--
--  The doors, the gateway and the reset only count when the goal is farther
--  than the "Teleport when farther than" setting. A door is paused when the
--  flight to it makes no progress for PAD_STUCK seconds, when it does not
--  send you on, or when it is used twice in PAD_LOOP_WINDOW seconds (Vxeze's
--  rules). The last LOG_SIZE events are kept in a travel log.
--=============================================================================

local Entrances = require("Game.Entrances")
local Gateway = require("Game.Gateway")
local Pads = require("Game.Pads")
local Player = require("Core.Player")
local Regions = require("Game.Regions")
local Services = require("Core.Services")
local Settings = require("Core.Settings")
local World = require("Game.World")

local Router = {}

Router.SNAP = 150              -- studs: closer goals are simply set
Router.FAR = 3000              -- the Portal fruit's island must be this near the goal
Router.COOLDOWN = 4            -- seconds before the same shortcut is tried again
Router.FAILS_TO_LOCK = 2       -- misses in a row before a shortcut is paused
Router.LOCK_TIME = 120         -- seconds a paused shortcut stays paused
Router.REPLAN_MOVE = 300       -- studs the goal may move before re-planning
Router.REPLAN_EVERY = 5        -- seconds a flight is kept before looking again
Router.DOCK_RADIUS = 8         -- the reference calls at 8 studs from a dock
Router.VERIFY_STEPS = 24       -- x 0.25 s to see a transport happen
Router.RESPAWN_STEPS = 60      -- x 0.25 s to wait for the new character
Router.MAX_RESPAWNS = 5        -- respawns for one goal, as the reference
Router.GATEWAY_STEPS = 25      -- x 0.2 s to land after the Gateway
Router.GATEWAY_ARRIVED = 500
Router.LOG_SIZE = 15
Router.DEFAULT_DISTANCE = 2000

-- Portal doors (Vxeze's numbers).
Router.PAD_DEPTH = 4           -- doors in one route at most
Router.PAD_GAIN = 1500         -- studs a route must save over flying
Router.PAD_STAND = 3           -- studs from the door to start calling it
Router.PAD_EVERY = 0.1         -- seconds between two checks at the door
Router.PAD_CALL_EVERY = 3      -- checks between two calls (0.3 s)
Router.PAD_TIME = 8            -- seconds of calls at a door
Router.PAD_TOUCH_TIME = 3      -- the same for a touch door
Router.PAD_ARRIVED = 200       -- studs from the door that mean it sent you on
Router.PAD_SETTLE = 1.5        -- seconds given to the landing
Router.PAD_STUCK = 10          -- seconds without getting closer to the door
Router.PAD_PAUSE = 120         -- seconds a failed door is left alone
Router.PAD_LOOP_WINDOW = 90    -- the same door twice in this time...
Router.PAD_LOOP_PAUSE = 90     -- ...is left alone this long

-- Temple of Time entrance (Vxeze's TeleportTempleOfTime).
Router.TEMPLE_NPC = "Mysterious Force"
Router.TEMPLE_NPC_RADIUS = 10
Router.TEMPLE_PROGRESS_EVERY = 5

-- Seconds each way costs before the flight from where it lands.
Router.COST = { gateway = 4, celestial = 3, mirror = 3, respawn = 10 }

-- Lost on death (Teddy Hub's list): no reset teleport while one is held.
Router.PROTECTED = { "Fist of Darkness", "God's Chalice", "Sweet Chalice", "Hallow Essence", "Special Microchip" }
Router.PROTECTED_SEA = {
    [2] = { "Flower 1", "Flower 2", "Flower 3", "Blue Flower", "Yellow Flower", "Red Flower" },
    [3] = { "Red Key" },
}

-- Sea 3 Submerged Island (reference): the island, the worker who sends you
-- there, the dock to leave from, and where leaving lands.
Router.ISLAND = Vector3.new(11538.599609375, -2154.7021484375, 9827.3125)
Router.ISLAND_RADIUS = 3000
Router.WORKER = Vector3.new(-16269.4082, 23.9799957, 1371.66235)
Router.DOCK = Vector3.new(11427.9189, -2156.36401, 9726.24023)
Router.TIKI = Vector3.new(-16456.5, 530.3, 436.2)

-- Sea 1 entrances (Teddy Kaitun's DoTween2): `dest` is called and the
-- character put there a few times; `to(goal)` says whether the goal is
-- behind it, `inside(here)` whether the character already is.
local function v(x, y, z) return Vector3.new(x, y, z) end
local UNDERWATER = v(61163.85, 11.6796875, 1819.7842)
local function underwater(position)
    return position.X > 55000 or (position - UNDERWATER).Magnitude < 3000
end
Router.ENTRANCES = {
    { name = "Underwater City entrance", dest = UNDERWATER, lift = 1.5, arrived = 2000,
        to = function(goal) return goal.X > 55000 or (goal - UNDERWATER).Magnitude < 4000 end,
        inside = underwater },
    { name = "Underwater City exit", dest = v(3864.6885, 6.7369504, -1926.2141), lift = 15, arrived = 2000,
        to = function(goal) return goal.X <= 55000 and (goal - UNDERWATER).Magnitude >= 4000 end,
        inside = function(here) return not underwater(here) end },
    { name = "Upper Sky entrance", dest = v(-6023.5767, 5469.7197, 2203.3083), lift = 0, arrived = 3000,
        to = function(goal) return goal.Y >= 4000 and (goal - v(-6023.5767, 5469.7197, 2203.3083)).Magnitude < 3500 end },
    { name = "Sky entrance", dest = v(-4166.61, 1093.698, -347.16226), lift = 0, arrived = 3000,
        to = function(goal) return goal.Y >= 200 and goal.Y < 4000
            and (goal - v(-4166.61, 1093.698, -347.16226)).Magnitude < 3000 end },
}
Router.ENTRANCE_TRIES = 4
Router.ENTRANCE_EVERY = 0.15

-- Sea 3 Temple of Time (reference): leaving it means standing on its exit
-- point and asking the game to send you back.
Router.TEMPLE = Vector3.new(28609.392578125, 14896.533203125, 106.4216537475586)
Router.TEMPLE_RADIUS = 3000

-- Sea 3 Cake Loaf: the big mirror leads to this place in the sky.
Router.MIRROR_INSIDE = Vector3.new(-1990.67, 4532.97, -14973.67)
Router.MIRROR_RADIUS = 1000

-- Sea 3 Celestial Domain: its NPC, and how close to it the transport works.
Router.CELESTIAL = "Celestial Domain"
Router.CELESTIAL_NPC = "Celestial Member"
Router.CELESTIAL_RADIUS = 300

local route, note, lastTrip
local events = {}              -- the travel log
local tripAt                   -- os.clock() of the trip the log is timing
local lastLogged               -- the last plan written to the log
local busy, justJumped = false, false
local confirmed, lastUsed = {}, {}
local failures, lockedAt, attempts = {}, {}, {}
local pausedUntil = {}         -- [door] = os.clock() it may be used again
local padUses = {}             -- [door] = { os.clock() of each use }
local respawns = { goal = nil, count = 0 }
local templeProgress = { value = nil, at = -math.huge }

---------------------------------------------------------------------------
-- Travel log
---------------------------------------------------------------------------

local function xyz(position)
    if not position then return "?" end
    return string.format("%d, %d, %d", math.floor(position.X), math.floor(position.Y), math.floor(position.Z))
end

-- Adds one event, timed from the start of the trip.
function Router.log(text)
    local now = os.clock()
    tripAt = tripAt or now
    events[#events + 1] = string.format("+%.1fs %s", now - tripAt, text)
    while #events > Router.LOG_SIZE do table.remove(events, 1) end
end

-- Starts timing a new trip in the log.
local function logTrip(here, goal)
    tripAt = os.clock()
    lastLogged = nil
    Router.log(string.format("trip from %s to %s, %d studs", xyz(here), xyz(goal), math.floor((goal - here).Magnitude)))
end

function Router.logText()
    if #events == 0 then return "No far trip yet." end
    return table.concat(events, "\n")
end

---------------------------------------------------------------------------
-- Shortcut memory
---------------------------------------------------------------------------

local function isLocked(name)
    local since = lockedAt[name]
    if not since then return false end
    if os.clock() - since >= Router.LOCK_TIME then
        lockedAt[name] = nil
        failures[name] = 0
        return false
    end
    return true
end

local function coolingDown(name)
    return os.clock() - (lastUsed[name] or -math.huge) < Router.COOLDOWN
end

local function usable(name)
    return not isLocked(name) and not coolingDown(name)
end

local function recordResult(name, ok, detail)
    attempts[name] = detail
    if ok then
        confirmed[name] = true
        failures[name] = 0
        lockedAt[name] = nil
        return
    end
    failures[name] = (failures[name] or 0) + 1
    if failures[name] >= Router.FAILS_TO_LOCK then
        lockedAt[name] = os.clock()
    end
end

-- Leaves door `name` alone for `seconds`, saying why.
local function pausePad(name, seconds, why)
    pausedUntil[name] = os.clock() + seconds
    attempts[name] = why
    Router.log(string.format("%s paused %d s: %s", name, seconds, why))
end

local function padPaused(name)
    local untilAt = pausedUntil[name]
    if untilAt and os.clock() < untilAt then return true end
    pausedUntil[name] = nil
    return false
end

-- How many times door `name` was used in the last PAD_LOOP_WINDOW seconds.
local function recentUses(name)
    local now, kept = os.clock(), {}
    for _, at in ipairs(padUses[name] or {}) do
        if now - at <= Router.PAD_LOOP_WINDOW then kept[#kept + 1] = at end
    end
    padUses[name] = kept
    return #kept
end

local function within(position, center, radius)
    return (position - center).Magnitude <= radius
end

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------

-- Whether door `pad` may be part of a route now. Returns ok, why not.
function Router.padUsable(pad)
    if padPaused(pad.name) then return false, "paused" end
    if recentUses(pad.name) >= 2 then
        pausePad(pad.name, Router.PAD_LOOP_PAUSE, "used twice in a row, flying instead")
        return false, "paused"
    end
    local blocked = Pads.blocked(pad)
    if blocked then return false, blocked end
    return true
end

-- The best route through doors from `here` to `goal`: cost (studs, with
-- the doors' time), the doors in order. Also why no door helps, if none.
function Router.padRoute(here, goal)
    local reasons, seen = {}, {}
    local cost, chain = Pads.route(here, goal, Router.PAD_DEPTH, function(pad)
        local ok, why = Router.padUsable(pad)
        if not ok and why ~= "paused" and not seen[why] then
            seen[why] = true
            reasons[#reasons + 1] = "doors " .. why
        end
        return ok
    end)
    return cost, chain, reasons
end

local function holding(name)
    local character = Player.character()
    local player = Services.player()
    return (character and character:FindFirstChild(name) ~= nil)
        or (player ~= nil and Services.find(player, "Backpack." .. name) ~= nil)
end

local function unstoredFruit()
    local player = Services.player()
    local places = { Player.character(), player and player:FindFirstChild("Backpack") }
    for _, place in pairs(places) do
        for _, tool in ipairs(place:GetChildren()) do
            if tool:IsA("Tool") and tool.Name:find("Fruit", 1, true) then return tool.Name end
        end
    end
    return nil
end

local function inside(moduleName, fn)
    local ok, module = pcall(require, moduleName)
    if not ok or type(module) ~= "table" or type(module[fn]) ~= "function" then return false end
    local ran, result = pcall(module[fn])
    return ran and result == true
end

-- Why a reset teleport must not happen now (something death would lose,
-- or a place a reset would throw you out of), or nil.
function Router.resetBlocked()
    local names = {}
    for _, name in ipairs(Router.PROTECTED) do names[#names + 1] = name end
    for _, name in ipairs(Router.PROTECTED_SEA[Player.sea() or 0] or {}) do names[#names + 1] = name end
    for _, name in ipairs(names) do
        if holding(name) then return "holding " .. name end
    end
    local fruit = unstoredFruit()
    if fruit then return "holding " .. fruit .. " (not stored)" end
    local here = Player.position()
    if here and Player.sea() == 3 and within(here, Router.ISLAND, Router.ISLAND_RADIUS) then
        return "on the Submerged Island"
    end
    if inside("Features.Raids", "inRaid") then return "in a raid" end
    if inside("Features.Dungeon", "inside") then return "in a dungeon" end
    return nil
end

function Router.teleportDistance()
    return tonumber(Settings.get("TeleportDistance")) or Router.DEFAULT_DISTANCE
end

local function isInterior(part)
    return part ~= nil and (part.Name == Router.CELESTIAL .. " (Interior)" or part.Name == Router.CELESTIAL .. " <Interior>")
end

local function isDomain(part)
    return part ~= nil and part.Name == Router.CELESTIAL
end

-- The nearest ready "Celestial Member" NPC (the reference's DetectNpcOni).
local function celestialMember()
    local best, bestDistance
    local folders = { workspace:FindFirstChild("NPCs"), Services.replicated():FindFirstChild("NPCs") }
    for _, folder in pairs(folders) do
        for _, npc in ipairs(folder:GetChildren()) do
            local root = npc:FindFirstChild("HumanoidRootPart")
            if root and npc:GetAttribute("NPCLoaded") and npc:GetAttribute("NPCReady")
                and npc:GetAttribute("DisplayName") == Router.CELESTIAL_NPC then
                local distance = Player.distanceTo(root.Position)
                if not bestDistance or distance < bestDistance then best, bestDistance = npc, distance end
            end
        end
    end
    return best
end

local function celestialPlan(here, goal)
    local hereIn, goalIn = Regions.containing(here), Regions.containing(goal)
    local hereNear, goalNear = Regions.nearest(here), Regions.nearest(goal)
    local function viaMember(step)
        local npc = celestialMember()
        if not npc then return nil end
        local dock = (npc.HumanoidRootPart.CFrame * CFrame.new(0, 0, 20)).Position
        return { kind = "celestial", step = step, name = "Celestial Domain transport", dock = dock,
            dockRadius = Router.CELESTIAL_RADIUS }
    end
    if isDomain(goalIn) and not isDomain(hereIn) then return viaMember("temple") end
    if isInterior(goalNear) then
        if isDomain(hereIn) then
            return { kind = "celestial", step = "interior", name = "Celestial Domain interior" }
        end
        if not hereIn or (not isDomain(hereIn) and not isInterior(hereNear)) then
            return viaMember("temple+interior")
        end
    end
    if isInterior(hereNear) and not isInterior(goalNear) then
        return { kind = "celestial", step = "leave", name = "leaving the Celestial Domain" }
    end
    if isDomain(hereIn) and not isDomain(goalIn) then
        return { kind = "celestial", step = "leave", name = "leaving the Celestial Domain" }
    end
    return nil
end

local function mirrorPlan(here, goal)
    local mirror = Services.find(workspace, "Map.CakeLoaf.BigMirror.Main")
    if not mirror then return nil end
    if within(goal, Router.MIRROR_INSIDE, Router.MIRROR_RADIUS)
        and not within(here, Router.MIRROR_INSIDE, Router.MIRROR_RADIUS) then
        return { kind = "mirror", name = "Cake mirror", dock = mirror.Position, part = mirror }
    end
    return nil
end

local function respawnsLeft(goal)
    if respawns.goal and within(goal, respawns.goal, Router.REPLAN_MOVE) then
        return respawns.count < Router.MAX_RESPAWNS
    end
    return true
end

-- The race V4 temple progress (0 = locked, 1 = to begin, 2+ = open),
-- asked at most every TEMPLE_PROGRESS_EVERY seconds.
function Router.templeProgress()
    if os.clock() - templeProgress.at >= Router.TEMPLE_PROGRESS_EVERY then
        templeProgress.at = os.clock()
        local value = Services.invoke("RaceV4Progress", "Check")
        if value == 0 and Services.invoke("CheckTempleDoor") then value = 2 end
        templeProgress.value = value
    end
    return templeProgress.value
end

local function entrancePlan(here, goal)
    for _, entrance in ipairs(Router.ENTRANCES) do
        local inside
        if entrance.inside then inside = entrance.inside(here)
        else inside = (here - entrance.dest).Magnitude <= entrance.arrived end
        if not inside and entrance.to(goal) and usable(entrance.name) then
            return { kind = "entrance", name = entrance.name, entrance = entrance }
        end
    end
    return nil
end

-- The ways that are taken whenever they apply. Also a reason when the
-- temple cannot be entered.
local function mandatoryPlan(here, goal)
    if Player.sea() == 1 then return entrancePlan(here, goal) end
    if Player.sea() ~= 3 then return nil end
    local inTemple = within(here, Router.TEMPLE, Router.TEMPLE_RADIUS)
    local toTemple = within(goal, Router.TEMPLE, Router.TEMPLE_RADIUS)
    local fromIsland = within(here, Router.ISLAND, Router.ISLAND_RADIUS)
    local toIsland = within(goal, Router.ISLAND, Router.ISLAND_RADIUS)
    if inTemple and not toTemple then
        return { kind = "temple", name = "Temple of Time exit", dock = Router.TEMPLE }
    elseif toTemple and not inTemple then
        local progress = Router.templeProgress()
        if not progress or progress == 0 then return nil, "Temple of Time locked (race V4 not started)" end
        local npc = World.npcPosition(Router.TEMPLE_NPC)
        if not npc then return nil, "the Mysterious Force is not loaded yet" end
        return { kind = "templeIn", name = "Temple of Time entrance", dock = npc + Vector3.new(0, 0, 4),
            dockRadius = Router.TEMPLE_NPC_RADIUS, begin = progress == 1 }
    elseif toIsland and not fromIsland then
        return { kind = "submarine", name = "Submarine", dock = Router.WORKER, enter = true }
    elseif fromIsland and not toIsland then
        return { kind = "submarine", name = "Submarine", dock = Router.DOCK, enter = false }
    end
    return nil
end

-- What to do to reach `goal` from `here`: the mandatory ways, else the way
-- that arrives first at `speed` studs per second.
function Router.plan(here, goal, speed)
    speed = math.max(tonumber(speed) or tonumber(Settings.get("TweenSpeed")) or 300, 1)
    local distance = (goal - here).Magnitude
    local direct = { kind = "direct" }
    local plan = direct

    if distance < Router.SNAP then
        plan = direct
    elseif not Player.sea() then
        direct.reason = "sea unknown"
    else
        local mandatory, templeWhy = mandatoryPlan(here, goal)
        plan = mandatory
        if not plan then
            local far = distance >= Router.teleportDistance()
            local candidates, reasons = {}, {}
            if templeWhy then reasons[#reasons + 1] = templeWhy end
            local flyTime = distance / speed
            local mustTransport = false
            local function add(candidate, landing, cost)
                candidate.eta = cost + (landing - goal).Magnitude / speed
                candidates[#candidates + 1] = candidate
            end

            if far then
                local cost, chain, why = Router.padRoute(here, goal)
                if #chain > 0 and distance - cost >= Router.PAD_GAIN then
                    local first = chain[1]
                    candidates[#candidates + 1] = { kind = "pad", name = first.name, pad = first, chain = chain,
                        dock = first.stand, dockRadius = Router.PAD_STAND, eta = cost / speed }
                elseif #chain == 0 then
                    for _, text in ipairs(why) do reasons[#reasons + 1] = text end
                end
            end

            if far and Settings.get("PortalFruit") then
                local island = Gateway.islandNear(goal, Router.FAR)
                local key = island and ("Portal fruit to " .. island.name)
                if island and usable(key) and Gateway.ready(true) then
                    add({ kind = "gateway", name = key, island = island }, island.position, Router.COST.gateway)
                end
            end

            if Player.sea() == 3 then
                local special = celestialPlan(here, goal) or mirrorPlan(here, goal)
                if special and usable(special.name) then
                    mustTransport = true
                    local toDock = special.dock and (special.dock - here).Magnitude or 0
                    special.eta = toDock / speed + Router.COST[special.kind]
                    candidates[#candidates + 1] = special
                end
            end

            if far then
                if not Settings.get("ResetTeleport") then
                    reasons[#reasons + 1] = "reset teleport off"
                else
                    local blocked = Router.resetBlocked()
                    if blocked then
                        reasons[#reasons + 1] = "reset teleport skipped: " .. blocked
                    elseif not respawnsLeft(goal) then
                        reasons[#reasons + 1] = "reset teleport: " .. Router.MAX_RESPAWNS .. " resets already for this goal"
                    elseif not Regions.shouldRespawn(here, goal) then
                        reasons[#reasons + 1] = "reset teleport: goal on your island"
                    else
                        local spawn = Regions.respawnTarget(here, goal)
                        local name = spawn and ("respawn at " .. spawn.name)
                        if not spawn then
                            reasons[#reasons + 1] = "reset teleport: no spawn closer to the goal"
                        elseif usable(name) then
                            add({ kind = "respawn", name = name, spawn = spawn }, spawn.position, Router.COST.respawn)
                        end
                    end
                end
            end

            local best
            for _, candidate in ipairs(candidates) do
                if not best or candidate.eta < best.eta then best = candidate end
            end
            if best and not mustTransport and best.eta >= flyTime then
                reasons[#reasons + 1] = string.format("%s slower than flying (%d s against %d s)", best.name,
                    math.ceil(best.eta), math.ceil(flyTime))
                best = nil
            end
            if best then
                best.flyTime = flyTime
                plan = best
            else
                direct.reason = #reasons > 0 and table.concat(reasons, "; ") or nil
                plan = direct
            end
        end
    end

    plan.goal = goal
    plan.at = os.clock()
    return plan
end

---------------------------------------------------------------------------
-- Running a shortcut
---------------------------------------------------------------------------

local function waitUntil(steps, test, interval)
    for _ = 1, steps do
        task.wait(interval or 0.25)
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
    local args = { n = select("#", ...), ... }
    local ok, result = pcall(function() return remote:InvokeServer((table.unpack or unpack)(args, 1, args.n)) end)
    return ok and result or nil
end

local actions = {}

-- Vxeze's ActivateGateway: held on the door (unless it is a touch door),
-- the door is called every PAD_CALL_EVERY checks until it has sent the
-- character PAD_ARRIVED studs away, or the time is up.
function actions.pad(plan)
    local pad = plan.pad
    local uses = padUses[pad.name] or {}
    uses[#uses + 1] = os.clock()
    padUses[pad.name] = uses
    local checks = math.floor((pad.touch and Router.PAD_TOUCH_TIME or Router.PAD_TIME) / Router.PAD_EVERY + 0.5)
    local calls, answer, gone = 0, nil, false
    for check = 1, checks do
        local hrp = Player.hrp()
        if not hrp then break end
        if (hrp.Position - pad.stand).Magnitude > Router.PAD_ARRIVED then
            gone = true
            break
        end
        pcall(function()
            if not pad.touch and (hrp.Position - pad.stand).Magnitude > Router.PAD_STAND then
                hrp.CFrame = CFrame.new(pad.stand)
            end
            hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end)
        if (check - 1) % Router.PAD_CALL_EVERY == 0 then
            calls = calls + 1
            local ok, result = pcall(Pads.use, pad)
            if ok then answer = result end
        end
        task.wait(Router.PAD_EVERY)
    end
    if not gone then
        local here = Player.position()
        gone = here ~= nil and (here - pad.stand).Magnitude > Router.PAD_ARRIVED
    end
    if gone then
        task.wait(Router.PAD_SETTLE)
        recordResult(pad.name, true, nil)
        lastTrip = string.format("through %s (%d calls)", pad.name, calls)
        Router.log(string.format("%s: sent on after %d calls, now at %s", pad.name, calls, xyz(Player.position())))
        return
    end
    pausePad(pad.name, Router.PAD_PAUSE, string.format("did not open after %d calls, answer %s", calls, tostring(answer)))
    lastTrip = pad.name .. " did not open"
end

-- Teddy's way: call the entrance and stand on its far side, a few times,
-- until the server keeps the character there.
function actions.entrance(plan)
    local entrance = plan.entrance
    local arrived = false
    for _ = 1, Router.ENTRANCE_TRIES do
        task.wait(Router.ENTRANCE_EVERY)
        pcall(Services.invoke, "requestEntrance", entrance.dest)
        local hrp = Player.hrp()
        if not hrp then break end
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            hrp.CFrame = CFrame.new(entrance.dest + Vector3.new(0, entrance.lift, 0))
        end)
        if near(entrance.dest, entrance.arrived) then
            arrived = true
            break
        end
    end
    -- The server may put the character back a moment later.
    task.wait(Router.ENTRANCE_EVERY * 2)
    arrived = arrived and near(entrance.dest, entrance.arrived)
    recordResult(plan.name, arrived, arrived and "arrived" or "put back")
    Router.log(string.format("%s: %s, now at %s", plan.name, arrived and "arrived" or "put back",
        xyz(Player.position())))
end

function actions.gateway(plan)
    if not Gateway.open(plan.island.name) then
        recordResult(plan.name, false, "the Gateway did not open")
        return
    end
    local ok = waitUntil(Router.GATEWAY_STEPS, function()
        return near(plan.island.position, Router.GATEWAY_ARRIVED)
    end, 0.2)
    recordResult(plan.name, ok, ok and "arrived" or "no arrival after the Gateway")
end

function actions.temple()
    Services.invoke("RaceV4Progress", "Check")
    Services.invoke("RaceV4Progress", "TeleportBack")
    waitUntil(Router.VERIFY_STEPS, function() return not near(Router.TEMPLE, Router.TEMPLE_RADIUS) end)
end

-- Vxeze's TeleportTempleOfTime, at the Mysterious Force.
function actions.templeIn(plan)
    if plan.begin then
        Services.invoke("RaceV4Progress", "Begin")
        templeProgress.at = -math.huge
        task.wait(1)
    end
    pcall(Entrances.borrowTemple)
    Services.invoke("RaceV4Progress", "Teleport")
    local ok = waitUntil(Router.VERIFY_STEPS, function() return near(Router.TEMPLE, Router.TEMPLE_RADIUS) end)
    recordResult(plan.name, ok, ok and "inside" or "the Mysterious Force did not send you")
    Router.log("Temple of Time entrance: " .. (ok and "inside" or "no teleport"))
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

function actions.celestial(plan)
    local function transport(what) return netInvoke("RF/CelestialDomainTransportation", what) end
    if plan.step == "temple" or plan.step == "temple+interior" then
        transport("InitiateTeleportToTemple")
        local controller = Services.module("Controllers.MapServices.CelestialDomainController")
        if type(controller) == "table" and controller.LoadMap then pcall(controller.LoadMap, controller) end
        task.wait(1)
        if plan.step == "temple+interior" then transport("InitiateTeleportToInterior") end
    elseif plan.step == "interior" then
        transport("InitiateTeleportToInterior")
        task.wait(1)
    else
        transport("Leave")
        task.wait(1)
    end
end

function actions.mirror(plan)
    local hrp = Player.hrp()
    if firetouchinterest and hrp then
        pcall(firetouchinterest, hrp, plan.part, 0)
        pcall(firetouchinterest, hrp, plan.part, 1)
    end
    local ok = waitUntil(12, function() return near(Router.MIRROR_INSIDE, Router.MIRROR_RADIUS) end)
    recordResult(plan.name, ok, ok and "inside" or "the mirror did not take you in")
end

-- The reference's TweenBypass: the character's own LastSpawnPoint script is
-- switched off so it cannot put the old spawn point back, the spawn point
-- is moved, then the character is reset.
function actions.respawn(plan)
    if respawns.goal and within(plan.goal, respawns.goal, Router.REPLAN_MOVE) then
        respawns.count = respawns.count + 1
    else
        respawns.goal, respawns.count = plan.goal, 1
    end
    local character = Player.character()
    local script = character and character:FindFirstChild("LastSpawnPoint")
    if script then pcall(function() script.Disabled = true end) end
    Services.invoke("SetLastSpawnPoint", plan.spawn.name)
    if Player.data("LastSpawnPoint") ~= plan.spawn.name then
        if script then pcall(function() script.Disabled = false end) end
        recordResult(plan.name, false, "spawn point refused")
        Router.log("reset teleport to " .. plan.spawn.name .. ": spawn point refused")
        return
    end
    local humanoid = Player.humanoid()
    if humanoid then humanoid.Health = 0 end
    local ok = waitUntil(Router.RESPAWN_STEPS, function()
        return Player.character() ~= character and Player.alive()
    end)
    if script and script.Parent then pcall(function() script.Disabled = false end) end
    recordResult(plan.name, ok, ok and "respawned" or "no new character")
    lastTrip = ok and ("reset teleport to " .. plan.spawn.name) or ("reset teleport to " .. plan.spawn.name .. " failed")
    Router.log(string.format("reset teleport to %s: %s", plan.spawn.name, ok and ("respawned at " .. xyz(Player.position()))
        or "no new character"))
end

local function run(plan)
    busy = true
    lastUsed[plan.name] = os.clock()
    task.spawn(function()
        local started = os.clock()
        lastTrip = nil
        local ok, err = pcall(actions[plan.kind], plan)
        if not ok then warn("[Strawberry Hub] " .. plan.name .. ": " .. tostring(err)) end
        if plan.kind == "respawn" and lastTrip then
            lastTrip = string.format("%s, %.1f s", lastTrip, os.clock() - started)
        elseif not lastTrip then
            lastTrip = string.format("via %s, %.1f s", plan.name, os.clock() - started)
        end
        route = nil
        busy = false
        justJumped = true
    end)
end

-- One line for a plan, for the log, the status and "Show route".
function Router.planText(plan)
    if plan.kind == "direct" then
        return "fly" .. (plan.reason and (" (" .. plan.reason .. ")") or "")
    end
    local name = plan.name
    if plan.chain and #plan.chain > 1 then
        local names = {}
        for _, pad in ipairs(plan.chain) do names[#names + 1] = pad.name end
        name = table.concat(names, " > ")
    end
    if plan.eta and plan.flyTime then
        return string.format("%s via %s, about %d s (flying: %d s)", plan.kind, name, math.ceil(plan.eta),
            math.ceil(plan.flyTime))
    end
    return plan.kind .. " via " .. name
end

-- Called by Movement each frame. Returns handled (true: a shortcut is
-- running, do not move this frame) and an optional Vector3 to fly to
-- instead of the goal (a door, a dock, an NPC, the mirror).
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

    if not route or (route.goal - goal).Magnitude > Router.REPLAN_MOVE
        or (route.kind == "direct" and os.clock() - route.at >= Router.REPLAN_EVERY) then
        route = Router.plan(here, goal, speed)
        if (goal - here).Magnitude >= Router.teleportDistance() then
            local text = "plan: " .. Router.planText(route)
            if text ~= lastLogged then
                if not lastLogged then logTrip(here, goal) end
                lastLogged = text
                Router.log(text)
            end
        end
    end

    if route.kind == "direct" then
        note = route.reason and ("flying: " .. route.reason) or nil
        return false
    end
    note = Router.planText(route)

    if route.dock and (here - route.dock).Magnitude > (route.dockRadius or Router.DOCK_RADIUS) then
        -- Vxeze: a door that cannot be reached is left alone.
        if route.kind == "pad" then
            local reach = (here - route.dock).Magnitude
            if not route.bestReach or reach < route.bestReach - 20 then
                route.bestReach, route.progressAt = reach, os.clock()
            elseif os.clock() - route.progressAt > Router.PAD_STUCK then
                pausePad(route.pad.name, Router.PAD_PAUSE, "could not reach the door")
                route = nil
                return false
            end
        end
        return false, route.dock
    end

    run(route)
    return true
end

-- The route to `goal` from where the player stands, without moving.
function Router.routeText(goal)
    local here = Player.position()
    if not here then return "no character" end
    local speed = math.min(tonumber(Settings.get("TweenSpeed")) or 300, 350)
    local plan = Router.plan(here, goal, speed)
    local text = Router.planText(plan)
    if plan.kind == "pad" then
        local last = plan.chain[#plan.chain]
        text = text .. string.format(", then fly %d studs", math.floor((last.dest - goal).Magnitude))
    end
    return text
end

-- Forgets every miss, pause and cooldown (the "Clear portal pauses" button).
function Router.clearPauses()
    failures, lockedAt, attempts, lastUsed = {}, {}, {}, {}
    pausedUntil, padUses = {}, {}
    respawns = { goal = nil, count = 0 }
    route = nil
    pcall(Pads.reset)
end

function Router.busy() return busy end
function Router.note() return note end
function Router.lastTrip() return lastTrip end

-- The doors of this sea and what is known about them, for the Travel panel.
function Router.describe()
    local lines = {}
    for _, pad in ipairs(Pads.here()) do
        local state
        local blocked = Pads.blocked(pad)
        if padPaused(pad.name) then
            state = string.format("paused %d s", math.ceil(pausedUntil[pad.name] - os.clock()))
            if attempts[pad.name] then state = state .. " (" .. attempts[pad.name] .. ")" end
        elseif blocked then
            state = blocked
        elseif confirmed[pad.name] then
            state = "works"
        else
            state = "ready"
        end
        lines[#lines + 1] = pad.name .. ": " .. state
    end
    if #lines == 0 then lines[1] = "No portal door in this sea." end
    local fruit
    if not Settings.get("PortalFruit") then
        fruit = "off"
    elseif Gateway.owned() then
        fruit = Gateway.ready(false) and "ready" or "waiting for the C skill"
    else
        fruit = "needs the Portal fruit at level 200+"
    end
    lines[#lines + 1] = "Portal fruit: " .. fruit
    local reset = "off"
    if Settings.get("ResetTeleport") then
        local blocked = Router.resetBlocked()
        reset = blocked and ("on, skipped now: " .. blocked) or "on"
    end
    lines[#lines + 1] = "Reset teleport: " .. reset
    lines[#lines + 1] = string.format("Teleport when farther than %d studs", Router.teleportDistance())
    lines[#lines + 1] = "Last trip: " .. (lastTrip or "none yet")
    lines[#lines + 1] = "Now: " .. (note or "no far trip")
    lines[#lines + 1] = "Sea: " .. tostring(Player.sea() or "unknown")
    return table.concat(lines, "\n")
end

-- Test hook.
function Router.reset()
    route, note, lastTrip = nil, nil, nil
    events, tripAt, lastLogged = {}, nil, nil
    busy, justJumped = false, false
    confirmed, lastUsed = {}, {}
    failures, lockedAt, attempts = {}, {}, {}
    pausedUntil, padUses = {}, {}
    respawns = { goal = nil, count = 0 }
    templeProgress = { value = nil, at = -math.huge }
end

return Router
