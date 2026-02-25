--- Roider role definition.
--- The Roider can only deal damage with melee (crowbar), so the bot uses
--- a custom behavior tree that replaces the normal AttackTarget with RoiderAttack.
if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_ROIDER then return false end

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Custom FightBack node that uses RoiderAttack instead of normal AttackTarget
local RoiderFightBack = {
    _bh.ClearBreakables,
    _bh.RoiderAttack,
}

local bTree = {
    RoiderFightBack,
    _prior.Restore,
    _bh.UseTraitorTrap,  -- Activate map traitor traps when non-allies are nearby
    _bh.Stalk,           -- Stalk isolated targets then rush them with crowbar
    _bh.Interact,
    _prior.Investigate,
    _prior.Minge,
    _bh.Decrowd,
    _prior.Patrol,
}

local roider = TTTBots.RoleData.New("roider", TEAM_TRAITOR)
roider:SetDefusesC4(false)
roider:SetPlantsC4(false)
roider:SetStartsFights(true)        -- Will attack non-allies
roider:SetTeam(TEAM_TRAITOR)
roider:SetUsesSuspicion(false)       -- Knows who's who (traitor team)
roider:SetBTree(bTree)
roider:SetCanHaveRadar(false)
roider:SetCanCoordinate(true)        -- Can participate in traitor plans
roider:SetAlliedTeams({ [TEAM_TRAITOR] = true, [TEAM_JESTER or 'jesters'] = true })
roider:SetCanSnipe(false)            -- No point sniping with a crowbar
roider:SetCanHide(true)              -- Can hide and ambush
roider:SetLovesTeammates(true)
roider:SetAutoSwitch(false)          -- Don't auto-switch away from crowbar
roider:SetPreferredWeapon("weapon_zm_improvised") -- Crowbar
TTTBots.Roles.RegisterRole(roider)

return true
