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
--- Must check both GetTeam() (for normal jester roles) and the role's defaultTeam
--- (for unknownTeam roles like Beggar, where GetTeam() returns TEAM_NONE).
local function IsJesterTeam(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    local team = ply:GetTeam()
    if team == TEAM_JESTER or team == "jesters" then return true end

    -- For unknownTeam roles (like Beggar), GetTeam() returns TEAM_NONE.
    -- Check the role's defaultTeam from TTT2's role data instead.
    if ply.GetSubRoleData then
        local roleData = ply:GetSubRoleData()
        if roleData and roleData.unknownTeam and roleData.defaultTeam then
            local dt = roleData.defaultTeam
            if dt == TEAM_JESTER or dt == "jesters" then return true end
        end
    end

    return false
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



--- If a bot's current attack target is a Jester and they're no longer under
--- pressure, force them to drop the target. This handles the case where a
--- bot acquired a Jester target during panic but the threat has passed.
---
--- Also: Jester bots give up on targets that ignore them. If a Jester has
--- been attacking someone for a few seconds without taking damage from them,
--- they move on to find a more reactive victim.
local JESTER_GIVEUP_TIME = 3 -- seconds of being ignored before giving up

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

            -- Track when the Jester started this attack
            if not bot.tttbots_jesterAttackStart then
                bot.tttbots_jesterAttackStart = now
                bot.tttbots_jesterLastHurtBy = nil
            end

            -- Check if we've been attacking long enough to give up
            local elapsed = now - bot.tttbots_jesterAttackStart
            if elapsed >= JESTER_GIVEUP_TIME then
                -- Did the target retaliate? (hurt us at any point during the attack)
                local wasHurtByTarget = bot.tttbots_jesterLastHurtBy == target
                if not wasHurtByTarget then
                    -- Target ignored us, give up and find someone else
                    bot.attackTarget = nil
                    bot.tttbots_jesterAttackStart = nil
                    bot.tttbots_jesterLastHurtBy = nil
                    -- Brief cooldown: block re-targeting the same player for a bit
                    bot.tttbots_jesterIgnoredBy = target
                    bot.tttbots_jesterIgnoreExpiry = now + 10
                else
                    -- Target IS fighting back, reset the timer and keep going
                    bot.tttbots_jesterAttackStart = now
                    bot.tttbots_jesterLastHurtBy = nil
                end
            end
        end
    end
end)

--- Track when bots take damage so we know if they're under pressure.
--- Also tracks when Jester bots are hurt by their current attack target.
hook.Add("PlayerHurt", "TTTBots.jester.trackHurt", function(victim, attacker, healthRemaining, damageTaken)
    if not (IsValid(victim) and victim:IsBot()) then return end
    if damageTaken < 1 then return end
    victim.lastHurtTime = CurTime()

    -- If a Jester bot is hurt by their attack target, record it
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

---------------------------------------------------------------------------
-- Suspicion suppression: heavily reduce suspicion buildup against Jester-
-- team players. Even without cheat_know_jester, bots should be reluctant
-- to reach KOS threshold on a Jester.
---------------------------------------------------------------------------
hook.Add("TTTBotsModifySuspicion", "TTTBots.jester.sus", function(bot, target, reason, mult)
    if not (IsValid(target) and target:IsPlayer()) then return end
    if not IsJesterTeam(target) then return end

    -- With the cheat cvar: almost no suspicion (they "sense" something is off)
    -- Return a raw factor — sv_morality.lua multiplies mult by this return value
    if TTTBots.Lib.GetConVarBool("cheat_know_jester") then
        return 0.1
    end

    -- Without the cheat cvar: still reduce significantly so bots don't
    -- easily reach KOS threshold on a Jester through normal gameplay
    return 0.3
end)

return true
