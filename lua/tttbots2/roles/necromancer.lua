--- Necromancer role support for TTT Bots 2.
--- Independent role (TEAM_NECRO) that revives dead players as zombies using
--- a special defibrillator. Zombies fight on the Necromancer's team.
--- Goal: be the last team standing.
---
--- Addon: https://github.com/TTT-2/ttt2-role_necro
--- The Necromancer spawns with a special defib. Revived players become zombies
--- (slower, deagle-only with limited ammo) on TEAM_NECRO.

if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_NECROMANCER then return false end

TEAM_JESTER = TEAM_JESTER or "jesters"
TEAM_NECRO = TEAM_NECRO or "necros"

local allyTeams = {
    [TEAM_NECRO] = true,
    [TEAM_JESTER] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Behavior tree: NecroRevive is top priority (after fighting back) so the
--- bot actively seeks corpses to raise. Falls through to stalking/combat
--- when no corpses are available or the defib is spent.
local bTree = {
    _prior.FightBack,           -- Always fight back when attacked
    _bh.NecroRevive,            -- Revive ANY corpse with the necro defib
    _prior.Restore,             -- Heal / pick up weapons
    _bh.Stalk,                  -- Stalk players (wait for kills to create corpses)
    _prior.Minge,               -- Occasional minging to appear innocent
    _prior.Investigate,         -- Investigate noises
    _prior.Patrol               -- Patrol / wander
}

local necromancer = TTTBots.RoleData.New("necromancer", TEAM_NECRO)
necromancer:SetDefusesC4(false)
necromancer:SetPlantsC4(false)
necromancer:SetCanCoordinate(false)     -- Independent, no team coordination
necromancer:SetStartsFights(true)       -- Will fight when needed
necromancer:SetTeam(TEAM_NECRO)
necromancer:SetUsesSuspicion(false)     -- Knows who is who
necromancer:SetKnowsLifeStates(true)   -- Knows who is dead (important for finding corpses)
necromancer:SetBTree(bTree)
necromancer:SetAlliedTeams(allyTeams)
necromancer:SetLovesTeammates(true)     -- Loves zombies it creates
necromancer:SetCanSnipe(false)          -- Prefers to get close for defib usage
necromancer:SetCanHide(true)            -- Can hide and wait for opportunities
TTTBots.Roles.RegisterRole(necromancer)

return true
