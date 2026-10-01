--=============================================================================
-- PADS — the game's portal doors (Vxeze Hub's GatewayPads)
--=============================================================================
--  A portal is a door: the character must stand on it (`stand`) for the
--  server to send it on (`dest`). Standing there, Vxeze calls
--  requestEntrance(dest) again and again; a few doors work by touching a
--  part instead (`touch`). Some need an item in the inventory (`requires`):
--  the rip_indra doors the Valkyrie Helm, the Castle <-> Tiki door the
--  Feathered Visage. Calling requestEntrance from anywhere else answers nil,
--  and a character only placed on the far side is put back by the server
--  (the user's travel log).
--
--  Pads.route chains up to `depth` doors, Vxeze's way: the cost of a route
--  is the flight to each door, plus HOP studs per door for the time a door
--  takes (so going through a door and straight back never wins).
--=============================================================================

local Player = require("Core.Player")
local Services = require("Core.Services")

local Pads = {}

Pads.HOP = 600                 -- studs a door is worth in time (about 2 s)
Pads.INVENTORY_CACHE = 10      -- seconds an item check is reused
Pads.TAG = "BoatCastleTeleporter"

local function v(x, y, z) return Vector3.new(x, y, z) end

Pads.LIST = {
    [1] = {
        { name = "Enter Underwater City", stand = v(4050, 6, -1815), dest = v(61163.85, 11.6796875, 1819.7842) },
        { name = "Leave Underwater City", stand = v(61170, 1, 1952), dest = v(3864.6885, 6.74402, -1926.2141) },
    },
    [2] = {
        { name = "Enter Ghost Ship", stand = v(-6499, 91, -127), dest = v(923, 126, 32852) },
        { name = "Leave Ghost Ship", stand = v(920, 155, 32838), dest = v(-6509, 89, -133) },
    },
    [3] = {
        { name = "Castle to Mansion", stand = v(-5060.4116, 318.502, -3193.2249),
            dest = v(-12463.603, 378.32706, -7566.083), requires = "Valkyrie Helm" },
        { name = "Mansion to Castle", stand = v(-12463.603, 378.32706, -7566.083),
            dest = v(-5060.4116, 318.502, -3193.2249), requires = "Valkyrie Helm" },
        { name = "Castle to Hydra", stand = v(-5027.0303, 318.502, -3206.7036),
            dest = v(5650.9478, 1017.2748, -350.37918), requires = "Valkyrie Helm" },
        { name = "Hydra to Castle", stand = v(5650.9478, 1017.2748, -350.37918),
            dest = v(-5027.0303, 318.502, -3206.7036), requires = "Valkyrie Helm" },
        { name = "Castle to Tiki", stand = v(-5097.132, 318.502, -3178.3984), dest = v(-16814, 58, 304),
            touch = { map = "Boat Castle", part = "MapTeleportC" }, requires = "Feathered Visage" },
        { name = "Tiki to Castle", stand = v(-16799.092, 84.3228, 291.07285), dest = v(-5084.727, 318.502, -3155.858),
            touch = { map = "TikiOutpost", part = "MapTeleportC" }, requires = "Feathered Visage" },
    },
}

local owned = {}   -- [item name] = { has, at }

-- The doors of the current sea.
function Pads.here()
    return Pads.LIST[Player.sea() or 0] or {}
end

function Pads.named(name)
    for _, pad in ipairs(Pads.here()) do
        if pad.name == name then return pad end
    end
    return nil
end

-- Whether the inventory holds `item` (the game's item list, through the
-- Stack's inventory reader; a worn accessory counts too).
function Pads.has(item)
    local cached = owned[item]
    if cached and os.clock() - cached.at < Pads.INVENTORY_CACHE then return cached.has end
    local has = false
    local character = Player.character()
    if character and character:FindFirstChild(item) then has = true end
    if not has then
        local ok, Common = pcall(require, "Features.Stack.Common")
        if ok and type(Common) == "table" and Common.item then
            local found, entry = pcall(Common.item, item)
            has = found and entry ~= nil
        end
    end
    owned[item] = { has = has, at = os.clock() }
    return has
end

local function touchPart(pad)
    local map = workspace:FindFirstChild("Map")
    local model = map and map:FindFirstChild(pad.touch.map)
    return model and model:FindFirstChild(pad.touch.part)
end

-- Why `pad` cannot be used now, or nil. (Pauses are the Router's.)
function Pads.blocked(pad)
    if pad.requires and not Pads.has(pad.requires) then return "needs " .. pad.requires end
    if pad.touch then
        local part = touchPart(pad)
        -- No part loaded yet: Vxeze lets it be tried.
        if part then
            local ok, tagged = pcall(function()
                return Services.get("CollectionService"):HasTag(part, Pads.TAG)
            end)
            if ok and not tagged then return "door not open" end
        end
    end
    return nil
end

-- One try: touch the door's hitbox, or ask the server to send us on.
function Pads.use(pad)
    if pad.touch then
        local part = touchPart(pad)
        local hitbox = part and part:FindFirstChild("Hitbox")
        local hrp = Player.hrp()
        if hitbox and hrp and firetouchinterest then
            pcall(firetouchinterest, hrp, hitbox, 0)
            task.wait(0.15)
            pcall(firetouchinterest, hrp, hitbox, 1)
        end
        return nil
    end
    return Services.invoke("requestEntrance", pad.arg or pad.dest)
end

-- The cheapest way from `from` to `goal` through up to `depth` doors that
-- `allowed(pad)` accepts. Returns the cost in studs and the doors in order
-- (empty when flying straight is cheapest).
function Pads.route(from, goal, depth, allowed)
    local best, chain = (goal - from).Magnitude, {}
    if depth <= 0 then return best, chain end
    for _, pad in ipairs(Pads.here()) do
        if pad.dest and allowed(pad) then
            local rest, restChain = Pads.route(pad.dest, goal, depth - 1, allowed)
            local cost = (pad.stand - from).Magnitude + Pads.HOP + rest
            if cost < best then
                best, chain = cost, { pad }
                for _, next in ipairs(restChain) do chain[#chain + 1] = next end
            end
        end
    end
    return best, chain
end

-- Test hook.
function Pads.reset()
    owned = {}
end

return Pads
