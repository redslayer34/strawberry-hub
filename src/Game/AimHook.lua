--=============================================================================
-- AIM HOOK — points skills at the farmed mob instead of the mouse
--=============================================================================
--  A skill sends where it is aimed as the single argument of its tool's
--  RemoteEvent:FireServer (a Vector3 or a CFrame). While AimHook.target is
--  set, that argument is swapped for the target -- the same redirect the
--  reference uses. With no target (or after Unload) every call passes
--  through untouched.
--
--  Needs the executor's hookmetamethod; without it skills simply aim where
--  the camera looks.
--=============================================================================

local AimHook = {
    target = nil,     -- CFrame to aim at, or nil
    enabled = true,
    installed = false,
}

-- The arguments to forward for one call. Pure, so it can be tested.
function AimHook.rewrite(remote, method, ...)
    local target = AimHook.target
    if not target or not AimHook.enabled or method ~= "FireServer" then return ... end
    if select("#", ...) ~= 1 then return ... end
    local ok, name = pcall(function() return remote.Name end)
    if not ok or name ~= "RemoteEvent" then return ... end

    local arg = ...
    local kind = typeof(arg)
    if kind == "Vector3" then return target.Position end
    if kind == "CFrame" then return target end
    return ...
end

function AimHook.install()
    if AimHook.installed then return true end
    if not hookmetamethod or not getnamecallmethod then return false end

    local original
    local function handler(self, ...)
        if AimHook.target and AimHook.enabled then
            return original(self, AimHook.rewrite(self, getnamecallmethod(), ...))
        end
        return original(self, ...)
    end
    local wrapped = newcclosure and newcclosure(handler) or handler

    local ok = pcall(function()
        original = hookmetamethod(game, "__namecall", wrapped)
    end)
    AimHook.installed = ok and original ~= nil
    return AimHook.installed
end

-- A metamethod hook cannot be removed safely, so Unload turns it into a
-- pure pass-through instead.
function AimHook.disable()
    AimHook.enabled = false
    AimHook.target = nil
end

return AimHook
