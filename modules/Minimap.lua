-- Minimap.lua - Minimap button for GuildWorkOrders
local addonName, addon = ...
addon.Minimap = addon.Minimap or {}
local Minimap = addon.Minimap

-- Local references
local Config = nil
local UI = nil

-- Minimap button frame
local minimapButton = nil

function Minimap.Initialize()
    Config = addon.Config
    UI = addon.UI
    
    -- Only create button if enabled in config
    if Config.Get("showMinimapButton") then
        Minimap.CreateMinimapButton()
    end
    
    if Config.IsDebugMode() then
        print("|cff00ff00[GuildWorkOrders Debug]|r Minimap module initialized")
    end
end

-- Create the minimap button
function Minimap.CreateMinimapButton()
    -- Create the button frame (use _G.Minimap to reference the WoW frame, not our module)
    minimapButton = CreateFrame("Button", "GWOMinimapButton", _G.Minimap)
    minimapButton:SetSize(31, 31)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:SetMovable(true)
    minimapButton:EnableMouse(true)
    minimapButton:RegisterForDrag("LeftButton")
    
    -- Button icon
    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Scroll_03") -- Use a scroll icon for work orders
    minimapButton.icon = icon
    
    -- Button border
    local overlay = minimapButton:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetPoint("TOPLEFT")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    
    -- Highlight texture
    local highlight = minimapButton:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(31, 31)
    highlight:SetPoint("CENTER")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")
    
    -- Position the button on the minimap
    local angle = Config.Get("minimapButtonAngle") or 45
    Minimap.UpdateButtonPosition(angle)
    
    -- Event handlers
    minimapButton:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "LeftButton" then
            -- Toggle the main UI
            if UI then
                UI.Toggle()
            end
        end
    end)
    
    minimapButton:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", function()
            Minimap.OnUpdate()
        end)
    end)
    
    minimapButton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
        
        -- Save new position
        local pos = Minimap.GetPosition()
        Config.Set("minimapButtonAngle", pos)
    end)
    
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff00ff00Guild Work Orders|r")
        GameTooltip:AddLine("Click to open/close", 1, 1, 1)
        GameTooltip:AddLine("Drag to reposition", 1, 1, 1)
        GameTooltip:Show()
    end)
    
    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Show the button
    minimapButton:Show()
end

-- Update button position on minimap
function Minimap.UpdateButtonPosition(angle)
    if not minimapButton then return end
    
    local radius = 80 -- Distance from minimap center
    local radian = math.rad(angle or Config.Get("minimapButtonAngle") or 45)
    local x = math.cos(radian) * radius
    local y = math.sin(radian) * radius
    
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end

-- Handle dragging updates
function Minimap.OnUpdate()
    if not minimapButton then return end
    
    local mx, my = _G.Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = _G.Minimap:GetEffectiveScale()
    
    px, py = px / scale, py / scale
    
    local pos = math.deg(math.atan2(py - my, px - mx)) % 360
    Minimap.SetPosition(pos)
end

-- Get current position
function Minimap.GetPosition()
    if not minimapButton then return 45 end
    
    local px, py = minimapButton:GetCenter()
    local mx, my = _G.Minimap:GetCenter()
    
    local pos = math.deg(math.atan2(py - my, px - mx)) % 360
    return pos
end

-- Set position by angle
function Minimap.SetPosition(pos)
    if not minimapButton then return end
    
    local angle = math.rad(pos or Config.Get("minimapButtonAngle") or 45)
    local radius = 80
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end


-- Show/Hide functions
function Minimap.Show()
    if minimapButton then
        minimapButton:Show()
    else
        Minimap.CreateMinimapButton()
    end
end

function Minimap.Hide()
    if minimapButton then
        minimapButton:Hide()
    end
end

function Minimap.Toggle()
    if minimapButton and minimapButton:IsShown() then
        Minimap.Hide()
    else
        Minimap.Show()
    end
end

-- Check if button is shown
function Minimap.IsShown()
    return minimapButton and minimapButton:IsShown()
end