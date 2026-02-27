--- Copycat role support for TTT Bots 2.

if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_COPYCAT then return false end

TEAM_NONE = TEAM_NONE or "none"

local lib = TTTBots.Lib

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

local bTree = {
    _prior.FightBack,
    _prior.Restore,
    { _bh.Interact },
    { _bh.InvestigateCorpse },
    { _bh.InvestigateNoise },
    { _bh.Stalk },
    _prior.Minge,
    _prior.Patrol
}

local copycat = TTTBots.RoleData.New("copycat", TEAM_NONE)
copycat:SetDefusesC4(false)
copycat:SetPlantsC4(false)
copycat:SetCanCoordinate(false)
copycat:SetStartsFights(true)
copycat:SetTeam(TEAM_NONE)
copycat:SetUsesSuspicion(false)
copycat:SetKnowsLifeStates(false)
copycat:SetBTree(bTree)
copycat:SetAlliedTeams({})
copycat:SetAlliedRoles({})
copycat:SetLovesTeammates(false)
copycat:SetCanSnipe(true)
copycat:SetCanHide(true)
TTTBots.Roles.RegisterRole(copycat)

-- Copycats always investigate corpses to learn roles.

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
            return true
        end
        return originalGetShould(bot)
    end
end

-- Automated role selection from The Copycat Files.

local PREFERRED_ROLES = {}

--- Build preferred roles list at round start.
local function BuildPreferredRoles()
    PREFERRED_ROLES = {}
    if ROLE_TRAITOR then table.insert(PREFERRED_ROLES, ROLE_TRAITOR) end
    if ROLE_DETECTIVE then table.insert(PREFERRED_ROLES, ROLE_DETECTIVE) end
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

--- Returns available roles from The Copycat Files weapon.
local function GetAvailableRoles(filesWep)
    if not IsValid(filesWep) then return {} end
    -- Check common storage patterns
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

    -- Try the addon's role change methods
    if filesWep.ChangeRole and isfunction(filesWep.ChangeRole) then
        filesWep:ChangeRole(targetRole)
        return true
    end

    if filesWep.SelectRole and isfunction(filesWep.SelectRole) then
        filesWep:SelectRole(targetRole)
        return true
    end

    -- Fallback: TTT2 role change
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

local nextCopycatThink = 0
local THINK_INTERVAL = 3

hook.Add("Think", "TTTBots.copycat.autoTransform", function()
    local curTime = CurTime()
    if curTime < nextCopycatThink then return end
    nextCopycatThink = curTime + THINK_INTERVAL

    if not TTTBots.Match.IsRoundActive() then return end

    for _, bot in pairs(TTTBots.Bots) do
        if not (IsValid(bot) and bot:IsBot() and lib.IsPlayerAlive(bot)) then continue end
        if not IsCopycat(bot) then continue end

        if (bot.tttbots_copycatLastChange or 0) > curTime then continue end

        local filesWep = GetCopycatFiles(bot)
        if not filesWep then continue end

        local available = GetAvailableRoles(filesWep)
        if #available == 0 then continue end

        local bestRole = PickBestRole(available)
        if not bestRole then continue end

        -- Stagger transforms so bots don't all change at once
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

-- Clean up state when Copycat transforms.
hook.Add("TTT2UpdateSubrole", "TTTBots.copycat.conversion", function(ply, oldRole, newRole)
    if not (IsValid(ply) and ply:IsBot()) then return end
    if oldRole ~= ROLE_COPYCAT then return end
    if newRole == ROLE_COPYCAT then return end

    ply.corpseTarget = nil

    if ply.attackTarget then
        ply:SetAttackTarget(nil)
    end
end)

return true
