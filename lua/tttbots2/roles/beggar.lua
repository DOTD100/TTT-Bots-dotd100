if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_BEGGAR then return false end

TEAM_JESTER = TEAM_JESTER or "jesters"

local allyTeams = {
    [TEAM_JESTER] = true,
    [TEAM_TRAITOR] = true, -- Traitors know Beggar is Jester-team, won't attack
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Pre-conversion behavior tree: passive Jester-like behavior.
--- BeggarScavenge is the primary behavior: find and pick up shop items.
--- Fallback is innocent-like patrol/investigate (to blend in).
--- Does no damage, doesn't start fights.
local bTreePreConvert = {
    _bh.BeggarScavenge,         -- PRIMARY: seek and pick up dropped shop items
    _prior.Restore,             -- Pick up weapons / heal (also finds items on ground)
    _bh.Interact,               -- Use map interactables (look busy)
    _prior.Minge,               -- Minge occasionally (jester-like)
    _prior.Investigate,         -- Investigate noises (blend in)
    _prior.Patrol               -- Patrol / wander
    -- NOTE: No FightBack, no Stalk, no AttackTarget — Beggar does no damage pre-conversion
}

local beggar = TTTBots.RoleData.New("beggar", TEAM_JESTER)
beggar:SetDefusesC4(false)
beggar:SetPlantsC4(false)
beggar:SetCanHaveRadar(false)
beggar:SetCanCoordinate(false)         -- Solo until converted
beggar:SetStartsFights(false)          -- Does no damage as Beggar
beggar:SetTeam(TEAM_JESTER)
beggar:SetUsesSuspicion(false)
beggar:SetKnowsLifeStates(false)
beggar:SetBTree(bTreePreConvert)
beggar:SetAlliedTeams(allyTeams)
beggar:SetLovesTeammates(false)
beggar:SetCanSnipe(false)
beggar:SetCanHide(false)
TTTBots.Roles.RegisterRole(beggar)

---------------------------------------------------------------------------
-- Dynamic conversion: detect when the Beggar's team changes.
-- The Beggar addon changes the player's team when they pick up a shop item.
-- We detect this and set a PER-BOT btree override so that only the converted
-- bot changes behavior — other Beggars keep the pre-conversion tree.
--
-- The override is stored on bot.tttbots_btreeOverride and checked by a hook
-- on GetTreeFor (via TTTBots.Behaviors.GetTreeFor patching below).
---------------------------------------------------------------------------

local function GetInnocentTree()
    return {
        _prior.FightBack,
        _bh.Defuse,
        _bh.InvestigateCorpse,
        _prior.Restore,
        _prior.Minge,
        _prior.Investigate,
        _prior.Patrol
    }
end

local function GetTraitorTree()
    return {
        _prior.FightBack,
        _bh.Stalk,
        _bh.PlantBomb,
        _bh.UseTraitorTrap,
        _bh.Defib,
        _prior.Restore,
        _bh.FollowPlan,
        _bh.Interact,
        _prior.Minge,
        _prior.Investigate,
        _prior.Patrol
    }
end

--- Patch GetTreeFor to check for a per-bot override first.
--- This is safe to call multiple times; the original only gets saved once.
local origGetTreeFor = TTTBots.Behaviors._origGetTreeFor or TTTBots.Behaviors.GetTreeFor
TTTBots.Behaviors._origGetTreeFor = origGetTreeFor

function TTTBots.Behaviors.GetTreeFor(bot)
    if bot.tttbots_btreeOverride then
        return bot.tttbots_btreeOverride
    end
    return origGetTreeFor(bot)
end

--- Periodically check if any Beggar bots have had their team changed by the addon.
--- When detected, set a per-bot btree override (does NOT touch the shared role data).
hook.Add("Think", "TTTBots.Beggar.ConversionCheck", function()
    if not TTTBots.Match.IsRoundActive() then return end

    -- Throttle: check once per second
    local now = CurTime()
    if (TTTBots._beggarLastCheck or 0) + 1 > now then return end
    TTTBots._beggarLastCheck = now

    for _, bot in ipairs(player.GetBots()) do
        if not (IsValid(bot) and bot:IsPlayer()) then continue end
        if not (bot.GetSubRole and bot:GetSubRole() == ROLE_BEGGAR) then continue end

        local team = bot:GetTeam()
        -- Pre-conversion: Beggar has unknownTeam=true so GetTeam() returns
        -- TEAM_NONE, not TEAM_JESTER. Check for both.
        if team == TEAM_JESTER or team == "jesters" or team == TEAM_NONE or team == "none" then continue end

        -- Already handled this conversion?
        if bot.beggarConvertedTeam == team then continue end
        bot.beggarConvertedTeam = team

        if team == TEAM_TRAITOR then
            bot.tttbots_btreeOverride = GetTraitorTree()
            print(string.format("[TTT Bots 2] Beggar %s converted to TRAITOR team!", bot:Nick()))
        else
            bot.tttbots_btreeOverride = GetInnocentTree()
            print(string.format("[TTT Bots 2] Beggar %s converted to %s team!", bot:Nick(), team))
        end
    end
end)

--- Reset per-bot overrides each round (shared role data stays untouched).
hook.Add("TTTBeginRound", "TTTBots.Beggar.RoundReset", function()
    for _, bot in ipairs(player.GetBots()) do
        bot.beggarConvertedTeam = nil
        bot.beggarConverted = nil
        bot.tttbots_btreeOverride = nil
    end
end)

return true
