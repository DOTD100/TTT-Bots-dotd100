if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_JESTER then return false end

local allyTeams = {
    [TEAM_JESTER] = true,
    [TEAM_TRAITOR] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes
local bTree = {
    _prior.FightBack,
    _prior.Restore,
    _bh.Stalk,
    _prior.Minge,
    _prior.Investigate,
    _prior.Patrol
}

local jester = TTTBots.RoleData.New("jester", TEAM_JESTER)
jester:SetDefusesC4(false)
jester:SetStartsFights(true)
jester:SetTeam(TEAM_JESTER)
jester:SetBTree(bTree)
jester:SetAlliedTeams(allyTeams)
TTTBots.Roles.RegisterRole(jester)

---------------------------------------------------------------------------
-- Jester protection: prevent bots from proactively attacking Jester-team
-- players. This is critical because killing a Jester gives them the win.
--
-- Bots will only fire on a Jester-team player if they are currently under
-- direct pressure — i.e. actively being hurt by SOMEONE (not necessarily
-- the Jester). This simulates panic fire where the bot can't tell friend
-- from foe in a hectic situation.
---------------------------------------------------------------------------

--- Returns true if the target is on Team Jester (Jester, pre-conversion Beggar, etc.)
local function IsJesterTeam(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    local team = ply:GetTeam()
    return team == TEAM_JESTER or team == "jesters"
end

--- Returns true if the bot is currently under active threat (took damage recently).
--- This provides a narrow window where panic fire at a Jester is allowed.
local PRESSURE_WINDOW = 2 -- seconds since last damage taken

local function IsUnderPressure(bot)
    if not bot.lastHurtTime then return false end
    return (CurTime() - bot.lastHurtTime) < PRESSURE_WINDOW
end

--- Block attacks on Jester-team players unless the bot is panicking.
hook.Add("TTTBotsCanAttack", "TTTBots.jester.protect", function(bot, target)
    if not IsJesterTeam(target) then return end

    -- Allow the attack ONLY if the bot is under active pressure
    if IsUnderPressure(bot) then return end

    -- Otherwise, refuse to target the Jester
    return false
end)

--- Track when bots take damage so we know if they're under pressure.
hook.Add("PlayerHurt", "TTTBots.jester.trackHurt", function(victim, attacker, healthRemaining, damageTaken)
    if not (IsValid(victim) and victim:IsBot()) then return end
    if damageTaken < 1 then return end
    victim.lastHurtTime = CurTime()
end)

--- If a bot's current attack target is a Jester and they're no longer under
--- pressure, force them to drop the target. This handles the case where a
--- bot acquired a Jester target during panic but the threat has passed.
hook.Add("Think", "TTTBots.jester.clearTarget", function()
    if not TTTBots.Match.IsRoundActive() then return end

    -- Throttle to twice per second
    local now = CurTime()
    if (TTTBots._jesterClearCheck or 0) + 0.5 > now then return end
    TTTBots._jesterClearCheck = now

    for _, bot in pairs(TTTBots.Bots) do
        if not (IsValid(bot) and bot.attackTarget) then continue end
        if not IsJesterTeam(bot.attackTarget) then continue end
        if IsUnderPressure(bot) then continue end

        -- Pressure has expired — stop attacking the Jester
        bot.attackTarget = nil
    end
end)

---------------------------------------------------------------------------
-- Suspicion suppression: heavily reduce suspicion buildup against Jester-
-- team players. Even without cheat_know_jester, bots should be reluctant
-- to reach KOS threshold on a Jester.
---------------------------------------------------------------------------
hook.Add("TTTBotsModifySuspicion", "TTTBots.jester.sus", function(bot, target, reason, mult)
    if not (IsValid(target) and target:IsPlayer()) then return end
    if not IsJesterTeam(target) then return end

    -- With the cheat cvar: almost no suspicion (they "sense" something is off)
    if TTTBots.Lib.GetConVarBool("cheat_know_jester") then
        return mult * 0.1
    end

    -- Without the cheat cvar: still reduce significantly so bots don't
    -- easily reach KOS threshold on a Jester through normal gameplay
    return mult * 0.3
end)

return true
