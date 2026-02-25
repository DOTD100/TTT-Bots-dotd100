--- Mesmerist role support for TTT Bots 2.
--- Traitor subrole with a special defibrillator (weapon_ttt_mesdefi) that
--- revives dead players as Thralls on the traitor team. The Mesmerist should
--- be sneaky — reviving while witnessed exposes them as a traitor.
---
--- Addon: https://github.com/ZacharyHinds/ttt2-role-mesmerist
--- The Mesmerist spawns with a special defib (limited uses, default 1).
--- Revived players become Thralls who inherit the traitor team.

if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_MESMERIST then return false end

TEAM_JESTER = TEAM_JESTER or "jesters"

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Behavior tree: MesmeristRevive sits high in priority so the bot actively
--- seeks corpses to convert into Thralls. Once the defib is spent (default
--- 1 use), the bot falls through to normal traitor behaviors.
local bTree = {
    _prior.FightBack,           -- Always fight back when attacked
    _bh.MesmeristRevive,        -- Sneakily revive a corpse as a Thrall
    _bh.Defib,                  -- Revive traitor allies with regular defib if available
    _bh.PlantBomb,              -- Plant C4 when the opportunity is there
    _bh.UseTraitorTrap,         -- Activate traitor traps when non-allies are nearby
    _bh.InvestigateCorpse,      -- Blend in by investigating corpses
    _prior.Restore,             -- Heal / pick up weapons
    _bh.Stalk,                  -- Stalk isolated players for kills or revive opportunities
    _bh.FollowPlan,             -- Follow traitor coordination plans
    _bh.Interact,               -- Use map interactables
    _prior.Minge,               -- Occasional minging
    _prior.Investigate,         -- Investigate noises to appear innocent
    _prior.Patrol               -- Patrol / wander
}

local mesmerist = TTTBots.RoleData.New("mesmerist", TEAM_TRAITOR)
mesmerist:SetDefusesC4(false)
mesmerist:SetPlantsC4(true)
mesmerist:SetCanHaveRadar(true)
mesmerist:SetCanCoordinate(true)        -- Traitor coordination
mesmerist:SetStartsFights(true)
mesmerist:SetTeam(TEAM_TRAITOR)
mesmerist:SetUsesSuspicion(false)       -- Traitor subrole, knows teams
mesmerist:SetKnowsLifeStates(true)     -- Knows who is dead (essential for finding corpses)
mesmerist:SetBTree(bTree)
mesmerist:SetAlliedTeams(allyTeams)
mesmerist:SetLovesTeammates(true)
mesmerist:SetCanSnipe(false)            -- Prefers to get close for defib usage
mesmerist:SetCanHide(true)              -- Hide and wait for revive opportunities
TTTBots.Roles.RegisterRole(mesmerist)

return true
