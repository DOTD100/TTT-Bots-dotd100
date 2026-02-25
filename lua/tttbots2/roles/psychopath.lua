if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_PSYCHOPATH then return false end

--- Psychopath: A traitor subrole with access to the detective shop.
--- Behaves identically to a traitor in terms of AI behavior (kills non-allies,
--- coordinates with other traitors, plants C4, uses traps, etc.) but can purchase
--- detective-tier equipment (health stations, defuse kits, stungun, defibrillator).

TEAM_JESTER = TEAM_JESTER or "jesters"

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER] = true,
}

local psychopath = TTTBots.RoleData.New("psychopath", TEAM_TRAITOR)
psychopath:SetDefusesC4(false)
psychopath:SetPlantsC4(true)
psychopath:SetCanHaveRadar(true)
psychopath:SetCanCoordinate(true)
psychopath:SetStartsFights(true)
psychopath:SetTeam(TEAM_TRAITOR)
psychopath:SetUsesSuspicion(false)
psychopath:SetBTree(TTTBots.Behaviors.DefaultTrees.traitor)
psychopath:SetAlliedTeams(allyTeams)
psychopath:SetCanSnipe(true)
psychopath:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(psychopath)

return true
