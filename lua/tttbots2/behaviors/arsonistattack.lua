--- ArsonistAttack: hold-to-spray flamethrower behavior.
--- Falls back to AttackTarget if flamethrower is unavailable.

---@class BArsonistAttack
TTTBots.Behaviors.ArsonistAttack = {}

local lib = TTTBots.Lib

---@class BArsonistAttack
local ArsonistAttack = TTTBots.Behaviors.ArsonistAttack
ArsonistAttack.Name = "ArsonistAttack"
ArsonistAttack.Description = "Attack target with flamethrower (Arsonist)"
ArsonistAttack.Interruptible = true

ArsonistAttack.SPRAY_RANGE = 300       --- Max effective range of flamethrower
ArsonistAttack.CLOSE_RANGE = 120       --- Distance at which we stop advancing and just spray
ArsonistAttack.SEEK_TIMEOUT = 15       --- Seconds before giving up on an unseen target
ArsonistAttack.FLAMETHROWER_CLASS = "weapon_ttt2_arsonthrower"

local STATUS = TTTBots.STATUS

--- Check if the bot has the flamethrower and return it.
---@param bot Bot
---@return Weapon|nil
function ArsonistAttack.GetFlamethrower(bot)
    if bot:HasWeapon(ArsonistAttack.FLAMETHROWER_CLASS) then
        return bot:GetWeapon(ArsonistAttack.FLAMETHROWER_CLASS)
    end
    return nil
end

--- Force-equip the flamethrower. Returns true if successful.
---@param bot Bot
---@return boolean
function ArsonistAttack.EquipFlamethrower(bot)
    local wep = ArsonistAttack.GetFlamethrower(bot)
    if not wep or not IsValid(wep) then return false end

    local active = bot:GetActiveWeapon()
    if IsValid(active) and active == wep then return true end

    pcall(bot.SelectWeapon, bot, ArsonistAttack.FLAMETHROWER_CLASS)

    -- Verify
    active = bot:GetActiveWeapon()
    return IsValid(active) and active:GetClass() == ArsonistAttack.FLAMETHROWER_CLASS
end

--- Validate -- uses same logic as normal AttackTarget
function ArsonistAttack.Validate(bot)
    return TTTBots.Behaviors.AttackTarget.Validate(bot)
end

--- Called when the behavior is started
function ArsonistAttack.OnStart(bot)
    local inv = bot:BotInventory()
    if inv then
        inv:PauseAutoSwitch() -- Keep the flamethrower equipped
    end
    bot.arsonistSeekStart = nil
    return STATUS.RUNNING
end

--- Seek mode: can't see the target, rush toward last known position.
---@param bot Bot
---@param target Player
function ArsonistAttack.Seek(bot, target)
    local loco = bot:BotLocomotor()
    if not loco then return end
    loco.stopLookingAround = false
    loco:StopAttack()

    ---@type CMemory
    local memory = bot.components and bot.components.memory
    if not memory then return end
    local lastKnownPos = memory:GetSuspectedPositionFor(target) or memory:GetKnownPositionFor(target)
    local lastSeenTime = memory:GetLastSeenTime(target)
    local secsSince = CurTime() - lastSeenTime

    if not bot.arsonistSeekStart then
        bot.arsonistSeekStart = CurTime()
    end

    if lastKnownPos and secsSince < ArsonistAttack.SEEK_TIMEOUT then
        loco:SetGoal(lastKnownPos)
        loco:LookAt(lastKnownPos + Vector(0, 0, 40))
    else
        lib.CallEveryNTicks(
            bot,
            function()
                local wanderArea = TTTBots.Behaviors.Wander.GetAnyRandomNav(bot)
                if not IsValid(wanderArea) then return end
                loco:SetGoal(wanderArea:GetCenter())
            end,
            math.ceil(TTTBots.Tickrate * 5)
        )
    end
end

--- Engage mode: visible target, rush in and hold fire with flamethrower.
---@param bot Bot
---@param target Player
function ArsonistAttack.Engage(bot, target)
    local loco = bot:BotLocomotor()
    if not loco then return end
    loco.stopLookingAround = true

    local targetPos = target:GetPos()
    local distToTarget = bot:GetPos():Distance(targetPos)

    -- Keep flamethrower equipped
    ArsonistAttack.EquipFlamethrower(bot)

    -- Always rush toward the target - flamethrower is short range
    if distToTarget > ArsonistAttack.CLOSE_RANGE then
        loco:SetGoal(targetPos)
        loco:SetForceForward(true)
    else
        -- Very close, stop and spray
        loco:StopMoving()
        loco:SetForceForward(false)
    end

    -- Aim at body center
    local aimPos = TTTBots.Behaviors.AttackTarget.GetTargetBodyPos(target)
    local predictedPoint = aimPos + TTTBots.Behaviors.AttackTarget.PredictMovement(target, 0.3)
    loco:LookAt(predictedPoint)

    -- Hold fire when in range and looking at target
    if distToTarget <= ArsonistAttack.SPRAY_RANGE then
        local activeWep = bot:GetActiveWeapon()
        if IsValid(activeWep) and TTTBots.Behaviors.AttackTarget.LookingCloseToTarget(bot, target) then
            if not TTTBots.Behaviors.AttackTarget.WillShootingTeamkill(bot, target) then
                loco:StartAttack() -- Hold fire continuously for the spray
            end
        end
    else
        loco:StopAttack()
    end

    -- Strafe at medium range to be harder to hit while closing distance
    if distToTarget < 350 and distToTarget > ArsonistAttack.CLOSE_RANGE then
        local strafeDir = math.random(0, 1) == 0 and "left" or "right"
        loco:Strafe(strafeDir)
    end
end

--- Main tick
---@param bot Bot
---@return BStatus
function ArsonistAttack.OnRunning(bot)
    local target = bot.attackTarget

    if not TTTBots.Behaviors.AttackTarget.ValidateTarget(bot) then return STATUS.FAILURE end
    if TTTBots.Behaviors.AttackTarget.IsTargetAlly(bot) then return STATUS.FAILURE end
    if target == bot then
        bot:SetAttackTarget(nil)
        return STATUS.FAILURE
    end

    -- If we don't have the flamethrower, fall through to let normal AttackTarget handle it
    if not ArsonistAttack.GetFlamethrower(bot) then
        return STATUS.FAILURE
    end

    -- Keep flamethrower equipped
    ArsonistAttack.EquipFlamethrower(bot)

    local activeWep = bot:GetActiveWeapon()
    if not IsValid(activeWep) then
        local loco = bot:BotLocomotor()
        if loco then loco:StopAttack() end
        return STATUS.RUNNING
    end

    local canShoot = lib.CanShoot(bot, target)

    if canShoot then
        ArsonistAttack.Engage(bot, target)
        bot.arsonistSeekStart = nil
    else
        ArsonistAttack.Seek(bot, target)

        if bot.arsonistSeekStart and (CurTime() - bot.arsonistSeekStart) > ArsonistAttack.SEEK_TIMEOUT then
            return STATUS.FAILURE
        end
    end

    return STATUS.RUNNING
end

function ArsonistAttack.OnSuccess(bot)
end

function ArsonistAttack.OnFailure(bot)
end

function ArsonistAttack.OnEnd(bot)
    bot:SetAttackTarget(nil)
    bot.arsonistSeekStart = nil
    local loco = bot:BotLocomotor()
    local inv = bot:BotInventory()
    if loco then
        loco.stopLookingAround = false
        loco:StopAttack()
        loco:SetForceForward(false)
    end
    if inv then
        inv:ResumeAutoSwitch()
    end
end
