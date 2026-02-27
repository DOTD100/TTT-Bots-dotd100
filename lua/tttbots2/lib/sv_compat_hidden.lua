-- Compatibility patch for [TTT2] Hidden [ROLE] (Workshop 2487229784).
-- Adds GetSubRole() guards to all Hidden hooks.

if not ROLE_HIDDEN then return end

hook.Add("InitPostEntity", "TTTBots.Compat.HiddenPatch", function()
    hook.Add("ScalePlayerDamage", "HiddenDmgPreTransform", function(ply, _, dmginfo)
        local attacker = dmginfo:GetAttacker()
        if not IsValid(attacker) or not attacker:IsPlayer() then return end
        if not attacker.GetSubRole then return end
        if attacker:GetSubRole() ~= ROLE_HIDDEN then return end
        if attacker:GetNWBool("ttt2_hd_stalker_mode") then return end
        dmginfo:ScaleDamage(0.2)
    end)

    hook.Add("PlayerSpawn", "TTT2HiddenRespawn", function(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        if not ply.GetSubRole then return end
        if ply:GetSubRole() ~= ROLE_HIDDEN then return end
        ply:SetStalkerMode(false)
    end)

    hook.Add("DoPlayerDeath", "TTT2HiddenDied", function(ply, attacker, dmgInfo)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        if not ply.GetSubRole then return end
        if ply:GetSubRole() ~= ROLE_HIDDEN or not ply:GetNWBool("ttt2_hd_stalker_mode", false) then return end
        ply:SetStalkerMode(false)
        net.Start("ttt2_hdn_epop_defeat")
        net.WriteString(ply:Nick())
        net.Broadcast()
    end)

    hook.Add("TTTPlayerSpeedModifier", "HiddenSpeedBonus", function(ply, _, _, speedMod)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        if not ply.GetSubRole then return end
        if ply:GetSubRole() ~= ROLE_HIDDEN or not ply:GetNWBool("ttt2_hd_stalker_mode") then return end
        speedMod[1] = speedMod[1] * 1.6
    end)

    hook.Add("TTT2StaminaRegen", "HiddenStaminaMod", function(ply, stamMod)
        if not IsValid(ply) or not ply:Alive() or ply:IsSpec() then return end
        if not ply.GetSubRole then return end
        if ply:GetSubRole() ~= ROLE_HIDDEN or not ply:GetNWBool("ttt2_hd_stalker_mode") then return end
        stamMod[1] = stamMod[1] * 1.5
    end)

    hook.Add("PlayerCanPickupWeapon", "NoHiddenPickups", function(ply, wep)
        if not IsValid(ply) or not ply:Alive() or ply:IsSpec() then return end
        if not ply.GetSubRole then return end
        if ply:GetSubRole() ~= ROLE_HIDDEN or not ply:GetNWBool("ttt2_hd_stalker_mode", false) then return end
        return (wep:GetClass() == "weapon_ttt_hd_knife" or wep:GetClass() == "weapon_ttt_hd_nade")
    end)

    hook.Add("PlayerCanPickupWeapon", "NoPickupHiddenKnife", function(ply, wep)
        if wep:GetClass() ~= "weapon_ttt_hd_knife" then return end
        if not IsValid(ply) or not ply:Alive() or ply:IsSpec() then return end
        if not ply.GetSubRole then return end
        return ply:GetSubRole() == ROLE_HIDDEN
    end)

    hook.Remove("InitPostEntity", "TTTBots.Compat.HiddenPatch")
end)
