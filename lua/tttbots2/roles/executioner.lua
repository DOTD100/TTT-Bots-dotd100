--- Executioner role support for TTT Bots 2.
--- Traitor subrole with a randomly assigned target to hunt (via GetTargetPlayer).
--- Functions identically to Hitman in behavior -- prioritizes hunting the contract target.
--- The Executioner addon handles target assignment, damage multipliers, and punishment.

if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_EXECUTIONER then return false end

TEAM_JESTER = TEAM_JESTER or 'jesters'

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Custom behavior tree for the Executioner role.
--- HitmanHunt works here because the Executioner uses the same GetTargetPlayer() API.
--- The bot hunts the assigned contract target first, then falls through to traitor behaviors.
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

local executioner = TTTBots.RoleData.New("executioner", TEAM_TRAITOR)
executioner:SetDefusesC4(false)
executioner:SetPlantsC4(true)
executioner:SetCanHaveRadar(true)
executioner:SetCanCoordinate(false)     -- Lone wolf hunter, focused on contract target
executioner:SetStartsFights(true)
executioner:SetTeam(TEAM_TRAITOR)
executioner:SetUsesSuspicion(false)     -- Omniscient role, knows teams
executioner:SetKnowsLifeStates(true)   -- Can see who is alive (omniscient)
executioner:SetBTree(bTree)
executioner:SetAlliedTeams(allyTeams)
executioner:SetLovesTeammates(true)
executioner:SetCanSnipe(true)           -- Can use sniper spots to wait for target
executioner:SetCanHide(true)            -- Can hide and ambush
TTTBots.Roles.RegisterRole(executioner)

return true
