local Registry = {}

local function testPlyHasTrait(ply, trait, N)
    local personality = ply:BotPersonality()
    if not personality then return false end
    return (personality:GetTraitBool(trait)) or math.random(1, N) == 1
end

local function testPlyIsArchetype(ply, archetype, N)
    local personality = ply:BotPersonality()
    if not personality then return false end
    return (personality:GetClosestArchetype() == archetype) or math.random(1, N) == 1
end

--- List of detective-shop roles. Used to check team health station coverage.
local DETECTIVE_SHOP_ROLES = {
    ["detective"] = true,
    ["psychopath"] = true,
    ["bandit"] = true,
    ["survivalist"] = true,
}

--- Returns true if any alive bot with a detective-shop role already has a health station.
local function teamHasHealthStation()
    for _, bot in pairs(TTTBots.Bots) do
        if not (IsValid(bot) and bot ~= NULL and TTTBots.Lib.IsPlayerAlive(bot)) then continue end
        local roleStr = bot:GetRoleStringRaw()
        if not DETECTIVE_SHOP_ROLES[roleStr] then continue end
        if bot:HasWeapon("weapon_ttt_health_station") then return true end
        if bot.tttbots_boughtHealthStation then return true end
    end
    return false
end

---@type Buyable
Registry.C4 = {
    Name = "C4",
    Class = "weapon_ttt_c4",
    Price = 1,
    Priority = 1,
    RandomChance = 1, -- 1 since chance is calculated in CanBuy
    ShouldAnnounce = false,
    AnnounceTeam = false,
    CanBuy = function(ply)
        return testPlyHasTrait(ply, "planter", 6)
    end,
    Roles = { "traitor", "psychopath", "executioner", "brainwasher" },
}

--- Knife: assassin-trait traitors always buy; others have a 1-in-8 chance.
---@type Buyable
Registry.Knife = {
    Name = "Knife",
    Class = nil, -- Resolved dynamically in CanBuy/BuyFunc
    Price = 1,
    Priority = 1,
    RandomChance = 1, -- Chance is calculated in CanBuy
    ShouldAnnounce = false,
    AnnounceTeam = false,
    CanBuy = function(ply)
        if ply.tttbots_boughtKnife then return false end

        -- Find the first available knife class on this server
        local knifeCandidates = {
            "weapon_ttt_knife",
            "weapon_ttt2_knife",
            "weapon_ttt_xknife",
        }
        local foundKnife = nil
        for _, cls in ipairs(knifeCandidates) do
            if TTTBots.Lib.WepClassExists(cls) then
                foundKnife = cls
                break
            end
        end
        if not foundKnife then return false end

        -- Cache the choice on the bot for BuyFunc
        ply.tttbots_knifeClass = foundKnife

        -- Assassin trait always buys; others have a small random chance
        return testPlyHasTrait(ply, "useKnives", 8)
    end,
    BuyFunc = function(ply)
        local cls = ply.tttbots_knifeClass
        if not cls then return end

        local cost = 1
        local stored = weapons.GetStored(cls)
        if stored then
            if stored.EquipMenuData and stored.EquipMenuData.credits then
                local c = tonumber(stored.EquipMenuData.credits)
                if c and c > 0 then cost = c end
            elseif stored.credits then
                local c = tonumber(stored.credits)
                if c and c > 0 then cost = c end
            end
        end

        TTTBots.Buyables.OrderEquipmentFor(ply, cls, cost)
    end,
    OnBuy = function(ply)
        ply.tttbots_boughtKnife = true
    end,
    Roles = { "traitor", "psychopath", "executioner", "brainwasher", "shanker", "hitman" },
}

--- Flare Gun: bodyBurner-trait traitors buy to burn victim corpses.
---@type Buyable
Registry.FlareGun = {
    Name = "FlareGun",
    Class = "weapon_ttt_flaregun",
    Price = 1,
    Priority = 1,
    RandomChance = 1, -- Chance is calculated in CanBuy
    ShouldAnnounce = false,
    AnnounceTeam = false,
    CanBuy = function(ply)
        if ply.tttbots_boughtFlareGun then return false end
        if not TTTBots.Lib.WepClassExists("weapon_ttt_flaregun") then return false end
        -- Body burner trait always buys; others have a small random chance
        return testPlyHasTrait(ply, "bodyBurner", 10)
    end,
    OnBuy = function(ply)
        ply.tttbots_boughtFlareGun = true
    end,
    Roles = { "traitor", "psychopath", "executioner", "brainwasher", "shanker", "hitman" },
}

--- Disguiser: hides the bot's name. Auto-activated after a short delay.
---@type Buyable
Registry.Disguiser = {
    Name = "Disguiser",
    Class = nil, -- Equipment item, not a weapon
    Price = 1,
    Priority = 1,
    RandomChance = 1, -- Chance calculated in CanBuy
    ShouldAnnounce = false,
    AnnounceTeam = false,
    CanBuy = function(ply)
        if ply.tttbots_hasDisguiser then return false end
        -- Check if the disguiser item exists
        local hasItem = (items and items.GetStored and items.GetStored("item_ttt_disguise"))
            or (EQUIP_DISGUISE ~= nil)
        if not hasItem then return false end
        return testPlyHasTrait(ply, "disguiser", 8)
    end,
    BuyFunc = function(ply)
        local cls = "item_ttt_disguise"
        if not (items and items.GetStored and items.GetStored(cls)) then
            -- Legacy EQUIP constant fallback
            if EQUIP_DISGUISE and ply.GiveEquipmentItem then
                ply:GiveEquipmentItem(EQUIP_DISGUISE)
                if ply.SubtractCredits then ply:SubtractCredits(1) end
                if ply.AddBought then ply:AddBought(tostring(EQUIP_DISGUISE)) end
            end
        else
            TTTBots.Buyables.OrderEquipmentFor(ply, cls, 1)
        end

        -- Auto-activate the disguise after a short delay
        timer.Simple(math.random(3, 8), function()
            if not IsValid(ply) then return end
            if not TTTBots.Lib.IsPlayerAlive(ply) then return end

            ply:SetNWBool("disguised", true)
        end)
    end,
    OnBuy = function(ply)
        ply.tttbots_hasDisguiser = true
    end,
    Roles = { "traitor", "psychopath", "executioner", "brainwasher", "shanker", "hitman" },
}

--- Radio: radiohead-trait bots deploy a distraction device.
---@type Buyable
Registry.Radio = {
    Name = "Radio",
    Class = "weapon_ttt_radio",
    Price = 1,
    Priority = 1,
    RandomChance = 1, -- Chance calculated in CanBuy
    ShouldAnnounce = false,
    AnnounceTeam = false,
    CanBuy = function(ply)
        if ply.tttbots_boughtRadio then return false end
        if not TTTBots.Lib.WepClassExists("weapon_ttt_radio") then return false end
        return testPlyHasTrait(ply, "radio", 10)
    end,
    OnBuy = function(ply)
        ply.tttbots_boughtRadio = true
    end,
    Roles = { "traitor", "psychopath", "executioner", "brainwasher", "hitman" },
}

--- Martyrdom: drops a live grenade on death. Low-priority traitor passive.
---@type Buyable
Registry.Martyrdom = {
    Name = "Martyrdom",
    Class = nil, -- Equipment item, not a weapon
    Price = 1,
    Priority = 0, -- Lower than weapons/armor — buy only with spare credits
    RandomChance = 2, -- 50% chance — not every traitor needs it
    ShouldAnnounce = false,
    AnnounceTeam = false,
    TTT2 = true,
    CanBuy = function(ply)
        -- Don't double-buy
        if ply.tttbots_hasMartyrdom then return false end
        -- Only if the item exists on the server
        if not items or not items.GetStored then return false end
        local itemData = items.GetStored("item_ttt_martyrdom")
        if not itemData then return false end
        return true
    end,
    BuyFunc = function(ply)
        TTTBots.Buyables.OrderEquipmentFor(ply, "item_ttt_martyrdom", 1)
    end,
    OnBuy = function(ply)
        ply.tttbots_hasMartyrdom = true
    end,
    Roles = { "traitor", "psychopath", "executioner", "brainwasher", "shanker", "hitman" },
}

--- Health Station: first detective buys one if no teammate already has it.
---@type Buyable
Registry.HealthStation = {
    Name = "Health Station",
    Class = "weapon_ttt_health_station",
    Price = 1,
    Priority = 3, -- Higher priority so the team-check happens before weapon/armor purchases
    RandomChance = 1,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    CanBuy = function(ply)
        if not GetConVar("ttt_bot_healthstation"):GetBool() then return false end
        if teamHasHealthStation() then return false end
        return testPlyHasTrait(ply, "healer", 3)
    end,
    OnBuy = function(ply)
        ply.tttbots_boughtHealthStation = true
    end,
    Roles = { "detective", "survivalist", "psychopath", "bandit" },
}

--- Body Armor: bought if bot has >1 credit. Controlled by ttt_bot_armor cvar.
---@type Buyable
Registry.BodyArmor = {
    Name = "Body Armor",
    Class = nil, -- Equipment item, not a weapon -- bypasses the WepClassExists check
    Price = 1,
    Priority = 2, -- Higher than weapons (1) so armor is bought first when affordable
    RandomChance = 1,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    CanBuy = function(ply)
        if not GetConVar("ttt_bot_armor"):GetBool() then return false end
        if ply.tttbots_hasArmor then return false end
        -- Only buy if we have spare credits for weapons/etc.
        local credits = 0
        if ply.GetCredits then credits = ply:GetCredits() or 0 end
        if credits <= 1 then return false end
        return true
    end,
    BuyFunc = function(ply)
        TTTBots.Buyables.OrderEquipmentFor(ply, "item_ttt_armor", 1)
    end,
    OnBuy = function(ply)
        ply.tttbots_hasArmor = true
    end,
    Roles = nil, -- Filled dynamically below
}

---@type Buyable
Registry.Defuser = {
    Name           = "Defuser",
    Class          = "weapon_ttt_defuser",
    Price          = 1,
    Priority       = 1,
    RandomChance   = 1, -- 1 since chance is calculated in CanBuy
    ShouldAnnounce = false,
    AnnounceTeam   = false,
    CanBuy         = function(ply)
        return testPlyHasTrait(ply, "defuser", 3)
    end,
    Roles          = { "detective", "psychopath", "bandit" },
}

---@type Buyable
Registry.Defib = {
    Name = "Defibrillator",
    Class = "weapon_ttt_defibrillator",
    Price = 1,
    Priority = 2, -- higher priority because this is an objectively useful item
    RandomChance = 1,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    CanBuy = function(ply)
        return testPlyIsArchetype(ply, TTTBots.Archetypes.Teamer, 3)
    end,
    Roles = { "detective", "traitor", "survivalist", "psychopath", "bandit" },
}

-- Set BodyArmor roles dynamically before registration
Registry.BodyArmor.Roles = TTTBots.Buyables.GetAllRoleNames()

for key, data in pairs(Registry) do
    TTTBots.Buyables.RegisterBuyable(data)
end

--- Clear per-round bot purchase flags at the start of each round.
hook.Add("TTTBeginRound", "TTTBots_Buyables_ClearFlags", function()
    timer.Simple(0.5, function()
        for _, bot in pairs(TTTBots.Bots) do
            if not (IsValid(bot) and bot ~= NULL) then continue end
            bot.tttbots_boughtHealthStation = nil
            bot.tttbots_hasArmor = nil
            bot.tttbots_hasMartyrdom = nil
            bot.tttbots_boughtKnife = nil
            bot.tttbots_knifeClass = nil
            bot.tttbots_boughtFlareGun = nil
            bot.tttbots_burnTarget = nil
            bot.tttbots_hasDisguiser = nil
            bot.tttbots_boughtRadio = nil
            bot.tttbots_radioPlaced = nil
            bot.tttbots_radioEntity = nil
        end
    end)
end)

--- Mid-round: buy armor when bots gain credits during the round.
timer.Create("TTTBots.Buyables.CreditWatcher", 3, 0, function()
    if not TTTBots.Match.IsRoundActive() then return end
    if not GetConVar("ttt_bot_armor"):GetBool() then return end

    for _, bot in pairs(TTTBots.Bots) do
        if not (IsValid(bot) and bot ~= NULL and TTTBots.Lib.IsPlayerAlive(bot)) then continue end

        if bot.tttbots_hasArmor then continue end

        local credits = 0
        if bot.GetCredits then
            credits = bot:GetCredits() or 0
        end

        if credits > 0 then
            TTTBots.Buyables.OrderEquipmentFor(bot, "item_ttt_armor", 1)
            bot.tttbots_hasArmor = true
        end
    end
end)
