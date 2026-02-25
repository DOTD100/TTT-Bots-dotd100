--- Swapper role support for TTT Bots 2.
--- Jester-team role that swaps roles with whoever kills them.
--- When the Swapper is killed, the killer becomes the new Swapper (with reduced
--- health) and the Swapper revives with the killer's old role and equipment.
---
--- Addon: https://github.com/Guardian954/ttt2-role_swapper_git
---
--- Bot strategy: The Swapper WANTS to be killed — so it acts provocatively,
--- getting in people's faces and being generally suspicious. It uses the Stalk
--- behavior to follow players closely. The existing Jester protection system
--- (in jester.lua) already prevents other bots from targeting TEAM_JESTER
--- players, so the Swapper is naturally protected against bot-on-bot kills.
---
--- After the swap occurs (addon handles this automatically on death), the bot
--- will be assigned a new role and behavior tree dynamically.

if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_SWAPPER then return false end

TEAM_JESTER = TEAM_JESTER or "jesters"

local allyTeams = {
    [TEAM_JESTER] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Behavior tree: The Swapper wants to get killed, so it acts like a Jester —
--- stalking players, being visible, and generally getting in the way.
--- No fighting (can't really benefit from killing anyone).
--- No C4, no coordination, no shop usage.
local bTree = {
    _prior.FightBack,           -- Defend self if cornered (may provoke retaliation)
    _prior.Restore,             -- Pick up weapons to look normal
    _bh.Stalk,                  -- Follow players closely — be suspicious
    _bh.Interact,               -- Use map interactables
    _prior.Minge,               -- Minge around — act suspicious
    _prior.Investigate,         -- Investigate sounds (be present near action)
    _prior.Patrol               -- Patrol / wander
}

local swapper = TTTBots.RoleData.New("swapper", TEAM_JESTER)
swapper:SetDefusesC4(false)
swapper:SetPlantsC4(false)
swapper:SetCanCoordinate(false)         -- No team to coordinate with
swapper:SetStartsFights(true)           -- Acts aggressively to provoke
swapper:SetTeam(TEAM_JESTER)
swapper:SetUsesSuspicion(false)         -- Jester team, no suspicion tracking
swapper:SetKnowsLifeStates(false)
swapper:SetBTree(bTree)
swapper:SetAlliedTeams(allyTeams)
swapper:SetLovesTeammates(false)        -- Doesn't love anyone — wants to get killed
swapper:SetCanSnipe(false)
swapper:SetCanHide(false)               -- Wants to be visible, not hidden
TTTBots.Roles.RegisterRole(swapper)

return true
