TTTBots.Buyables = {}
TTTBots.Buyables.m_buyables = {}
TTTBots.Buyables.m_buyables_role = {}
local buyables = TTTBots.Buyables.m_buyables
local buyables_role = TTTBots.Buyables.m_buyables_role

---@class Buyable
---@field Name string - The pretty name of this item.
---@field Class string - The class of this item.
---@field Price number - The price of this item, in credits. Bots are given an allowance of 2 credits.
---@field Priority number - The priority of this item. Higher numbers = higher priority. If two buyables have the same priority, the script will select one at random.
---@field OnBuy function? - Called when the bot successfully buys this item.
---@field CanBuy function? - Return false to prevent a bot from buying this item.
---@field Roles table<string> - A table of roles that can buy this item.
---@field RandomChance number? - An integer from 1 to math.huge. Functionally the item will be selected if random(1, RandomChoice) == 1.
---@field ShouldAnnounce boolean? - Should this create a chatter event?
---@field AnnounceTeam boolean? - Is announcing team-only?
---@field BuyFunc function? - Custom buy function. Defaults to OrderEquipmentFor().
---@field TTT2 boolean? - Is this TTT2 specific?
---@field PrimaryWeapon boolean? - Should the bot use this over whatever other primaries they have? (affects autoswitch)

--- A table of weapons that are preferred over primary weapons (PrimaryWeapon == true). Indexed by the weapon's classname.
---@type table<string, boolean>
TTTBots.Buyables.PrimaryWeapons = {}

--- Return a buyable item by its name.
---@param name string - The name of the buyable item.
---@return Buyable|nil - The buyable item, or nil if it does not exist.
function TTTBots.Buyables.GetBuyable(name) return buyables[name] end

---Return a list of buyables for the given rolestring. Defaults to an empty table.
---The result is ALWAYS sorted by priority, descending.
---@param roleString string
---@return table<Buyable>
function TTTBots.Buyables.GetBuyablesFor(roleString) return buyables_role[roleString] or {} end

---Adds the given Buyable data to the roleString. This is called automatically when registering a Buyable, but exists for sanity.
---@param buyable Buyable
---@param roleString string
function TTTBots.Buyables.AddBuyableToRole(buyable, roleString)
    buyables_role[roleString] = buyables_role[roleString] or {}
    table.insert(buyables_role[roleString], buyable)
    table.sort(buyables_role[roleString], function(a, b) return a.Priority > b.Priority end)
end

---Purchases any registered buyables for the given bot's rolestring. Returns a table of Buyables that were successfully purchased.
---Uses the bot's actual in-game credits (TTT2) instead of a hardcoded allowance.
---@param bot Bot
---@return table<Buyable>
function TTTBots.Buyables.PurchaseBuyablesFor(bot)
    local roleString = bot:GetRoleStringRaw()
    local options = TTTBots.Buyables.GetBuyablesFor(roleString)
    local purchased = {}

    -- TTT2 uses real credits; vanilla TTT uses a local 2-credit allowance.
    local hasCreditSystem = bot.GetCredits ~= nil
    local vanillaAllowance = 2

    local function getCredits()
        if hasCreditSystem then return bot:GetCredits() or 0 end
        return vanillaAllowance
    end

    for i, option in pairs(options) do
        if option.TTT2 and not TTTBots.Lib.IsTTT2() then continue end                      -- for mod compat.
        if option.Class and not TTTBots.Lib.WepClassExists(option.Class) then continue end -- for mod compat.
        if option.Price > getCredits() then continue end
        if option.CanBuy and not option.CanBuy(bot) then continue end
        if option.RandomChance and math.random(1, option.RandomChance) ~= 1 then continue end

        table.insert(purchased, option)

        -- Custom BuyFunc handles giving + credit deduction.
        -- Default: use TTT2's OrderEquipment pipeline.
        local buyfunc = option.BuyFunc
        if buyfunc then
            buyfunc(bot)
        else
            TTTBots.Buyables.OrderEquipmentFor(bot, option.Class, option.Price)
        end

        -- Track spending for vanilla TTT (no real credit system)
        if not hasCreditSystem then
            vanillaAllowance = vanillaAllowance - option.Price
        end

        if option.OnBuy then option.OnBuy(bot) end
        if option.ShouldAnnounce then
            local chatter = bot:BotChatter()
            if not chatter then continue end
            chatter:On("Buy" .. option.Name, {}, option.AnnounceTeam or false)
        end
    end

    return purchased
end

--- Order equipment through TTT2's pipeline. Falls back to Give() for vanilla TTT.
---@param bot Player
---@param cls string
---@param cost number (defaults to 1)
function TTTBots.Buyables.OrderEquipmentFor(bot, cls, cost)
    if not cls then return end
    cost = cost or 1

    local isTTT2 = TTTBots.Lib.IsTTT2()

    local isItem = false
    if isTTT2 and items and items.GetStored then
        isItem = items.GetStored(cls) ~= nil
    end

    if isItem then
        if bot.GiveEquipmentItem then
            bot:GiveEquipmentItem(cls)
        end
    else
        if isTTT2 and GiveEquipmentWeapon then
            GiveEquipmentWeapon(bot:SteamID64(), cls)
        else
            bot:Give(cls)
        end
    end

    if bot.SubtractCredits then
        bot:SubtractCredits(cost)
    end

    if bot.AddBought then
        bot:AddBought(cls)
    end

    hook.Run("TTTOrderedEquipment", bot, cls, isItem)
end

--- Collect all known role name strings from both TTTBots and TTT2 registries.
---@return string[]
function TTTBots.Buyables.GetAllRoleNames()
    local names = {}
    local seen = {}

    if TTTBots.Roles and TTTBots.Roles.m_roles then
        for name, _ in pairs(TTTBots.Roles.m_roles) do
            if not seen[name] then
                names[#names + 1] = name
                seen[name] = true
            end
        end
    end

    if roles and roles.GetList then
        for _, roleData in ipairs(roles.GetList()) do
            local name = roleData.name
            if name and not seen[name] then
                names[#names + 1] = name
                seen[name] = true
            end
        end
    end

    for _, name in ipairs({"traitor", "detective", "innocent", "jackal", "survivalist"}) do
        if not seen[name] then
            names[#names + 1] = name
            seen[name] = true
        end
    end

    return names
end

--- Register a buyable item. This is useful for modders wanting to add custom buyable items.
---@param data Buyable - The data of the buyable item.
---@return boolean - Whther or not the override was successful.
function TTTBots.Buyables.RegisterBuyable(data)
    buyables[data.Name] = data

    for _, roleString in pairs(data.Roles) do
        TTTBots.Buyables.AddBuyableToRole(data, roleString)
    end

    if data.PrimaryWeapon and data.Class then
        TTTBots.Buyables.PrimaryWeapons[data.Class] = true
    end

    return true
end

-- hook for TTTBeginRound
hook.Add("TTTBeginRound", "TTTBots_Buyables", function()
    -- The two second delay can avoid a bunch of confusing errors. Don't ask why, I don't fucking know.
    timer.Simple(2,
        function()
            if not TTTBots.Match.IsRoundActive() then return end
            for _, bot in pairs(TTTBots.Bots) do
                if not TTTBots.Lib.IsPlayerAlive(bot) then continue end
                if bot == NULL then continue end
                if not bot.initialized or not bot.components then continue end
                TTTBots.Buyables.PurchaseBuyablesFor(bot)
            end
        end)
end)

-- Import default data
include("tttbots2/data/sv_default_buyables.lua")

-- Import role weapon shop data (self-registers buyables per role)
include("tttbots2/data/sh_weapons.lua")
