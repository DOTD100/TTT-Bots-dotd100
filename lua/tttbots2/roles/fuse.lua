if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_FUSE then return false end

TEAM_JESTER = TEAM_JESTER or "jesters"

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Custom behavior tree for the Fuse role.
--- The Fuse must kill every ~60 seconds or self-destructs in an explosion.
--- The tree is heavily weighted toward aggressive target seeking.
--- FuseHunt is the primary behavior — it finds targets and hands off to
--- the attack system. The Fuse has no time for subtle play.
local bTree = {
    _prior.FightBack,           -- Always fight back (will also reset fuse timer on kill)
    _bh.FuseHunt,               -- PRIMARY: urgently find and engage targets before timer expires
    _bh.Stalk,                  -- Fallback: stalk someone if FuseHunt can't find a target
    _bh.PlantBomb,              -- Plant C4 if no targets nearby (might kill someone indirectly)
    _bh.UseTraitorTrap,         -- Activate traitor traps (another way to score a kill)
    _prior.Restore,             -- Quick heal between kills
    _bh.FollowPlan,             -- Follow traitor coordination plans
    _prior.Minge,               -- Occasional minging
    _prior.Investigate,         -- Investigate noises (might find a target)
    _prior.Patrol               -- Patrol when nothing else to do
    -- NOTE: InvestigateCorpse omitted — no time to waste confirming bodies
}

local fuse = TTTBots.RoleData.New("fuse", TEAM_TRAITOR)
fuse:SetDefusesC4(false)               -- No time for defusing
fuse:SetPlantsC4(true)                 -- C4 can score kills
fuse:SetCanHaveRadar(true)             -- Helps find targets faster
fuse:SetCanCoordinate(true)            -- Works with other traitors
fuse:SetStartsFights(true)             -- Very aggressive
fuse:SetTeam(TEAM_TRAITOR)
fuse:SetUsesSuspicion(false)           -- Traitor-side, knows teams
fuse:SetKnowsLifeStates(true)         -- Knows who's alive (critical for finding targets)
fuse:SetBTree(bTree)
fuse:SetAlliedTeams(allyTeams)
fuse:SetLovesTeammates(true)
fuse:SetCanSnipe(true)                 -- Will use any weapon to score a kill
fuse:SetCanHide(false)                 -- No time for hiding — must be aggressive
TTTBots.Roles.RegisterRole(fuse)

return true
