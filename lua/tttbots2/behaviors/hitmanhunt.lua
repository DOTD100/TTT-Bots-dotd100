--- Hitman-specific behavior: Hunt and kill the assigned contract target.
--- Uses the TTT2 Hitman addon's GetTargetPlayer() to find who to kill.
--- The Hitman earns bonus credits and score for killing the correct target,
--- so this behavior takes priority over generic traitor stalking.

---@class BHitmanHunt
TTTBots.Behaviors.HitmanHunt = {}

local lib = TTTBots.Lib

---@class BHitmanHunt
local HitmanHunt = TTTBots.Behaviors.HitmanHunt
HitmanHunt.Name = "HitmanHunt"
HitmanHunt.Description = "Hunt the Hitman's assigned contract target."
HitmanHunt.Interruptible = true

HitmanHunt.STRIKE_RANGE = 150       --- Distance to start the attack
HitmanHunt.MAX_WITNESSES = 2        --- Max non-ally witnesses before we wait for a better opening
HitmanHunt.PATIENCE_TIME = 40       --- Seconds of stalking before we attack regardless of witnesses
HitmanHunt.GIVEUP_DIST = 3000       --- If path to target is insanely long, just wander and retry later

local STATUS = TTTBots.STATUS

--- Get the Hitman's current contract target via TTT2's API.
---@param bot Bot
---@return Player|nil
function HitmanHunt.GetContractTarget(bot)
    if not bot.GetTargetPlayer then return nil end
    local target = bot:GetTargetPlayer()
    if not (target and IsValid(target) and target:IsPlayer()) then return nil end
    if not lib.IsPlayerAlive(target) then return nil end
    return target
end

--- Validate: only runs for Hitman bots that have a living contract target.
---@param bot Bot
---@return boolean
function HitmanHunt.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not IsValid(bot) then return false end

    -- Don't override if we're already in active combat (FightBack handles that)
    if bot.attackTarget ~= nil then return false end

    local target = HitmanHunt.GetContractTarget(bot)
    return target ~= nil
end

---@param bot Bot
---@return BStatus
function HitmanHunt.OnStart(bot)
    bot.hitmanHuntStart = CurTime()
    return STATUS.RUNNING
end

--- Called every tick while behavior is running.
---@param bot Bot
---@return BStatus
function HitmanHunt.OnRunning(bot)
    local target = HitmanHunt.GetContractTarget(bot)
    if not target then return STATUS.FAILURE end

    local loco = bot:BotLocomotor()
    if not loco then return STATUS.FAILURE end

    local botPos = bot:GetPos()
    local targetPos = target:GetPos()
    local targetEyes = target:EyePos()
    local dist = botPos:Distance(targetPos)

    -- Always path toward the target
    loco:SetGoal(targetPos)

    -- Can we see the target?
    local canSee = bot:Visible(target)
    local isClose = canSee and dist <= HitmanHunt.STRIKE_RANGE

    if not canSee then
        -- Can't see them yet, use memory to track them down
        local memory = bot.components.memory
        if memory then
            local knownPos = memory:GetKnownPositionFor(target)
            if knownPos then
                loco:SetGoal(knownPos)
            end
        end
        return STATUS.RUNNING
    end

    -- We can see the target. Look at them.
    loco:LookAt(targetEyes)

    if not isClose then
        -- Visible but not close enough. Keep pursuing.
        return STATUS.RUNNING
    end

    -- We're close. Check if we should strike now or wait for a better moment.
    loco:SetGoal() -- Stop pathing, we're in position.

    local nonAllies = TTTBots.Roles.GetNonAllies(bot)
    local witnesses = lib.GetAllWitnessesBasic(botPos, nonAllies, bot)
    local witnessCount = table.Count(witnesses)
    local elapsed = CurTime() - (bot.hitmanHuntStart or CurTime())
    local outOfPatience = elapsed > HitmanHunt.PATIENCE_TIME

    -- Strike if few witnesses or we've been stalking long enough
    if witnessCount <= HitmanHunt.MAX_WITNESSES or outOfPatience then
        bot:SetAttackTarget(target)
        return STATUS.SUCCESS
    end

    -- Too many witnesses. Linger nearby and wait.
    return STATUS.RUNNING
end

---@param bot Bot
function HitmanHunt.OnSuccess(bot)
end

---@param bot Bot
function HitmanHunt.OnFailure(bot)
end

---@param bot Bot
function HitmanHunt.OnEnd(bot)
    bot.hitmanHuntStart = nil
    local loco = bot:BotLocomotor()
    if loco then
        loco:SetGoal()
    end
end
