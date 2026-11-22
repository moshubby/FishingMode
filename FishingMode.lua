-- FishingMode: /fishing toggles fishing mode.
-- In fishing mode one key does everything:
--   not fishing  -> casts Fishing
--   bobber out   -> interacts with the bobber (soft-target interact, no hovering needed)
--   loot window  -> everything is looted automatically
-- Sound is adjusted while fishing so the bobber splash stands out.

local ADDON = ...

-- Modern API with fallbacks to the old globals
local GetSpellName   = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end
local GetNumSlots    = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetBagItemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
local GetItemInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local EquipItem      = (C_Item and C_Item.EquipItemByName) or EquipItemByName

local FISHING = GetSpellName(7620) or "Fishing"

-- Sound channels we control while fishing (the splash is an SFX sound)
local SOUNDS = {
    { key = "master",   cvar = "Sound_MasterVolume",   label = "Master",   default = 1.0 },
    { key = "sfx",      cvar = "Sound_SFXVolume",      label = "Effects (splash)", default = 1.0 },
    { key = "music",    cvar = "Sound_MusicVolume",    label = "Music",    default = 0.0 },
    { key = "ambience", cvar = "Sound_AmbienceVolume", label = "Ambience", default = 0.0 },
    { key = "dialog",   cvar = "Sound_DialogVolume",   label = "Dialog",   default = 0.0 },
}

local active = false
local savedMain, savedOff   -- weapons we swapped out
local savedCVars = {}       -- cvar -> value to restore on exit

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffFishingMode:|r " .. msg)
end

-- Secure button that casts Fishing (casting needs a secure button + key press)
local castButton = CreateFrame("Button", "FishingModeCastButton", UIParent, "SecureActionButtonTemplate")
castButton:SetAttribute("type", "spell")
castButton:SetAttribute("spell", FISHING)
castButton:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")

-- Frame that owns our temporary key bindings
local owner = CreateFrame("Frame")

---------------------------------------------------------------------------
-- CVar save / restore
---------------------------------------------------------------------------
local function SetTempCVar(cvar, value)
    if savedCVars[cvar] == nil then savedCVars[cvar] = GetCVar(cvar) end
    SetCVar(cvar, value)
end

local function RestoreCVars()
    for cvar, value in pairs(savedCVars) do SetCVar(cvar, value) end
    wipe(savedCVars)
end

local function ApplySound()
    if not active or not FishingModeDB.soundEnabled then return end
    for _, s in ipairs(SOUNDS) do
        SetTempCVar(s.cvar, FishingModeDB.sound[s.key])
    end
end

local function RestoreSound()
    for _, s in ipairs(SOUNDS) do
        if savedCVars[s.cvar] ~= nil then
            SetCVar(s.cvar, savedCVars[s.cvar])
            savedCVars[s.cvar] = nil
        end
    end
end

---------------------------------------------------------------------------
-- Key handling
---------------------------------------------------------------------------
local function BindCast()
    if InCombatLockdown() then return end
    ClearOverrideBindings(owner)
    SetOverrideBindingClick(owner, true, FishingModeDB.key, "FishingModeCastButton", "LeftButton")
end

local function BindInteract()
    if InCombatLockdown() then return end
    ClearOverrideBindings(owner)
    SetOverrideBinding(owner, true, FishingModeDB.key, "INTERACTTARGET")
end

local function Unbind()
    if InCombatLockdown() then return end
    ClearOverrideBindings(owner)
end

local function SetKey(key)
    FishingModeDB.key = key
    Print("Key set to " .. key)
    if active then BindCast() end
end

---------------------------------------------------------------------------
-- Gear swapping
---------------------------------------------------------------------------
local function IsFishingPole(link)
    if not link then return false end
    local _, _, _, _, _, classID, subclassID = GetItemInstant(link)
    return classID == 2 and subclassID == 20 -- Weapon / Fishing Pole
end

local function FindPoleInBags()
    for bag = 0, 4 do
        for slot = 1, (GetNumSlots(bag) or 0) do
            local link = GetBagItemLink(bag, slot)
            if IsFishingPole(link) then return link end
        end
    end
end

local function EquipPole()
    local main = GetInventoryItemLink("player", 16)
    if IsFishingPole(main) then return true end -- already holding one

    local pole = FindPoleInBags()
    if not pole then
        Print("No fishing pole found in your bags.")
        return false
    end
    savedMain = main
    savedOff = GetInventoryItemLink("player", 17)
    EquipItem(pole)
    return true
end

local recheckWeapons = false -- try the swap again once combat ends

local function RestoreWeapons()
    if savedMain then EquipItem(savedMain, 16) end
    if savedOff then EquipItem(savedOff, 17) end
end

-- Called after combat: re-equip anything the game blocked, then forget the links
local function FinishWeaponRestore()
    if savedMain and GetInventoryItemLink("player", 16) ~= savedMain then EquipItem(savedMain, 16) end
    if savedOff and GetInventoryItemLink("player", 17) ~= savedOff then EquipItem(savedOff, 17) end
    savedMain, savedOff = nil, nil
    recheckWeapons = false
    Unbind() -- in case unbinding was blocked too
end

---------------------------------------------------------------------------
-- Mode on/off
---------------------------------------------------------------------------
local function Enter()
    if InCombatLockdown() then Print("Can't enter fishing mode in combat.") return end
    if not EquipPole() then return end
    active = true

    SetTempCVar("SoftTargetInteract", 3) -- let the Interact key grab the bobber
    ApplySound()

    BindCast()
    Print("ON - press [" .. FishingModeDB.key .. "] to cast, again to reel in.")
end

local function Exit(reason)
    active = false
    RestoreCVars()
    RestoreWeapons()
    Unbind()
    recheckWeapons = true
    if not InCombatLockdown() and not UnitAffectingCombat("player") then
        FinishWeaponRestore()
    end
    Print("OFF" .. (reason and (" - " .. reason) or ""))
end

---------------------------------------------------------------------------
-- Options window
---------------------------------------------------------------------------
local options

local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local IGNORED_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true }

local function ModPrefix()
    local p = ""
    if IsAltKeyDown() then p = p .. "ALT-" end
    if IsControlKeyDown() then p = p .. "CTRL-" end
    if IsShiftKeyDown() then p = p .. "SHIFT-" end
    return p
end

local function CreateSlider(parent, s, y)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 20, y)

    local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", 20, y - 18)
    slider:SetSize(240, 16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(0, 1)
    slider:SetValueStep(0.05)
    slider:SetObeyStepOnDrag(true)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })

    local function UpdateLabel(v)
        label:SetText(("%s: %d%%"):format(s.label, math.floor(v * 100 + 0.5)))
    end

    slider:SetScript("OnValueChanged", function(self, value)
        FishingModeDB.sound[s.key] = value
        UpdateLabel(value)
        ApplySound()
    end)

    slider.Refresh = function()
        slider:SetValue(FishingModeDB.sound[s.key])
        UpdateLabel(FishingModeDB.sound[s.key])
    end
    return slider
end

local function CreateOptions()
    local f = CreateFrame("Frame", "FishingModeOptions", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(280, 400)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, "FishingModeOptions") -- close with Escape

    local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if not f.TitleText then title:SetPoint("TOP", 0, -5) end
    title:SetText("FishingMode Options")

    -- Key bind button
    local keyLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    keyLabel:SetPoint("TOPLEFT", 20, -38)
    keyLabel:SetText("Fishing key")

    local keyButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    keyButton:SetPoint("TOPLEFT", 20, -56)
    keyButton:SetSize(240, 24)
    keyButton:RegisterForClicks("AnyUp")

    local listening = false
    local function RefreshKey()
        keyButton:SetText(listening and "Press a key... (Esc to cancel)" or FishingModeDB.key)
    end
    local function StopListening()
        listening = false
        keyButton:EnableKeyboard(false)
        RefreshKey()
    end

    keyButton:SetScript("OnClick", function(self, button)
        if listening then
            -- clicking with a mouse button while listening binds that button
            if button ~= "LeftButton" and button ~= "RightButton" then
                SetKey(ModPrefix() .. (MOUSE_KEYS[button] or button:upper()))
            end
            StopListening()
            return
        end
        listening = true
        self:EnableKeyboard(true)
        self:SetPropagateKeyboardInput(false)
        RefreshKey()
    end)
    keyButton:SetScript("OnKeyDown", function(self, key)
        if IGNORED_KEYS[key] then return end
        if key ~= "ESCAPE" then SetKey(ModPrefix() .. key) end
        StopListening()
    end)
    keyButton:SetScript("OnHide", StopListening)

    -- Sound toggle
    local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 16, -92)
    local checkText = check.text or check.Text or f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    checkText:ClearAllPoints()
    checkText:SetPoint("LEFT", check, "RIGHT", 2, 0)
    checkText:SetText("Change sound while fishing")
    check:SetScript("OnClick", function(self)
        FishingModeDB.soundEnabled = self:GetChecked() and true or false
        if active then
            if FishingModeDB.soundEnabled then ApplySound() else RestoreSound() end
        end
    end)

    -- Volume sliders
    local sliders = {}
    for i, s in ipairs(SOUNDS) do
        sliders[i] = CreateSlider(f, s, -130 - (i - 1) * 50)
    end

    f:SetScript("OnShow", function()
        RefreshKey()
        check:SetChecked(FishingModeDB.soundEnabled)
        for _, sl in ipairs(sliders) do sl.Refresh() end
    end)
    return f
end

local function ToggleOptions()
    options = options or CreateOptions()
    options:SetShown(not options:IsShown())
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function IsFishingSpell(spellID)
    return spellID and GetSpellName(spellID) == FISHING
end

local function LoadSettings()
    FishingModeDB = FishingModeDB or {}
    local db = FishingModeDB
    db.key = db.key or "F"
    if db.soundEnabled == nil then db.soundEnabled = true end
    db.sound = db.sound or {}
    for _, s in ipairs(SOUNDS) do
        if db.sound[s.key] == nil then db.sound[s.key] = s.default end
    end
end

owner:RegisterEvent("ADDON_LOADED")
owner:RegisterEvent("PLAYER_LOGOUT")
owner:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
owner:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
owner:RegisterEvent("LOOT_READY")
owner:RegisterEvent("PLAYER_REGEN_DISABLED")
owner:RegisterEvent("PLAYER_REGEN_ENABLED")

owner:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then LoadSettings() end
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- fires just before combat lockdown, so we can still unbind and swap gear
        if active then Exit("entered combat") end
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        if recheckWeapons then FinishWeaponRestore() end
        return
    end

    if not active then return end

    if event == "PLAYER_LOGOUT" then
        RestoreCVars() -- don't leave the game muted after logging out mid-fishing
    -- channel events: unit, castGUID, spellID
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" and arg1 == "player" and IsFishingSpell(arg3) then
        BindInteract()   -- bobber is out: key now interacts with it
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" and arg1 == "player" and IsFishingSpell(arg3) then
        BindCast()       -- fishing ended: key casts again
    elseif event == "LOOT_READY" and IsFishingLoot() then
        for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
    end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
SLASH_FISHINGMODE1 = "/fishing"
SlashCmdList["FISHINGMODE"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()

    if cmd == "options" or cmd == "config" then
        ToggleOptions()
    elseif cmd == "key" then
        if rest == "" then
            Print("Current key: " .. FishingModeDB.key .. "  (change with /fishing key G)")
        else
            SetKey(rest:upper())
        end
    elseif active then
        Exit()
    else
        Enter()
    end
end
