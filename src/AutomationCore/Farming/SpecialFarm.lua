--=============================================================================
-- SPECIAL FARM — objectifs ponctuels et quetes d'evenement
--=============================================================================
--  Sert de socle aux objectifs qui ne suivent pas le cycle de quete normal :
--  quetes d'evenement, chasses limitees dans le temps, etapes scenarisees.
--  CDKController est le premier client de cette interface.
--
--  Un objectif expose quatre choses et rien d'autre :
--
--      :requirements() -> ok, motif      -- pre-conditions verifiables
--      :step()         -> statut         -- un pas, non bloquant
--      :describe()     -> texte          -- pour le journal
--      :stop()                           -- liberation propre
--
--  Le statut rendu par :step() vaut "running", "done" ou "failed". Le core
--  ne connait que ces trois valeurs, ce qui permet de brancher un objectif
--  arbitraire sans toucher a la machine a etats.
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

-- L'objectif doit satisfaire l'interface decrite plus haut. On le verifie a
-- l'inscription plutot que de decouvrir un champ manquant en plein farm.
function SpecialFarm:setObjective(name, objective)
    if objective ~= nil then
        assert(type(objective.step) == "function",
            "objectif special : step() est obligatoire")
    end
    self.objective = objective
    self.name = name
    self.startedAt = os.clock()
    self.checked = false

    if objective then
        Log.write("Core", "objectif special arme :", tostring(name))
    end
    return true
end

function SpecialFarm:active() return self.objective ~= nil end

-- Renvoie "running" | "done" | "failed" | "idle".
function SpecialFarm:step()
    local objective = self.objective
    if not objective then return "idle" end

    -- Les pre-conditions sont verifiees une fois, a la premiere execution :
    -- les revalider a chaque pas couterait cher pour rien.
    if not self.checked then
        self.checked = true
        if objective.requirements then
            local ok, reason = objective:requirements()
            if not ok then
                Log.write("Core", "objectif", tostring(self.name),
                    "abandonne :", tostring(reason))
                self.objective = nil
                return "failed"
            end
        end
    end

    local ok, status = pcall(function() return objective:step() end)
    if not ok then
        Log.write("Core", "objectif", tostring(self.name), "a leve :", status)
        self:stop()
        return "failed"
    end

    if status == "done" or status == "failed" then
        Log.write("Core", "objectif", tostring(self.name), "termine :", status)
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
    if not self.objective then return "aucun objectif special" end
    if self.objective.describe then
        local ok, text = pcall(function() return self.objective:describe() end)
        if ok and text then return text end
    end
    return tostring(self.name)
end

return SpecialFarm
