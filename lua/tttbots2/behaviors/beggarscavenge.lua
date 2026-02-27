--- Beggar behavior: scavenge for dropped shop items to trigger team conversion.

---@class BBeggarScavenge
TTTBots.Behaviors.BeggarScavenge = {}

local lib = TTTBots.Lib

---@class BBeggarScavenge
local BeggarScavenge = TTTBots.Behaviors.BeggarScavenge
BeggarScavenge.Name = "BeggarScavenge"
BeggarScavenge.Description = "Seek and pick up shop items to trigger team conversion."
BeggarScavenge.Interruptible = true

BeggarScavenge.SCAN_INTERVAL = 2       --- Seconds between scanning for items
BeggarScavenge.PICKUP_RANGE = 60       --- Distance to consider item "picked up" (walk over it)

local STATUS = TTTBots.STATUS

--- Check if a weapon entity is a shop/equipment item lying on the ground.
---@param ent Entity
---@return boolean
function BeggarScavenge.IsShopItem(ent)
    if not (ent and IsValid(ent)) then return false end
    if not ent:IsWeapon() then return false end
    if ent:GetOwner() ~= nil and IsValid(ent:GetOwner()) then return false end

    ---@cast ent Weapon
    local kind = ent.Kind
    -- WEAPON_EQUIP1 = 6, WEAPON_EQUIP2 = 7 in TTT/TTT2
    -- Also check WEAPON_ROLE = 8 and any CanBuy table
    if kind and (kind >= 6) then return true end

    -- Fallback: check if the weapon has a CanBuy table (shop-buyable weapon)
    if ent.CanBuy and istable(ent.CanBuy) and #ent.CanBuy > 0 then return true end

    return false
end

--- Cached list of shop items on the ground, updated every 2 seconds.
BeggarScavenge.ShopItemCache = {}

function BeggarScavenge.UpdateShopItemCache()
    BeggarScavenge.ShopItemCache = {}
    for _, ent in ipairs(ents.GetAll()) do
        if BeggarScavenge.IsShopItem(ent) then
            BeggarScavenge.ShopItemCache[#BeggarScavenge.ShopItemCache + 1] = ent
        end
    end
end

timer.Create("TTTBots.BeggarScavenge.CacheUpdate", 2, 0, function()
    if not TTTBots.Match.IsRoundActive() then return end
    BeggarScavenge.UpdateShopItemCache()
end)

hook.Add("TTTBeginRound", "TTTBots.BeggarScavenge.Reset", function()
    BeggarScavenge.ShopItemCache = {}
end)

--- Find the nearest shop item on the ground.
---@param bot Bot
---@return Entity|nil item
---@return number distance
function BeggarScavenge.FindNearestShopItem(bot)
    local botPos = bot:GetPos()
    local bestItem, bestDist = nil, math.huge

    for _, ent in ipairs(BeggarScavenge.ShopItemCache) do
        if not BeggarScavenge.IsShopItem(ent) then continue end
        local d = botPos:DistToSqr(ent:GetPos())
        if d < bestDist then
            bestDist = d
            bestItem = ent
        end
    end

    if bestItem then
        bestDist = math.sqrt(bestDist)
    end

    return bestItem, bestDist
end

--- Check if the Beggar has been converted (no longer on Team Jester).
---@param bot Bot
---@return boolean
function BeggarScavenge.HasConverted(bot)
    local team = bot:GetTeam()
    return team ~= TEAM_JESTER and team ~= "jesters"
end

---@param bot Bot
---@return boolean
function BeggarScavenge.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not IsValid(bot) then return false end
    -- Only run while still a Beggar on Team Jester
    -- Once converted, this behavior should stop
    if BeggarScavenge.HasConverted(bot) then return false end
    return true
end

---@param bot Bot
---@return BStatus
function BeggarScavenge.OnStart(bot)
    bot.beggarTargetItem = nil
    bot.beggarLastScan = 0
    bot.beggarConverted = false
    return STATUS.RUNNING
end

---@param bot Bot
---@return BStatus
function BeggarScavenge.OnRunning(bot)
    local loco = bot:BotLocomotor()
    if not loco then return STATUS.FAILURE end

    -- Check if we've been converted (addon changed our team)
    if BeggarScavenge.HasConverted(bot) then
        bot.beggarConverted = true
        return STATUS.SUCCESS
    end

    ---------------------------------------------------------------------------
    -- SCAN for shop items periodically
    ---------------------------------------------------------------------------
    if CurTime() - (bot.beggarLastScan or 0) > BeggarScavenge.SCAN_INTERVAL then
        bot.beggarLastScan = CurTime()

        local item, dist = BeggarScavenge.FindNearestShopItem(bot)
        if item and IsValid(item) then
            bot.beggarTargetItem = item
        end
    end

    ---------------------------------------------------------------------------
    -- NAVIGATE to the target shop item
    ---------------------------------------------------------------------------
    local target = bot.beggarTargetItem
    if target and IsValid(target) and not (target:GetOwner() ~= nil and IsValid(target:GetOwner())) then
        local targetPos = target:GetPos()
        loco:SetGoal(targetPos)

        local dist = bot:GetPos():Distance(targetPos)
        if dist < BeggarScavenge.PICKUP_RANGE then
            -- Press Use on the item to trigger the actual pickup system.
            -- TTT2's weapon pickup requires Use; just walking over it won't work.
            target:Use(bot, bot, USE_ON, 1)
            bot.beggarTargetItem = nil
        end

        return STATUS.RUNNING
    end

    -- No shop item found — clear stale target and let fallback behaviors run
    bot.beggarTargetItem = nil
    return STATUS.FAILURE
end

---@param bot Bot
function BeggarScavenge.OnSuccess(bot)
end

---@param bot Bot
function BeggarScavenge.OnFailure(bot)
end

---@param bot Bot
function BeggarScavenge.OnEnd(bot)
    bot.beggarTargetItem = nil
end
