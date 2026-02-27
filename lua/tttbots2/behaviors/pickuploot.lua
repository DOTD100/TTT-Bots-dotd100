--- PickupLoot: seek and pick up dropped shop items on the ground.

TTTBots.Behaviors.PickupLoot = {}

local lib = TTTBots.Lib

local PickupLoot = TTTBots.Behaviors.PickupLoot
PickupLoot.Name = "PickupLoot"
PickupLoot.Description = "Pick up dropped shop equipment"
PickupLoot.Interruptible = true
PickupLoot.PickupRange = 64        --- Units within which the bot auto-picks up
PickupLoot.MaxSearchDist = 1500    --- Don't travel further than this

local STATUS = TTTBots.STATUS

---------------------------------------------------------------------------
-- Detection: identify dropped shop/equipment weapons on the ground
---------------------------------------------------------------------------

--- Returns true if the entity is a dropped equipment weapon worth picking up.
--- Equipment weapons are Kind 6, 7, or 8 (WEAPON_EQUIP slots) or have
--- CanBuy tables (shop items). We also check Kind 0 (special/role weapons).
---@param ent Entity
---@return boolean
function PickupLoot.IsLootWeapon(ent)
    if not (ent and IsValid(ent)) then return false end
    if not ent:IsWeapon() then return false end

    -- Must be on the ground (no owner)
    local owner = ent:GetOwner()
    if IsValid(owner) then return false end

    -- Must be droppable
    if ent.AllowDrop == false then return false end

    -- Check if it's an equipment/shop weapon
    -- Kind values: 0=special, 1=melee, 2=pistol, 3=heavy, 4=nade, 5=carry,
    --              6=equip1, 7=equip2, 8=equip (role-specific)
    local kind = ent.Kind
    if kind and (kind == 6 or kind == 7 or kind == 8) then
        return true
    end

    -- Also check for CanBuy table (TTT2 shop items have this)
    if ent.CanBuy and istable(ent.CanBuy) and #ent.CanBuy > 0 then
        return true
    end

    -- Check for equipment flag (TTT1 style)
    if ent.IsEquipment and ent:IsEquipment() then
        return true
    end

    return false
end

--- Returns true if this weapon appears to be a traitor-exclusive item.
---@param wep Weapon
---@return boolean
function PickupLoot.IsTraitorWeapon(wep)
    if not IsValid(wep) then return false end

    -- Check CanBuy for traitor roles
    if wep.CanBuy then
        for _, roleIdx in ipairs(wep.CanBuy) do
            -- ROLE_TRAITOR is typically index 1 in TTT/TTT2
            if roleIdx == ROLE_TRAITOR then return true end
        end
    end

    -- Check the class name for common traitor weapon patterns
    local cls = wep:GetClass()
    if string.find(cls, "traitor", 1, true) then return true end

    return false
end

--- Returns true if the bot should bother picking up loot.
---@param bot Bot
---@return boolean
function PickupLoot.ShouldPickupLoot(bot)
    -- Don't pick up loot if fighting
    if bot.attackTarget ~= nil then return false end
    -- Don't pick up loot if the bot can't fight (Jester, Cursed, etc.)
    -- They have no use for weapons and it looks suspicious
    local roleData = TTTBots.Roles.GetRoleFor(bot)
    if roleData and not roleData:GetStartsFights() then return false end
    return true
end

---------------------------------------------------------------------------
-- Loot cache — updated periodically
---------------------------------------------------------------------------

PickupLoot.LootCache = {}

function PickupLoot.UpdateLootCache()
    PickupLoot.LootCache = {}
    for _, ent in ipairs(ents.GetAll()) do
        if PickupLoot.IsLootWeapon(ent) then
            PickupLoot.LootCache[#PickupLoot.LootCache + 1] = ent
        end
    end
end

timer.Create("TTTBots.PickupLoot.CacheUpdate", 2, 0, function()
    if not TTTBots.Match.IsRoundActive() then return end
    PickupLoot.UpdateLootCache()
end)

--- Find the nearest loot weapon for this bot.
---@param bot Bot
---@return Entity|nil
function PickupLoot.FindNearestLoot(bot)
    local botPos = bot:GetPos()
    local best = nil
    local bestDistSqr = math.huge
    local maxDistSqr = PickupLoot.MaxSearchDist * PickupLoot.MaxSearchDist

    for i = 1, #PickupLoot.LootCache do
        local ent = PickupLoot.LootCache[i]
        if not PickupLoot.IsLootWeapon(ent) then continue end
        local d = botPos:DistToSqr(ent:GetPos())
        if d < bestDistSqr and d < maxDistSqr then
            bestDistSqr = d
            best = ent
        end
    end

    return best, best and math.sqrt(bestDistSqr) or math.huge
end

---------------------------------------------------------------------------
-- Behavior callbacks
---------------------------------------------------------------------------

function PickupLoot.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not IsValid(bot) then return false end
    if not lib.IsPlayerAlive(bot) then return false end
    if not PickupLoot.ShouldPickupLoot(bot) then return false end

    -- Already have a valid target?
    if bot.tttbots_lootTarget and IsValid(bot.tttbots_lootTarget)
        and PickupLoot.IsLootWeapon(bot.tttbots_lootTarget) then
        return true
    end

    -- Throttle scanning
    if (bot.tttbots_lootNextScan or 0) > CurTime() then return false end
    bot.tttbots_lootNextScan = CurTime() + 3

    local loot = PickupLoot.FindNearestLoot(bot)
    if loot then
        bot.tttbots_lootTarget = loot
        return true
    end

    return false
end

function PickupLoot.OnStart(bot)
    return STATUS.RUNNING
end

function PickupLoot.OnRunning(bot)
    local loco = bot:BotLocomotor()
    if not loco then return STATUS.FAILURE end

    if not PickupLoot.ShouldPickupLoot(bot) then
        return STATUS.FAILURE
    end

    local target = bot.tttbots_lootTarget
    if not (target and IsValid(target) and PickupLoot.IsLootWeapon(target)) then
        bot.tttbots_lootTarget = nil
        return STATUS.FAILURE
    end

    local targetPos = target:GetPos()
    loco:SetGoal(targetPos)

    local dist = bot:GetPos():Distance(targetPos)
    if dist < 300 then
        loco:LookAt(targetPos)
    end

    return STATUS.RUNNING
end

function PickupLoot.OnSuccess(bot)
end

function PickupLoot.OnFailure(bot)
end

function PickupLoot.OnEnd(bot)
    bot.tttbots_lootTarget = nil
end

---------------------------------------------------------------------------
-- Timer: actually pick up the weapon when close enough
-- Walking over a weapon in GMod auto-picks it up if the player has a free
-- slot, but we also call Use to ensure it works for equipment items.
---------------------------------------------------------------------------

timer.Create("TTTBots.PickupLoot.GrabNearby", 0.5, 0, function()
    if not TTTBots.Match.IsRoundActive() then return end

    for _, bot in pairs(TTTBots.Bots) do
        if not (IsValid(bot) and lib.IsPlayerAlive(bot)) then continue end

        local loot = bot.tttbots_lootTarget
        if not (loot and IsValid(loot) and PickupLoot.IsLootWeapon(loot)) then continue end

        local dist = bot:GetPos():Distance(loot:GetPos())
        if dist < PickupLoot.PickupRange then
            local wasTraitorWep = PickupLoot.IsTraitorWeapon(loot)
            local wepName = loot:GetPrintName() or loot:GetClass() or "unknown weapon"

            -- Try to pick it up
            loot:Use(bot, bot, USE_ON, 1)

            -- Check if pickup succeeded (weapon now has the bot as owner)
            timer.Simple(0.2, function()
                if not IsValid(bot) then return end
                if not TTTBots.Match.IsRoundActive() then return end

                -- Announce traitor weapon pickup in chat if the bot is innocent-team
                if wasTraitorWep then
                    local botTeam = bot:GetTeam()
                    local isInnocentSide = (botTeam == TEAM_INNOCENT or botTeam == TEAM_DETECTIVE)
                        or (botTeam ~= TEAM_TRAITOR and botTeam ~= TEAM_JESTER and botTeam ~= "jesters")

                    if isInnocentSide then
                        local chatter = bot:BotChatter()
                        if chatter then
                            chatter:On("PickedUpTraitorWeapon", {}, false)
                        end
                    end
                end
            end)

            bot.tttbots_lootTarget = nil
        end
    end
end)

---------------------------------------------------------------------------
-- Round reset
---------------------------------------------------------------------------

hook.Add("TTTBeginRound", "TTTBots.PickupLoot.Reset", function()
    PickupLoot.LootCache = {}
    for _, bot in pairs(TTTBots.Bots) do
        if not (IsValid(bot) and bot ~= NULL) then continue end
        bot.tttbots_lootTarget = nil
        bot.tttbots_lootNextScan = 0
    end
end)
