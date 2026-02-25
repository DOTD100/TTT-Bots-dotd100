if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_HITMAN then return false end

TEAM_JESTER = TEAM_JESTER or 'jesters'

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Custom behavior tree for the Hitman role.
--- HitmanHunt sits right after FightBack so the bot actively hunts
--- the assigned contract target. If no target is available (or the bot
--- is already in a fight), the tree falls through to normal traitor
--- behaviors like planting bombs or stalking.
local bTree = {
    _prior.FightBack,           -- Always fight back when attacked
    _bh.BurnCorpse,             -- Burn victim corpses with flare gun (bodyBurner trait only)
    _bh.PlaceRadio,             -- Place radio for distraction (radiohead trait only)
    _bh.HitmanHunt,             -- Hunt the assigned contract target
    _bh.Defib,                  -- Revive allies if possible
    _bh.PlantBomb,              -- Plant C4 when the opportunity is there
    _bh.UseTraitorTrap,         -- Activate map traitor traps when non-allies are nearby
    _bh.InvestigateCorpse,      -- Blend in by investigating corpses
    _prior.Restore,             -- Heal / pick up weapons
    _bh.Stalk,                  -- Fallback: stalk isolated players if no contract target
    _bh.FollowPlan,             -- Follow traitor coordination plans
    _bh.Interact,               -- Use map interactables
    _prior.Minge,               -- Occasional minging
    _prior.Investigate,         -- Investigate noises to appear innocent
    _prior.Patrol               -- Patrol / wander
}

local hitman = TTTBots.RoleData.New("hitman", TEAM_TRAITOR)
hitman:SetDefusesC4(false)
hitman:SetPlantsC4(true)
hitman:SetCanHaveRadar(true)
hitman:SetCanCoordinate(false)       -- Lone wolf
hitman:SetStartsFights(true)
hitman:SetTeam(TEAM_TRAITOR)
hitman:SetUsesSuspicion(false)       -- Omniscient role, knows teams
hitman:SetKnowsLifeStates(true)     -- Can see who is alive (omniscient)
hitman:SetBTree(bTree)
hitman:SetAlliedTeams(allyTeams)
hitman:SetLovesTeammates(true)
hitman:SetCanSnipe(true)             -- Can use sniper spots to wait for target
hitman:SetCanHide(true)              -- Can hide and ambush
TTTBots.Roles.RegisterRole(hitman)

return true
