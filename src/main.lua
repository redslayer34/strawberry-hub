--=============================================================================
-- MAIN — bundle entry point
--=============================================================================
--  Deliberate order: the engine loads first, the AutomationCore attaches to
--  it, then the interface is built on top of both. Each step is guarded, and
--  a failure at one step leaves the previous ones working:
--
--      engine only        -> the hub is inert but loaded
--      engine + core      -> farming works, no window
--      engine + core + UI -> everything
--=============================================================================

local hub = require("Runtime.Legacy")

-- The runtime returns its table even when initialisation partly failed.
-- Without its internals there is nothing to drive.
if type(hub) ~= "table" or type(hub.Internal) ~= "table" then
    warn("[Strawberry Hub] runtime unavailable -- nothing attached")
    return hub
end

local function guard(label, fn)
    local ok, result = xpcall(fn, function(err)
        return tostring(err) .. "\n" .. debug.traceback("", 2)
    end)
    if not ok then
        warn("[Strawberry Hub] " .. label .. " failed: " .. tostring(result))
        return nil
    end
    return result
end

---------------------------------------------------------------------------
-- Automation core
---------------------------------------------------------------------------

local core = guard("AutomationCore", function()
    local AutomationCore = require("AutomationCore")
    return AutomationCore.new(hub.Internal)
end)

if core then
    hub.AutomationCore = core
    hub.Log = require("AutomationCore.Log")

    -- This is what replaces the body of Farming.tick. The
    -- Config.Farming.UseAutomationCore flag, exposed in the interface, falls
    -- back to the legacy loop without reloading the script.
    hub.FarmDriver = function() core:update() end
else
    warn("[Strawberry Hub] farming falls back to the legacy loop.")
end

---------------------------------------------------------------------------
-- Interface
---------------------------------------------------------------------------

local UI = guard("UI library", function() return require("UI") end)

local window = UI and guard("interface", function()
    local Interface = require("Runtime.Interface")
    return Interface.build(hub.Internal, hub)
end)

if window then
    hub.Window = window
    hub.UI = UI
elseif UI then
    -- The window failed to build but the library loaded: a notification is
    -- still the clearest way to say so in game.
    pcall(function()
        UI:Notify({
            Title = "Strawberry Hub",
            Content = "Interface failed to build -- check the console",
            Duration = 10,
        })
    end)
end

---------------------------------------------------------------------------
-- Teardown
---------------------------------------------------------------------------

-- Unloading must release the anchor, the bring driver and every UI instance:
-- otherwise the runtime keeps calling a driver whose context is gone, and the
-- window survives the hub that owned it.
local previousUnload = hub.Unload
hub.Unload = function()
    if core then pcall(function() core:stop() end) end
    if UI then pcall(function() UI:Destroy() end) end
    hub.FarmDriver = nil
    hub.Window = nil
    return previousUnload()
end

return hub
