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
        -- Also check if they were already flagged as the health station buyer this round
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

--- Knife: Traitor bots with the assassin trait will buy a knife from the shop.
--- Common TTT knife class names are tried in order; the first one found on the
--- server is used. Assassin-trait bots always buy it; non-assassin traitors have
--- a 1-in-8 chance.
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

        if ply.GetCredits and ply.SubtractCredits then
            local credits = ply:GetCredits() or 0
            if credits < cost then return end
            ply:SubtractCredits(cost)
        end

        TTTBots.Buyables._suppressTEBN = true
        ply:Give(cls)
        TTTBots.Buyables._suppressTEBN = false
    end,
    OnBuy = function(ply)
        ply.tttbots_boughtKnife = true
    end,
    Roles = { "traitor", "psychopath", "executioner", "brainwasher", "shanker", "hitman" },
}

--- Flare Gun: Traitor bots with the bodyBurner trait buy a flare gun to burn
--- corpses of their victims, destroying evidence. The BurnCorpse behavior
--- handles actually shooting the bodies.
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

--- Disguiser: The built-in TTT2 passive equipment item that hides the player's
--- name from appearing when other players look at them. In TTT2 this is toggled
--- via a HUD button; for bots we auto-activate after a short delay.
--- Internally it works by setting the "disguised" NWBool to true, which makes
--- cl_targetid not show the player's name overhead.
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
        -- Check if the disguiser item exists (standard TTT/TTT2 equipment)
        -- Try item-based (TTT2) first, then legacy EQUIP constant
        local hasItem = (items and items.GetStored and items.GetStored("item_ttt_disguise"))
            or (EQUIP_DISGUISE ~= nil)
        if not hasItem then return false end
        return testPlyHasTrait(ply, "disguiser", 8)
    end,
    BuyFunc = function(ply)
        -- Give the equipment item via TTT2's item system or legacy EQUIP constant
        if ply.GiveEquipmentItem then
            if items and items.GetStored and items.GetStored("item_ttt_disguise") then
                ply:GiveEquipmentItem("item_ttt_disguise")
            elseif EQUIP_DISGUISE then
                ply:GiveEquipmentItem(EQUIP_DISGUISE)
            end
        end
        if ply.SubtractCredits then
            ply:SubtractCredits(1)
        end

        -- Auto-activate the disguise after a short random delay.
        -- In TTT2, human players toggle this via a HUD button; for bots we
        -- simply set the NWBool directly, which is exactly what the toggle does.
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

--- Radio: A deployable distraction device. Bots with the radiohead trait buy and
--- place the radio, then it auto-triggers random sounds to distract innocents.
--- The PlaceRadio behavior handles deployment and sound triggering.
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

--- Martyrdom: A passive equipment item that drops a live grenade on death.
--- Addon: ttt2_martyrdom_updated (item_ttt_martyrdom)
--- Traitor-side bots buy this as a low-priority passive if they have credits to spare.
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
        if ply.GiveEquipmentItem then
            ply:GiveEquipmentItem("item_ttt_martyrdom")
        end
        if ply.SubtractCredits then
            ply:SubtractCredits(1)
        end
    end,
    OnBuy = function(ply)
        ply.tttbots_hasMartyrdom = true
    end,
    Roles = { "traitor", "psychopath", "executioner", "brainwasher", "shanker", "hitman" },
}

--- Health Station: If no detective-shop teammate already has one, the first detective buys it.
--- Otherwise, they skip it (and will buy armor instead via the BodyArmor buyable).
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
        -- Check cvar
        if not GetConVar("ttt_bot_healthstation"):GetBool() then return false end
        -- If someone on the team already has one, skip it
        if teamHasHealthStation() then return false end
        -- Otherwise, this bot buys it (healer trait gets preference, but anyone can be assigned)
        return testPlyHasTrait(ply, "healer", 3)
    end,
    OnBuy = function(ply)
        -- Flag this bot so other detectives know a health station has been claimed
        ply.tttbots_boughtHealthStation = true
    end,
    Roles = { "detective", "survivalist", "psychopath", "bandit" },
}

--- Body Armor: A passive equipment item available from any shop.
--- At round start, only bought if the bot has MORE than 1 credit (so they
--- still have credits left for weapons/health stations). Mid-round purchases
--- happen whenever a bot gains credits and doesn't have armor yet.
--- Controlled by the ttt_bot_armor cvar.
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
        -- Check cvar
        if not GetConVar("ttt_bot_armor"):GetBool() then return false end
        -- Don't double-buy armor
        if ply.tttbots_hasArmor then return false end
        -- At round start: only buy if we have MORE than 1 credit,
        -- so we still have credits for weapons/health station/etc.
        local credits = 0
        if ply.GetCredits then credits = ply:GetCredits() or 0 end
        if credits <= 1 then return false end
        return true
    end,
    BuyFunc = function(ply)
        -- Armor is an equipment item, not a weapon -- use GiveEquipmentItem if available (TTT2),
        -- otherwise fall back to the EQUIP_ARMOR constant (vanilla TTT).
        if ply.GiveEquipmentItem then
            ply:GiveEquipmentItem("item_ttt_armor")
        elseif EQUIP_ARMOR then
            ply:GiveEquipmentItem(EQUIP_ARMOR)
        end
        -- Deduct credit
        if ply.SubtractCredits then
            ply:SubtractCredits(1)
        end
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

--- Collect all known role names for armor registration.
--- Armor should be available to any role that might have a shop.
local function GetAllKnownRoles()
    local names = {}
    local seen = {}

    -- From registered TTT Bots roles
    if TTTBots.Roles and TTTBots.Roles.m_roles then
        for name, _ in pairs(TTTBots.Roles.m_roles) do
            if not seen[name] then
                names[#names + 1] = name
                seen[name] = true
            end
        end
    end

    -- From TTT2's role registry
    if roles and roles.GetList then
        for _, roleData in ipairs(roles.GetList()) do
            local name = roleData.name
            if name and not seen[name] then
                names[#names + 1] = name
                seen[name] = true
            end
        end
    end

    -- Fallback essentials
    for _, name in ipairs({"traitor", "detective", "innocent", "jackal", "survivalist"}) do
        if not seen[name] then
            names[#names + 1] = name
            seen[name] = true
        end
    end

    return names
end

-- Set BodyArmor roles dynamically before registration
Registry.BodyArmor.Roles = GetAllKnownRoles()

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

--- Mid-round credit watcher: Any bot with credits and a shop who doesn't have
--- armor yet will buy it when they gain credits during the round (from kills,
--- confirmations, etc.). Controlled by the ttt_bot_armor cvar.
timer.Create("TTTBots.Buyables.CreditWatcher", 3, 0, function()
    if not TTTBots.Match.IsRoundActive() then return end
    if not GetConVar("ttt_bot_armor"):GetBool() then return end

    for _, bot in pairs(TTTBots.Bots) do
        if not (IsValid(bot) and bot ~= NULL and TTTBots.Lib.IsPlayerAlive(bot)) then continue end

        -- Skip bots who already have armor
        if bot.tttbots_hasArmor then continue end

        -- Check current credits (TTT2 uses GetCredits, vanilla TTT uses similar)
        local credits = 0
        if bot.GetCredits then
            credits = bot:GetCredits() or 0
        end

        -- If they have credits available, buy armor (suppress TEBN)
        if credits > 0 then
            TTTBots.Buyables._suppressTEBN = true
            if bot.GiveEquipmentItem then
                bot:GiveEquipmentItem("item_ttt_armor")
            elseif EQUIP_ARMOR then
                bot:GiveEquipmentItem(EQUIP_ARMOR)
            end
            TTTBots.Buyables._suppressTEBN = false
            bot.tttbots_hasArmor = true

            -- Deduct the credit
            if bot.SubtractCredits then
                bot:SubtractCredits(1)
            elseif bot.SetCredits then
                bot:SetCredits(math.max(credits - 1, 0))
            end
        end
    end
end)
