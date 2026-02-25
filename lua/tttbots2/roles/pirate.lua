--- Pirate role support for TTT Bots 2.
--- The Pirate is a crew member who follows the Pirate Captain's lead. Pirates
--- fight for whatever team the Captain has bound them to via the Contract.
--- If the Captain dies, a remaining Pirate becomes the new Captain.
---
--- Bot behavior: follows the Captain, fights non-allies, helps defend
--- teammates. Similar to the Sidekick role but for the pirate team.
---
--- Addon: https://github.com/TTT-2/ttt2-role_pir

if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_PIRATE then return false end

TEAM_JESTER = TEAM_JESTER or "jesters"
TEAM_PIRATE = TEAM_PIRATE or TEAM_PIR or "pirates"

local allyTeams = {
    [TEAM_PIRATE] = true,
    [TEAM_JESTER] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Behavior tree: Pirates follow their Captain (FollowMaster) and fight
--- alongside them. When no master is available, they stalk and patrol.
local bTree = {
    _prior.FightBack,           -- Always fight back when attacked
    _prior.Restore,             -- Heal / pick up weapons
    _bh.Stalk,                  -- Stalk and hunt targets
    _prior.Minge,               -- Occasional minging
    _prior.Investigate,         -- Investigate noises
    _prior.Patrol               -- Patrol / wander
}

local pirate = TTTBots.RoleData.New("pirate", TEAM_PIRATE)
pirate:SetDefusesC4(false)
pirate:SetPlantsC4(false)
pirate:SetCanCoordinate(false)          -- Pirates coordinate via Captain, not bot system
pirate:SetStartsFights(true)            -- Will fight for their team
pirate:SetTeam(TEAM_PIRATE)
pirate:SetUsesSuspicion(false)          -- Knows teams
pirate:SetKnowsLifeStates(true)
pirate:SetBTree(bTree)
pirate:SetAlliedTeams(allyTeams)
pirate:SetLovesTeammates(true)          -- Loves fellow pirates and captain
pirate:SetCanSnipe(true)
pirate:SetCanHide(true)
TTTBots.Roles.RegisterRole(pirate)

--- Pirates help their Captain when the Captain is attacked
hook.Add("TTTBotsOnWitnessHurt", "TTTBots.pirate.helpCaptain",
    function(witness, victim, attacker, healthRemaining, damageTaken)
        if not IsValid(attacker) then return end
        if not (IsValid(witness) and IsValid(victim)) then return end

        local witnessRole = witness:GetRoleStringRaw()
        local victimRole = victim:GetRoleStringRaw()

        -- Pirates rush to defend their Captain
        if witnessRole == "pirate" and victimRole == "pirate_captain" then
            witness:SetAttackTarget(attacker)
        end

        -- Captain defends their Pirates too
        if witnessRole == "pirate_captain" and victimRole == "pirate" then
            witness:SetAttackTarget(attacker)
        end
    end)

--- Pirates assist when the Captain starts shooting at someone
hook.Add("TTTBotsOnWitnessFireBullets", "TTTBots.pirate.assistCaptain",
    function(witness, attacker, data, angleDiff)
        local attackerRole = attacker:GetRoleStringRaw()
        local witnessRole = witness:GetRoleStringRaw()

        -- If a pirate sees the captain shooting, help them
        if witnessRole == "pirate" and attackerRole == "pirate_captain" then
            local eyeTracePos = attacker:GetEyeTrace().HitPos
            if not eyeTracePos then return end
            local target = TTTBots.Lib.GetClosest(
                TTTBots.Roles.GetNonAllies(witness), eyeTracePos
            )
            if not target then return end
            witness:SetAttackTarget(target)
        end

        -- If the captain sees a pirate shooting, help them too
        if witnessRole == "pirate_captain" and attackerRole == "pirate" then
            local eyeTracePos = attacker:GetEyeTrace().HitPos
            if not eyeTracePos then return end
            local target = TTTBots.Lib.GetClosest(
                TTTBots.Roles.GetNonAllies(witness), eyeTracePos
            )
            if not target then return end
            witness:SetAttackTarget(target)
        end
    end)

return true
