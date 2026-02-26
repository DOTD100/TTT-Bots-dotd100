--- Copycat role support for TTT Bots 2.
--- The Copycat is a 3rd-party neutral killer who carries "The Copycat Files",
--- a special weapon that records the roles of corpses they investigate.
--- After investigating a corpse, the Copycat can use The Files to change
--- into that dead player's role.
---
--- Addon: https://github.com/AaronMcKenney/ttt2-role_copy
--- Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=2862417222
---
--- Bot strategy:
---   PRE-CONVERSION: The Copycat is a neutral killer. Their #1 priority is
---     finding and investigating corpses to learn roles, then using The Copycat
---     Files weapon to transform into a powerful role (preferably traitor or
---     detective for shop access). They fight to survive but will actively
---     seek corpses. They trust no one.
---   POST-CONVERSION: Once the bot uses The Files and changes role, the
---     TTT2UpdateSubrole hook fires and GetRoleFor() dynamically reads the
---     new role, so the behavior tree automatically switches.
---
--- The Copycat Files weapon (weapon_ttt2_copycatfiles) has a SWEP:UseFiles()
--- method that opens a VGUI menu for humans. For bots, we automate the role
--- selection by calling the weapon's role-change function directly.

if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_COPYCAT then return false end

TEAM_NONE = TEAM_NONE or "none"

local lib = TTTBots.Lib

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Behavior tree: Neutral killer that aggressively investigates corpses.
--- InvestigateCorpse is high priority so the bot seeks bodies to learn roles.
--- Stalk is used to find and kill targets for more corpses.
--- Once converted, the tree swaps automatically via GetRoleFor().
local bTree = {
    _prior.FightBack,               -- Defend self if attacked
    _prior.Restore,                 -- Pick up weapons, health
    { _bh.Interact },              -- Interact with the world
    { _bh.InvestigateCorpse },     -- HIGH PRIORITY: find and inspect corpses
    { _bh.InvestigateNoise },      -- Investigate suspicious sounds
    { _bh.Stalk },                 -- Hunt targets — need corpses to learn from
    _prior.Minge,                  -- Some minging
    _prior.Patrol                  -- Patrol the map looking for corpses/targets
}

--- The Copycat has no allies — they're a lone neutral killer.
local copycat = TTTBots.RoleData.New("copycat", TEAM_NONE)
copycat:SetDefusesC4(false)
copycat:SetPlantsC4(false)
copycat:SetCanCoordinate(false)             -- Lone wolf, no team coordination
copycat:SetStartsFights(true)               -- Neutral killer — initiates fights
copycat:SetTeam(TEAM_NONE)
copycat:SetUsesSuspicion(false)             -- Doesn't track suspicion — kills everyone
copycat:SetKnowsLifeStates(false)
copycat:SetBTree(bTree)
copycat:SetAlliedTeams({})                  -- No allied teams
copycat:SetAlliedRoles({})                  -- No allied roles
copycat:SetLovesTeammates(false)
copycat:SetCanSnipe(true)
copycat:SetCanHide(true)                    -- Can ambush
TTTBots.Roles.RegisterRole(copycat)

---------------------------------------------------------------------------
-- Override InvestigateCorpse validation for Copycat bots:
-- Copycats should ALWAYS investigate visible corpses since that's how they
-- learn roles to transform into.
---------------------------------------------------------------------------

local function IsCopycat(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    local ok, role = pcall(ply.GetSubRole, ply)
    return ok and role == ROLE_COPYCAT
end

--- Make Copycat bots always investigate corpses.
local originalGetShould = TTTBots.Behaviors.InvestigateCorpse.GetShouldInvestigateCorpses
if originalGetShould then
    TTTBots.Behaviors.InvestigateCorpse.GetShouldInvestigateCorpses = function(bot)
        if IsCopycat(bot) then
            return true -- Always investigate — need to learn roles from corpses
        end
        return originalGetShould(bot)
    end
end

---------------------------------------------------------------------------
-- Automated role selection: After the Copycat investigates a corpse, the
-- Copycat Files weapon records the role. We periodically check if the bot
-- has roles available in The Files and trigger a role change.
--
-- The bot prefers roles in this order:
--   1. Traitor (or traitor subroles) — strong combat + shop access
--   2. Detective (or detective subroles) — shop access + trusted status
--   3. Any other role that has shop access
--   4. Any combat role
--
-- We look for weapon_ttt2_copycatfiles and invoke its transformation.
---------------------------------------------------------------------------

--- Preferred roles for transformation, ordered by priority.
--- The bot picks the first available match from this list.
local PREFERRED_ROLES = {}

--- Build the preferred roles list at round start when role globals are available.
local function BuildPreferredRoles()
    PREFERRED_ROLES = {}
    -- Traitor-team roles (best for a killer)
    if ROLE_TRAITOR then table.insert(PREFERRED_ROLES, ROLE_TRAITOR) end
    -- Detective-team roles (shop + trusted)
    if ROLE_DETECTIVE then table.insert(PREFERRED_ROLES, ROLE_DETECTIVE) end
    -- Other useful roles
    if ROLE_JACKAL then table.insert(PREFERRED_ROLES, ROLE_JACKAL) end
    if ROLE_SERIALKILLER then table.insert(PREFERRED_ROLES, ROLE_SERIALKILLER) end
    if ROLE_HITMAN then table.insert(PREFERRED_ROLES, ROLE_HITMAN) end
end

hook.Add("TTTBeginRound", "TTTBots.copycat.buildPreferred", BuildPreferredRoles)

--- Returns the Copycat Files weapon if the bot has it.
local function GetCopycatFiles(bot)
    if not (IsValid(bot) and bot:IsPlayer()) then return nil end
    for _, wep in pairs(bot:GetWeapons()) do
        if IsValid(wep) and wep:GetClass() == "weapon_ttt2_copycatfiles" then
            return wep
        end
    end
    return nil
end

--- Returns the list of available roles from The Copycat Files weapon.
--- The addon stores discovered roles on the weapon entity.
local function GetAvailableRoles(filesWep)
    if not IsValid(filesWep) then return {} end
    -- The Copycat Files addon stores roles in filesWep.roles or similar.
    -- Check common storage patterns used by the addon.
    if filesWep.roles and istable(filesWep.roles) then
        return filesWep.roles
    end
    if filesWep.GetRoles and isfunction(filesWep.GetRoles) then
        return filesWep:GetRoles()
    end
    if filesWep.copy_roles and istable(filesWep.copy_roles) then
        return filesWep.copy_roles
    end
    return {}
end

--- Pick the best role from available options.
local function PickBestRole(availableRoles)
    if #availableRoles == 0 then return nil end

    -- Try preferred roles first
    for _, preferred in ipairs(PREFERRED_ROLES) do
        for _, available in ipairs(availableRoles) do
            local roleIdx = available
            -- Handle if it's stored as a table entry with an index field
            if istable(available) then
                roleIdx = available.index or available.role or available[1]
            end
            if roleIdx == preferred then
                return roleIdx
            end
        end
    end

    -- No preferred role found — just pick the first available
    local first = availableRoles[1]
    if istable(first) then
        return first.index or first.role or first[1]
    end
    return first
end

--- Attempt to transform the bot using The Copycat Files.
local function TryTransform(bot, filesWep, targetRole)
    if not (IsValid(bot) and IsValid(filesWep)) then return false end
    if not targetRole then return false end

    -- Try the addon's built-in role change function
    if filesWep.ChangeRole and isfunction(filesWep.ChangeRole) then
        filesWep:ChangeRole(targetRole)
        return true
    end

    -- Alternative: some versions use SetRole or SelectRole
    if filesWep.SelectRole and isfunction(filesWep.SelectRole) then
        filesWep:SelectRole(targetRole)
        return true
    end

    -- Fallback: directly invoke the TTT2 role change system
    -- This mimics what the VGUI menu does when a human clicks a role
    if bot.SetRole then
        local roleData = roles.GetByIndex(targetRole)
        if roleData then
            bot:SetRole(targetRole)
            if bot.UpdateTeam and roleData.defaultTeam then
                bot:UpdateTeam(roleData.defaultTeam)
            end
            SendFullStateUpdate()
            return true
        end
    end

    return false
end

---------------------------------------------------------------------------
-- Periodic think hook: check if a Copycat bot has roles available in
-- The Files and trigger transformation.
---------------------------------------------------------------------------

local nextCopycatThink = 0
local THINK_INTERVAL = 3 -- Check every 3 seconds

hook.Add("Think", "TTTBots.copycat.autoTransform", function()
    local curTime = CurTime()
    if curTime < nextCopycatThink then return end
    nextCopycatThink = curTime + THINK_INTERVAL

    if not TTTBots.Match.IsRoundActive() then return end

    for _, bot in pairs(TTTBots.Bots) do
        if not (IsValid(bot) and bot:IsBot() and lib.IsPlayerAlive(bot)) then continue end
        if not IsCopycat(bot) then continue end

        -- Check cooldown — don't spam role changes
        if (bot.tttbots_copycatLastChange or 0) > curTime then continue end

        local filesWep = GetCopycatFiles(bot)
        if not filesWep then continue end

        local available = GetAvailableRoles(filesWep)
        if #available == 0 then continue end

        local bestRole = PickBestRole(available)
        if not bestRole then continue end

        -- Add a small random delay so bots don't all transform at once
        local delay = math.random(2, 8)
        bot.tttbots_copycatLastChange = curTime + delay

        timer.Simple(delay, function()
            if not (IsValid(bot) and IsCopycat(bot) and lib.IsPlayerAlive(bot)) then return end

            local success = TryTransform(bot, filesWep, bestRole)
            if success then
                -- Announce transformation
                local chatter = bot:BotChatter()
                if chatter then
                    chatter:On("CopycatTransformed", {}, false)
                end
            end
        end)
    end
end)

---------------------------------------------------------------------------
-- Role conversion cleanup: when the Copycat changes role via The Files,
-- TTT2UpdateSubrole fires. Clean up leftover state.
---------------------------------------------------------------------------

hook.Add("TTT2UpdateSubrole", "TTTBots.copycat.conversion", function(ply, oldRole, newRole)
    if not (IsValid(ply) and ply:IsBot()) then return end
    if oldRole ~= ROLE_COPYCAT then return end
    if newRole == ROLE_COPYCAT then return end -- No change

    -- Clear investigation state
    ply.corpseTarget = nil

    -- Clear attack targets — fresh start with new role
    if ply.attackTarget then
        ply:SetAttackTarget(nil)
    end
end)

return true
