if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_BANDIT then return false end

--- Bandit: A lone wolf role on its own team (similar to Jackal/Serial Killer).
--- Goal is to be the last man standing. Has access to the detective shop.
--- Does not coordinate with traitors -- everyone is the enemy.

TEAM_JESTER = TEAM_JESTER or "jesters"

local allyTeams = {
    [TEAM_BANDIT] = true,
    [TEAM_JESTER] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes
local bTree = {
    _prior.FightBack,
    _bh.Defuse,              -- Can defuse C4 since everyone is an enemy
    _bh.Defib,              -- Can revive allies (sidekicks etc.) with detective shop defibrillator
    _prior.Restore,
    _bh.Stalk,              -- Stalk and pick off isolated targets
    _bh.InvestigateCorpse,  -- Investigate corpses for intel
    _prior.Minge,
    _prior.Investigate,
    _prior.Patrol
}

local bandit = TTTBots.RoleData.New("bandit", TEAM_BANDIT)
bandit:SetDefusesC4(true)           -- Can defuse C4 since everyone is an enemy
bandit:SetPlantsC4(false)           -- No traitor C4
bandit:SetCanCoordinate(false)      -- Lone wolf, no traitor coordination
bandit:SetCanHaveRadar(false)       -- No traitor radar
bandit:SetStartsFights(true)        -- Will attack non-allies (everyone)
bandit:SetUsesSuspicion(false)      -- Knows who the enemies are (everyone)
bandit:SetTeam(TEAM_BANDIT)
bandit:SetBTree(bTree)
bandit:SetKnowsLifeStates(true)    -- Lone wolves keep track of who is alive
bandit:SetAlliedTeams(allyTeams)
bandit:SetCanSnipe(true)
bandit:SetCanHide(true)             -- Can use hiding spots to ambush
bandit:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(bandit)

return true
