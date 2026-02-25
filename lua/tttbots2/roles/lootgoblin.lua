--- Loot Goblin role support for TTT Bots 2.
--- Neutral role that is smaller and faster than everyone else but cannot deal
--- damage. The Loot Goblin wins if they survive to round end, and loses if
--- they die. When killed, they drop random traitor shop weapons as loot.
---
--- Addon: https://github.com/sipcogames/ttt2-role_lootgoblin
--- Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=2710196952
---
--- Bot strategy:
---   AS the Loot Goblin: Pure survival — flee from everyone, hide, avoid combat.
---   AGAINST the Loot Goblin: High-priority target — everyone wants the loot.
---     The Loot Goblin overrides Jester protection so bots WILL attack them.

if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_LOOTGOBLIN then return false end

TEAM_JESTER = TEAM_JESTER or "jesters"

local lib = TTTBots.Lib

--- The Loot Goblin has no real allies — everyone is a threat.
--- We list TEAM_JESTER so it doesn't attack other Jester-team roles.
local allyTeams = {
    [TEAM_JESTER] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

--- Behavior tree: The Loot Goblin wants to survive above all else.
--- FightBack first so it flees when attacked (cannot deal damage).
--- Then hide and stay away from everyone.
local bTree = {
    _prior.FightBack,           -- Flee when attacked (cannot deal damage)
    _prior.Restore,             -- Pick up weapons (look normal, minor benefit)
    _prior.Minge,               -- Occasional minging
    _prior.Investigate,         -- Investigate noises (stay aware of surroundings)
    _prior.Patrol               -- Patrol remote areas — keep moving to stay alive
}

local lootgoblin = TTTBots.RoleData.New("lootgoblin", TEAM_JESTER)
lootgoblin:SetDefusesC4(false)
lootgoblin:SetPlantsC4(false)
lootgoblin:SetCanCoordinate(false)          -- No team to coordinate with
lootgoblin:SetStartsFights(false)           -- Cannot deal damage
lootgoblin:SetTeam(TEAM_JESTER)
lootgoblin:SetUsesSuspicion(false)          -- Neutral, no suspicion tracking
lootgoblin:SetKnowsLifeStates(false)
lootgoblin:SetBTree(bTree)
lootgoblin:SetAlliedTeams(allyTeams)
lootgoblin:SetLovesTeammates(false)
lootgoblin:SetCanSnipe(false)               -- Cannot deal damage
lootgoblin:SetCanHide(true)                 -- Wants to HIDE — survival is the goal
TTTBots.Roles.RegisterRole(lootgoblin)

---------------------------------------------------------------------------
-- Loot Goblin is a PRIORITY TARGET for all bots.
-- Override Jester protection so bots will actively hunt the Loot Goblin.
---------------------------------------------------------------------------

--- Returns true if the player is a Loot Goblin.
local function IsLootGoblin(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    local ok, role = pcall(ply.GetRoleStringRaw, ply)
    return ok and role == "lootgoblin"
end

--- Override Jester protection: allow attacks on Loot Goblins.
--- This hook runs BEFORE the jester.lua protection hook because hook.Add
--- with a different name fires in registration order. We use a very early
--- return to explicitly allow attacking the Loot Goblin.
--- Note: TTTBotsCanAttack returns false to block, true/nil to allow.
hook.Add("TTTBotsCanAttack", "TTTBots.lootgoblin.allowAttack", function(bot, target)
    if IsLootGoblin(target) then
        return true -- Explicitly allow — overrides Jester protection
    end
end)

--- Actively hunt the Loot Goblin: periodically check if any bot can see a
--- Loot Goblin and doesn't already have a target, then set them to attack.
--- This makes the Loot Goblin a high-priority target that bots pursue on sight.
timer.Create("TTTBots.LootGoblin.HuntTarget", 1, 0, function()
    if not TTTBots.Match.IsRoundActive() then return end

    -- Find all living Loot Goblins
    local goblins = {}
    for _, ply in ipairs(TTTBots.Match.AlivePlayers or {}) do
        if IsValid(ply) and IsLootGoblin(ply) then
            goblins[#goblins + 1] = ply
        end
    end
    if #goblins == 0 then return end

    for _, bot in pairs(TTTBots.Bots) do
        if not (IsValid(bot) and lib.IsPlayerAlive(bot)) then continue end
        if bot.attackTarget ~= nil then continue end -- Already fighting someone

        -- Don't make Loot Goblin bots hunt other Loot Goblins
        if IsLootGoblin(bot) then continue end

        -- Find the closest visible Loot Goblin
        for _, goblin in ipairs(goblins) do
            if not IsValid(goblin) then continue end
            if not lib.IsPlayerAlive(goblin) then continue end
            local dist = bot:GetPos():Distance(goblin:GetPos())
            if dist < 1500 and lib.CanSeeArc(bot, goblin:EyePos(), 90) then
                bot:SetAttackTarget(goblin)
                break
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Loot Goblin bot: flee from nearby players.
-- The Loot Goblin should treat every nearby player as a threat and run.
-- We simulate this by giving the Loot Goblin bot a fake "attacker" when
-- players get close, triggering FightBack (flee behavior).
---------------------------------------------------------------------------

timer.Create("TTTBots.LootGoblin.FleeNearby", 0.5, 0, function()
    if not TTTBots.Match.IsRoundActive() then return end

    for _, bot in pairs(TTTBots.Bots) do
        if not (IsValid(bot) and lib.IsPlayerAlive(bot)) then continue end
        if not IsLootGoblin(bot) then continue end

        -- If the bot already has an attack target (fleeing from someone), skip
        if bot.attackTarget ~= nil then continue end

        -- Find the nearest visible player and flee from them
        local FLEE_RADIUS = 600
        local closestDist = math.huge
        local closestPly = nil

        for _, ply in ipairs(TTTBots.Match.AlivePlayers or {}) do
            if not IsValid(ply) then continue end
            if ply == bot then continue end
            if not lib.IsPlayerAlive(ply) then continue end

            local dist = bot:GetPos():Distance(ply:GetPos())
            if dist < FLEE_RADIUS and dist < closestDist then
                if lib.CanSeeArc(bot, ply:EyePos(), 120) then
                    closestDist = dist
                    closestPly = ply
                end
            end
        end

        if closestPly then
            -- Simulate being under attack to trigger FightBack (flee)
            bot.lastHurtTime = CurTime()
            bot:SetAttackTarget(closestPly)
        end
    end
end)

return true
