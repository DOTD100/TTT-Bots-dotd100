---@class InvestigateNoise
TTTBots.Behaviors.InvestigateNoise = {}

local lib = TTTBots.Lib

---@class InvestigateNoise
local InvestigateNoise = TTTBots.Behaviors.InvestigateNoise
InvestigateNoise.Name = "Investigate Noise"
InvestigateNoise.Description = "Investigates suspicious noises, with urgency for active gunfights"
InvestigateNoise.Interruptible = true

InvestigateNoise.INVESTIGATE_CATEGORIES = {
    Gunshot = true,
    Death = true,
    C4Beep = false, -- Disabled due to behavior where bot would hover around an armed bomb that's about to explode
    Explosion = true
}

--- Minimum gunfight cluster size to count as an "active gunfight" (bypasses random chance)
InvestigateNoise.GUNFIGHT_THRESHOLD = 3

---@class Bot
---@field investigateNoiseTimer number The last time the bot investigated a noise

local STATUS = TTTBots.STATUS

function InvestigateNoise.GetInterestingSounds(bot)
    ---@type CMemory
    local memory = bot.components.memory
    local sounds = memory:GetRecentSounds()
    local interesting = {}
    for i, v in pairs(sounds) do
        local wasme = v.ent == bot or v.ply == bot
        if not wasme and InvestigateNoise.INVESTIGATE_CATEGORIES[v.sound] then
            table.insert(interesting, v)
        end
    end
    return interesting
end

function InvestigateNoise.FindClosestSound(bot, mustBeVisible)
    mustBeVisible = mustBeVisible or false
    local sounds = InvestigateNoise.GetInterestingSounds(bot)
    local closestSound = nil
    local closestDist
    for i, v in pairs(sounds) do
        local dist = bot:GetPos():Distance(v.pos)
        local visible = (mustBeVisible and bot:VisibleVec(v.pos)) or not mustBeVisible
        if (closestDist == nil or dist < closestDist) and visible then
            closestDist = dist
            closestSound = v
        end
    end
    return closestSound
end

--- Check if there's an active gunfight cluster the bot should urgently investigate.
--- Returns the cluster if so, nil otherwise.
---@param bot Bot
---@return table|nil cluster {pos, count, newest}
function InvestigateNoise.GetUrgentGunfight(bot)
    local memory = bot.components and bot.components.memory
    if not memory then return nil end
    local cluster = memory:GetMostUrgentGunfight()
    if not cluster then return nil end
    -- Must have enough sounds to count as a gunfight
    if cluster.count < InvestigateNoise.GUNFIGHT_THRESHOLD then return nil end
    -- Must be recent (within 10 seconds)
    if CurTime() - cluster.newest > 10 then return nil end
    return cluster
end

function InvestigateNoise.OnStart(bot)
    bot.components.chatter:On("InvestigateNoise", {})
    return STATUS.RUNNING
end

function InvestigateNoise.OnRunning(bot)
    local loco = bot:BotLocomotor()

    -- Abort investigation if the bot is under attack or has a combat target
    if bot.attackTarget and IsValid(bot.attackTarget) then return STATUS.FAILURE end
    if bot.lastHurtTime and (CurTime() - bot.lastHurtTime) < 3 then return STATUS.FAILURE end

    -- Priority 1: If we can see the source of a sound, just look at it
    local closestVisible = InvestigateNoise.FindClosestSound(bot, true)
    if closestVisible then
        loco:LookAt(closestVisible.pos + Vector(0, 0, 72))
        return STATUS.RUNNING
    end

    -- Priority 2: Active gunfight — always investigate (bypass random chance)
    local urgentFight = InvestigateNoise.GetUrgentGunfight(bot)
    if urgentFight then
        loco:LookAt(urgentFight.pos + Vector(0, 0, 72))
        loco:SetGoal(urgentFight.pos)
        return STATUS.RUNNING
    end

    -- Priority 3: Normal noise investigation (subject to random chance)
    if not InvestigateNoise.ShouldInvestigateNoise(bot) then
        return STATUS.FAILURE
    end

    local closestHidden = InvestigateNoise.FindClosestSound(bot, false)
    if closestHidden then
        loco:LookAt(closestHidden.pos + Vector(0, 0, 72))
        loco:SetGoal(closestHidden.pos)
        return STATUS.RUNNING
    end

    return STATUS.SUCCESS
end

--- Return true/false based off of a random chance. This is meant to be called every tick (5x per sec as of writing), so the chance is low by default.
---@param bot Bot
function InvestigateNoise.ShouldInvestigateNoise(bot)
    local MTB = lib.GetConVarInt("noise_investigate_mtb")
    if bot.investigateNoiseTimer and bot.investigateNoiseTimer > CurTime() then
        return false
    else
        bot.investigateNoiseTimer = CurTime() + MTB
    end
    local mult = bot:GetTraitMult("investigateNoise")
    local baseChance = lib.GetConVarInt("noise_investigate_chance")
    local pct = baseChance * mult

    local passed = lib.TestPercent(pct)
    return passed
end

function InvestigateNoise.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    -- Combat takes priority over investigating sounds
    if bot.attackTarget and IsValid(bot.attackTarget) then return false end
    if bot.lastHurtTime and (CurTime() - bot.lastHurtTime) < 3 then return false end
    -- Valid if we hear any interesting sounds OR there's an active gunfight
    if #InvestigateNoise.GetInterestingSounds(bot) > 0 then return true end
    if InvestigateNoise.GetUrgentGunfight(bot) then return true end
    return false
end

function InvestigateNoise.OnFailure(bot) end

function InvestigateNoise.OnSuccess(bot) end

function InvestigateNoise.OnEnd(bot) end
