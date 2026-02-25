if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_SHANKER then return false end

TEAM_JESTER = TEAM_JESTER or "jesters"

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Custom behavior tree for the Shanker role.
--- Shank is the primary behavior: hunt isolated targets, backstab with the
--- shanker knife, flee after kills. The shanker never investigates corpses
--- (they don't want to be found near their own kills).
--- Stalk is the fallback if Shank can't find a target or lost the knife.
local bTree = {
    _prior.FightBack,           -- Always fight back if attacked
    _bh.BurnCorpse,             -- Burn victim corpses with flare gun (bodyBurner trait only)
    _bh.Shank,                  -- PRIMARY: backstab isolated targets with shanker knife
    _bh.Defib,                  -- Revive allies if possible
    _bh.PlantBomb,              -- Plant C4 opportunistically
    _bh.UseTraitorTrap,         -- Activate traitor traps
    _prior.Restore,             -- Heal / pick up weapons
    _bh.Stalk,                  -- Fallback: stalk isolated players if shank behavior fails
    _bh.FollowPlan,             -- Follow traitor coordination plans
    _bh.Interact,               -- Use map interactables
    _prior.Minge,               -- Occasional minging
    _prior.Investigate,         -- Investigate noises to appear innocent
    _prior.Patrol               -- Patrol / wander
    -- NOTE: InvestigateCorpse deliberately omitted — shanker avoids corpses
}

local shanker = TTTBots.RoleData.New("shanker", TEAM_TRAITOR)
shanker:SetDefusesC4(false)
shanker:SetPlantsC4(true)
shanker:SetCanHaveRadar(true)           -- Free radar (part of the role's kit)
shanker:SetCanCoordinate(true)          -- Can work with other traitors
shanker:SetStartsFights(true)
shanker:SetTeam(TEAM_TRAITOR)
shanker:SetUsesSuspicion(false)         -- Traitor-side, knows teams
shanker:SetKnowsLifeStates(true)       -- Radar shows who is alive
shanker:SetBTree(bTree)
shanker:SetAlliedTeams(allyTeams)
shanker:SetLovesTeammates(true)
shanker:SetCanSnipe(false)              -- Shanker prefers close range, not sniping
shanker:SetCanHide(true)                -- Uses hiding spots for ambushes
TTTBots.Roles.RegisterRole(shanker)

return true
