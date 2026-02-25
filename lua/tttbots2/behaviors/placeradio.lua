--- PlaceRadio behavior: Bots with the radio trait deploy a radio in a spot
--- where innocent players congregate, then periodically trigger distraction
--- sounds remotely. The radio weapon in TTT works by placing it on the ground
--- (primary fire), which creates a ttt_radio entity that the owner can trigger.
--- Since bots can't use the radio's VGUI, we auto-trigger sounds via the
--- entity's PlaySound method after placement.

---@class BPlaceRadio
TTTBots.Behaviors.PlaceRadio = {}

local lib = TTTBots.Lib

---@class BPlaceRadio
local PlaceRadio = TTTBots.Behaviors.PlaceRadio
PlaceRadio.Name = "PlaceRadio"
PlaceRadio.Description = "Place a radio to distract innocent players with sounds."
PlaceRadio.Interruptible = true

PlaceRadio.PLACE_DELAY = 15          --- Seconds into the round before placing (don't place immediately)
PlaceRadio.SOUND_INTERVAL_MIN = 15   --- Minimum seconds between radio sounds
PlaceRadio.SOUND_INTERVAL_MAX = 40   --- Maximum seconds between radio sounds

local STATUS = TTTBots.STATUS

--- Available radio sound commands (these are the standard TTT radio sounds).
local RADIO_SOUNDS = {
    "scream",
    "explosion",
    "pistol",
    "shotgun",
    "rifle",
    "huge",
    "beep",
    "burning",
}

--- Find the radio weapon in the bot's inventory.
---@param bot Bot
---@return Weapon|nil
function PlaceRadio.GetRadioWeapon(bot)
    if bot:HasWeapon("weapon_ttt_radio") then
        return bot:GetWeapon("weapon_ttt_radio")
    end
    return nil
end

--- Validate: only runs for bots with the radio trait who have a radio weapon
--- and haven't placed one yet.
---@param bot Bot
---@return boolean
function PlaceRadio.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not IsValid(bot) then return false end

    -- Must have radio trait
    if not bot:GetTraitBool("radio") then return false end

    -- Already placed? Don't run again.
    if bot.tttbots_radioPlaced then return false end

    -- Must have the radio weapon
    if not PlaceRadio.GetRadioWeapon(bot) then return false end

    -- Wait a bit into the round before placing
    if TTTBots.Match.Time() < PlaceRadio.PLACE_DELAY then return false end

    return true
end

---@param bot Bot
---@return BStatus
function PlaceRadio.OnStart(bot)
    bot.radioPlacePhase = "navigate"
    bot.radioPlaceTarget = nil

    -- Find a popular navigation area where innocents tend to gather
    local popularNav = nil
    if TTTBots.PopularNavs and TTTBots.PopularNavs.GetMostPopular then
        local popular = TTTBots.PopularNavs.GetMostPopular(5)
        if popular and #popular > 0 then
            popularNav = popular[math.random(#popular)]
        end
    end

    -- Fallback: pick a random nav area
    if not popularNav then
        local allNavs = navmesh.GetAllNavAreas()
        if allNavs and #allNavs > 0 then
            popularNav = allNavs[math.random(#allNavs)]
        end
    end

    if popularNav and IsValid(popularNav) then
        bot.radioPlaceTarget = popularNav:GetCenter()
    end

    return STATUS.RUNNING
end

---@param bot Bot
---@return BStatus
function PlaceRadio.OnRunning(bot)
    local loco = bot:BotLocomotor()
    if not loco then return STATUS.FAILURE end
    local inv = bot:BotInventory()

    local phase = bot.radioPlacePhase or "navigate"

    ---------------------------------------------------------------------------
    -- PHASE: NAVIGATE — go to a popular area
    ---------------------------------------------------------------------------
    if phase == "navigate" then
        local target = bot.radioPlaceTarget
        if not target then return STATUS.FAILURE end

        loco:SetGoal(target)

        local dist = bot:GetPos():Distance(target)
        if dist < 200 then
            bot.radioPlacePhase = "place"
        end

        return STATUS.RUNNING
    end

    ---------------------------------------------------------------------------
    -- PHASE: PLACE — equip and drop the radio
    ---------------------------------------------------------------------------
    if phase == "place" then
        local radio = PlaceRadio.GetRadioWeapon(bot)
        if not (radio and IsValid(radio)) then
            -- Radio gone (maybe dropped or removed)
            return STATUS.FAILURE
        end

        -- Equip the radio
        local activeWep = bot:GetActiveWeapon()
        if not (IsValid(activeWep) and activeWep == radio) then
            pcall(bot.SelectWeapon, bot, radio:GetClass())
            if inv then inv:PauseAutoSwitch() end
            return STATUS.RUNNING
        end

        -- Look at the ground ahead and place it (primary fire)
        local groundPos = bot:GetPos() + bot:GetForward() * 50
        loco:LookAt(groundPos)
        loco:StartAttack()

        -- After a brief moment, stop attacking and mark as placed
        timer.Simple(0.3, function()
            if not IsValid(bot) then return end
            local botLoco = bot:BotLocomotor()
            if botLoco then botLoco:StopAttack() end

            bot.tttbots_radioPlaced = true

            -- Find the radio entity we just placed
            timer.Simple(0.5, function()
                if not IsValid(bot) then return end
                local radios = ents.FindByClass("ttt_radio")
                local bestRadio = nil
                local bestDist = math.huge
                for _, ent in ipairs(radios) do
                    if not IsValid(ent) then continue end
                    -- The radio's owner should be us
                    local owner = ent:GetNWEntity("ttt_radio_owner", nil)
                        or ent.GetOwner and ent:GetOwner()
                    if owner == bot then
                        local d = bot:GetPos():Distance(ent:GetPos())
                        if d < bestDist then
                            bestDist = d
                            bestRadio = ent
                        end
                    end
                end

                -- Fallback: find the closest radio if owner check fails
                if not bestRadio then
                    for _, ent in ipairs(radios) do
                        if not IsValid(ent) then continue end
                        local d = bot:GetPos():Distance(ent:GetPos())
                        if d < 200 and d < bestDist then
                            bestDist = d
                            bestRadio = ent
                        end
                    end
                end

                if bestRadio then
                    bot.tttbots_radioEntity = bestRadio
                    -- Start periodic sound triggers
                    PlaceRadio.ScheduleSounds(bot, bestRadio)
                end
            end)

            -- Resume normal weapon
            local botInv = bot:BotInventory()
            if botInv then botInv:ResumeAutoSwitch() end
        end)

        return STATUS.SUCCESS
    end

    return STATUS.FAILURE
end

--- Schedule periodic random sounds on the placed radio.
---@param bot Bot
---@param radioEnt Entity
function PlaceRadio.ScheduleSounds(bot, radioEnt)
    local timerName = "TTTBots.Radio." .. bot:EntIndex()

    local function TriggerRandomSound()
        if not IsValid(bot) or not IsValid(radioEnt) then
            timer.Remove(timerName)
            return
        end
        if not TTTBots.Match.IsRoundActive() then
            timer.Remove(timerName)
            return
        end
        if not TTTBots.Lib.IsPlayerAlive(bot) then
            timer.Remove(timerName)
            return
        end

        -- Pick a random sound and play it on the radio
        local sound = RADIO_SOUNDS[math.random(#RADIO_SOUNDS)]

        -- TTT radios have a PlaySound or similar mechanism
        -- The standard TTT radio entity responds to net messages from its owner,
        -- but we can trigger sounds directly by calling its internal method
        if radioEnt.PlaySound then
            radioEnt:PlaySound(sound)
        elseif radioEnt.Play then
            radioEnt:Play(sound)
        else
            -- Fallback: use the TTT radio net message system
            -- The radio entity stores sound commands and plays them
            -- We simulate the owner sending the play command
            if radioEnt.SetSound then
                radioEnt:SetSound(sound)
            end
            -- Try triggering via Use
            if radioEnt.Use then
                radioEnt:Use(bot, bot, USE_ON, 1)
            end
        end

        -- Schedule next sound
        local nextDelay = math.random(PlaceRadio.SOUND_INTERVAL_MIN, PlaceRadio.SOUND_INTERVAL_MAX)
        timer.Create(timerName, nextDelay, 1, TriggerRandomSound)
    end

    -- First sound after a random delay
    local firstDelay = math.random(PlaceRadio.SOUND_INTERVAL_MIN, PlaceRadio.SOUND_INTERVAL_MAX)
    timer.Create(timerName, firstDelay, 1, TriggerRandomSound)
end

function PlaceRadio.OnSuccess(bot)
end

function PlaceRadio.OnFailure(bot)
end

function PlaceRadio.OnEnd(bot)
    bot.radioPlacePhase = nil
    bot.radioPlaceTarget = nil
    local loco = bot:BotLocomotor()
    if loco then loco:StopAttack() end
    local inv = bot:BotInventory()
    if inv then inv:ResumeAutoSwitch() end
end
