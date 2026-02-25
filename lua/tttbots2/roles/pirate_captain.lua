--- Pirate Captain role support for TTT Bots 2.
--- The Pirate Captain is the leader of the pirate team. They spawn with a
--- "Contract" item that can be given to another player, binding the pirates
--- to fight for that player's team. If the Captain dies, a new Captain is
--- chosen from the remaining Pirates.
---
--- Bot behavior: The Captain stalks players and looks for opportunities to
--- give the Contract to someone (handled by the addon's own mechanics).
--- Once bound to a master, the Captain fights alongside that team.
---
--- Addon: https://github.com/TTT-2/ttt2-role_pir

if not TTTBots.Lib.IsTTT2() then return false end
--- The addon may use ROLE_PIRATE_CAPTAIN or just the captain subrole of pirate.
--- We check for the pirate captain role constant. The regular ROLE_PIRATE is
--- handled in pirate.lua.
if not ROLE_PIRATE_CAPTAIN then return false end

TEAM_JESTER = TEAM_JESTER or "jesters"
TEAM_PIRATE = TEAM_PIRATE or TEAM_PIR or "pirates"

local allyTeams = {
    [TEAM_PIRATE] = true,
    [TEAM_JESTER] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Behavior tree: The Captain drops the contract near a non-pirate player
--- first, then stalks and fights for whatever team the new master belongs to.
local bTree = {
    _prior.FightBack,           -- Always fight back when attacked
    _prior.Restore,             -- Heal / pick up weapons
    _bh.DropContract,           -- Drop contract near a non-pirate player
    _bh.Stalk,                  -- Stalk players to find targets
    _bh.Interact,               -- Use interactables
    _prior.Minge,               -- Occasional minging
    _prior.Investigate,         -- Investigate noises
    _prior.Patrol               -- Patrol / wander
}

local captain = TTTBots.RoleData.New("pirate_captain", TEAM_PIRATE)
captain:SetDefusesC4(false)
captain:SetPlantsC4(false)
captain:SetCanCoordinate(false)         -- Independent until bound to a team
captain:SetStartsFights(true)           -- Will fight
captain:SetTeam(TEAM_PIRATE)
captain:SetUsesSuspicion(false)         -- Knows teams
captain:SetKnowsLifeStates(true)
captain:SetBTree(bTree)
captain:SetAlliedTeams(allyTeams)
captain:SetLovesTeammates(true)         -- Loves fellow pirates
captain:SetCanSnipe(true)
captain:SetCanHide(true)
TTTBots.Roles.RegisterRole(captain)

return true
