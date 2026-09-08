--=============================================================================
-- SPECIAL FARM — one-off objectives and event quests
--=============================================================================
--  The base for objectives that do not follow the normal quest cycle: event
--  quests, time-limited hunts, scripted sequences. CDKController is this
--  interface's first client.
--
--  An objective exposes four things and nothing else:
--
--      :requirements() -> ok, reason     -- verifiable preconditions
--      :step()         -> status         -- one step, non-blocking
--      :describe()     -> text           -- for the journal
--      :stop()                           -- clean release
--
--  :step() returns "running", "done" or "failed". The core knows only those
--  three values, which is what lets an arbitrary objective be plugged in
--  without touching the state machine.
--=============================================================================

local Log = require("AutomationCore.Log")

local SpecialFarm = {}
SpecialFarm.__index = SpecialFarm

function SpecialFarm.new(ctx)
    return setmetatable({
        ctx = ctx,
        objective = nil,
        name = nil,
        startedAt = 0,
        checked = false,
    }, SpecialFarm)
end

-- The objective must satisfy the interface described above. We check that on
-- registration rather than discover a missing field mid-farm.
function SpecialFarm:setObjective(name, objective)
    if objective ~= nil then
        assert(type(objective.step) == "function",
            "special objective: step() is required")
    end
    self.objective = objective
    self.name = name
    self.startedAt = os.clock()
    self.checked = false

    if objective then
        Log.write("Core", "special objective armed:", tostring(name))
    end
    return true
end

function SpecialFarm:active() return self.objective ~= nil end

-- Returns "running" | "done" | "failed" | "idle".
function SpecialFarm:step()
    local objective = self.objective
    if not objective then return "idle" end

    -- Preconditions are checked once, on the first run: revalidating on every
    -- step would cost a lot for nothing.
    if not self.checked then
        self.checked = true
        if objective.requirements then
            local ok, reason = objective:requirements()
            if not ok then
                Log.write("Core", "objective", tostring(self.name),
                    "abandoned:", tostring(reason))
                self.objective = nil
                return "failed"
            end
        end
    end

    local ok, status = pcall(function() return objective:step() end)
    if not ok then
        Log.write("Core", "objective", tostring(self.name), "raised:", status)
        self:stop()
        return "failed"
    end

    if status == "done" or status == "failed" then
        Log.write("Core", "objective", tostring(self.name), "finished:", status)
        self.objective = nil
        return status
    end

    return "running"
end

function SpecialFarm:stop()
    if self.objective and self.objective.stop then
        pcall(function() self.objective:stop() end)
    end
    self.objective = nil
    self.name = nil
end

function SpecialFarm:describe()
    if not self.objective then return "no special objective" end
    if self.objective.describe then
        local ok, text = pcall(function() return self.objective:describe() end)
        if ok and text then return text end
    end
    return tostring(self.name)
end

return SpecialFarm
