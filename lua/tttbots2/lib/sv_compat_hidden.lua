---------------------------------------------------------------------------
-- Hidden Role Compatibility Patch
---------------------------------------------------------------------------
-- The [TTT2] Hidden [ROLE] addon (Workshop ID 2487229784) has a bug in
-- sh_hd_handler.lua where several hooks call ply:GetSubRole() without
-- first validating that the entity is a player with role data.
--
-- The primary crash at line ~331 is in the "ScalePlayerDamage" hook
-- ("HiddenDmgPreTransform") which does:
--     local attacker = dmginfo:GetAttacker()
--     if attacker:GetSubRole() ~= ROLE_HIDDEN then return end
--
-- dmginfo:GetAttacker() can return ANY entity (world, prop_physics, C4,
-- fire, trigger_hurt, etc.) — none of which have GetSubRole(). This
-- produces: "attempt to call method 'GetSubRole' (a nil value)"
--
-- Similarly, "PlayerSpawn" ("TTT2HiddenRespawn") calls ply:GetSubRole()
-- before TTT2 has initialized role data on the entity.
--
-- Since we can't modify the Hidden addon, we re-register those specific
-- hooks with fixed versions that add proper validation guards. Using the
-- same hook identifiers overwrites the originals cleanly.
---------------------------------------------------------------------------

-- Only apply when the Hidden role addon is installed
if not ROLE_HIDDEN then return end

-- Wait until after all addons have loaded, so the Hidden addon's hooks
-- are already registered and we can safely overwrite them.
hook.Add("InitPostEntity", "TTTBots.Compat.HiddenPatch", function()

    -------------------------------------------------------------------
    -- Fix 1: ScalePlayerDamage — the main crash
    -- GetAttacker() returns non-player entities (world, props, C4, fire)
    -------------------------------------------------------------------
    hook.Add("ScalePlayerDamage", "HiddenDmgPreTransform", function(ply, _, dmginfo)
        local attacker = dmginfo:GetAttacker()

        -- Guard: attacker might be world, prop, C4, fire, etc.
        if not IsValid(attacker) or not attacker:IsPlayer() then return end
        if not attacker.GetSubRole then return end

        if attacker:GetSubRole() ~= ROLE_HIDDEN then return end
        if attacker:GetNWBool("ttt2_hd_stalker_mode") then return end

        dmginfo:ScaleDamage(0.2)
    end)

    -------------------------------------------------------------------
    -- Fix 2: PlayerSpawn — can fire before TTT2 role init
    -------------------------------------------------------------------
    hook.Add("PlayerSpawn", "TTT2HiddenRespawn", function(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        if not ply.GetSubRole then return end

        if ply:GetSubRole() ~= ROLE_HIDDEN then return end
        ply:SetStalkerMode(false)
    end)

    -------------------------------------------------------------------
    -- Fix 3: DoPlayerDeath — guard for edge timing
    -------------------------------------------------------------------
    hook.Add("DoPlayerDeath", "TTT2HiddenDied", function(ply, attacker, dmgInfo)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        if not ply.GetSubRole then return end

        if ply:GetSubRole() ~= ROLE_HIDDEN or not ply:GetNWBool("ttt2_hd_stalker_mode", false) then return end

        ply:SetStalkerMode(false)
        net.Start("ttt2_hdn_epop_defeat")
        net.WriteString(ply:Nick())
        net.Broadcast()
    end)

    -------------------------------------------------------------------
    -- Fix 4: TTTPlayerSpeedModifier — guard GetSubRole
    -------------------------------------------------------------------
    hook.Add("TTTPlayerSpeedModifier", "HiddenSpeedBonus", function(ply, _, _, speedMod)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        if not ply.GetSubRole then return end

        if ply:GetSubRole() ~= ROLE_HIDDEN or not ply:GetNWBool("ttt2_hd_stalker_mode") then return end

        speedMod[1] = speedMod[1] * 1.6
    end)

    -------------------------------------------------------------------
    -- Fix 5: TTT2StaminaRegen — guard GetSubRole
    -------------------------------------------------------------------
    hook.Add("TTT2StaminaRegen", "HiddenStaminaMod", function(ply, stamMod)
        if not IsValid(ply) or not ply:Alive() or ply:IsSpec() then return end
        if not ply.GetSubRole then return end

        if ply:GetSubRole() ~= ROLE_HIDDEN or not ply:GetNWBool("ttt2_hd_stalker_mode") then return end

        stamMod[1] = stamMod[1] * 1.5
    end)

    -------------------------------------------------------------------
    -- Fix 6: PlayerCanPickupWeapon (NoHiddenPickups) — guard GetSubRole
    -------------------------------------------------------------------
    hook.Add("PlayerCanPickupWeapon", "NoHiddenPickups", function(ply, wep)
        if not IsValid(ply) or not ply:Alive() or ply:IsSpec() then return end
        if not ply.GetSubRole then return end

        if ply:GetSubRole() ~= ROLE_HIDDEN or not ply:GetNWBool("ttt2_hd_stalker_mode", false) then return end

        return (wep:GetClass() == "weapon_ttt_hd_knife" or wep:GetClass() == "weapon_ttt_hd_nade")
    end)

    -------------------------------------------------------------------
    -- Fix 7: PlayerCanPickupWeapon (NoPickupHiddenKnife) — guard GetSubRole
    -------------------------------------------------------------------
    hook.Add("PlayerCanPickupWeapon", "NoPickupHiddenKnife", function(ply, wep)
        if wep:GetClass() ~= "weapon_ttt_hd_knife" then return end
        if not IsValid(ply) or not ply:Alive() or ply:IsSpec() then return end
        if not ply.GetSubRole then return end

        return ply:GetSubRole() == ROLE_HIDDEN
    end)

    -- One-shot: remove this InitPostEntity hook after patching
    hook.Remove("InitPostEntity", "TTTBots.Compat.HiddenPatch")
end)
