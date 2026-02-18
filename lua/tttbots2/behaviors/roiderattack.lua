--- Roider-specific attack behavior. Forces the bot to always use the crowbar (melee weapon)
--- since the Roider role can only deal damage with melee attacks.
--- This behavior replaces the normal AttackTarget in the Roider's behavior tree.

---@class BRoiderAttack
TTTBots.Behaviors.RoiderAttack = {}

local lib = TTTBots.Lib

---@class BRoiderAttack
local RoiderAttack = TTTBots.Behaviors.RoiderAttack
RoiderAttack.Name = "RoiderAttack"
RoiderAttack.Description = "Attack target with crowbar (Roider)"
RoiderAttack.Interruptible = true

RoiderAttack.RUSH_RANGE = 160      --- Max distance to swing the crowbar
RoiderAttack.CLOSE_RANGE = 70      --- Distance at which we stop moving and just swing
RoiderAttack.SEEK_TIMEOUT = 15     --- Seconds before giving up on an unseen target

local STATUS = TTTBots.STATUS

--- Validate the behavior -- piggyback off the normal attack validation
function RoiderAttack.Validate(bot)
    return TTTBots.Behaviors.AttackTarget.Validate(bot)
end

--- Called when the behavior is started
function RoiderAttack.OnStart(bot)
    local inv = bot:BotInventory()
    if inv then
        inv:PauseAutoSwitch() -- Prevent the bot from switching away from the crowbar
    end
    bot.roiderSeekStart = nil
    return STATUS.RUNNING
end

--- Force-equip the crowbar. Returns true if the bot has a crowbar equipped.
---@param bot Bot
---@return boolean
function RoiderAttack.EquipCrowbar(bot)
    local inv = bot:BotInventory()
    if not inv then return false end

    -- Try the standard melee equip
    inv:EquipMelee()

    -- Verify we're holding melee
    local held = inv:GetHeldWeaponInfo()
    return held and not held.is_gun
end

--- Seek mode: we know where the target was but can't shoot them yet. Rush towards them.
---@param bot Bot
---@param target Player
function RoiderAttack.Seek(bot, target)
    local loco = bot:BotLocomotor()
    if not loco then return end
    loco.stopLookingAround = false
    loco:StopAttack()

    ---@type CMemory
    local memory = bot.components.memory
    local lastKnownPos = memory:GetSuspectedPositionFor(target) or memory:GetKnownPositionFor(target)
    local lastSeenTime = memory:GetLastSeenTime(target)
    local secsSince = CurTime() - lastSeenTime

    -- Track how long we've been seeking
    if not bot.roiderSeekStart then
        bot.roiderSeekStart = CurTime()
    end

    if lastKnownPos and secsSince < RoiderAttack.SEEK_TIMEOUT then
        loco:SetGoal(lastKnownPos)
        loco:LookAt(lastKnownPos + Vector(0, 0, 40))
    else
        -- Wander towards random nav areas to find the target
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

--- Engage mode: we can see the target, rush in and swing the crowbar.
---@param bot Bot
---@param target Player
function RoiderAttack.Engage(bot, target)
    local loco = bot:BotLocomotor()
    if not loco then return end
    loco.stopLookingAround = true

    local targetPos = target:GetPos()
    local distToTarget = bot:GetPos():Distance(targetPos)

    -- Always equip crowbar
    RoiderAttack.EquipCrowbar(bot)

    -- Rush towards the target - Roiders are melee, so always close the gap
    if distToTarget > RoiderAttack.CLOSE_RANGE then
        loco:SetGoal(targetPos)
        loco:SetForceForward(true)
    else
        loco:StopMoving()
        loco:SetForceForward(false)
    end

    -- Look at the target's body
    local aimPos = TTTBots.Behaviors.AttackTarget.GetTargetBodyPos(target)
    local predictedPoint = aimPos + TTTBots.Behaviors.AttackTarget.PredictMovement(target, 0.3)
    loco:LookAt(predictedPoint)

    -- Swing if close enough and looking at the target
    local tooFar = distToTarget > RoiderAttack.RUSH_RANGE
    if not tooFar then
        if TTTBots.Behaviors.AttackTarget.LookingCloseToTarget(bot, target) then
            if not TTTBots.Behaviors.AttackTarget.WillShootingTeamkill(bot, target) then
                loco:StartAttack()
            end
        end
    else
        loco:StopAttack()
    end

    -- Strafe a bit when very close to be harder to hit
    if distToTarget < 200 and distToTarget > RoiderAttack.CLOSE_RANGE then
        local strafeDir = math.random(0, 1) == 0 and "left" or "right"
        loco:Strafe(strafeDir)
    end
end

--- Called when the behavior's last state is running
---@param bot Bot
---@return BStatus
function RoiderAttack.OnRunning(bot)
    local target = bot.attackTarget

    -- Validate target using the standard attack validation
    if not TTTBots.Behaviors.AttackTarget.ValidateTarget(bot) then return STATUS.FAILURE end
    if TTTBots.Behaviors.AttackTarget.IsTargetAlly(bot) then return STATUS.FAILURE end
    if target == bot then
        bot:SetAttackTarget(nil)
        return STATUS.FAILURE
    end

    -- Force crowbar equipped
    RoiderAttack.EquipCrowbar(bot)

    -- Determine if we can see/shoot the target
    local canShoot = lib.CanShoot(bot, target)

    if canShoot then
        RoiderAttack.Engage(bot, target)
        bot.roiderSeekStart = nil -- Reset seek timer when we can see them
    else
        RoiderAttack.Seek(bot, target)

        -- Give up if we've been seeking too long
        if bot.roiderSeekStart and (CurTime() - bot.roiderSeekStart) > RoiderAttack.SEEK_TIMEOUT then
            return STATUS.FAILURE
        end
    end

    return STATUS.RUNNING
end

--- Called when the behavior returns a success state
function RoiderAttack.OnSuccess(bot)
end

--- Called when the behavior returns a failure state
function RoiderAttack.OnFailure(bot)
end

--- Called when the behavior ends
function RoiderAttack.OnEnd(bot)
    bot:SetAttackTarget(nil)
    bot.roiderSeekStart = nil
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
