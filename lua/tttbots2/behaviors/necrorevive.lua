--- NecroRevive: revive any corpse as a zombie using the Necromancer's defibrillator.

---@class BNecroRevive
TTTBots.Behaviors.NecroRevive = {}

local lib = TTTBots.Lib

---@class BNecroRevive
local NecroRevive = TTTBots.Behaviors.NecroRevive
NecroRevive.Name = "NecroRevive"
NecroRevive.Description = "Revive any corpse using the necromancer defibrillator."
NecroRevive.Interruptible = true

--- Possible weapon classes for the necro defib. The addon may use different
--- names across versions, so we try several patterns.
NecroRevive.WeaponClasses = {
    "weapon_ttt_necrodefib",
    "weapon_ttt_necromancer_defib",
    "weapon_ttt_necromancer",
}

local STATUS = TTTBots.STATUS

---------------------------------------------------------------------------
-- Weapon detection
---------------------------------------------------------------------------

--- Check if the bot has any necro defib weapon. Also auto-detects by scanning
--- the bot's weapons for anything with "necro" in the class name.
---@param bot Bot
---@return boolean
function NecroRevive.HasDefib(bot)
    -- Check known weapon classes
    for _, class in ipairs(NecroRevive.WeaponClasses) do
        if bot:HasWeapon(class) then return true end
    end

    -- Fallback: scan for any weapon with "necro" in the class name
    local weapons = bot:GetWeapons()
    for _, wep in pairs(weapons) do
        if IsValid(wep) then
            local cls = wep:GetClass()
            if string.find(cls, "necro", 1, true) then
                return true
            end
        end
    end

    return false
end

--- Get the necro defib weapon entity from the bot's inventory.
---@param bot Bot
---@return Weapon?
function NecroRevive.GetDefib(bot)
    -- Check known weapon classes first
    for _, class in ipairs(NecroRevive.WeaponClasses) do
        local wep = bot:GetWeapon(class)
        if IsValid(wep) then return wep end
    end

    -- Fallback: scan for any weapon with "necro" in the class name
    local weapons = bot:GetWeapons()
    for _, wep in pairs(weapons) do
        if IsValid(wep) then
            local cls = wep:GetClass()
            if string.find(cls, "necro", 1, true) then
                return wep
            end
        end
    end

    return nil
end

---------------------------------------------------------------------------
-- Corpse finding (revives ANY corpse, not just allies)
---------------------------------------------------------------------------

--- Get the closest revivable corpse. Unlike the standard Defib behavior,
--- this targets ALL corpses — the necromancer revives enemies too.
---@param bot Bot
---@return Player? closest
---@return Entity? ragdoll
function NecroRevive.GetCorpse(bot)
    local options = TTTBots.Lib.GetRevivableCorpses()
    local cTime = CurTime()
    local botPos = bot:GetPos()
    local bestDist = math.huge
    local bestPly, bestRag = nil, nil

    for _, rag in pairs(options) do
        if not TTTBots.Lib.IsValidBody(rag) then continue end
        local deadply = player.GetBySteamID64(rag.sid64)
        if not IsValid(deadply) then continue end
        if (deadply.reviveCooldown or 0) > cTime then continue end

        local dist = botPos:Distance(rag:GetPos())
        if dist < bestDist then
            bestDist = dist
            bestPly = deadply
            bestRag = rag
        end
    end

    return bestPly, bestRag
end

---------------------------------------------------------------------------
-- Spine position helper (reuse from Defib)
---------------------------------------------------------------------------

function NecroRevive.GetSpinePos(rag)
    local default = rag:GetPos()
    local spineName = "ValveBiped.Bip01_Spine"
    local spine = rag:LookupBone(spineName)
    if spine then
        return rag:GetBonePosition(spine)
    end
    return default
end

---------------------------------------------------------------------------
-- Revival logic
---------------------------------------------------------------------------

local function failFunc(bot, target)
    if not IsValid(target) then return end
    target.reviveCooldown = CurTime() + 30
end

local function startFunc(bot)
    -- The necromancer addon handles its own sounds.
end

local function successFunc(bot)
    -- The necromancer addon handles its own sounds.
end

--- Revive a player using TTT2's Revive system.
---@param bot Bot
---@param target Player
function NecroRevive.FullRevive(bot, target)
    -- Guard against round-end: don't call Revive during round transition
    if not TTTBots.Match.IsRoundActive() then return end
    if not (IsValid(bot) and IsValid(target)) then return end

    target:Revive(
        0,                                        -- delay
        function() successFunc(bot) end,          -- OnRevive
        nil,                                      -- DoCheck
        true,                                     -- needsCorpse
        REVIVAL_BLOCK_NONE,                       -- blockRound
        function() failFunc(bot, target) end,     -- OnFail
        nil,                                      -- spawnPos
        nil                                       -- spawnAng
    )
end

---------------------------------------------------------------------------
-- Behavior lifecycle
---------------------------------------------------------------------------

function NecroRevive.Validate(bot)
    if not TTTBots.Lib.IsTTT2() then return false end
    if not TTTBots.Match.IsRoundActive() then return false end

    -- Must have the necro defib
    if not NecroRevive.HasDefib(bot) then return false end

    -- Re-use existing target if still valid
    if bot.necroRag and lib.IsValidBody(bot.necroRag) then
        return true
    end

    -- Find a new corpse
    local corpse, rag = NecroRevive.GetCorpse(bot)
    if not corpse then return false end
    if not lib.IsValidBody(rag) then return false end

    return true
end

function NecroRevive.OnStart(bot)
    bot.necroTarget, bot.necroRag = NecroRevive.GetCorpse(bot)
    return STATUS.RUNNING
end

---@param bot Bot
function NecroRevive.OnRunning(bot)
    local inventory, loco = bot:BotInventory(), bot:BotLocomotor()
    if not (inventory and loco) then return STATUS.FAILURE end

    local defib = NecroRevive.GetDefib(bot)
    local target = bot.necroTarget
    local rag = bot.necroRag
    if not (target and rag and defib) then return STATUS.FAILURE end
    if not (IsValid(target) and IsValid(rag) and IsValid(defib)) then return STATUS.FAILURE end

    local ragPos = NecroRevive.GetSpinePos(rag)

    loco:SetGoal(ragPos)
    loco:LookAt(ragPos)

    local dist = bot:GetPos():Distance(ragPos)

    if dist < 40 then
        -- Check for witnesses — Necromancer should be sneaky about reviving
        local numWitnesses = #lib.GetAllWitnessesBasic(bot:GetPos(), TTTBots.Roles.GetNonAllies(bot))
        if numWitnesses > 1 and bot.necroReviveStartTime == nil then
            return STATUS.RUNNING -- Wait for witnesses to leave
        end

        inventory:PauseAutoSwitch()
        bot:SetActiveWeapon(defib)
        loco:SetGoal() -- stop moving
        loco:PauseAttackCompat()
        loco:Crouch(true)
        loco:PauseRepel()

        if bot.necroReviveStartTime == nil then
            bot.necroReviveStartTime = CurTime()
            startFunc(bot)
        end

        -- Necro defib takes ~3 seconds (same as regular defib)
        if bot.necroReviveStartTime + 3 < CurTime() then
            NecroRevive.FullRevive(bot, target)
            return STATUS.SUCCESS
        end
    else
        inventory:ResumeAutoSwitch()
        loco:ResumeAttackCompat()
        loco:SetHalt(false)
        loco:ResumeRepel()
        bot.necroReviveStartTime = nil
    end

    return STATUS.RUNNING
end

function NecroRevive.OnSuccess(bot)
end

function NecroRevive.OnFailure(bot)
end

function NecroRevive.OnEnd(bot)
    bot.necroTarget = nil
    bot.necroRag = nil
    bot.necroReviveStartTime = nil

    local inventory, loco = bot:BotInventory(), bot:BotLocomotor()
    if not (inventory and loco) then return end

    loco:ResumeAttackCompat()
    loco:Crouch(false)
    loco:SetHalt(false)
    loco:ResumeRepel()
    inventory:ResumeAutoSwitch()
end
