--- Brainwasher role support for TTT Bots 2.
--- Traitor subrole that recruits players using the Slave Deagle, converting them
--- into Slaves. Behaves sneakily -- finds isolated targets and converts them
--- when few witnesses are around, similar to how the Jackal recruits Sidekicks.

if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_BRAINWASHER then return false end

TEAM_JESTER = TEAM_JESTER or 'jesters'

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Behavior tree: Brainwash sits high in priority so the bot actively
--- seeks isolated targets to convert. Once the deagle is spent, the bot
--- falls through to normal traitor behaviors.
local bTree = {
    _prior.FightBack,           -- Always fight back when attacked
    _bh.BurnCorpse,             -- Burn victim corpses with flare gun (bodyBurner trait only)
    _bh.PlaceRadio,             -- Place radio for distraction (radiohead trait only)
    _bh.Brainwash,              -- Sneakily recruit a target with the Slave Deagle
    _bh.Defib,                  -- Revive allies if possible
    _bh.PlantBomb,              -- Plant C4 when the opportunity is there
    _bh.UseTraitorTrap,         -- Activate map traitor traps when non-allies are nearby
    _bh.InvestigateCorpse,      -- Blend in by investigating corpses
    _prior.Restore,             -- Heal / pick up weapons
    _bh.Stalk,                  -- Fallback: stalk isolated players
    _bh.FollowPlan,             -- Follow traitor coordination plans
    _bh.Interact,               -- Use map interactables
    _prior.Minge,               -- Occasional minging
    _prior.Investigate,         -- Investigate noises to appear innocent
    _prior.Patrol               -- Patrol / wander
}

local brainwasher = TTTBots.RoleData.New("brainwasher", TEAM_TRAITOR)
brainwasher:SetDefusesC4(false)
brainwasher:SetPlantsC4(true)
brainwasher:SetCanHaveRadar(true)
brainwasher:SetCanCoordinate(true)      -- Can participate in traitor coordination
brainwasher:SetStartsFights(true)
brainwasher:SetTeam(TEAM_TRAITOR)
brainwasher:SetUsesSuspicion(false)     -- Traitor subrole, knows teams
brainwasher:SetKnowsLifeStates(true)
brainwasher:SetBTree(bTree)
brainwasher:SetAlliedTeams(allyTeams)
brainwasher:SetLovesTeammates(true)
brainwasher:SetCanSnipe(false)          -- Wants to get close for the deagle
brainwasher:SetCanHide(true)            -- Can hide and ambush for conversions
TTTBots.Roles.RegisterRole(brainwasher)

return true
