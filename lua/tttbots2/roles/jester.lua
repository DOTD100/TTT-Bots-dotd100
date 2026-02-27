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

-- Jester protection: prevent bots from attacking Jester-team players
-- unless they're under direct pressure (took damage recently).

--- Returns true if the target is on Team Jester (including unknownTeam roles like Beggar).
local function IsJesterTeam(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    local team = ply:GetTeam()
    if team == TEAM_JESTER or team == "jesters" then return true end

    -- unknownTeam roles report TEAM_NONE; check defaultTeam instead
    if ply.GetSubRoleData then
        local roleData = ply:GetSubRoleData()
        if roleData and roleData.unknownTeam and roleData.defaultTeam then
            local dt = roleData.defaultTeam
            if dt == TEAM_JESTER or dt == "jesters" then return true end
        end
    end

    return false
end

--- Returns true if the bot took damage recently (panic window).
local PRESSURE_WINDOW = 2

local function IsUnderPressure(bot)
    if not bot.lastHurtTime then return false end
    return (CurTime() - bot.lastHurtTime) < PRESSURE_WINDOW
end

--- Block attacks on Jester-team players unless the bot is panicking.
hook.Add("TTTBotsCanAttack", "TTTBots.jester.protect", function(bot, target)
    if not IsJesterTeam(target) then return end
    if IsUnderPressure(bot) then return end
    return false
end)



--- Drop Jester targets when pressure fades; give up after JESTER_GIVEUP_TIME.
local JESTER_GIVEUP_TIME = 3

hook.Add("Think", "TTTBots.jester.clearTarget", function()
    if not TTTBots.Match.IsRoundActive() then return end

    -- Throttle to twice per second
    local now = CurTime()
    if (TTTBots._jesterClearCheck or 0) + 0.5 > now then return end
    TTTBots._jesterClearCheck = now

    for _, bot in pairs(TTTBots.Bots) do
        if not (IsValid(bot) and bot.attackTarget) then continue end

        -- Non-Jester bots: stop attacking Jester-team targets once pressure fades
        if IsJesterTeam(bot.attackTarget) and not IsUnderPressure(bot) then
            bot.attackTarget = nil
            bot.tttbots_jesterAttackStart = nil
            continue
        end

        -- Jester bots: give up on targets that ignore them
        if IsJesterTeam(bot) then
            local target = bot.attackTarget

            if not bot.tttbots_jesterAttackStart then
                bot.tttbots_jesterAttackStart = now
                bot.tttbots_jesterLastHurtBy = nil
            end

            local elapsed = now - bot.tttbots_jesterAttackStart
            if elapsed >= JESTER_GIVEUP_TIME then
                local wasHurtByTarget = bot.tttbots_jesterLastHurtBy == target
                if not wasHurtByTarget then
                    -- Target ignored us, move on
                    bot.attackTarget = nil
                    bot.tttbots_jesterAttackStart = nil
                    bot.tttbots_jesterLastHurtBy = nil
                    bot.tttbots_jesterIgnoredBy = target
                    bot.tttbots_jesterIgnoreExpiry = now + 10
                else
                    -- Target fighting back, keep going
                    bot.tttbots_jesterAttackStart = now
                    bot.tttbots_jesterLastHurtBy = nil
                end
            end
        end
    end
end)

--- Track damage for pressure detection and Jester retaliation tracking.
hook.Add("PlayerHurt", "TTTBots.jester.trackHurt", function(victim, attacker, healthRemaining, damageTaken)
    if not (IsValid(victim) and victim:IsBot()) then return end
    if damageTaken < 1 then return end
    victim.lastHurtTime = CurTime()

    -- Track if Jester's attack target retaliates
    if IsJesterTeam(victim) and IsValid(attacker) and attacker == victim.attackTarget then
        victim.tttbots_jesterLastHurtBy = attacker
    end
end)

--- Prevent Jester bots from immediately re-targeting someone who just ignored them
hook.Add("TTTBotsCanAttack", "TTTBots.jester.ignoreBlock", function(bot, target)
    if not IsJesterTeam(bot) then return end
    if not (bot.tttbots_jesterIgnoredBy and bot.tttbots_jesterIgnoredBy == target) then return end
    if CurTime() < (bot.tttbots_jesterIgnoreExpiry or 0) then
        return false
    end
    -- Cooldown expired, clear it
    bot.tttbots_jesterIgnoredBy = nil
    bot.tttbots_jesterIgnoreExpiry = nil
end)

-- Reduce suspicion buildup against Jester-team players.
hook.Add("TTTBotsModifySuspicion", "TTTBots.jester.sus", function(bot, target, reason, mult)
    if not (IsValid(target) and target:IsPlayer()) then return end
    if not IsJesterTeam(target) then return end

    -- Raw factor; sv_morality multiplies this in
    if TTTBots.Lib.GetConVarBool("cheat_know_jester") then
        return 0.1
    end

    return 0.3
end)

return true
