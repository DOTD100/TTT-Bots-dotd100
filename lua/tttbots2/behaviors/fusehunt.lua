--- Fuse-specific behavior: urgently hunt and kill targets before the fuse timer expires.
--- The Fuse is a traitor subrole that must get a kill every ~60 seconds
--- or self-destructs in an explosion. The bot should always be aggressively
--- seeking kills, getting more desperate as the timer runs low.

---@class BFuseHunt
TTTBots.Behaviors.FuseHunt = {}

local lib = TTTBots.Lib

---@class BFuseHunt
local FuseHunt = TTTBots.Behaviors.FuseHunt
FuseHunt.Name = "FuseHunt"
FuseHunt.Description = "Urgently hunt targets before the fuse timer expires."
FuseHunt.Interruptible = true

FuseHunt.FUSE_DURATION = 60          --- Seconds between required kills (matches default cvar)
FuseHunt.DESPERATE_THRESHOLD = 20    --- Below this many seconds, pick closest target regardless
FuseHunt.CRITICAL_THRESHOLD = 10     --- Below this, sprint straight at anyone visible
FuseHunt.RETARGET_INTERVAL = 4       --- How often to re-evaluate targets (seconds)
FuseHunt.APPROACH_RANGE = 800        --- Start engaging target at this range

local STATUS = TTTBots.STATUS

--- Find the nearest non-ally target (not most isolated — speed matters).
---@param bot Bot
---@return Player|nil target
---@return number distance
function FuseHunt.FindNearestTarget(bot)
    local nonAllies = TTTBots.Roles.GetNonAllies(bot)
    local botPos = bot:GetPos()
    local bestTarget, bestDist = nil, math.huge

    for _, other in ipairs(nonAllies) do
        if IsValid(other) and lib.IsPlayerAlive(other) then
            local d = botPos:Distance(other:GetPos())
            if d < bestDist then
                bestDist = d
                bestTarget = other
            end
        end
    end

    return bestTarget, bestDist
end

--- Find the best target balancing distance and isolation.
--- When time is plentiful, prefer isolated targets. When time is scarce, prefer closest.
---@param bot Bot
---@return Player|nil
function FuseHunt.FindBestTarget(bot)
    local timeLeft = FuseHunt.GetTimeLeft(bot)

    -- Desperate: just pick the nearest living enemy
    if timeLeft < FuseHunt.DESPERATE_THRESHOLD then
        local target, _ = FuseHunt.FindNearestTarget(bot)
        return target
    end

    -- Normal: prefer isolated targets (higher chance of clean kill)
    local isolated = lib.FindIsolatedTarget(bot)
    if isolated and IsValid(isolated) and lib.IsPlayerAlive(isolated) then
        return isolated
    end

    -- Fallback: nearest
    local target, _ = FuseHunt.FindNearestTarget(bot)
    return target
end

--- Get the fuse timer remaining for this bot.
---@param bot Bot
---@return number secondsLeft
function FuseHunt.GetTimeLeft(bot)
    if not bot.fuseDeadline then return FuseHunt.FUSE_DURATION end
    return math.max(0, bot.fuseDeadline - CurTime())
end

--- Reset the fuse timer (called on kill).
---@param bot Bot
function FuseHunt.ResetTimer(bot)
    bot.fuseDeadline = CurTime() + FuseHunt.FUSE_DURATION
end

---@param bot Bot
---@return boolean
function FuseHunt.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not IsValid(bot) then return false end
    -- Don't run if already fighting a target via FightBack
    if bot.attackTarget ~= nil then return false end
    return true
end

---@param bot Bot
---@return BStatus
function FuseHunt.OnStart(bot)
    bot.fuseTarget = nil
    bot.fuseLastRetarget = 0
    -- Initialize the fuse deadline if not set (first activation)
    if not bot.fuseDeadline then
        FuseHunt.ResetTimer(bot)
    end
    return STATUS.RUNNING
end

---@param bot Bot
---@return BStatus
function FuseHunt.OnRunning(bot)
    local loco = bot:BotLocomotor()
    if not loco then return STATUS.FAILURE end

    local timeLeft = FuseHunt.GetTimeLeft(bot)

    ---------------------------------------------------------------------------
    -- TARGET SELECTION
    ---------------------------------------------------------------------------
    local target = bot.fuseTarget
    local needRetarget = not (target and IsValid(target) and lib.IsPlayerAlive(target))

    -- Retarget more frequently when desperate
    local retargetInterval = FuseHunt.RETARGET_INTERVAL
    if timeLeft < FuseHunt.DESPERATE_THRESHOLD then
        retargetInterval = 1.5
    end

    if not needRetarget and CurTime() - (bot.fuseLastRetarget or 0) > retargetInterval then
        needRetarget = true
    end

    if needRetarget then
        local newTarget = FuseHunt.FindBestTarget(bot)
        if not (newTarget and IsValid(newTarget) and lib.IsPlayerAlive(newTarget)) then
            return STATUS.FAILURE -- No targets at all
        end
        bot.fuseTarget = newTarget
        bot.fuseLastRetarget = CurTime()
        target = newTarget
    end

    local botPos = bot:GetPos()
    local targetPos = target:GetPos()
    local dist = botPos:Distance(targetPos)
    local canSee = bot:Visible(target)

    ---------------------------------------------------------------------------
    -- CRITICAL: Timer about to expire — charge at anyone visible
    ---------------------------------------------------------------------------
    if timeLeft < FuseHunt.CRITICAL_THRESHOLD then
        -- Absolute emergency: run at the target and engage
        if canSee then
            bot:SetAttackTarget(target)
            return STATUS.SUCCESS
        end
        -- Can't see anyone — rush toward last known position
        loco:SetGoal(targetPos)
        return STATUS.RUNNING
    end

    ---------------------------------------------------------------------------
    -- ENGAGE: Close enough and can see target — hand off to attack system
    ---------------------------------------------------------------------------
    if canSee and dist < FuseHunt.APPROACH_RANGE then
        -- When desperate, always engage immediately
        if timeLeft < FuseHunt.DESPERATE_THRESHOLD or dist < 500 then
            bot:SetAttackTarget(target)
            return STATUS.SUCCESS
        end
    end

    ---------------------------------------------------------------------------
    -- APPROACH: Move toward the target
    ---------------------------------------------------------------------------
    if not canSee then
        -- Use memory to track target position
        local memory = bot.components and bot.components.memory
        if memory then
            local knownPos = memory:GetKnownPositionFor(target)
            if knownPos then
                loco:SetGoal(knownPos)
                return STATUS.RUNNING
            end
        end
    end

    loco:SetGoal(targetPos)
    return STATUS.RUNNING
end

---@param bot Bot
function FuseHunt.OnSuccess(bot)
end

---@param bot Bot
function FuseHunt.OnFailure(bot)
end

---@param bot Bot
function FuseHunt.OnEnd(bot)
    bot.fuseTarget = nil
end

---------------------------------------------------------------------------
-- Kill tracking: reset the fuse timer when the Fuse bot kills someone.
---------------------------------------------------------------------------
hook.Add("PlayerDeath", "TTTBots.Behavior.FuseHunt.KillTrack", function(victim, weapon, attacker)
    if not (IsValid(attacker) and attacker:IsPlayer() and attacker:IsBot()) then return end
    if not TTTBots.Match.IsRoundActive() then return end
    if not ROLE_FUSE then return end
    if not (attacker.GetSubRole and attacker:GetSubRole() == ROLE_FUSE) then return end

    -- Reset the fuse timer — the bot lives another minute
    FuseHunt.ResetTimer(attacker)
    attacker.fuseTarget = nil
    attacker.fuseLastRetarget = 0
end)

---------------------------------------------------------------------------
-- Round cleanup: reset fuse state on round start.
---------------------------------------------------------------------------
hook.Add("TTTBeginRound", "TTTBots.Behavior.FuseHunt.RoundReset", function()
    for _, bot in ipairs(player.GetBots()) do
        bot.fuseDeadline = nil
        bot.fuseTarget = nil
        bot.fuseLastRetarget = nil
    end
end)
