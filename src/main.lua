--=============================================================================
-- MAIN — point d'entree du bundle
--=============================================================================
--  Ordre volontaire : le runtime historique se charge et construit son UI en
--  premier, l'AutomationCore se branche ensuite. Le core n'est qu'un pilote
--  de la boucle de farm ; si sa construction echoue, le hub reste utilisable
--  et retombe sur la boucle historique.
--=============================================================================

local hub = require("Runtime.Legacy")

-- Le runtime rend son objet meme quand la construction de l'UI a echoue. Sans
-- ses primitives internes, le core n'a rien a piloter.
if type(hub) ~= "table" or type(hub.Internal) ~= "table" then
    warn("[Strawberry Hub] runtime indisponible -- AutomationCore non branche")
    return hub
end

local ok, result = xpcall(function()
    local AutomationCore = require("AutomationCore")
    return AutomationCore.new(hub.Internal)
end, function(err)
    return tostring(err) .. "\n" .. debug.traceback("", 2)
end)

if not ok then
    warn("[Strawberry Hub] AutomationCore indisponible : " .. tostring(result))
    warn("[Strawberry Hub] le farm utilise la boucle historique.")
    return hub
end

local core = result
hub.AutomationCore = core
hub.Log = require("AutomationCore.Log")

-- C'est ce branchement qui remplace le corps de Farming.tick. Le drapeau
-- Config.Farming.UseAutomationCore, expose dans l'UI, permet de revenir a
-- l'ancienne boucle sans recharger le script.
hub.FarmDriver = function()
    core:update()
end

-- L'arret du hub doit relacher l'ancre et le pilote de bring : sans cela le
-- runtime continuerait d'appeler un pilote dont le contexte a disparu.
local previousUnload = hub.Unload
hub.Unload = function()
    pcall(function() core:stop() end)
    hub.FarmDriver = nil
    return previousUnload()
end

return hub
