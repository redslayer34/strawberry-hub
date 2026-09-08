--=============================================================================
-- CDK CONTROLLER — Cursed Dual Katana, fully independent of QuestFarm
--=============================================================================
--  No dependency on QuestFarm, and none the other way: both plug into the same
--  AutomationCore through the special-objective interface (requirements /
--  step / describe / stop). Switching one off does not affect the other.
--
--  Guiding principle, the same as everywhere else: we do NOT assume the puzzle
--  is where we left it. On every step we DETECT the trial that is actually
--  active. A hardcoded trial order (Trial1, Trial2, ...) breaks the moment the
--  game reorganises the puzzle, and above all it makes resuming mid-way
--  impossible -- the normal case when joining a server where someone has
--  already made progress.
--
--  ------------------------------------------------------------------------
--  TO VERIFY IN GAME: the SIGNALS table below describes HOW to recognise each
--  trial, not where it is. The candidate instance names are the publicly
--  observed ones; they need confirming with a live server. This is
--  deliberately a DATA table: fixing a name means touching no algorithm.
--  ------------------------------------------------------------------------
--=============================================================================

local Log = require("AutomationCore.Log")
local Names = require("AutomationCore.Names")
local StateMachine = require("AutomationCore.StateMachine")
local TravelController = require("AutomationCore.Movement.TravelController")

local CDKController = {}
CDKController.__index = CDKController

---------------------------------------------------------------------------
-- Requirements
---------------------------------------------------------------------------

-- Weapon mastery. The game stores this value under different names depending
-- on the tool, so we try the known variants rather than mandating one.
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
-- Detecting the active trial
---------------------------------------------------------------------------

-- Each signal describes a way of recognising a step. `match` takes the context
-- and returns true when that step is active. Adding a trial means one more
-- entry, without touching the machine.
local SIGNALS = {
    {
        id = "scroll",
        label = "scroll pickup",
        containers = { "Scroll", "CursedScroll", "Katana Scroll" },
    },
    {
        id = "trial_sword",
        label = "sword trial",
        containers = { "SwordTrial", "Trial1", "TrialSword" },
    },
    {
        id = "trial_fruit",
        label = "fruit trial",
        containers = { "FruitTrial", "Trial2", "TrialFruit" },
    },
    {
        id = "trial_gun",
        label = "gun trial",
        containers = { "GunTrial", "Trial3", "TrialGun" },
    },
    {
        id = "final_boss",
        label = "final boss",
        containers = { "CursedCaptain", "Final Boss", "Boss" },
    },
}

-- Looks anywhere under the Workspace for a container carrying one of the
-- candidate names AND currently visible/active. Visibility is the real signal:
-- a trial folder often exists permanently, only its state changes.
local function containerActive(node)
    if not node or not node.Parent then return false end

    local enabled = node:GetAttribute("Active")
    if enabled ~= nil then return enabled == true end

    -- A trial in progress exposes at least one interactive or visible element.
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
-- Controller
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

-- Special-objective interface: verifiable preconditions BEFORE anything is
-- started. Failing here costs one journal line; failing mid-puzzle costs the
-- attempt.
function CDKController:requirements()
    local ctx = self.ctx
    local cfg = ctx.cfg.CDK

    local level = ctx.player.level()
    if level < cfg.MinLevel then
        return false, string.format("level %d < %d required", level, cfg.MinLevel)
    end

    local yama = findTool(ctx, "Yama")
    if not yama then return false, "Yama not obtained" end

    local tushita = findTool(ctx, "Tushita")
    if not tushita then return false, "Tushita not obtained" end

    local yamaMastery = masteryOf(yama)
    if yamaMastery and yamaMastery < cfg.MinYamaMastery then
        return false, string.format("Yama mastery %d < %d",
            yamaMastery, cfg.MinYamaMastery)
    end

    local tushitaMastery = masteryOf(tushita)
    if tushitaMastery and tushitaMastery < cfg.MinTushitaMastery then
        return false, string.format("Tushita mastery %d < %d",
            tushitaMastery, cfg.MinTushitaMastery)
    end

    -- Unreadable mastery: do not block on a failed read, warn instead. The
    -- game will refuse by itself if the requirement is not met.
    if not yamaMastery or not tushitaMastery then
        Log.CDK("mastery unreadable on at least one blade -- leaving the check to the game")
    end

    Log.CDK("requirements satisfied (level " .. level .. ")")
    return true
end

-- Works out which trial is REALLY active, without relying on the expected
-- order.
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
                Log.CDK("crypt located")
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

                -- On site: opening happens through the game's own prompt.
                for _, node in ipairs(crypt:GetDescendants()) do
                    if node:IsA("ProximityPrompt") and node.Enabled then
                        pcall(function() fireproximityprompt(node) end)
                    end
                end
                return "DETECT_CURRENT_SCROLL"
            end,
        },

        -- Both detection states share the same read: the puzzle's real state
        -- decides, not our assumed progress.
        DETECT_CURRENT_SCROLL = {
            timeout = 20,
            onTimeout = "DETECT_CURRENT_TRIAL",
            update = function()
                local trial = self:detectActiveTrial()
                if not trial then return nil end
                self.activeTrial = trial
                if trial.id == "scroll" then
                    Log.CDK("scroll active")
                    return "EXECUTE_TRIAL"
                end
                -- The scroll is already taken: move on to the trial.
                return "DETECT_CURRENT_TRIAL"
            end,
        },

        DETECT_CURRENT_TRIAL = {
            timeout = 30,
            onTimeout = function()
                self.failure = "no trial detected"
                return "FAILED"
            end,
            update = function()
                local trial = self:detectActiveTrial()
                if not trial then return nil end

                self.activeTrial = trial
                if trial.id == "final_boss" then return "FINAL_BOSS" end

                Log.CDK("active trial:", trial.label)
                return "EXECUTE_TRIAL"
            end,
        },

        EXECUTE_TRIAL = {
            timeout = ctx.cfg.CDK.TrialTimeout,
            onTimeout = function()
                Log.CDK("trial not finished within the allotted time")
                return "DETECT_CURRENT_TRIAL"
            end,
            update = function()
                local trial = self.activeTrial
                if not trial or not trial.container.Parent then
                    return "DETECT_CURRENT_TRIAL"
                end

                -- The trial closed itself: that is the most reliable success
                -- signal available client-side.
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

                -- Verified by observation, not assumption: reconfirm the trial
                -- is no longer active.
                if containerActive(trial.container) then
                    return "EXECUTE_TRIAL"
                end

                self.completed[trial.id] = true
                Log.CDK("trial confirmed:", trial.label)
                return "NEXT_TRIAL"
            end,
        },

        NEXT_TRIAL = {
            timeout = 20,
            onTimeout = "DETECT_CURRENT_TRIAL",
            update = function()
                local trial = self:detectActiveTrial()
                if not trial then
                    -- Nothing active: either everything is done, or the puzzle
                    -- takes a moment to expose the next step.
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
                Log.CDK("trials complete")
                return "FINAL_BOSS"
            end,
        },

        -- The final boss is handed to BossFarm, which already knows how to
        -- confirm a kill and handle a respawn. No reason to reimplement it.
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
                    -- The boss is down (AWAIT_RESPAWN follows CONFIRM_KILL).
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
                    Log.CDK("reward obtained")
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

    self.machine:goTo("CDK_START", "CDK startup")
end

-- Special-objective interface: "running" | "done" | "failed".
function CDKController:step()
    if self.finished then
        return self.machine:is("DONE") and "done" or "failed"
    end

    self.perception:update(false)
    self.machine:update()

    if self.machine:is("DONE") then return "done" end
    if self.machine:is("FAILED") then
        if self.failure then Log.CDK("failed:", self.failure) end
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
