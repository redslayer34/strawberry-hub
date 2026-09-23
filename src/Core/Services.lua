--=============================================================================
-- SERVICES — game services, remotes and game modules, resolved lazily
--=============================================================================
--  Everything the hub needs from the game goes through here, for two reasons:
--  nothing is looked up before the game has replicated it, and a missing
--  remote degrades one feature instead of crashing the whole script.
--
--  The game facts below (remote names, module paths, argument shapes) were
--  taken from a working reference script, not guessed.
--=============================================================================

local Services = {}

local services = {}

function Services.get(name)
    local service = services[name]
    if not service then
        service = game:GetService(name)
        services[name] = service
    end
    return service
end

function Services.player()
    return Services.get("Players").LocalPlayer
end

function Services.replicated()
    return Services.get("ReplicatedStorage")
end

-- Walks a dotted path from `root` ("Modules.CombatUtil"). Returns nil as soon
-- as one link is missing, instead of erroring on a nil index.
function Services.find(root, path)
    local node = root
    for part in path:gmatch("[^%.]+") do
        if not node then return nil end
        node = node:FindFirstChild(part)
    end
    return node
end

---------------------------------------------------------------------------
-- Game modules
---------------------------------------------------------------------------

-- A module that exists but errors when required is remembered as broken, so
-- it is not re-required every frame. A module that does not exist YET is not
-- remembered: it may simply not have replicated.
local modules = {}

function Services.module(path)
    local cached = modules[path]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local node = Services.find(Services.replicated(), path)
    if not node then return nil end

    local ok, result = pcall(require, node)
    if ok and result ~= nil then
        modules[path] = result
        return result
    end
    modules[path] = false
    warn("[Strawberry Hub] could not load " .. path .. ": " .. tostring(result))
    return nil
end

---------------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------------

-- Remotes.CommF_ : the RemoteFunction almost every game action goes through
-- (StartQuest, travel, shop, stats...).
function Services.commF()
    return Services.find(Services.replicated(), "Remotes.CommF_")
end

-- Invokes CommF_ and returns its result, or nil when the remote is missing or
-- the call errors. Never throws: a failed purchase must not kill a loop.
function Services.invoke(...)
    local remote = Services.commF()
    if not remote then return nil end
    local ok, result = pcall(remote.InvokeServer, remote, ...)
    if ok then return result end
    return nil
end

local remotes = {}

local function netChild(name)
    local net = Services.find(Services.replicated(), "Modules.Net")
    return net and net:FindFirstChild("RE/" .. name)
end

local function netModuleEvent(name)
    local netModule = Services.module("Modules.Net")
    if type(netModule) ~= "table" or not netModule.RemoteEvent then return nil end
    local ok, result = pcall(netModule.RemoteEvent, netModule, name, true)
    if ok then return result end
    return nil
end

-- ReplicatedStorage.Modules.Net holds the combat remotes. The reference
-- reaches RE/RegisterAttack as a plain child, but RegisterHit through the Net
-- module's own accessor, Net:RemoteEvent(name, true). The same split is kept
-- here: `viaModule` picks the accessor first, the child being the fallback.
function Services.netRemote(name, viaModule)
    local cached = remotes[name]
    if cached and cached.Parent then return cached end

    local remote
    if viaModule then
        remote = netModuleEvent(name) or netChild(name)
    else
        remote = netChild(name) or netModuleEvent(name)
    end

    remotes[name] = remote
    return remote
end

-- Where the hub's own screen GUIs go: the executor's hidden container when
-- it has one (the game cannot see it), CoreGui otherwise.
function Services.guiParent()
    if gethui then
        local ok, parent = pcall(gethui)
        if ok and parent then return parent end
    end
    return Services.get("CoreGui")
end

-- Test hook: forget every cached lookup.
function Services.reset()
    services, modules, remotes = {}, {}, {}
end

return Services
