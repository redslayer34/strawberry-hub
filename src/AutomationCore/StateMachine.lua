--=============================================================================
-- STATE MACHINE — machine a etats generique
--=============================================================================
--  Remplace la grande fonction `tick()` qui enchainait tout dans un seul flux
--  de `if`. Chaque etat declare son entree, son timeout, sa sortie et ses
--  transitions ; la machine ne fait qu'appliquer ces regles.
--
--  Interet concret : un etat qui n'aboutit pas ne peut plus bloquer le farm
--  indefiniment. Le timeout est structurel, pas ajoute au cas par cas.
--
--  Definition d'un etat :
--      {
--        enter    = function(ctx, from)         -- optionnel
--        update   = function(ctx) -> nextState  -- nil = rester ici
--        exit     = function(ctx, to)           -- optionnel
--        timeout  = 8,                          -- secondes, optionnel
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
    assert(type(stateName) == "string", "nom d'etat invalide")
    assert(type(def) == "table", "definition d'etat invalide")
    assert(type(def.update) == "function", stateName .. " : update() est obligatoire")
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

-- Etats traverses, du plus recent au plus ancien. RecoveryController s'en
-- sert pour savoir ou reprendre au lieu de tout recommencer.
function StateMachine:recent(count)
    local out = {}
    local n = math.min(count or HISTORY_LIMIT, #self.history)
    for i = 0, n - 1 do
        out[i + 1] = self.history[#self.history - i]
    end
    return out
end

-- Dernier etat traverse qui satisfait le predicat. Sert a reprendre le fil
-- apres une recuperation : on revient au dernier etat "utile", pas a IDLE.
function StateMachine:lastWhere(predicate)
    for i = #self.history, 1, -1 do
        local record = self.history[i]
        if predicate(record.state) then return record.state end
    end
    return nil
end

function StateMachine:goTo(stateName, reason)
    if not self.states[stateName] then
        Log.State("etat inconnu :", stateName, "-- passage en RECOVERY")
        stateName = self.states.RECOVERY and "RECOVERY" or self.current
        if not stateName then return end
    end

    local from = self.current
    if from == stateName then
        -- Reentrer dans le meme etat remet seulement le chrono a zero :
        -- sans cela, une boucle serree sur place declencherait le timeout.
        self.enteredAt = os.clock()
        return
    end

    if from then
        local def = self.states[from]
        if def and def.exit then
            local ok, err = pcall(def.exit, self.ctx, stateName)
            if not ok then Log.State("exit", from, "a echoue :", err) end
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
            Log.State("enter", stateName, "a echoue :", err)
            self.lastError = err
        end
    end
end

-- Un tour de machine. Ne bloque jamais : l'etat rend la main a chaque appel,
-- c'est l'appelant qui cadence.
function StateMachine:update()
    if not self.current then return end
    local def = self.states[self.current]
    if not def then
        self:goTo("RECOVERY", "definition d'etat manquante")
        return
    end

    -- Le timeout prime sur update() : un etat bloque ne doit pas pouvoir
    -- decider de rester en place indefiniment.
    if def.timeout and self:elapsed() > def.timeout then
        local target = def.onTimeout
        if type(target) == "function" then
            local ok, result = pcall(target, self.ctx)
            target = ok and result or "RECOVERY"
        end
        Log.State(self.current, "timeout apres",
            string.format("%.1f", self:elapsed()), "s")
        self:goTo(target or "RECOVERY", "timeout")
        return
    end

    local ok, result = pcall(def.update, self.ctx)
    if not ok then
        Log.State(self.current, "a leve une erreur :", result)
        self.lastError = result
        self:goTo("RECOVERY", "erreur dans update")
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
    self:goTo(stateName, reason or "reinitialisation")
end

return StateMachine
