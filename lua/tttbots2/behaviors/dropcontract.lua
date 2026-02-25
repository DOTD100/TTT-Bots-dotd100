--- Behavior: DropContract
--- The Pirate Captain spawns with a Contract weapon (weapon_ttt2_contract).
--- Attacking with it drops it on the ground. When another player walks over
--- and picks it up, the pirate crew becomes bound to fight for that player's
--- team. This behavior makes the Captain bot find a suitable nearby player,
--- walk up to them, and drop the contract at their feet.
---
--- The addon's Equip/MakeContract handles the actual binding — we just need
--- the Captain to physically drop the weapon near someone.
---
--- Once the contract is dropped and picked up, or if the Captain no longer
--- has the contract, this behavior exits.

TTTBots.Behaviors.DropContract = {}

local lib = TTTBots.Lib

local DropContract = TTTBots.Behaviors.DropContract
DropContract.Name = "DropContract"
DropContract.Description = "Drop the pirate contract near a non-pirate player"
DropContract.Interruptible = true

local STATUS = TTTBots.STATUS

--- How close we need to be to the target before dropping (units)
DropContract.DROP_RANGE = 120
--- How far we'll travel to find a drop target
DropContract.MAX_SEARCH_DIST = 2000
--- Minimum time into the round before dropping (seconds from round start)
DropContract.MIN_ROUND_TIME = 8
--- Maximum time to spend approaching before giving up
DropContract.APPROACH_TIMEOUT = 15

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Check if the bot has the contract weapon in inventory
---@param bot Player
---@return Entity|nil contractWep
function DropContract.GetContract(bot)
    if not (IsValid(bot) and bot:IsPlayer()) then return nil end
    for _, wep in pairs(bot:GetWeapons()) do
        if IsValid(wep) and wep:GetClass() == "weapon_ttt2_contract" then
            return wep
        end
    end
    return nil
end

--- Find the best player to drop the contract near.
--- Prefers non-pirate, non-jester, alive players who are nearby.
--- Slightly prefers players who are isolated (fewer witnesses to the drop).
---@param bot Player
---@return Player|nil target
function DropContract.FindDropTarget(bot)
    local alive = TTTBots.Match.AlivePlayers or {}
    local botPos = bot:GetPos()
    local bestTarget = nil
    local bestScore = -math.huge

    TEAM_PIRATE = TEAM_PIRATE or TEAM_PIR or "pirates"
    TEAM_JESTER = TEAM_JESTER or "jesters"

    for _, ply in pairs(alive) do
        if not (IsValid(ply) and lib.IsPlayerAlive(ply)) then continue end
        if ply == bot then continue end

        -- Skip other pirates (they're already on our team)
        local plyTeam = ply:GetTeam()
        if plyTeam == TEAM_PIRATE then continue end

        -- Skip jesters (don't want to bind to jester team)
        if plyTeam == TEAM_JESTER then continue end

        local dist = botPos:Distance(ply:GetPos())
        if dist > DropContract.MAX_SEARCH_DIST then continue end

        -- Score: prefer closer players, slight bonus for isolation
        local score = 1000 - dist
        local isolation = lib.RateIsolation and lib.RateIsolation(bot, ply) or 0
        score = score + isolation * 50

        if score > bestScore then
            bestScore = score
            bestTarget = ply
        end
    end

    return bestTarget
end

---------------------------------------------------------------------------
-- Behavior interface
---------------------------------------------------------------------------

function DropContract.Validate(bot)
    -- Must be a pirate captain
    local roleStr = bot:GetRoleStringRaw()
    if roleStr ~= "pirate_captain" then return false end

    -- Must have the contract weapon
    local contract = DropContract.GetContract(bot)
    if not contract then return false end

    -- Must have already dropped it? Check AllowDrop
    if contract.AllowDrop == false then return false end

    -- Don't drop too early in the round
    local matchTime = TTTBots.Match.Time and TTTBots.Match.Time() or 0
    if matchTime < DropContract.MIN_ROUND_TIME then return false end

    -- Must have a valid target to drop near
    local target = DropContract.FindDropTarget(bot)
    if not target then return false end

    return true
end

function DropContract.OnStart(bot)
    local target = DropContract.FindDropTarget(bot)
    bot.contractTarget = target
    bot.contractPhase = "approach"
    bot.contractStartTime = CurTime()

    return STATUS.RUNNING
end

function DropContract.OnRunning(bot)
    local target = bot.contractTarget
    local loco = bot:BotLocomotor()
    local inv = bot:BotInventory()

    -- Abort if target is no longer valid
    if not (IsValid(target) and lib.IsPlayerAlive(target)) then
        return STATUS.FAILURE
    end

    -- Abort if we lost the contract
    local contract = DropContract.GetContract(bot)
    if not contract then
        return STATUS.SUCCESS -- Contract was dropped/picked up, we're done
    end

    -- Abort if AllowDrop became false (already dropped once)
    if contract.AllowDrop == false then
        return STATUS.SUCCESS
    end

    -- Timeout check
    if CurTime() - (bot.contractStartTime or 0) > DropContract.APPROACH_TIMEOUT then
        -- Try a new target next time
        return STATUS.FAILURE
    end

    local dist = bot:GetPos():Distance(target:GetPos())

    if bot.contractPhase == "approach" then
        -- Navigate toward the target
        loco:SetGoal(target:GetPos())
        loco:LookAt(target:EyePos())

        if dist <= DropContract.DROP_RANGE then
            bot.contractPhase = "drop"
        end

        return STATUS.RUNNING
    end

    if bot.contractPhase == "drop" then
        -- Equip the contract weapon
        if inv then inv:PauseAutoSwitch() end
        pcall(bot.SelectWeapon, bot, "weapon_ttt2_contract")

        -- Look at the target
        loco:LookAt(target:EyePos())

        -- Drop the contract directly via DropWeapon (same as PrimaryAttack does)
        -- This is more reliable for bots than simulating a key press
        if contract.AllowDrop then
            bot:DropWeapon(contract)
        end

        -- Announce in chat
        local chatter = bot:BotChatter()
        if chatter then
            chatter:Say("DroppedContract", { target = target:Nick() })
        end

        -- Resume auto-switch after brief delay
        timer.Simple(0.3, function()
            if not IsValid(bot) then return end
            local i = bot:BotInventory()
            if i then i:ResumeAutoSwitch() end
        end)

        bot.contractPhase = "done"
        return STATUS.RUNNING
    end

    if bot.contractPhase == "done" then
        -- Contract should have been dropped. Resume auto-switch and finish.
        if inv then inv:ResumeAutoSwitch() end
        return STATUS.SUCCESS
    end

    return STATUS.FAILURE
end

function DropContract.OnEnd(bot)
    bot.contractTarget = nil
    bot.contractPhase = nil
    bot.contractStartTime = nil

    local inv = bot:BotInventory()
    if inv then inv:ResumeAutoSwitch() end
end

return true
