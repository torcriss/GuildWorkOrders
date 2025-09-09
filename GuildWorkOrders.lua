-- GuildWorkOrders Addon for WoW Classic Era (Interface 11507)
-- Guild-wide work order management system with hidden synchronization
-- Version 4.4.0

local addonName, addon = ...
addon = addon or {}

-- Module references will be set by individual modules
-- No need to import here since modules will set addon.ModuleName directly

-- Version info
addon.version = "4.5.0"
addon.build = "Production Ready & Realistic Timings"

-- Core initialization
local function Initialize()
    -- Load modules in dependency order
    if addon.Config then addon.Config.Load() end
    if addon.Database then addon.Database.Initialize() end
    if addon.Parser then addon.Parser.Initialize() end
    if addon.Sync then addon.Sync.Initialize() end
    if addon.UI then addon.UI.Initialize() end
    if addon.Commands then addon.Commands.Initialize() end
    if addon.Minimap then addon.Minimap.Initialize() end
    
    local playerName = UnitName("player")
    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    
    print(string.format("|cff00ff00[GuildWorkOrders v%s]|r Loaded for %s (Level %d %s) - Type /gwo help for commands", 
        addon.version, playerName, level, class))
    
    -- Initialize ping system only (no auto-sync requests)
    if addon.Config and addon.Config.IsDebugMode() then
        print("|cff00ff00[GuildWorkOrders Debug]|r Full sync disabled - using heartbeat-only system")
    end
    
    -- User discovery removed - orders sync via heartbeat only
    
    -- Status bar refresh timer (every 30 seconds) to keep "time ago" display current
    C_Timer.NewTicker(30, function()
        if addon.UI and addon.UI.UpdateStatusBar and addon.UI.IsShown and addon.UI.IsShown() then
            addon.UI.UpdateStatusBar()
        end
    end)
    
    -- Periodic cleanup timer (every 30 seconds) for order expiration and purging
    C_Timer.NewTicker(30, function()
        if addon.Database then
            -- First expire active orders that exceeded TTL
            local expiredCount = addon.Database.CleanupExpiredOrders()
            -- Then purge old non-active orders (PURGED state and deletion)
            local purgedCount = addon.Database.CleanupOldOrders()
            
            -- Refresh UI if any orders were cleaned up and UI is visible
            if (expiredCount > 0 or purgedCount > 0) and addon.UI and addon.UI.IsShown and addon.UI.IsShown() then
                addon.UI.RefreshOrders()
                if addon.Config and addon.Config.IsDebugMode() then
                    print("|cffAAAAFF[GWO Debug]|r UI refreshed after cleanup")
                end
            end
            
            if addon.Config and addon.Config.IsDebugMode() then
                print(string.format("|cffAAAAFF[GWO Debug]|r Periodic cleanup cycle completed (expired: %d, purged: %d)", expiredCount or 0, purgedCount or 0))
            end
        end
    end)
    
    if addon.Config and addon.Config.IsDebugMode() then
        print("|cff00ff00[GuildWorkOrders Debug]|r All modules initialized successfully")
    end
end

-- Event handling
local GWO = CreateFrame("Frame")
GWO:RegisterEvent("PLAYER_LOGIN")
GWO:RegisterEvent("CHAT_MSG_ADDON")
GWO:RegisterEvent("GUILD_ROSTER_UPDATE")
GWO:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        Initialize()
        
    elseif event == "CHAT_MSG_ADDON" then
        -- Handle sync messages
        if addon.Sync then
            addon.Sync.OnAddonMessage(...)
        end
        
    elseif event == "GUILD_ROSTER_UPDATE" then
        -- Guild roster changed - no action needed in heartbeat-only system
    end
end)

-- Global API for other addons
_G.GuildWorkOrders = {
    version = addon.version,
    
    -- Public API functions
    GetVersion = function()
        return addon.version
    end,
    
    IsAvailable = function()
        return addon.Database ~= nil
    end,
    
    GetOrderCount = function()
        if addon.Database then
            local stats = addon.Database.GetStats()
            return stats.activeOrders or 0
        end
        return 0
    end,
    
    GetMyOrderCount = function()
        if addon.Database then
            local stats = addon.Database.GetStats()
            return stats.myActiveOrders or 0
        end
        return 0
    end,
    
    ShowUI = function()
        if addon.UI then
            addon.UI.Show()
            return true
        end
        return false
    end,
    
    HideUI = function()
        if addon.UI then
            addon.UI.Hide()
            return true
        end
        return false
    end,
    
    ToggleUI = function()
        if addon.UI then
            addon.UI.Toggle()
            return true
        end
        return false
    end,
    
    CreateOrder = function(orderType, itemLink, quantity, price)
        if addon.Database and addon.Sync then
            local order = addon.Database.CreateOrder(orderType, itemLink, quantity, price)
            if order then
                addon.Sync.BroadcastNewOrder(order)
                return true, order.id
            end
        end
        return false, "Database or Sync not available"
    end,
    
    CancelOrder = function(orderID)
        if addon.Database and addon.Sync then
            local success = addon.Database.CancelOrder(orderID)
            if success then
                addon.Sync.BroadcastOrderUpdate(orderID, addon.Database.STATUS.CANCELLED, 1)
                return true
            end
        end
        return false
    end,
    
    SearchOrders = function(searchText)
        if addon.Database then
            return addon.Database.SearchOrders(searchText)
        end
        return {}
    end,
    
    GetStats = function()
        if addon.Database then
            return addon.Database.GetStats()
        end
        return {}
    end,
    
    ForceSync = function()
        if addon.Sync then
            -- Full sync disabled - heartbeat-only system
            if addon.Config and addon.Config.IsDebugMode() then
                print("|cff00ff00[GuildWorkOrders Debug]|r Full sync disabled - orders share via heartbeat")
            end
            return true
        end
        return false
    end
}

-- Handle addon communication requests from other addons
local function HandleAddonComm(prefix, message, channel, sender)
    if prefix == "GWO_API" then
        -- Future: Handle API requests from other addons
        if addon.Config and addon.Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r API request from %s: %s", sender, message))
        end
    end
end

-- Register for addon communication
C_ChatInfo.RegisterAddonMessagePrefix("GWO_API")
local commFrame = CreateFrame("Frame")
commFrame:RegisterEvent("CHAT_MSG_ADDON")
commFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_ADDON" then
        HandleAddonComm(...)
    end
end)