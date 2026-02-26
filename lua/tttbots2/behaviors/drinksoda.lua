--- Behavior: DrinkSoda
--- Bots seek out and drink super soda cans (ttt2-super-soda addon).
--- Sodas are entities whose class contains "super_soda" spawned in the world.
--- Bots walk to them, look down at the can, and call entity:Use(bot) to drink.
--- Respects the max-sodas-per-player convar so bots don't exceed the limit.
---
--- Super soda cans spawn at round start by replacing ammo entities.
--- We cache all soda locations shortly after round start so bots know
--- where to find them, then verify the entity still exists when approaching.

TTTBots.Behaviors.DrinkSoda = {}

local lib = TTTBots.Lib

local DrinkSoda = TTTBots.Behaviors.DrinkSoda
DrinkSoda.Name = "DrinkSoda"
DrinkSoda.Description = "Find and drink a super soda can"
DrinkSoda.Interruptible = true
DrinkSoda.UseRange = 64          --- Units within which we call Use
DrinkSoda.MaxSearchDist = 2000   --- Don't travel further than this

local STATUS = TTTBots.STATUS

---------------------------------------------------------------------------
-- Soda location cache — populated once after round starts
---------------------------------------------------------------------------

--- All known soda entity references and their spawn positions.
--- { ent = Entity, pos = Vector }
DrinkSoda.KnownSodas = {}

--- Scans the map for all super soda entities and caches them.
function DrinkSoda.CacheSodaLocations()
    DrinkSoda.KnownSodas = {}

    -- Primary class pattern
    local sodas = ents.FindByClass("ttt_super_soda*")

    -- Broader fallback for forks with non-standard naming
    if #sodas == 0 then
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and string.find(ent:GetClass(), "super_soda", 1, true) then
                sodas[#sodas + 1] = ent
            end
        end
    end

    for _, ent in ipairs(sodas) do
        if IsValid(ent) then
            table.insert(DrinkSoda.KnownSodas, {
                ent = ent,
                pos = ent:GetPos(),
            })
        end
    end
end

---------------------------------------------------------------------------
-- Convar: max sodas per player (cached)
---------------------------------------------------------------------------

local cachedMaxConvar = nil
local convarLookedUp = false

function DrinkSoda.GetMaxSodas()
    if not convarLookedUp then
        convarLookedUp = true
        local names = {
            "ttt_super_soda_max_cans",
            "ttt2_super_soda_max_cans",
            "ttt_super_soda_max_per_player",
            "ttt_super_soda_max",
        }
        for _, name in ipairs(names) do
            local cv = GetConVar(name)
            if cv then
                cachedMaxConvar = cv
                break
            end
        end
    end
    if cachedMaxConvar then return cachedMaxConvar:GetInt() end
    return 0 -- not found → treat as unlimited
end

function DrinkSoda.CanDrinkMore(bot)
    local max = DrinkSoda.GetMaxSodas()
    if max <= 0 then return true end
    return (bot.tttbots_sodasDrunk or 0) < max
end

---------------------------------------------------------------------------
-- Entity detection
---------------------------------------------------------------------------

function DrinkSoda.IsValidSoda(ent)
    if not IsValid(ent) then return false end
    local cls = ent:GetClass()
    return string.find(cls, "super_soda", 1, true) ~= nil
end

--- Find the nearest valid soda from the cached locations.
---@param bot Bot
---@return Entity|nil, number
function DrinkSoda.FindNearestSoda(bot)
    local botPos = bot:GetPos()
    local best = nil
    local bestDistSqr = math.huge
    local maxDistSqr = DrinkSoda.MaxSearchDist * DrinkSoda.MaxSearchDist

    -- First try from cached locations
    for i = #DrinkSoda.KnownSodas, 1, -1 do
        local entry = DrinkSoda.KnownSodas[i]
        if not DrinkSoda.IsValidSoda(entry.ent) then
            -- Soda was consumed or removed — clean from cache
            table.remove(DrinkSoda.KnownSodas, i)
        else
            local d = botPos:DistToSqr(entry.pos)
            if d < bestDistSqr and d < maxDistSqr then
                bestDistSqr = d
                best = entry.ent
            end
        end
    end

    -- Fallback: refresh cache once if we missed, don't scan every tick
    if not best and not DrinkSoda._cacheRefreshedThisRound then
        DrinkSoda._cacheRefreshedThisRound = true
        DrinkSoda.CacheSodaLocations()
        -- Retry with refreshed cache
        for _, entry in ipairs(DrinkSoda.KnownSodas) do
            if not DrinkSoda.IsValidSoda(entry.ent) then continue end
            local d = botPos:DistToSqr(entry.pos)
            if d < bestDistSqr and d < maxDistSqr then
                bestDistSqr = d
                best = entry.ent
            end
        end
    end

    return best, best and math.sqrt(bestDistSqr) or math.huge
end

---------------------------------------------------------------------------
-- Behavior callbacks
---------------------------------------------------------------------------

function DrinkSoda.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not IsValid(bot) then return false end
    if not lib.IsPlayerAlive(bot) then return false end
    if bot.attackTarget ~= nil then return false end -- fighting takes priority

    if not DrinkSoda.CanDrinkMore(bot) then return false end

    -- Already have a valid target?
    if bot.tttbots_sodaTarget and IsValid(bot.tttbots_sodaTarget)
        and DrinkSoda.IsValidSoda(bot.tttbots_sodaTarget) then
        return true
    end

    -- Throttle scanning to once every few seconds
    if (bot.tttbots_sodaNextScan or 0) > CurTime() then return false end
    bot.tttbots_sodaNextScan = CurTime() + 3

    local soda = DrinkSoda.FindNearestSoda(bot)
    if soda then
        bot.tttbots_sodaTarget = soda
        return true
    end

    return false
end

function DrinkSoda.OnStart(bot)
    return STATUS.RUNNING
end

function DrinkSoda.OnRunning(bot)
    local loco = bot:BotLocomotor()
    if not loco then return STATUS.FAILURE end

    if not DrinkSoda.CanDrinkMore(bot) then
        return STATUS.SUCCESS
    end

    local target = bot.tttbots_sodaTarget
    if not (target and IsValid(target) and DrinkSoda.IsValidSoda(target)) then
        bot.tttbots_sodaTarget = nil
        return STATUS.FAILURE
    end

    local targetPos = target:GetPos()

    -- Navigate toward the soda
    loco:SetGoal(targetPos)

    local dist = bot:GetPos():Distance(targetPos)

    -- When close, look DOWN at the soda can on the ground.
    -- The super soda addon requires the player to be looking at the entity
    -- for the E-key (Use) to register via TTT2's trace-based use system.
    if dist < 300 then
        -- Look at the entity's actual ground-level position.
        loco:LookAt(targetPos)
    end

    return STATUS.RUNNING
end

function DrinkSoda.OnSuccess(bot)
end

function DrinkSoda.OnFailure(bot)
end

function DrinkSoda.OnEnd(bot)
    bot.tttbots_sodaTarget = nil
end

---------------------------------------------------------------------------
-- Timer: Use the soda when close + looking at it
---------------------------------------------------------------------------

timer.Create("TTTBots.DrinkSoda.UseNearbySodas", 0.33, 0, function()
    if not TTTBots.Match.IsRoundActive() then return end

    for _, bot in pairs(TTTBots.Bots) do
        if not (IsValid(bot) and lib.IsPlayerAlive(bot)) then continue end

        local soda = bot.tttbots_sodaTarget
        if not (soda and IsValid(soda) and DrinkSoda.IsValidSoda(soda)) then continue end

        if not DrinkSoda.CanDrinkMore(bot) then
            bot.tttbots_sodaTarget = nil
            continue
        end

        local dist = bot:GetPos():Distance(soda:GetPos())
        if dist < DrinkSoda.UseRange then
            -- Force look down at the soda right before using it
            local loco = bot:BotLocomotor()
            if loco then
                loco:LookAt(soda:GetPos())
            end

            -- Use the soda entity
            soda:Use(bot, bot, USE_ON, 1)
            bot.tttbots_sodasDrunk = (bot.tttbots_sodasDrunk or 0) + 1
            bot.tttbots_sodaTarget = nil
        end
    end
end)

---------------------------------------------------------------------------
-- Round reset + soda location caching
---------------------------------------------------------------------------

hook.Add("TTTBeginRound", "TTTBots.DrinkSoda.Reset", function()
    for _, bot in pairs(TTTBots.Bots) do
        if not (IsValid(bot) and bot ~= NULL) then continue end
        bot.tttbots_sodasDrunk = 0
        bot.tttbots_sodaTarget = nil
        bot.tttbots_sodaNextScan = 0
    end
    -- Re-resolve convar each round in case addon was loaded/reloaded
    convarLookedUp = false
    cachedMaxConvar = nil
    DrinkSoda._cacheRefreshedThisRound = false

    -- Cache soda locations shortly after round start.
    -- Sodas spawn when the prep phase ends (i.e. TTTBeginRound), so a small
    -- delay ensures they've been created by the addon.
    timer.Simple(2, function()
        if not TTTBots.Match.IsRoundActive() then return end
        DrinkSoda.CacheSodaLocations()
    end)
end)
