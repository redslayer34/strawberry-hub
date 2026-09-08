--=============================================================================
-- SERVER HOP — changer de serveur, mais pas en boucle
--=============================================================================
--  Le changement de serveur est l'outil le plus couteux du systeme : une
--  minute de chargement, toute la memoire de carte jetee, la detection a
--  refaire. Il n'est justifie que lorsque le probleme vient reellement du
--  serveur — un boss absent, une zone vide sur ce shard.
--
--  Le piege classique est la boucle : on saute, la nouvelle destination
--  presente le meme symptome, on ressaute. Ce module l'empeche par un delai
--  minimal entre deux sauts et un plafond sur une fenetre glissante.
--=============================================================================

local Log = require("AutomationCore.Log")

local ServerHop = {}
ServerHop.__index = ServerHop

local MIN_INTERVAL = 45      -- s entre deux sauts
local WINDOW = 600           -- fenetre d'observation (s)
local MAX_IN_WINDOW = 5      -- sauts autorises dans la fenetre

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

-- Vrai si un saut est autorise maintenant, sinon false + motif.
function ServerHop:allowed()
    local now = os.clock()

    if now < self.blockedUntil then
        return false, "en attente apres saturation"
    end
    if now - self.lastHop < MIN_INTERVAL then
        return false, string.format("dernier saut il y a %.0f s", now - self.lastHop)
    end

    prune(self, now)
    if #self.history >= MAX_IN_WINDOW then
        -- Trop de sauts rapproches : le probleme n'est probablement pas le
        -- serveur. On se bloque le temps de laisser la situation evoluer.
        self.blockedUntil = now + WINDOW / 2
        return false, "trop de sauts recents"
    end

    return true
end

-- lowestOnly : viser les serveurs les moins peuples (spawns plus stables).
function ServerHop:hop(reason, lowestOnly)
    local ok, why = self:allowed()
    if not ok then
        Log.ServerHop("refuse --", why)
        return false
    end

    local now = os.clock()
    self.lastHop = now
    self.history[#self.history + 1] = now

    Log.ServerHop("saut --", reason or "non precise")

    -- Tout ce qui a ete appris ici sera faux ailleurs.
    self.ctx.map:clear("changement de serveur")
    self.ctx.region = nil
    self.ctx.questGiver = nil

    local sent = pcall(function()
        self.ctx.server.hop(lowestOnly ~= false)
    end)
    if not sent then Log.ServerHop("le runtime a refuse le saut") end
    return sent
end

function ServerHop:describe()
    return string.format("%d saut(s) sur la fenetre", #self.history)
end

return ServerHop
