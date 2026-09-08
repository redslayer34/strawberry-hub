--=============================================================================
-- STATE MACHINE — generic finite state machine
--=============================================================================
--  Replaces the one big `tick()` that chained everything through a single run
--  of `if`s. Each state declares its entry, timeout, exit and transitions; the
--  machine only applies those rules.
--
--  The concrete benefit: a state that does not complete can no longer block
--  the farm indefinitely. The timeout is structural, not bolted on case by
--  case.
--
--  A state definition:
--      {
--        enter    = function(ctx, from)         -- optional
--        update   = function(ctx) -> nextState  -- nil = stay here
--        exit     = function(ctx, to)           -- optional
--        timeout  = 8,                          -- seconds, optional
--        onTimeout= "RECOVERY" | function(ctx) -> nextState
--      }
--=============================================================================

local Log = require("AutomationCore.Log")

local StateMachine = {}
StateMachine.__index = StateMachine

local HISTORY_LIMIT = 24

function StateMachine.new(name, ctx)
    return setmetatable({
        name = name,
        ctx = ctx,
        states = {},
        current = nil,
        enteredAt = 0,
        history = {},
        transitions = 0,
        lastError = nil,
    }, StateMachine)
end

function StateMachine:define(stateName, def)
    assert(type(stateName) == "string", "invalid state name")
    assert(type(def) == "table", "invalid state definition")
    assert(type(def.update) == "function", stateName .. ": update() is required")
    self.states[stateName] = def
    return self
end

function StateMachine:defineAll(map)
    for stateName, def in pairs(map) do self:define(stateName, def) end
    return self
end

function StateMachine:elapsed()
    return os.clock() - self.enteredAt
end

function StateMachine:is(stateName) return self.current == stateName end

-- States passed through, most recent first. RecoveryController uses this to
-- work out where to resume instead of starting over.
function StateMachine:recent(count)
    local out = {}
    local n = math.min(count or HISTORY_LIMIT, #self.history)
    for i = 0, n - 1 do
        out[i + 1] = self.history[#self.history - i]
    end
    return out
end

-- Most recent visited state satisfying the predicate. Used to pick the thread
-- back up after a recovery: we return to the last *useful* state, not to IDLE.
function StateMachine:lastWhere(predicate)
    for i = #self.history, 1, -1 do
        local record = self.history[i]
        if predicate(record.state) then return record.state end
    end
    return nil
end

function StateMachine:goTo(stateName, reason)
    if not self.states[stateName] then
        Log.State("unknown state:", stateName, "-- falling back to RECOVERY")
        stateName = self.states.RECOVERY and "RECOVERY" or self.current
        if not stateName then return end
    end

    local from = self.current
    if from == stateName then
        -- Re-entering the same state only resets the clock: without this, a
        -- tight loop in place would trip its own timeout.
        self.enteredAt = os.clock()
        return
    end

    if from then
        local def = self.states[from]
        if def and def.exit then
            local ok, err = pcall(def.exit, self.ctx, stateName)
            if not ok then Log.State("exit", from, "failed:", err) end
        end
    end

    self.current = stateName
    self.enteredAt = os.clock()
    self.transitions = self.transitions + 1
    self.history[#self.history + 1] = { state = stateName, clock = self.enteredAt, from = from }
    if #self.history > HISTORY_LIMIT then table.remove(self.history, 1) end

    Log.State(tostring(from or "-"), "->", stateName,
        reason and ("(" .. reason .. ")") or "")

    local def = self.states[stateName]
    if def.enter then
        local ok, err = pcall(def.enter, self.ctx, from)
        if not ok then
            Log.State("enter", stateName, "failed:", err)
            self.lastError = err
        end
    end
end

-- One turn of the machine. Never blocks: a state hands control back on every
-- call, and the caller sets the pace.
function StateMachine:update()
    if not self.current then return end
    local def = self.states[self.current]
    if not def then
        self:goTo("RECOVERY", "missing state definition")
        return
    end

    -- The timeout wins over update(): a stuck state must not be able to decide
    -- to stay put forever.
    if def.timeout and self:elapsed() > def.timeout then
        local target = def.onTimeout
        if type(target) == "function" then
            local ok, result = pcall(target, self.ctx)
            target = ok and result or "RECOVERY"
        end
        Log.State(self.current, "timed out after",
            string.format("%.1f", self:elapsed()), "s")
        self:goTo(target or "RECOVERY", "timeout")
        return
    end

    local ok, result = pcall(def.update, self.ctx)
    if not ok then
        Log.State(self.current, "raised:", result)
        self.lastError = result
        self:goTo("RECOVERY", "error in update")
        return
    end

    if result and result ~= self.current then
        self:goTo(result)
    end
end

function StateMachine:reset(stateName, reason)
    self.current = nil
    self.lastError = nil
    table.clear(self.history)
    self:goTo(stateName, reason or "reset")
end

return StateMachine
