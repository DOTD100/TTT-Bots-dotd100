--- Amnesiac role support for TTT Bots 2.
--- The Amnesiac starts on the innocent team but doesn't know their true role.
--- They must confirm a dead player's body to transform into that dead player's
--- role. The confirmation (not just inspection) triggers the transformation,
--- which is handled automatically by the Amnesiac addon.
---
--- Addon: https://github.com/TTT-2/ttt2-role_amne
--- Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=2001213453
---
--- Bot strategy:
---   PRE-CONVERSION: Aggressively seek out and confirm corpses. The Amnesiac's
---     #1 priority is finding a body to confirm ASAP, since they are essentially
---     roleless until then. The existing InvestigateCorpse behavior handles the
---     actual confirmation (CORPSE.ShowSearch + CORPSE.SetFound).
---   POST-CONVERSION: The addon fires TTT2UpdateSubrole, and GetRoleFor()
---     dynamically reads the new role, so the behavior tree automatically
---     switches to the new role's tree.

if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_AMNESIAC then return false end

TEAM_INNOCENT = TEAM_INNOCENT or "innocents"

local lib = TTTBots.Lib

--- The Amnesiac is on TEAM_INNOCENT and allied with innocents pre-conversion.
local allyTeams = {
    [TEAM_INNOCENT] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Behavior tree: The Amnesiac wants to find and confirm corpses above all else.
--- InvestigateCorpse is placed at HIGH priority (before Minge/Patrol) so the
--- bot actively seeks bodies. Once confirmed, the addon converts the role and
--- the behavior tree swaps automatically via GetRoleFor().
local bTree = {
    _prior.FightBack,           -- Defend self if attacked
    { _bh.Defuse },             -- Still defuse C4 as a good innocent
    _prior.Restore,             -- Pick up weapons, health
    { _bh.Interact },           -- Interact with the world
    { _bh.InvestigateCorpse },  -- HIGH PRIORITY: find and confirm bodies
    { _bh.InvestigateNoise },   -- Investigate suspicious sounds
    _prior.Minge,               -- Some minging
    _prior.Patrol               -- Patrol the map looking for bodies
}

local amnesiac = TTTBots.RoleData.New("amnesiac", TEAM_INNOCENT)
amnesiac:SetDefusesC4(true)                 -- Act as a good innocent pre-conversion
amnesiac:SetPlantsC4(false)
amnesiac:SetCanCoordinate(false)            -- Can't coordinate — doesn't know their role
amnesiac:SetStartsFights(false)             -- Doesn't initiate fights pre-conversion
amnesiac:SetTeam(TEAM_INNOCENT)
amnesiac:SetUsesSuspicion(true)             -- Track suspicion like a normal innocent
amnesiac:SetKnowsLifeStates(false)
amnesiac:SetBTree(bTree)
amnesiac:SetAlliedTeams(allyTeams)
amnesiac:SetLovesTeammates(true)            -- Standard innocent team loyalty
amnesiac:SetCanSnipe(false)                 -- Don't snipe — focus on finding bodies
amnesiac:SetCanHide(false)
TTTBots.Roles.RegisterRole(amnesiac)

---------------------------------------------------------------------------
-- Override InvestigateCorpse validation for Amnesiac bots:
-- Normal bots have a random chance to investigate corpses (75% base).
-- Amnesiac bots should ALWAYS investigate visible corpses since that's
-- their primary objective. We boost this via personality trait override.
---------------------------------------------------------------------------

--- Returns true if the player is currently an Amnesiac (pre-conversion).
local function IsAmnesiac(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    local ok, role = pcall(ply.GetSubRole, ply)
    return ok and role == ROLE_AMNESIAC
end

--- Make Amnesiac bots always want to investigate corpses by forcing high
--- probability. We hook into the corpse validation at a higher level —
--- the InvestigateCorpse behavior checks GetShouldInvestigateCorpses which
--- rolls a dice. For Amnesiac bots, we override this to always return true.
local originalGetShould = TTTBots.Behaviors.InvestigateCorpse.GetShouldInvestigateCorpses
TTTBots.Behaviors.InvestigateCorpse.GetShouldInvestigateCorpses = function(bot)
    if IsAmnesiac(bot) then
        return true -- Always investigate — this is the Amnesiac's primary goal
    end
    return originalGetShould(bot)
end

---------------------------------------------------------------------------
-- Role conversion cleanup: when the Amnesiac confirms a body, the addon
-- transforms them via TTT2UpdateSubrole. We clean up any leftover state
-- so the new role starts fresh.
---------------------------------------------------------------------------

hook.Add("TTT2UpdateSubrole", "TTTBots.amnesiac.conversion", function(ply, oldRole, newRole)
    if not (IsValid(ply) and ply:IsBot()) then return end
    if oldRole ~= ROLE_AMNESIAC then return end
    if newRole == ROLE_AMNESIAC then return end -- No change

    -- Clear investigation state
    ply.corpseTarget = nil

    -- Clear any attack targets — fresh start with new role
    if ply.attackTarget then
        ply:SetAttackTarget(nil)
    end

    -- Announce in chat that we transformed
    local chatter = ply:BotChatter()
    if chatter then
        chatter:On("AmnesiacTransformed", {}, false)
    end
end)

return true
