--- Arsonist role definition.
if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_ARSONIST then return false end

TEAM_JESTER = TEAM_JESTER or "jesters"

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Custom FightBack that prefers the flamethrower
local ArsonistFightBack = {
    _bh.ClearBreakables,
    _bh.ThrowGrenade,
    _bh.ArsonistAttack,
    _bh.AttackTarget,
}

local bTree = {
    ArsonistFightBack,
    _bh.BurnCorpse,
    _bh.PlantBomb,
    _bh.UseTraitorTrap,
    _bh.InvestigateCorpse,
    _prior.Restore,
    _bh.FollowPlan,
    _bh.Interact,
    _prior.Minge,
    _prior.Investigate,
    _prior.Patrol,
}

local arsonist = TTTBots.RoleData.New("arsonist", TEAM_TRAITOR)
arsonist:SetDefusesC4(false)
arsonist:SetPlantsC4(false)
arsonist:SetStartsFights(true)
arsonist:SetTeam(TEAM_TRAITOR)
arsonist:SetUsesSuspicion(false)
arsonist:SetBTree(bTree)
arsonist:SetCanHaveRadar(true)
arsonist:SetCanCoordinate(true)
arsonist:SetAlliedTeams(allyTeams)
arsonist:SetCanSnipe(false)
arsonist:SetCanHide(true)
arsonist:SetLovesTeammates(true)
arsonist:SetAutoSwitch(false)
arsonist:SetPreferredWeapon("weapon_ttt2_arsonthrower")
TTTBots.Roles.RegisterRole(arsonist)

--- Arsonist always has bodyBurner trait.
local origGetTraitBool = FindMetaTable("Player").GetTraitBool
if origGetTraitBool then
    FindMetaTable("Player").GetTraitBool = function(self, attribute, falseHasPriority)
        if attribute == "bodyBurner" and IsValid(self) and self:IsBot() then
            local roleStr = self.GetRoleStringRaw and self:GetRoleStringRaw()
            if roleStr == "arsonist" then
                return true
            end
        end
        return origGetTraitBool(self, attribute, falseHasPriority)
    end
end

--- Add "arsonist" to the FlareGun buyable so they can purchase it.
timer.Simple(0, function()
    local registry = TTTBots.Buyables and TTTBots.Buyables.Registry
    if registry and registry.FlareGun and registry.FlareGun.Roles then
        table.insert(registry.FlareGun.Roles, "arsonist")
    end
end)

return true
