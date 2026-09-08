--=============================================================================
-- CDK CONTROLLER — Cursed Dual Katana, totalement independant du QuestFarm
--=============================================================================
--  Aucune dependance vers QuestFarm, et reciproquement : les deux se
--  branchent sur le meme AutomationCore par l'interface d'objectif special
--  (requirements / step / describe / stop). Couper l'un n'affecte pas l'autre.
--
--  Principe directeur, identique au reste : on ne suppose PAS que le puzzle
--  se trouve a l'etape ou on l'a laisse. A chaque pas, on DETECTE l'epreuve
--  reellement active. Un ordre d'epreuves code en dur (Trial1, Trial2, ...)
--  casse des que le jeu reorganise le puzzle, et surtout il rend impossible
--  la reprise en cours de route — cas normal quand on rejoint un serveur ou
--  quelqu'un a deja avance.
--
--  ------------------------------------------------------------------------
--  A VERIFIER EN JEU : la table SIGNALS ci-dessous decrit COMMENT reconnaitre
--  chaque epreuve, pas ou elle se trouve. Les noms d'instances candidats sont
--  ceux observes publiquement ; ils doivent etre confirmes serveur en main.
--  C'est volontairement une table de DONNEES : corriger un nom ne demande de
--  toucher a aucun algorithme.
--  ------------------------------------------------------------------------
--=============================================================================

local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")
local StateMachine = require("AutomationCore.StateMachine")
local TravelController = require("AutomationCore.Movement.TravelController")

local CDKController = {}
CDKController.__index = CDKController

---------------------------------------------------------------------------
-- Pre-requis
---------------------------------------------------------------------------

-- Maitrise d'une arme. Le jeu range cette valeur sous des noms differents
-- selon les outils : on essaie les variantes connues plutot que d'en imposer
-- une seule.
local MASTERY_FIELDS = { "Level", "Mastery", "MasteryLevel", "Exp" }

local function findTool(ctx, toolName)
    local wanted = Names.normalize(toolName)
    local player = ctx.player.instance
    if not player then return nil end

    local containers = {}
    local backpack = player:FindFirstChild("Backpack")
    if backpack then containers[#containers + 1] = backpack end
    local character = ctx.player.character()
    if character then containers[#containers + 1] = character end

    for _, container in ipairs(containers) do
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and Names.normalize(tool.Name) == wanted then
                return tool
            end
        end
    end
    return nil
end

local function masteryOf(tool)
    if not tool then return nil end
    for _, field in ipairs(MASTERY_FIELDS) do
        local value = tool:FindFirstChild(field)
        if value and typeof(value.Value) == "number" then return value.Value end
    end
    local attribute = tool:GetAttribute("Mastery")
    if typeof(attribute) == "number" then return attribute end
    return nil
end

---------------------------------------------------------------------------
-- Detection de l'epreuve active
---------------------------------------------------------------------------

-- Chaque signal decrit une facon de reconnaitre une etape. `match` recoit le
-- contexte et rend true quand l'etape est active. Ajouter une epreuve = une
-- entree de plus, sans toucher a la machine.
local SIGNALS = {
    {
        id = "scroll",
        label = "recuperation du parchemin",
        containers = { "Scroll", "CursedScroll", "Katana Scroll" },
    },
    {
        id = "trial_sword",
        label = "epreuve de l'epee",
        containers = { "SwordTrial", "Trial1", "TrialSword" },
    },
    {
        id = "trial_fruit",
        label = "epreuve du fruit",
        containers = { "FruitTrial", "Trial2", "TrialFruit" },
    },
    {
        id = "trial_gun",
        label = "epreuve de l'arme a feu",
        containers = { "GunTrial", "Trial3", "TrialGun" },
    },
    {
        id = "final_boss",
        label = "boss final",
        containers = { "CursedCaptain", "Final Boss", "Boss" },
    },
}

-- Cherche, n'importe ou sous le Workspace, un conteneur portant l'un des
-- noms candidats ET actuellement visible/actif. La visibilite est le vrai
-- signal : un dossier d'epreuve existe souvent en permanence, seul son etat
-- change.
local function containerActive(node)
    if not node or not node.Parent then return false end

    local enabled = node:GetAttribute("Active")
    if enabled ~= nil then return enabled == true end

    -- Une epreuve en cours expose au moins un element interactif ou visible.
    for _, child in ipairs(node:GetDescendants()) do
        if child:IsA("ProximityPrompt") and child.Enabled then return true end
        if child:IsA("BasePart") and child.Transparency < 1 and child.CanCollide then
            return true
        end
    end
    return false
end

local function findContainer(names)
    for _, name in ipairs(names) do
        local direct = workspace:FindFirstChild(name, true)
        if direct then return direct end
    end
    return nil
end

---------------------------------------------------------------------------
-- Controleur
---------------------------------------------------------------------------

function CDKController.new(ctx, perception, recovery)
    local self = setmetatable({
        ctx = ctx,
        perception = perception,
        recovery = recovery,
        crypt = nil,
        activeTrial = nil,
        completed = {},
        failure = nil,
        finished = false,
        machine = nil,
    }, CDKController)

    self.machine = StateMachine.new("CDK", ctx)
    self:defineStates()
    return self
end

-- Interface d'objectif special : pre-conditions verifiables AVANT de lancer
-- quoi que ce soit. Echouer ici coute une ligne de journal ; echouer en
-- cours de puzzle coute la tentative.
function CDKController:requirements()
    local ctx = self.ctx
    local cfg = ctx.cfg.CDK

    local level = ctx.player.level()
    if level < cfg.MinLevel then
        return false, string.format("niveau %d < %d requis", level, cfg.MinLevel)
    end

    local yama = findTool(ctx, "Yama")
    if not yama then return false, "Yama non obtenue" end

    local tushita = findTool(ctx, "Tushita")
    if not tushita then return false, "Tushita non obtenue" end

    local yamaMastery = masteryOf(yama)
    if yamaMastery and yamaMastery < cfg.MinYamaMastery then
        return false, string.format("maitrise Yama %d < %d",
            yamaMastery, cfg.MinYamaMastery)
    end

    local tushitaMastery = masteryOf(tushita)
    if tushitaMastery and tushitaMastery < cfg.MinTushitaMastery then
        return false, string.format("maitrise Tushita %d < %d",
            tushitaMastery, cfg.MinTushitaMastery)
    end

    -- Maitrise illisible : on ne bloque pas sur une lecture ratee, on
    -- previent. Le jeu refusera de lui-meme si le pre-requis n'est pas tenu.
    if not yamaMastery or not tushitaMastery then
        Log.CDK("maitrise illisible sur au moins une lame -- verification laissee au jeu")
    end

    Log.CDK("pre-requis satisfaits (niveau " .. level .. ")")
    return true
end

-- Determine l'epreuve REELLEMENT active, sans se fier a l'ordre attendu.
function CDKController:detectActiveTrial()
    for _, signal in ipairs(SIGNALS) do
        local container = findContainer(signal.containers)
        if container and containerActive(container) then
            return {
                id = signal.id,
                label = signal.label,
                container = container,
            }
        end
    end
    return nil
end

function CDKController:defineStates()
    local ctx = self.ctx

    self.machine:defineAll({

        CDK_START = {
            update = function() return "REQUIREMENTS" end,
        },

        REQUIREMENTS = {
            timeout = 10,
            onTimeout = "FAILED",
            update = function()
                local ok, reason = self:requirements()
                if not ok then
                    self.failure = reason
                    return "FAILED"
                end
                return "FIND_CRYPT"
            end,
        },

        FIND_CRYPT = {
            timeout = 30,
            onTimeout = "FAILED",
            update = function()
                local crypt = findContainer({ "Crypt", "CursedCrypt", "Katana Crypt" })
                if not crypt then return nil end
                self.crypt = crypt
                Log.CDK("crypte reperee")
                return "OPEN_CRYPT"
            end,
        },

        OPEN_CRYPT = {
            timeout = 60,
            onTimeout = "FAILED",
            exit = function() TravelController.reset(ctx) end,
            update = function()
                local crypt = self.crypt
                if not crypt or not crypt.Parent then
                    self.crypt = nil
                    return "FIND_CRYPT"
                end

                local ok, pivot = pcall(function() return crypt:GetPivot() end)
                local position = ok and pivot and pivot.Position or nil
                if not position then return "FIND_CRYPT" end

                if not TravelController.arrived(ctx, position, 20) then
                    TravelController.step(ctx, position, { lift = 6 })
                    return nil
                end

                -- Sur place : l'ouverture se fait par l'invite du jeu.
                for _, node in ipairs(crypt:GetDescendants()) do
                    if node:IsA("ProximityPrompt") and node.Enabled then
                        pcall(function() fireproximityprompt(node) end)
                    end
                end
                return "DETECT_CURRENT_SCROLL"
            end,
        },

        -- Les deux etats de detection partagent la meme lecture : c'est
        -- l'etat reel du puzzle qui decide, pas notre progression supposee.
        DETECT_CURRENT_SCROLL = {
            timeout = 20,
            onTimeout = "DETECT_CURRENT_TRIAL",
            update = function()
                local trial = self:detectActiveTrial()
                if not trial then return nil end
                self.activeTrial = trial
                if trial.id == "scroll" then
                    Log.CDK("parchemin actif")
                    return "EXECUTE_TRIAL"
                end
                -- Le parchemin est deja pris : on enchaine sur l'epreuve.
                return "DETECT_CURRENT_TRIAL"
            end,
        },

        DETECT_CURRENT_TRIAL = {
            timeout = 30,
            onTimeout = function()
                self.failure = "aucune epreuve detectee"
                return "FAILED"
            end,
            update = function()
                local trial = self:detectActiveTrial()
                if not trial then return nil end

                self.activeTrial = trial
                if trial.id == "final_boss" then return "FINAL_BOSS" end

                Log.CDK("epreuve active :", trial.label)
                return "EXECUTE_TRIAL"
            end,
        },

        EXECUTE_TRIAL = {
            timeout = ctx.cfg.CDK.TrialTimeout,
            onTimeout = function()
                Log.CDK("epreuve non terminee dans le temps imparti")
                return "DETECT_CURRENT_TRIAL"
            end,
            update = function()
                local trial = self.activeTrial
                if not trial or not trial.container.Parent then
                    return "DETECT_CURRENT_TRIAL"
                end

                -- L'epreuve s'est refermee : c'est le signal de reussite le
                -- plus fiable dont on dispose cote client.
                if not containerActive(trial.container) then
                    return "VERIFY_TRIAL"
                end

                local ok, pivot = pcall(function() return trial.container:GetPivot() end)
                if ok and pivot then
                    TravelController.step(ctx, pivot.Position, { lift = 8 })
                end

                for _, node in ipairs(trial.container:GetDescendants()) do
                    if node:IsA("ProximityPrompt") and node.Enabled then
                        pcall(function() fireproximityprompt(node) end)
                    end
                end
                return nil
            end,
        },

        VERIFY_TRIAL = {
            timeout = 15,
            onTimeout = "DETECT_CURRENT_TRIAL",
            update = function()
                local trial = self.activeTrial
                if not trial then return "DETECT_CURRENT_TRIAL" end

                -- Verification par observation, pas par supposition : on
                -- reconfirme que l'epreuve n'est plus active.
                if containerActive(trial.container) then
                    return "EXECUTE_TRIAL"
                end

                self.completed[trial.id] = true
                Log.CDK("epreuve validee :", trial.label)
                return "NEXT_TRIAL"
            end,
        },

        NEXT_TRIAL = {
            timeout = 20,
            onTimeout = "DETECT_CURRENT_TRIAL",
            update = function()
                local trial = self:detectActiveTrial()
                if not trial then
                    -- Plus rien d'actif : soit tout est fait, soit le puzzle
                    -- met un instant a exposer l'etape suivante.
                    if self.machine:elapsed() > 6 then return "ALL_TRIALS_COMPLETE" end
                    return nil
                end
                if trial.id == "final_boss" then return "FINAL_BOSS" end
                self.activeTrial = trial
                return "EXECUTE_TRIAL"
            end,
        },

        ALL_TRIALS_COMPLETE = {
            timeout = 20,
            onTimeout = "FINAL_BOSS",
            update = function()
                Log.CDK("epreuves terminees")
                return "FINAL_BOSS"
            end,
        },

        -- Le boss final est confie a BossFarm, qui sait deja confirmer une
        -- mort et gerer un respawn. Aucune raison de le reimplementer ici.
        FINAL_BOSS = {
            timeout = 600,
            onTimeout = "FAILED",
            enter = function()
                local boss = ctx.bossFarm
                if boss then boss:setBoss("Cursed Captain") end
            end,
            update = function()
                local boss = ctx.bossFarm
                if not boss then return "VERIFY_REWARD" end

                boss:update()
                if boss.machine:is("AWAIT_RESPAWN") or boss.machine:is("SERVER_HOP") then
                    -- Le boss est tombe (AWAIT_RESPAWN suit CONFIRM_KILL).
                    boss:stop()
                    return "VERIFY_REWARD"
                end
                return nil
            end,
        },

        VERIFY_REWARD = {
            timeout = 30,
            onTimeout = "FAILED",
            update = function()
                if findTool(ctx, "Cursed Dual Katana") then
                    Log.CDK("recompense obtenue")
                    return "DONE"
                end
                return nil
            end,
        },

        DONE = {
            update = function()
                self.finished = true
                return nil
            end,
        },

        FAILED = {
            update = function()
                self.finished = true
                return nil
            end,
        },
    })

    self.machine:goTo("CDK_START", "demarrage CDK")
end

-- Interface d'objectif special : "running" | "done" | "failed".
function CDKController:step()
    if self.finished then
        return self.machine:is("DONE") and "done" or "failed"
    end

    self.perception:update(false)
    self.machine:update()

    if self.machine:is("DONE") then return "done" end
    if self.machine:is("FAILED") then
        if self.failure then Log.CDK("echec :", self.failure) end
        return "failed"
    end
    return "running"
end

function CDKController:stop()
    TravelController.stop(self.ctx)
    if self.ctx.bossFarm then self.ctx.bossFarm:stop() end
    self.activeTrial = nil
end

function CDKController:describe()
    return string.format("[CDK %s] %s", tostring(self.machine.current),
        self.activeTrial and self.activeTrial.label or "-")
end

return CDKController
