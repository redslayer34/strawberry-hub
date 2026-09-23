--=============================================================================
-- HOOK — one __namecall hook shared by every feature that needs one
--=============================================================================
--  Installing a metamethod hook twice chains them and cannot be undone, so
--  the hub installs exactly one, lazily, the first time a feature asks.
--
--    observers   see every remote call (InvokeServer / FireServer), with
--                whether it came from the game's own scripts
--    rewriters   may replace the arguments of a call (AimHook)
--
--  With the hub unloaded, the hook becomes a pure pass-through.
--
--  Nothing inside the hook may call a method on an Instance: a namecall made
--  there replaces the pending namecall method, and the game's own
--  InvokeServer would then run as that method instead ("you cannot access
--  this portal yet"). Observers therefore run deferred, after the call, and
--  the method is restored before forwarding when the executor allows it.
--=============================================================================

local Hook = {
    installed = false,
    enabled = true,
}

local observers, rewriters = {}, {}

local REMOTE_METHODS = { InvokeServer = true, FireServer = true }

local function pack(...)
    return { n = select("#", ...), ... }
end

local function unpackAll(packed)
    return (table.unpack or unpack)(packed, 1, packed.n)
end

function Hook.observe(fn)
    observers[#observers + 1] = fn
end

function Hook.rewrite(fn)
    rewriters[#rewriters + 1] = fn
end

-- What the hook does for one call, minus the call itself: notify the
-- observers, then let each rewriter transform the arguments. Returns the
-- arguments to forward. Pure enough to be tested without an executor.
function Hook.dispatch(remote, method, fromGame, ...)
    if not Hook.enabled or not REMOTE_METHODS[method] then return ... end

    if #observers > 0 then
        local args, at = pack(...), os.clock()
        task.defer(function()
            for _, observer in ipairs(observers) do
                pcall(observer, remote, method, args, fromGame, at)
            end
        end)
    end

    if #rewriters == 0 then return ... end
    -- pack keeps the real argument count, nils included (FireServer(a, nil, b)).
    local packed = pack(...)
    for _, rewriter in ipairs(rewriters) do
        packed = pack(rewriter(remote, method, unpackAll(packed)))
    end
    return unpackAll(packed)
end

function Hook.install()
    if Hook.installed then return true end
    if not hookmetamethod or not getnamecallmethod then return false end

    local original
    local function handler(self, ...)
        if Hook.enabled then
            local method = getnamecallmethod()
            if REMOTE_METHODS[method] then
                local fromGame = not (checkcaller and checkcaller())
                local function forward(...)
                    if setnamecallmethod then setnamecallmethod(method) end
                    return original(self, ...)
                end
                return forward(Hook.dispatch(self, method, fromGame, ...))
            end
        end
        return original(self, ...)
    end
    local wrapped = newcclosure and newcclosure(handler) or handler

    local ok = pcall(function()
        original = hookmetamethod(game, "__namecall", wrapped)
    end)
    Hook.installed = ok and original ~= nil
    return Hook.installed
end

function Hook.disable()
    Hook.enabled = false
end

-- Test hook.
function Hook.reset()
    observers, rewriters = {}, {}
    Hook.enabled = true
end

return Hook
