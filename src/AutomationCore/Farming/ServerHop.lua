--=============================================================================
-- SERVER HOP — change server, but not in a loop
--=============================================================================
--  A server change is the most expensive tool in the system: a minute of
--  loading, the whole map memory thrown away, detection to redo. It is only
--  justified when the problem really is the server -- a missing boss, an empty
--  zone on this shard.
--
--  The classic trap is the loop: you hop, the new place shows the same
--  symptom, you hop again. This module prevents it with a minimum delay
--  between hops and a cap over a sliding window.
--=============================================================================

local Log = require("AutomationCore.Log")

local ServerHop = {}
ServerHop.__index = ServerHop

local MIN_INTERVAL = 45      -- s between two hops
local WINDOW = 600           -- observation window (s)
local MAX_IN_WINDOW = 5      -- hops allowed within the window

function ServerHop.new(ctx)
    return setmetatable({
        ctx = ctx,
        lastHop = 0,
        history = {},
        blockedUntil = 0,
    }, ServerHop)
end

local function prune(self, now)
    for i = #self.history, 1, -1 do
        if now - self.history[i] > WINDOW then table.remove(self.history, i) end
    end
end

-- True when a hop is allowed right now, otherwise false plus a reason.
function ServerHop:allowed()
    local now = os.clock()

    if now < self.blockedUntil then
        return false, "cooling down after saturation"
    end
    if now - self.lastHop < MIN_INTERVAL then
        return false, string.format("last hop %.0f s ago", now - self.lastHop)
    end

    prune(self, now)
    if #self.history >= MAX_IN_WINDOW then
        -- Too many hops close together: the problem is probably not the
        -- server. Block ourselves and let the situation move on.
        self.blockedUntil = now + WINDOW / 2
        return false, "too many recent hops"
    end

    return true
end

-- lowestOnly : aim for the least populated servers (steadier spawns).
function ServerHop:hop(reason, lowestOnly)
    local ok, why = self:allowed()
    if not ok then
        Log.ServerHop("refused --", why)
        return false
    end

    local now = os.clock()
    self.lastHop = now
    self.history[#self.history + 1] = now

    Log.ServerHop("hopping --", reason or "unspecified")

    -- Everything learned here will be wrong elsewhere.
    self.ctx.map:clear("server change")
    self.ctx.region = nil
    self.ctx.questGiver = nil

    local sent = pcall(function()
        self.ctx.server.hop(lowestOnly ~= false)
    end)
    if not sent then Log.ServerHop("the runtime refused the hop") end
    return sent
end

function ServerHop:describe()
    return string.format("%d hop(s) in the window", #self.history)
end

return ServerHop
