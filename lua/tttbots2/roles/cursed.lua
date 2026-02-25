--- Cursed role support for TTT Bots 2.
--- The Cursed has no team and cannot win. They cannot deal damage.
--- Death is impermanent — they always resurrect. Their goal is to remove
--- the curse by swapping roles with another player via "tagging" (interacting)
--- or shooting them with the RoleSwap Deagle.
---
--- Addon: https://github.com/AaronMcKenney/ttt2-role_curs
--- The Cursed swaps roles by getting close and pressing +USE on a player,
--- or by shooting them with the RoleSwap Deagle. "No backsies" rule prevents
--- immediately re-tagging the person who just tagged you.

if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_CURSED then return false end

TEAM_JESTER = TEAM_JESTER or "jesters"

--- The Cursed has no real team — it's on TEAM_NONE or its own team.
--- It cannot win, so ally definitions are mostly moot. We list TEAM_JESTER
--- to avoid accidentally attacking other no-win roles.
local allyTeams = {
    [TEAM_JESTER] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Behavior tree: The Cursed wants to find and tag someone ASAP.
--- CursedTag is the primary behavior — aggressively chase players to swap.
--- Since the Cursed can't deal damage, FightBack is less useful but kept
--- for self-preservation instincts (running away).
--- After swapping, the bot will get a new role and a new btree dynamically.
local bTree = {
    _prior.FightBack,           -- Try to flee if being attacked (can't fight back)
    _bh.CursedTag,              -- Chase and tag a player to swap roles
    _prior.Restore,             -- Pick up weapons (RoleSwap Deagle)
    _prior.Minge,               -- Occasional minging (blend in)
    _prior.Investigate,         -- Investigate noises (find players)
    _prior.Patrol               -- Patrol to find targets
}

local cursed = TTTBots.RoleData.New("cursed", TEAM_NONE)
cursed:SetDefusesC4(false)
cursed:SetPlantsC4(false)
cursed:SetCanCoordinate(false)          -- No team to coordinate with
cursed:SetStartsFights(false)           -- Cannot deal damage
cursed:SetTeam(TEAM_NONE)
cursed:SetUsesSuspicion(false)          -- No point building suspicion
cursed:SetKnowsLifeStates(false)
cursed:SetBTree(bTree)
cursed:SetAlliedTeams(allyTeams)
cursed:SetLovesTeammates(false)
cursed:SetCanSnipe(false)               -- Needs to get close to tag
cursed:SetCanHide(false)                -- No reason to hide — needs to be active
TTTBots.Roles.RegisterRole(cursed)

--- The Cursed always resurrects after death. During the brief window between
--- death and resurrection, the bot entity remains valid with components intact,
--- but the locomotor will error on RequestPath ("Owner must be a living player")
--- if it still has an active goal. Clear the goal on death to prevent this.
hook.Add("PlayerDeath", "TTTBots_CursedDeathCleanup", function(victim, _, _)
    if not IsValid(victim) then return end
    if not victim:IsBot() then return end
    if not victim.GetRoleStringRaw then return end

    local ok, role = pcall(victim.GetRoleStringRaw, victim)
    if not ok or role ~= "cursed" then return end

    local loco = victim:BotLocomotor()
    if loco then
        loco:SetGoal()
        loco:StopAttack()
    end
end)

return true
