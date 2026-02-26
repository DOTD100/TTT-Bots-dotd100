--- Arsonist role definition.
--- The Arsonist uses a flamethrower (weapon_ttt2_arsonthrower) as their primary
--- weapon, holding fire to spray targets at close range. After kills, they use
--- the standard flare gun to burn corpses and destroy evidence.
if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_ARSONIST then return false end

TEAM_JESTER = TEAM_JESTER or "jesters"

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Custom FightBack that prefers the flamethrower, falling back to normal attack
local ArsonistFightBack = {
    _bh.ClearBreakables,
    _bh.ArsonistAttack,     -- Spray with flamethrower
    _bh.AttackTarget,        -- Fallback if no flamethrower
}

local bTree = {
    ArsonistFightBack,
    _bh.BurnCorpse,          -- Burn victim corpses with flare gun
    _bh.PlantBomb,
    _bh.UseTraitorTrap,      -- Activate map traitor traps when non-allies are nearby
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
arsonist:SetStartsFights(true)          -- Will attack non-allies
arsonist:SetTeam(TEAM_TRAITOR)
arsonist:SetUsesSuspicion(false)        -- Traitor team, knows who's who
arsonist:SetBTree(bTree)
arsonist:SetCanHaveRadar(true)
arsonist:SetCanCoordinate(true)         -- Can participate in traitor plans
arsonist:SetAlliedTeams(allyTeams)
arsonist:SetCanSnipe(false)             -- Flamethrower is close-range only
arsonist:SetCanHide(true)               -- Can ambush from hiding spots
arsonist:SetLovesTeammates(true)
arsonist:SetAutoSwitch(false)           -- Keep the flamethrower equipped
arsonist:SetPreferredWeapon("weapon_ttt2_arsonthrower")
TTTBots.Roles.RegisterRole(arsonist)

--- Make Arsonist bots always report bodyBurner = true so BurnCorpse behavior
--- activates without needing the random bodyBurner trait.
local origGetTraitBool = FindMetaTable("Player").GetTraitBool
if origGetTraitBool then
    FindMetaTable("Player").GetTraitBool = function(self, attribute, falseHasPriority)
        -- Arsonist always has bodyBurner
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
