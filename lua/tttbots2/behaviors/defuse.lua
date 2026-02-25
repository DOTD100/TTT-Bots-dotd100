
TTTBots.Behaviors.Defuse = {}

local lib = TTTBots.Lib

local Defuse = TTTBots.Behaviors.Defuse
Defuse.Name = "Defuse"
Defuse.Description = "Defuse a spotted bomb"
Defuse.Interruptible = true

Defuse.DEFUSE_RANGE = 80       --- The maximum range that a defuse attempt can be made
Defuse.ABANDON_TIME = 5        --- Seconds until explosion to abandon defuse attempt
Defuse.DEFUSE_WIN_CHANCE = 3   --- 1 in X chance of a successful defuse
Defuse.DEFUSE_TRY_CHANCE = 30  --- 1 in X chance of attempting to defuse (per tick) if other conditions not met
Defuse.DEFUSE_TIME_DELAY = 1.5 --- Seconds to wait before defusing (when within range!)

local STATUS = TTTBots.STATUS

---@class Bot
---@field lastDefuseTime number The last time the bot attempted to defuse a bomb


---Returns true if a bot is able to defuse C4 per their role data.
---@param bot Bot
---@return boolean
function Defuse.IsBotEligableRole(bot)
    local role = TTTBots.Roles.GetRoleFor(bot) ---@type RoleData
    if not role then return false end
    return role:GetDefusesC4()
end

---Return whether or not a bot is elligible to defuse a C4 (does not factor in if there is one nearby)
---@param bot Bot
---@return boolean eligible, boolean hasPriority
function Defuse.IsEligible(bot)
    if not lib.IsPlayerAlive(bot) then return false, false end
    if not Defuse.IsBotEligableRole(bot) then return false, false end

    local hasDefuseKit = bot:HasWeapon("weapon_ttt_defuser")
    local isPolice = TTTBots.Roles.GetRoleFor(bot):GetAppearsPolice()

    -- A detective/police with a defuser kit ALWAYS defuses (highest priority)
    if hasDefuseKit and isPolice then
        return true, true
    end

    -- A detective/police without a kit still gets a good chance
    if isPolice then
        return true, false
    end

    -- Anyone with a defuser kit gets guaranteed eligibility
    if hasDefuseKit then
        return true, true
    end

    -- Other roles: trait-based or random chance
    local personality = bot:BotPersonality()
    if not personality then return false, false end

    local isDefuser = personality:GetTraitBool("defuser")
    local chance = math.random(1, Defuse.DEFUSE_TRY_CHANCE) == 1

    if isDefuser or chance then
        return true, false
    end

    return false, false
end

---Returns the first visible C4 that has been spotted
---@param bot Bot
---@return Entity|nil C4
function Defuse.GetVisibleC4(bot)
    local allC4 = TTTBots.Match.AllArmedC4s
    for bomb, _ in pairs(allC4) do
        if not Defuse.IsC4Defusable(bomb) then continue end
        if lib.CanSeeArc(bot, bomb:GetPos() + Vector(0, 0, 16), 120) then
            return bomb
        end
    end

    return nil
end

--- Validate the behavior
function Defuse.Validate(bot)
    if not lib.GetConVarBool("defuse_c4") then return false end -- This behavior is disabled per the user's choice.
    if not TTTBots.Match.IsRoundActive() then return false end
    if not Defuse.IsBotEligableRole(bot) then return false end
    if bot.defuseTarget ~= nil then return true end

    local eligible, hasPriority = Defuse.IsEligible(bot)
    if not eligible then return false end

    local c4 = Defuse.GetVisibleC4(bot)
    if not c4 then return false end

    -- If another non-priority bot is already defusing this C4, a priority bot
    -- (detective with kit) can take over. Non-priority bots defer.
    if not hasPriority then
        -- Check if a priority defuser is already on this bomb
        for _, other in pairs(TTTBots.Bots) do
            if other == bot then continue end
            if not (IsValid(other) and lib.IsPlayerAlive(other)) then continue end
            if other.defuseTarget == c4 and other.defusePriority then
                return false -- A priority defuser is on the job, stand down
            end
        end
    end

    bot.defusePriority = hasPriority
    return true
end

--- Called when the behavior is started
function Defuse.OnStart(bot)
    bot.defuseTarget = Defuse.GetVisibleC4(bot)

    local chatter = bot:BotChatter()
    if not chatter then return end
    chatter:On("DefusingC4")

    return STATUS.RUNNING
end

function Defuse.IsC4Defusable(c4)
    if c4 == NULL then return false end
    if not IsValid(c4) then return false end
    if not c4:GetArmed() then return false end
    if c4:GetExplodeTime() <= CurTime() then return false end

    return true
end

function Defuse.GetTimeUntilExplode(c4)
    local explodeTime = c4:GetExplodeTime()
    local ct = CurTime()
    return explodeTime - ct
end

---Wrapper function to defuse a C4; called internally by Defuse.TryDefuse
---@param bot Bot
---@param c4 C4
---@param isSuccess boolean If true then actually defuses, otherwise KABOOM!
function Defuse.DefuseC4(bot, c4, isSuccess)
    if (bot.lastDefuseTime or 0) + Defuse.DEFUSE_TIME_DELAY > CurTime() then return end
    bot.lastDefuseTime = CurTime()
    timer.Simple(Defuse.DEFUSE_TIME_DELAY, function()
        if not Defuse.IsC4Defusable(c4) then return end
        if not (bot and lib.IsPlayerAlive(bot)) then return end
        if isSuccess then
            c4:Disarm(bot)

            local chatter = bot:BotChatter()
            if not chatter then return end
            chatter:On("DefusingSuccessful")
            Defuse.DestroyC4(c4)
        else
            c4:FailedDisarm(bot)
            -- No need to chat. We are dead.
        end
    end)
end

function Defuse.TryDefuse(bot, c4)
    local dist = bot:GetPos():Distance(c4:GetPos())

    if (dist > Defuse.DEFUSE_RANGE) then return nil end -- not close enough yet

    local hasDefuser = bot:HasWeapon("weapon_ttt_defuser")

    -- With a defuser kit: always safe
    if hasDefuser then
        Defuse.DefuseC4(bot, c4, true)
        return true
    end

    -- Without a defuser kit: one attempt only.
    -- If the bot already tried this bomb, don't re-roll — the result is locked in.
    if bot.defuseAttempted then
        return bot.defuseResult
    end

    bot.defuseAttempted = true
    local isSuccessful = math.random(1, Defuse.DEFUSE_WIN_CHANCE) == 1
    bot.defuseResult = isSuccessful
    Defuse.DefuseC4(bot, c4, isSuccessful)

    return isSuccessful
end

function Defuse.DestroyC4(c4)
    util.EquipmentDestroyed(c4:GetPos())
    c4:Remove()
end

function Defuse.ShouldAbandon(c4)
    local timeUntilExplode = Defuse.GetTimeUntilExplode(c4)
    return timeUntilExplode <= Defuse.ABANDON_TIME
end

--- Called when the behavior's last state is running
function Defuse.OnRunning(bot)
    local bomb = bot.defuseTarget
    if not Defuse.IsC4Defusable(bomb) then
        return STATUS.FAILURE
    end

    if Defuse.ShouldAbandon(bomb) then
        return STATUS.FAILURE
    end

    local result = Defuse.TryDefuse(bot, bomb)
    -- nil  = not close enough yet, keep moving
    -- true = defuse succeeded (or will succeed after the timer)
    -- false = wrong wire, bomb will explode after the timer
    if result == true then
        return STATUS.SUCCESS
    elseif result == false then
        -- Wrong wire — bot is committed, nothing more to do. The DefuseC4
        -- timer will call FailedDisarm shortly. Return FAILURE so the bot
        -- stops standing next to the bomb and possibly runs.
        return STATUS.FAILURE
    end

    -- Still approaching — navigate to the bomb
    local locomotor = bot:BotLocomotor()
    if not locomotor then return STATUS.FAILURE end

    local bombPos = bomb:GetPos()
    locomotor:SetGoal(bombPos)
    locomotor:LookAt(bombPos)

    return STATUS.RUNNING
end

--- Called when the behavior returns a success state
function Defuse.OnSuccess(bot)
end

--- Called when the behavior returns a failure state
function Defuse.OnFailure(bot)
end

--- Called when the behavior ends
function Defuse.OnEnd(bot)
    bot.defuseTarget = nil
    bot.defusePriority = nil
    bot.defuseAttempted = nil
    bot.defuseResult = nil
end
