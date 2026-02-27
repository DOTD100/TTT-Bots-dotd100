--- Shop weapons for TTT Bots 2.
--- Each bot randomly picks ONE weapon from their role's pool at round start.

local ShopWeaponLists = {}

ShopWeaponLists[ROLE_TRAITOR] = {
    "weapon_ttt_ak47",
    "ttt_thomas_swep",
    "weapon_ttt_sipistol",
    "weapon_ttt_silm4a1",
	"weapon_ttt_gauss_rifle",
	"weapon_ttt_predator_blade",
	"weapon_ttt_awp",
	"weapon_ttt_jihad_bomb",
	"weapon_ttt_dragon_elites",
	"weapon_ttt_ttt2_minethrower",
}

ShopWeaponLists[ROLE_DETECTIVE] = {
    "weapon_ttt_stungun",
    "weapon_ttt_p90",
	"weapon_ttt_dragon_elites",
	"weapon_ttt_ttt2_minethrower",
}

--- Map independent base roles to the shop they use.
local ShopAliases = {}

if ROLE_JACKAL then ShopAliases[ROLE_JACKAL] = ROLE_DETECTIVE end
if ROLE_BANDIT then ShopAliases[ROLE_BANDIT] = ROLE_DETECTIVE end
if ROLE_SURVIVALIST then ShopAliases[ROLE_SURVIVALIST] = ROLE_DETECTIVE end
if ROLE_SIDEKICK then ShopAliases[ROLE_SIDEKICK] = ROLE_DETECTIVE end
if ROLE_SERIALKILLER then ShopAliases[ROLE_SERIALKILLER] = ROLE_TRAITOR end
if ROLE_PIRATE then ShopAliases[ROLE_PIRATE] = ROLE_TRAITOR end
if ROLE_PIRATE_CAPTAIN then ShopAliases[ROLE_PIRATE_CAPTAIN] = ROLE_TRAITOR end

local weaponMetaCache = {}

--- Read credit cost and primary status from SWEP stored data.
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

        -- Kind 2 = pistol (secondary slot), anything else = primary
        local kind = stored.Kind
        if kind == 2 then
            isPrimary = false
        end
    end

    weaponMetaCache[className] = { cost = cost, isPrimary = isPrimary }
    return cost, isPrimary
end

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

--- Get the base role index for a bot (subroles map to their parent).
---@param bot Player
---@return number|nil
local function GetBotBaseRoleIndex(bot)
    if bot.GetSubRoleData then
        local ok, roleData = pcall(bot.GetSubRoleData, bot)
        if ok and roleData then
            return roleData.baserole or roleData.index
        end
    end

    if bot.GetSubRole then
        local ok, idx = pcall(bot.GetSubRole, bot)
        if ok and idx then return idx end
    end

    return nil
end

--- Get the weapon pool for a bot based on their base role.
---@param bot Player
---@return string[]
local function GetWeaponPoolForBot(bot)
    local baseIdx = GetBotBaseRoleIndex(bot)
    if not baseIdx then return {} end

    local shopIdx = ShopAliases[baseIdx] or baseIdx

    return ShopWeaponLists[shopIdx] or {}
end

--- Per-round claimed weapons, keyed by base role index.
local claimedWeapons = {}

local function getClaimedSet(baseIdx)
    if not claimedWeapons[baseIdx] then
        claimedWeapons[baseIdx] = {}
    end
    return claimedWeapons[baseIdx]
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
        if ply.tttbots_boughtRoleWeapon then return false end

        if ply.tttbots_roleWeaponChoice == nil then
            local pool = getAvailableWeapons(GetWeaponPoolForBot(ply))
            if #pool == 0 then
                ply.tttbots_roleWeaponChoice = false
                return false
            end

            -- Prefer unclaimed weapons (detective shop exempt — too few weapons)
            local baseIdx = GetBotBaseRoleIndex(ply) or 0
            local shopIdx = ShopAliases[baseIdx] or baseIdx
            local isDetectiveShop = (shopIdx == ROLE_DETECTIVE)

            local choices
            if isDetectiveShop then
                choices = pool
            else
                local claimed = getClaimedSet(shopIdx)
                local unclaimed = {}
                for _, cls in ipairs(pool) do
                    if not claimed[cls] then
                        unclaimed[#unclaimed + 1] = cls
                    end
                end

                -- All claimed? Allow duplicates
                choices = #unclaimed > 0 and unclaimed or pool
            end

            local choice = choices[math.random(#choices)]
            ply.tttbots_roleWeaponChoice = choice

            if not isDetectiveShop then
                local claimed = getClaimedSet(shopIdx)
                claimed[choice] = true
            end
        end

        if ply.tttbots_roleWeaponChoice == false then return false end

        -- Check if bot can afford it
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

        TTTBots.Buyables.OrderEquipmentFor(ply, cls, cost)

        if isPrimary then
            TTTBots.Buyables.PrimaryWeapons[cls] = true
        end
    end,
    OnBuy = function(ply)
        ply.tttbots_boughtRoleWeapon = true
    end,
    Roles = TTTBots.Buyables.GetAllRoleNames(),
})

hook.Add("TTTBeginRound", "TTTBots_RoleWeapons_ClearFlags", function()
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
