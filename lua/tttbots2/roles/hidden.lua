if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_HIDDEN then return false end

--- The Hidden has its own team (TEAM_HIDDEN) like serialkiller.
--- Fallback: if TEAM_HIDDEN doesn't exist, define it.
TEAM_HIDDEN = TEAM_HIDDEN or "hidden"
TEAM_JESTER = TEAM_JESTER or "jesters"

local allyTeams = {
    [TEAM_HIDDEN] = true,
    [TEAM_JESTER] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Custom behavior tree for the Hidden role.
--- HiddenHunt is the primary behavior: activate powers, then hunt isolated
--- targets with the knife while invisible. Flee when damaged.
--- The Hidden is a lone wolf — no team coordination, no C4, no corpse work.
--- Stalk is the fallback if HiddenHunt fails (e.g. before activation).
local bTree = {
    _prior.FightBack,           -- Fight back if cornered (will use knife)
    _bh.HiddenHunt,             -- PRIMARY: activate powers, hunt with knife, flee when visible
    _bh.Stalk,                  -- Fallback: stalk isolated players
    _prior.Minge,               -- Occasional minging
    _prior.Patrol               -- Patrol / wander
    -- NOTE: No InvestigateCorpse, no PlantBomb, no Defib, no FollowPlan
    -- The Hidden is a solo invisible predator.
}

local hidden = TTTBots.RoleData.New("hidden", TEAM_HIDDEN)
hidden:SetDefusesC4(false)
hidden:SetPlantsC4(false)              -- No C4
hidden:SetCanHaveRadar(false)          -- No radar
hidden:SetCanCoordinate(false)         -- Solo role
hidden:SetStartsFights(true)
hidden:SetTeam(TEAM_HIDDEN)
hidden:SetUsesSuspicion(false)         -- Knows who to kill (everyone)
hidden:SetKnowsLifeStates(true)       -- Wall hacks when standing still (effectively omniscient)
hidden:SetAutoSwitch(false)            -- Don't auto-switch weapons (knife only)
hidden:SetBTree(bTree)
hidden:SetAlliedTeams(allyTeams)
hidden:SetLovesTeammates(false)        -- No teammates to love
hidden:SetCanSnipe(false)              -- Melee only
hidden:SetCanHide(true)                -- Uses hiding spots for ambushes
TTTBots.Roles.RegisterRole(hidden)

return true
