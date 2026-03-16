-- KickTracker - Compact party interrupt tracker
local addonName, ns = ...
local ADDON_PREFIX = "KickTrkr"

local INTERRUPTS = {
    [6552]   = { cd = 15, class = "WARRIOR",      name = "Pummel",           icon = 132938 },
    [2139]   = { cd = 24, class = "MAGE",         name = "Counterspell",     icon = 135856 },
    [1766]   = { cd = 15, class = "ROGUE",        name = "Kick",             icon = 132219 },
    [57994]  = { cd = 12, class = "SHAMAN",       name = "Wind Shear",       icon = 136018 },
    [106839] = { cd = 15, class = "DRUID",        name = "Skull Bash",       icon = 236946 },
    [78675]  = { cd = 60, class = "DRUID",        name = "Solar Beam",       icon = 236748 },
    [47528]  = { cd = 15, class = "DEATHKNIGHT",  name = "Mind Freeze",      icon = 237527 },
    [96231]  = { cd = 15, class = "PALADIN",      name = "Rebuke",           icon = 523893 },
    [183752] = { cd = 15, class = "DEMONHUNTER",  name = "Disrupt",          icon = 1305153 },
    [116705] = { cd = 15, class = "MONK",         name = "Spear Hand Strike",icon = 608940 },
    [187707] = { cd = 15, class = "HUNTER",       name = "Muzzle",           icon = 1376045 },
    [147362] = { cd = 24, class = "HUNTER",       name = "Counter Shot",     icon = 249170 },
    [15487]  = { cd = 45, class = "PRIEST",       name = "Silence",          icon = 458230 },
    [351338] = { cd = 40, class = "EVOKER",       name = "Quell",            icon = 4622468 },
    [119910] = { cd = 24, class = "WARLOCK",      name = "Spell Lock",       icon = 136174 },
    [19647]  = { cd = 24, class = "WARLOCK",      name = "Spell Lock",       icon = 136174 },
    [132409] = { cd = 24, class = "WARLOCK",      name = "Spell Lock",       icon = 136174 },
}

local CLASS_KICK = {
    WARRIOR     = 6552,   MAGE        = 2139,   ROGUE       = 1766,
    SHAMAN      = 57994,  DRUID       = 106839, DEATHKNIGHT = 47528,
    PALADIN     = 96231,  DEMONHUNTER = 183752, MONK        = 116705,
    HUNTER      = 187707, PRIEST      = 15487,  EVOKER      = 351338,
    WARLOCK     = 119910,
}

local CLASS_COLORS = {
    WARRIOR     = {0.78,0.61,0.43}, MAGE        = {0.25,0.78,0.92},
    ROGUE       = {1.00,0.96,0.41}, SHAMAN      = {0.00,0.44,0.87},
    DRUID       = {1.00,0.49,0.04}, DEATHKNIGHT = {0.77,0.12,0.23},
    PALADIN     = {0.96,0.55,0.73}, DEMONHUNTER = {0.64,0.19,0.79},
    MONK        = {0.00,1.00,0.60}, HUNTER      = {0.67,0.83,0.45},
    PRIEST      = {1.00,1.00,1.00}, EVOKER      = {0.20,0.58,0.50},
    WARLOCK     = {0.53,0.53,0.93},
}

local activeKicks = {}
local partyMembers = {}
local rows = {}
local mainFrame, menuFrame
local FRAME_WIDTH = 170
local ROW_HEIGHT = 14
local HEADER_HEIGHT = 14
local menuOpen = false

-- Saved settings (persisted via SavedVariables)
local defaults = {
    opacity = 0.45,
    scale = 1.0,
    showSolo = true,
    posX = 300,
    posY = 200,
    frameWidth = 170,
}
local settings

local function ShortName(name)
    if not name then return "?" end
    return name:match("^([^%-]+)") or name
end

----------------------------------------------------------------------
-- Save/Load position
----------------------------------------------------------------------
local function SavePosition()
    if not mainFrame or not settings then return end
    local point, _, relPoint, x, y = mainFrame:GetPoint(1)
    settings.posX = x
    settings.posY = y
end

local function ApplySettings()
    if not mainFrame or not settings then return end
    mainFrame:SetBackdropColor(0.05, 0.05, 0.07, settings.opacity)
    mainFrame:SetBackdropBorderColor(0.25, 0.25, 0.3, settings.opacity * 0.8)
    mainFrame:SetScale(settings.scale)
    FRAME_WIDTH = settings.frameWidth
    mainFrame:SetWidth(FRAME_WIDTH)
    for i = 1, #rows do
        rows[i]:SetWidth(FRAME_WIDTH - 4)
    end
end

----------------------------------------------------------------------
-- Scan party/raid
----------------------------------------------------------------------
local function ScanGroup()
    wipe(partyMembers)

    local myName = UnitName("player")
    local _, myClass = UnitClass("player")
    local myKick = CLASS_KICK[myClass]
    if myName and myKick then
        local info = INTERRUPTS[myKick]
        partyMembers[myName] = {
            name = myName, class = myClass,
            spellID = myKick, icon = info.icon,
        }
    end

    local prefix, count
    if IsInRaid() then
        prefix, count = "raid", 40
    elseif IsInGroup() then
        prefix, count = "party", 4
    else
        return
    end

    for i = 1, count do
        local unit = prefix .. i
        local name = UnitName(unit)
        if name and name ~= myName then
            local _, class = UnitClass(unit)
            if class then
                local kickID = CLASS_KICK[class]
                if kickID then
                    local info = INTERRUPTS[kickID]
                    partyMembers[name] = {
                        name = name, class = class,
                        spellID = kickID, icon = info.icon,
                    }
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- Track & Broadcast
----------------------------------------------------------------------
local function TrackKick(name, class, spellID)
    local info = INTERRUPTS[spellID]
    if not info then return end

    if not partyMembers[name] then
        partyMembers[name] = {
            name = name, class = class or info.class,
            spellID = spellID, icon = info.icon,
        }
    end

    activeKicks[name] = {
        spellID = spellID,
        icon = info.icon,
        expires = GetTime() + info.cd,
        cd = info.cd,
        class = class or info.class,
    }
end

local function BroadcastKick(spellID)
    local channel = nil
    if IsInRaid() then
        channel = "RAID"
    elseif IsInGroup() then
        channel = "PARTY"
    end
    if channel then
        local _, class = UnitClass("player")
        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, spellID .. ":" .. (class or "UNKNOWN"), channel)
    end
end

----------------------------------------------------------------------
-- UI: Row creation
----------------------------------------------------------------------
local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(FRAME_WIDTH - 4, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -HEADER_HEIGHT - (index - 1) * (ROW_HEIGHT + 1))

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0.08, 0.08, 0.1, 0.3)

    row.bar = row:CreateTexture(nil, "ARTWORK", nil, -1)
    row.bar:SetPoint("TOPLEFT", 0, 0)
    row.bar:SetPoint("BOTTOMLEFT", 0, 0)
    row.bar:SetWidth(1)
    row.bar:SetColorTexture(0.3, 0.8, 0.3, 0.3)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
    row.nameText:SetWidth(70)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetFont(row.nameText:GetFont(), 9)

    row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.statusText:SetPoint("RIGHT", -3, 0)
    row.statusText:SetJustifyH("RIGHT")
    row.statusText:SetFont(row.statusText:GetFont(), 9)

    row:Hide()
    return row
end

----------------------------------------------------------------------
-- UI: Update display
----------------------------------------------------------------------
local function UpdateDisplay()
    if not mainFrame then return end
    local now = GetTime()

    local sorted = {}
    for name, member in pairs(partyMembers) do
        sorted[#sorted + 1] = member
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)

    local count = math.min(#sorted, 5)

    for i = 1, count do
        local member = sorted[i]
        local row = rows[i]
        local kick = activeKicks[member.name]

        row.icon:SetTexture(member.icon)

        local cc = CLASS_COLORS[member.class]
        if cc then
            row.nameText:SetTextColor(cc[1], cc[2], cc[3])
        else
            row.nameText:SetTextColor(1, 1, 1)
        end
        row.nameText:SetText(ShortName(member.name))

        if kick then
            local remaining = kick.expires - now
            if remaining <= 0 then
                activeKicks[member.name] = nil
                kick = nil
            end
        end

        local barWidth = FRAME_WIDTH - 4
        if kick then
            local remaining = kick.expires - now
            local pct = remaining / kick.cd

            row.bar:SetWidth(math.max(1, barWidth * pct))
            row.statusText:SetText(string.format("%.1fs", remaining))

            if remaining <= 3 then
                row.bar:SetColorTexture(0.2, 0.8, 0.2, 0.2)
                row.statusText:SetTextColor(0.2, 1, 0.2)
                row.bg:SetColorTexture(0.04, 0.12, 0.04, 0.3)
            elseif remaining <= 8 then
                row.bar:SetColorTexture(0.8, 0.7, 0.1, 0.2)
                row.statusText:SetTextColor(1, 1, 0.3)
                row.bg:SetColorTexture(0.1, 0.08, 0.02, 0.3)
            else
                row.bar:SetColorTexture(0.7, 0.25, 0.1, 0.2)
                row.statusText:SetTextColor(1, 0.5, 0.2)
                row.bg:SetColorTexture(0.1, 0.04, 0.02, 0.3)
            end
        else
            row.bar:SetWidth(barWidth)
            row.bar:SetColorTexture(0.12, 0.35, 0.12, 0.15)
            row.statusText:SetText("Ready")
            row.statusText:SetTextColor(0.3, 1, 0.3)
            row.bg:SetColorTexture(0.08, 0.08, 0.1, 0.3)
        end

        row:SetWidth(FRAME_WIDTH - 4)
        row:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 2, -HEADER_HEIGHT - (i - 1) * (ROW_HEIGHT + 1))
        row:Show()
    end

    for i = count + 1, #rows do
        rows[i]:Hide()
    end

    local totalHeight = HEADER_HEIGHT + (count > 0 and count * (ROW_HEIGHT + 1) + 2 or 8)
    mainFrame:SetHeight(totalHeight)
end

----------------------------------------------------------------------
-- Settings Menu
----------------------------------------------------------------------
local function CreateMenuButton(parent, yOffset, text, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(140, 18)
    btn:SetPoint("TOP", parent, "TOP", 0, yOffset)
    btn:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.15, 0.15, 0.18, 0.8)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.6)

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.label:SetPoint("CENTER")
    btn.label:SetText(text)
    btn.label:SetFont(btn.label:GetFont(), 9)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.25, 0.3, 0.9)
        self:SetBackdropBorderColor(0.8, 0.5, 0.1, 0.8)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.18, 0.8)
        self:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.6)
    end)
    btn:SetScript("OnClick", onClick)

    return btn
end

local function CreateSlider(parent, yOffset, label, minVal, maxVal, step, getter, setter, formatFn)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(140, 30)
    container:SetPoint("TOP", parent, "TOP", 0, yOffset)

    local fmt = formatFn or function(v) return string.format("%.0f%%", v * 100) end

    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOP", 0, 0)
    text:SetFont(text:GetFont(), 8)

    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetSize(120, 10)
    slider:SetPoint("TOP", 0, -10)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider.Low:SetText("")
    slider.High:SetText("")
    slider.Text:SetText("")

    local val = getter()
    slider:SetValue(val)
    text:SetText(label .. ": " .. fmt(val))

    -- Only update label while dragging, apply on release
    slider:SetScript("OnValueChanged", function(self, value)
        text:SetText(label .. ": " .. fmt(value))
    end)
    slider:SetScript("OnMouseUp", function(self)
        setter(self:GetValue())
    end)

    container.slider = slider
    container.text = text
    return container
end

local function ToggleMenu()
    if menuFrame and menuFrame:IsShown() then
        menuFrame:Hide()
        menuOpen = false
        return
    end

    menuOpen = true

    if not menuFrame then
        menuFrame = CreateFrame("Frame", "KickTrackerMenu", UIParent, "BackdropTemplate")
        menuFrame:SetSize(160, 245)
        menuFrame:SetFrameStrata("DIALOG")
        menuFrame:SetClampedToScreen(true)
        menuFrame:SetMovable(true)
        menuFrame:EnableMouse(true)

        menuFrame:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })
        menuFrame:SetBackdropColor(0.08, 0.08, 0.1, 0.92)
        menuFrame:SetBackdropBorderColor(0.8, 0.5, 0.1, 0.7)

        -- Title
        local title = menuFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -8)
        title:SetText("|cffcc8800KickTracker|r")

        -- Close button
        local closeBtn = CreateFrame("Button", nil, menuFrame)
        closeBtn:SetSize(14, 14)
        closeBtn:SetPoint("TOPRIGHT", -4, -4)
        closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        closeBtn.text:SetPoint("CENTER")
        closeBtn.text:SetText("|cffff4444x|r")
        closeBtn:SetScript("OnClick", function() ToggleMenu() end)
        closeBtn:SetScript("OnEnter", function(self) self.text:SetText("|cffff6666x|r") end)
        closeBtn:SetScript("OnLeave", function(self) self.text:SetText("|cffff4444x|r") end)

        local sep = menuFrame:CreateTexture(nil, "ARTWORK")
        sep:SetPoint("TOPLEFT", 8, -24)
        sep:SetPoint("TOPRIGHT", -8, -24)
        sep:SetHeight(1)
        sep:SetColorTexture(0.3, 0.3, 0.35, 0.5)

        -- Reset position
        CreateMenuButton(menuFrame, -30, "Reset Position", function()
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("CENTER", UIParent, "CENTER", 300, 200)
            settings.posX = 300
            settings.posY = 200
            print("|cffcc8800KT:|r Position reset.")
        end)

        -- Show solo toggle
        local soloBtn = CreateMenuButton(menuFrame, -52, "", nil)
        local function UpdateSoloLabel()
            if settings.showSolo then
                soloBtn.label:SetText("|cff88ff88Show Solo: ON|r")
            else
                soloBtn.label:SetText("|cffff8888Show Solo: OFF|r")
            end
        end
        soloBtn:SetScript("OnClick", function()
            settings.showSolo = not settings.showSolo
            UpdateSoloLabel()
            if not settings.showSolo and not IsInGroup() then
                wipe(partyMembers)
            else
                ScanGroup()
            end
        end)
        menuFrame.soloBtn = soloBtn
        menuFrame.UpdateSoloLabel = UpdateSoloLabel

        -- Test data
        CreateMenuButton(menuFrame, -74, "Load Test Data", function()
            local now = GetTime()
            wipe(partyMembers)
            wipe(activeKicks)
            partyMembers["Thrall"]  = { name = "Thrall",  class = "SHAMAN",      spellID = 57994,  icon = 136018 }
            partyMembers["Jaina"]   = { name = "Jaina",   class = "MAGE",        spellID = 2139,   icon = 135856 }
            partyMembers["Garrosh"] = { name = "Garrosh", class = "WARRIOR",     spellID = 6552,   icon = 132938 }
            partyMembers["Illidan"] = { name = "Illidan", class = "DEMONHUNTER", spellID = 183752, icon = 1305153 }
            partyMembers["Anduin"]  = { name = "Anduin",  class = "PRIEST",      spellID = 15487,  icon = 458230 }
            activeKicks["Thrall"]  = { spellID = 57994, icon = 136018,  expires = now + 12, cd = 12, class = "SHAMAN" }
            activeKicks["Jaina"]   = { spellID = 2139,  icon = 135856,  expires = now + 20, cd = 24, class = "MAGE" }
            activeKicks["Garrosh"] = { spellID = 6552,  icon = 132938,  expires = now + 5,  cd = 15, class = "WARRIOR" }
            print("|cffcc8800KT:|r Test data loaded.")
        end)

        -- Show macros
        CreateMenuButton(menuFrame, -96, "Show Macros", function()
            print("|cffcc8800KT macros:|r")
            print("|cff00ff00Pummel:|r /cast Pummel\\n/p kt:6552")
            print("|cff00ff00Kick:|r /cast Kick\\n/p kt:1766")
            print("|cff00ff00Counterspell:|r /cast Counterspell\\n/p kt:2139")
            print("|cff00ff00Wind Shear:|r /cast Wind Shear\\n/p kt:57994")
            print("|cff00ff00Skull Bash:|r /cast Skull Bash\\n/p kt:106839")
            print("|cff00ff00Mind Freeze:|r /cast Mind Freeze\\n/p kt:47528")
            print("|cff00ff00Rebuke:|r /cast Rebuke\\n/p kt:96231")
            print("|cff00ff00Disrupt:|r /cast Disrupt\\n/p kt:183752")
            print("|cff00ff00Spear Hand Strike:|r /cast Spear Hand Strike\\n/p kt:116705")
            print("|cff00ff00Muzzle:|r /cast Muzzle\\n/p kt:187707")
        end)

        -- Dato <3
        CreateMenuButton(menuFrame, -118, "|cffff6688<3 dato|r", function()
            SendChatMessage("<3", "SAY")
        end)

        local sep2 = menuFrame:CreateTexture(nil, "ARTWORK")
        sep2:SetPoint("TOPLEFT", 8, -140)
        sep2:SetPoint("TOPRIGHT", -8, -140)
        sep2:SetHeight(1)
        sep2:SetColorTexture(0.3, 0.3, 0.35, 0.5)

        -- Opacity slider
        CreateSlider(menuFrame, -148, "Opacity", 0.15, 1.0, 0.05,
            function() return settings.opacity end,
            function(v)
                settings.opacity = v
                ApplySettings()
            end
        )

        -- Scale slider
        CreateSlider(menuFrame, -183, "Scale", 0.5, 2.0, 0.05,
            function() return settings.scale end,
            function(v)
                settings.scale = v
                ApplySettings()
            end
        )

        -- Width slider
        local widthContainer = CreateFrame("Frame", nil, menuFrame)
        widthContainer:SetSize(140, 30)
        widthContainer:SetPoint("TOP", menuFrame, "TOP", 0, -218)

        local wText = widthContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        wText:SetPoint("TOP", 0, 0)
        wText:SetFont(wText:GetFont(), 8)

        local wSlider = CreateFrame("Slider", nil, widthContainer, "OptionsSliderTemplate")
        wSlider:SetSize(120, 10)
        wSlider:SetPoint("TOP", 0, -10)
        wSlider:SetMinMaxValues(120, 280)
        wSlider:SetValueStep(5)
        wSlider:SetObeyStepOnDrag(true)
        wSlider.Low:SetText("")
        wSlider.High:SetText("")
        wSlider.Text:SetText("")
        wSlider:SetValue(settings and settings.frameWidth or 170)
        wText:SetText("Width: " .. (settings and settings.frameWidth or 170) .. "px")

        wSlider:SetScript("OnValueChanged", function(self, value)
            wText:SetText("Width: " .. math.floor(value) .. "px")
        end)
        wSlider:SetScript("OnMouseUp", function(self)
            if settings then
                settings.frameWidth = math.floor(self:GetValue())
                ApplySettings()
            end
        end)

        -- Dragging the menu itself
        menuFrame:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then self:StartMoving() end
        end)
        menuFrame:SetScript("OnMouseUp", function(self)
            self:StopMovingOrSizing()
        end)
    end

    -- Position menu at screen center (independent of bar)
    if not menuFrame.hasBeenPositioned then
        menuFrame:ClearAllPoints()
        menuFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        menuFrame.hasBeenPositioned = true
    end
    menuFrame:Show()

    -- Update dynamic labels
    if menuFrame.UpdateSoloLabel then
        menuFrame.UpdateSoloLabel()
    end
end

----------------------------------------------------------------------
-- Resize handle
----------------------------------------------------------------------
local function CreateResizeHandle(parent)
    local handle = CreateFrame("Frame", nil, parent)
    handle:SetSize(8, 8)
    handle:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    handle:EnableMouse(true)

    local tex = handle:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetColorTexture(0.8, 0.5, 0.1, 0.4)

    handle:SetScript("OnEnter", function() tex:SetColorTexture(0.8, 0.5, 0.1, 0.8) end)
    handle:SetScript("OnLeave", function() tex:SetColorTexture(0.8, 0.5, 0.1, 0.4) end)

    local resizing = false
    handle:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and menuOpen then
            resizing = true
            parent:SetResizable(true)
            parent:SetResizeBounds(120, 30, 300, 200)
            parent:StartSizing("BOTTOMRIGHT")
        end
    end)
    handle:SetScript("OnMouseUp", function()
        if resizing then
            parent:StopMovingOrSizing()
            resizing = false
            parent:SetResizable(false)
            if settings then
                settings.frameWidth = math.floor(parent:GetWidth())
                FRAME_WIDTH = settings.frameWidth
                for i = 1, #rows do
                    rows[i]:SetWidth(FRAME_WIDTH - 4)
                end
            end
        end
    end)

    return handle
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local elapsed_acc = 0
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("CHAT_MSG_PARTY")
eventFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
eventFrame:RegisterEvent("CHAT_MSG_RAID")
eventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)

        -- Init saved settings
        if not KickTrackerDB then KickTrackerDB = {} end
        settings = KickTrackerDB
        for k, v in pairs(defaults) do
            if settings[k] == nil then settings[k] = v end
        end

        mainFrame = CreateFrame("Frame", "KickTrackerFrame", UIParent, "BackdropTemplate")
        mainFrame:SetSize(FRAME_WIDTH, HEADER_HEIGHT + 8)
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", settings.posX, settings.posY)
        mainFrame:SetFrameStrata("MEDIUM")
        mainFrame:SetClampedToScreen(true)
        mainFrame:SetMovable(false)
        mainFrame:EnableMouse(true)

        mainFrame:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })
        ApplySettings()

        -- Top accent
        local accent = mainFrame:CreateTexture(nil, "ARTWORK")
        accent:SetPoint("TOPLEFT", 0, 0)
        accent:SetPoint("TOPRIGHT", 0, 0)
        accent:SetHeight(1)
        accent:SetColorTexture(0.8, 0.5, 0.1, 0.6)

        -- Title
        mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mainFrame.title:SetPoint("TOPLEFT", 4, -3)
        mainFrame.title:SetText("|cffcc8800KT|r")
        mainFrame.title:SetFont(mainFrame.title:GetFont(), 8)

        -- Menu toggle icon (top right)
        local menuBtn = CreateFrame("Button", nil, mainFrame)
        menuBtn:SetSize(12, 12)
        menuBtn:SetPoint("TOPRIGHT", -2, -2)
        menuBtn.text = menuBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        menuBtn.text:SetPoint("CENTER")
        menuBtn.text:SetText("|cff888888=|r")
        menuBtn.text:SetFont(menuBtn.text:GetFont(), 9)
        menuBtn:SetScript("OnClick", function() ToggleMenu() end)
        menuBtn:SetScript("OnEnter", function(self) self.text:SetText("|cffcc8800=|r") end)
        menuBtn:SetScript("OnLeave", function(self) self.text:SetText("|cff888888=|r") end)

        -- No dragging on the bar

        -- Resize handle
        CreateResizeHandle(mainFrame)

        -- Create rows
        for i = 1, 5 do
            rows[i] = CreateRow(mainFrame, i)
        end

        -- Update loop
        mainFrame:SetScript("OnUpdate", function(_, elapsed)
            elapsed_acc = elapsed_acc + elapsed
            if elapsed_acc < 0.05 then return end
            elapsed_acc = 0
            UpdateDisplay()
        end)

        ScanGroup()
        print("|cffcc8800KickTracker|r loaded. |cff888888/kt|r to open menu.")

    elseif event == "GROUP_ROSTER_UPDATE" then
        ScanGroup()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not mainFrame then return end
        local unit, _, spellID = ...
        if unit ~= "player" then return end
        local info = INTERRUPTS[spellID]
        if not info then return end
        local name = UnitName("player")
        local _, class = UnitClass("player")
        TrackKick(name, class, spellID)
        BroadcastKick(spellID)

    elseif event == "CHAT_MSG_ADDON" then
        if not mainFrame then return end
        local prefix, msg, channel, sender = ...
        if prefix ~= ADDON_PREFIX then return end
        local myName = UnitName("player")
        local senderShort = sender:match("^([^%-]+)") or sender
        if senderShort == myName then return end
        local spellStr, class = msg:match("^(%d+):(.+)$")
        if spellStr then
            local spellID = tonumber(spellStr)
            if spellID and INTERRUPTS[spellID] then
                TrackKick(senderShort, class, spellID)
            end
        end

    elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER"
        or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
        if not mainFrame then return end
        local msg, sender = ...
        local spellStr = msg:match("^kt:(%d+)$")
        if spellStr then
            local spellID = tonumber(spellStr)
            if spellID and INTERRUPTS[spellID] then
                local senderShort = sender:match("^([^%-]+)") or sender
                local myName = UnitName("player")
                if senderShort ~= myName then
                    local class = nil
                    for i = 1, 4 do
                        local pname = UnitName("party" .. i)
                        if pname == senderShort then
                            local _, c = UnitClass("party" .. i)
                            class = c
                            break
                        end
                    end
                    if not class and IsInRaid() then
                        for i = 1, 40 do
                            local pname = UnitName("raid" .. i)
                            if pname == senderShort then
                                local _, c = UnitClass("raid" .. i)
                                class = c
                                break
                            end
                        end
                    end
                    TrackKick(senderShort, class or INTERRUPTS[spellID].class, spellID)
                end
            end
        end
    end
end)

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
SLASH_KICKTRACKER1 = "/kt"
SLASH_KICKTRACKER2 = "/kicktracker"
SlashCmdList["KICKTRACKER"] = function(msg)
    msg = (msg or ""):lower():trim()
    if msg == "dato" then
        SendChatMessage("<3", "SAY")
    elseif msg == "" then
        ToggleMenu()
    else
        ToggleMenu()
    end
end
