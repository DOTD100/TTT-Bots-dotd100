--- Shop weapons for TTT Bots 2.
--- Weapon lists are defined manually per base role below. Subroles auto-detect
--- which shop to use by inheriting their base role's weapon pool via TTT2's
--- role system (e.g. Psychopath inherits Traitor's shop, Sheriff inherits
--- Detective's shop, etc.).
---
--- Each bot randomly picks ONE weapon from their pool at round start.
--- Weapons are unique per pool — if one traitor buys an AK, no other traitor
--- will pick the same AK that round (unless all options are exhausted).
---
--- Credit cost and weapon slot are auto-read from the SWEP data.
--- Credit cost: EquipMenuData.credits → SWEP.credits → SWEP.Price → default 1.
--- Primary detection: SWEP.Kind (3 = heavy/primary, 6/7 = equip slots that are
---   guns). Kind 2 (WEAPON_PISTOL) → secondary. Unknown → primary (safe default).
---
--- Bot purchases use ply:Give() which bypasses TTT2's OrderEquipment pipeline.
--- TEBN_ItemBought net messages are suppressed during bot buys.
---
--- To add weapons: just add the SWEP class name to the appropriate list below.
--- To add a new shop: add a new entry to ShopWeaponLists keyed by the base
--- role's ROLE_ constant (e.g. ROLE_TRAITOR, ROLE_DETECTIVE).

---------------------------------------------------------------------------
-- Weapon lists (just class names — cost & slot are auto-read from SWEP data)
-- Key each list by the base role index constant (ROLE_TRAITOR, ROLE_DETECTIVE, etc.)
-- Subroles automatically inherit their base role's list.
---------------------------------------------------------------------------

local ShopWeaponLists = {}

--- Traitor shop weapons (also used by traitor subroles: Psychopath, Executioner, etc.)
ShopWeaponLists[ROLE_TRAITOR] = {
    "weapon_ttt_ak47",
    "ttt_thomas_swep",
    "weapon_ttt_sipistol",
    "weapon_ttt_silm4a1",
}

--- Detective shop weapons (also used by detective subroles: Sheriff, etc.)
ShopWeaponLists[ROLE_DETECTIVE] = {
    "weapon_ttt_stungun",
    "weapon_ttt_p90",
}

--- Jackal, Bandit, Survivalist, etc. are independent base roles (not subroles)
--- so they have their own ROLE_ constants. Map them to the shop they actually use.
--- Add entries here when a role uses another role's shop.
local ShopAliases = {}

if ROLE_JACKAL then ShopAliases[ROLE_JACKAL] = ROLE_DETECTIVE end
if ROLE_BANDIT then ShopAliases[ROLE_BANDIT] = ROLE_DETECTIVE end
if ROLE_SURVIVALIST then ShopAliases[ROLE_SURVIVALIST] = ROLE_DETECTIVE end
if ROLE_SIDEKICK then ShopAliases[ROLE_SIDEKICK] = ROLE_DETECTIVE end
if ROLE_SERIALKILLER then ShopAliases[ROLE_SERIALKILLER] = ROLE_TRAITOR end
if ROLE_PIRATE then ShopAliases[ROLE_PIRATE] = ROLE_TRAITOR end
if ROLE_PIRATE_CAPTAIN then ShopAliases[ROLE_PIRATE_CAPTAIN] = ROLE_TRAITOR end

---------------------------------------------------------------------------
-- Utility: read weapon metadata from SWEP data
---------------------------------------------------------------------------

--- Per-class cache so we only inspect weapons.GetStored once per class.
---@type table<string, {cost: number, isPrimary: boolean}>
local weaponMetaCache = {}

--- Read credit cost and primary-weapon status from SWEP stored data.
--- Cost checks (in order): EquipMenuData.credits, SWEP.credits, SWEP.Price → 1.
--- Primary checks SWEP.Kind: 3 (WEAPON_HEAVY) and 6/7 (WEAPON_EQUIP) → primary.
--- Kind 2 (WEAPON_PISTOL) → secondary. Unknown → primary (safe default).
---@param className string
---@return number cost, boolean isPrimary
local function GetWeaponMeta(className)
    if weaponMetaCache[className] then
        local c = weaponMetaCache[className]
        return c.cost, c.isPrimary
    end

    local cost = 1
    local isPrimary = true -- safe default: prefer over ground loot

    local stored = weapons.GetStored(className)
    if stored then
        -- Credit cost
        if stored.EquipMenuData and stored.EquipMenuData.credits then
            local c = tonumber(stored.EquipMenuData.credits)
            if c and c > 0 then cost = c end
        elseif stored.credits then
            local c = tonumber(stored.credits)
            if c and c > 0 then cost = c end
        elseif stored.Price then
            local c = tonumber(stored.Price)
            if c and c > 0 then cost = c end
        end

        -- Primary vs secondary from Kind
        -- Kind 2 = WEAPON_PISTOL (secondary slot)
        -- Kind 3 = WEAPON_HEAVY (primary slot)
        -- Kind 6/7 = WEAPON_EQUIP1/2 (equipment slots — treat as primary if it's a gun)
        -- Anything else or nil → default to primary
        local kind = stored.Kind
        if kind == 2 then
            isPrimary = false
        end
    end

    weaponMetaCache[className] = { cost = cost, isPrimary = isPrimary }
    return cost, isPrimary
end

---------------------------------------------------------------------------
-- Utility: filter available weapons
---------------------------------------------------------------------------

--- Filter a weapon list to only those installed on the server.
---@param list string[]
---@return string[]
local function getAvailableWeapons(list)
    if not list then return {} end
    local available = {}
    for _, cls in ipairs(list) do
        if cls and TTTBots.Lib.WepClassExists(cls) then
            available[#available + 1] = cls
        end
    end
    return available
end

---------------------------------------------------------------------------
-- Role → shop mapping: auto-detect base role from TTT2's role system
---------------------------------------------------------------------------

--- Get the base role index for a bot. Subroles map to their base role so
--- e.g. a Psychopath (traitor subrole) gets the traitor weapon pool.
---@param bot Player
---@return number|nil
local function GetBotBaseRoleIndex(bot)
    -- TTT2: get the role data and find its base role
    if bot.GetSubRoleData then
        local ok, roleData = pcall(bot.GetSubRoleData, bot)
        if ok and roleData then
            -- baserole is the index of the parent role (traitor, detective, etc.)
            -- If nil, this IS a base role, so use its own index
            return roleData.baserole or roleData.index
        end
    end

    -- Fallback: direct subrole index (works for base roles)
    if bot.GetSubRole then
        local ok, idx = pcall(bot.GetSubRole, bot)
        if ok and idx then return idx end
    end

    return nil
end

--- Get the weapon pool for a bot based on their base role.
--- Checks ShopAliases first so independent roles (Jackal, Bandit, etc.)
--- get redirected to the correct shop.
---@param bot Player
---@return string[]
local function GetWeaponPoolForBot(bot)
    local baseIdx = GetBotBaseRoleIndex(bot)
    if not baseIdx then return {} end

    -- Resolve alias: e.g. ROLE_JACKAL → ROLE_DETECTIVE
    local shopIdx = ShopAliases[baseIdx] or baseIdx

    return ShopWeaponLists[shopIdx] or {}
end

---------------------------------------------------------------------------
-- Per-round tracking: which weapon classes have been claimed this round
-- Keyed by base role index so teammates sharing a shop coordinate.
---------------------------------------------------------------------------

--- Maps base role index → set of claimed class names this round.
---@type table<number, table<string, boolean>>
local claimedWeapons = {}

--- Get the set of already-claimed classes for a base role index.
---@param baseIdx number
---@return table<string, boolean>
local function getClaimedSet(baseIdx)
    if not claimedWeapons[baseIdx] then
        claimedWeapons[baseIdx] = {}
    end
    return claimedWeapons[baseIdx]
end

---------------------------------------------------------------------------
-- TEBN suppression: block TEBN_ItemBought net messages during bot buys
---------------------------------------------------------------------------

local suppressTEBN = false
local suppressingNetMessage = false

--- Wrap net.Start to block TEBN_ItemBought while any suppression flag is true.
--- Also intercepts subsequent net.Write*/net.Send/net.Broadcast calls when a
--- message was suppressed, preventing GMod errors from writing to no active message.
local origNetStart = origNetStart or net.Start
local origNetSend = origNetSend or net.Send
local origNetBroadcast = origNetBroadcast or net.Broadcast

net.Start = function(messageName, ...)
    if messageName == "TEBN_ItemBought" then
        local centralSuppress = TTTBots.Buyables and TTTBots.Buyables._suppressTEBN
        if suppressTEBN or centralSuppress then
            suppressingNetMessage = true
            return
        end
    end
    suppressingNetMessage = false
    return origNetStart(messageName, ...)
end

net.Send = function(...)
    if suppressingNetMessage then
        suppressingNetMessage = false
        return
    end
    return origNetSend(...)
end

net.Broadcast = function(...)
    if suppressingNetMessage then
        suppressingNetMessage = false
        return
    end
    return origNetBroadcast(...)
end

---------------------------------------------------------------------------
-- Registration: single universal Buyable that uses base role auto-detection
---------------------------------------------------------------------------

--- Collect ALL role name strings that could potentially have a shop.
--- We register the buyable for every known role and let CanBuy filter
--- at runtime based on whether the bot's base role has a weapon pool.
---@return string[]
local function GetAllRoleNames()
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
    for _, name in ipairs({"traitor", "detective", "innocent", "jackal"}) do
        if not seen[name] then
            names[#names + 1] = name
            seen[name] = true
        end
    end

    return names
end

TTTBots.Buyables.RegisterBuyable({
    Name = "RoleWeapon_Shop",
    Class = nil, -- Dynamic, resolved per-bot via BuyFunc
    Price = 1,   -- Default; overridden per-bot in BuyFunc based on weapon's real cost
    Priority = 1,
    RandomChance = 1,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    CanBuy = function(ply)
        -- Only buy once per round
        if ply.tttbots_boughtRoleWeapon then return false end

        -- Pick a weapon once per round if we haven't yet
        if ply.tttbots_roleWeaponChoice == nil then
            local pool = getAvailableWeapons(GetWeaponPoolForBot(ply))
            if #pool == 0 then
                ply.tttbots_roleWeaponChoice = false
                return false
            end

            -- Build list of unclaimed weapons (unique per shop group)
            -- Detective shop is exempt from uniqueness — too few weapons to go around
            local baseIdx = GetBotBaseRoleIndex(ply) or 0
            local shopIdx = ShopAliases[baseIdx] or baseIdx
            local isDetectiveShop = (shopIdx == ROLE_DETECTIVE)

            local choices
            if isDetectiveShop then
                -- No uniqueness restriction for detective shop
                choices = pool
            else
                local claimed = getClaimedSet(shopIdx)
                local unclaimed = {}
                for _, cls in ipairs(pool) do
                    if not claimed[cls] then
                        unclaimed[#unclaimed + 1] = cls
                    end
                end

                -- If all weapons are claimed, allow duplicates (wrap around)
                choices = #unclaimed > 0 and unclaimed or pool
            end

            local choice = choices[math.random(#choices)]
            ply.tttbots_roleWeaponChoice = choice

            -- Mark this weapon as claimed for non-detective shops
            if not isDetectiveShop then
                local claimed = getClaimedSet(shopIdx)
                claimed[choice] = true
            end
        end

        if ply.tttbots_roleWeaponChoice == false then return false end

        -- Check if the bot can actually afford the chosen weapon
        local cost = GetWeaponMeta(ply.tttbots_roleWeaponChoice)
        if ply.GetCredits then
            local credits = ply:GetCredits() or 0
            if credits < cost then return false end
        end

        return true
    end,
    BuyFunc = function(ply)
        local cls = ply.tttbots_roleWeaponChoice
        if not cls then return end

        -- Read cost and primary status from SWEP data
        local cost, isPrimary = GetWeaponMeta(cls)

        -- Deduct the real cost from the bot's credits (TTT2)
        if ply.GetCredits and ply.SubtractCredits then
            local credits = ply:GetCredits() or 0
            if credits < cost then return end -- can't afford
            ply:SubtractCredits(cost)
        end

        -- Suppress TEBN during the Give call
        suppressTEBN = true
        ply:Give(cls)
        suppressTEBN = false

        -- Register as PrimaryWeapon so the bot prefers it over ground loot
        if isPrimary then
            TTTBots.Buyables.PrimaryWeapons[cls] = true
        end
    end,
    OnBuy = function(ply)
        ply.tttbots_boughtRoleWeapon = true
    end,
    Roles = GetAllRoleNames(),
})

---------------------------------------------------------------------------
-- Round cleanup: clear per-round weapon choice flags and claimed sets
---------------------------------------------------------------------------

hook.Add("TTTBeginRound", "TTTBots_RoleWeapons_ClearFlags", function()
    -- Clear claimed weapon tracking
    claimedWeapons = {}
    weaponMetaCache = {}

    timer.Simple(0.5, function()
        for _, bot in pairs(TTTBots.Bots) do
            if not (IsValid(bot) and bot ~= NULL) then continue end
            bot.tttbots_roleWeaponChoice = nil
            bot.tttbots_boughtRoleWeapon = nil
        end
    end)
end)
