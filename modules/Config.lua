-- Config.lua - Configuration management for GuildWorkOrders
local addonName, addon = ...
addon.Config = addon.Config or {}
local Config = addon.Config

-- Default configuration
local defaultConfig = {
    enabled = true,
    announceToGuild = false,       -- Whether to announce new orders to guild chat
    announceFormat = "simple",     -- "simple" or "detailed"
    autoSync = true,              -- Auto-sync on login
    syncTimeout = 30,             -- Sync timeout in seconds
    maxHistory = 100,             -- Max orders to keep in history
    orderExpiry = 86400,          -- 24 hours in seconds
    debugMode = false,            -- Debug output
    soundAlert = true,            -- Play sound on new orders
    whisperTemplate = "Is your %s still available? I'm interested in %s for %s.",  -- %s = item, quantity, price
    
    -- UI settings
    windowWidth = 700,
    windowHeight = 500,
    currentTab = "buy",
    
    -- Version tracking
    configVersion = "1.0"
}

local config = {}

-- Initialize config with defaults
for k, v in pairs(defaultConfig) do
    config[k] = v
end

function Config.Load()
    if not GuildWorkOrdersDB then
        GuildWorkOrdersDB = {
            config = {},
            orders = {},
            history = {},
            syncData = {
                lastSync = 0,
                onlineUsers = {}
            },
            version = "1.0.0"
        }
    end
    
    -- Load saved config, falling back to defaults
    if GuildWorkOrdersDB.config then
        for key, value in pairs(GuildWorkOrdersDB.config) do
            config[key] = value
        end
    end
    
    -- Update database structure if needed
    Config.UpdateDatabase()
    
    if config.debugMode then
        print("|cff00ff00[GuildWorkOrders Debug]|r Config loaded")
    end
end

function Config.Save()
    if GuildWorkOrdersDB then
        GuildWorkOrdersDB.config = config
    end
end

function Config.Get(key)
    return config[key]
end

function Config.Set(key, value)
    config[key] = value
    Config.Save()
end

function Config.GetDefaults()
    return defaultConfig
end

function Config.Reset()
    config = {}
    for k, v in pairs(defaultConfig) do
        config[k] = v
    end
    Config.Save()
    print("|cff00ff00[GuildWorkOrders]|r Configuration reset to defaults")
end

function Config.UpdateDatabase()
    if not GuildWorkOrdersDB then return end
    
    -- Ensure all required tables exist
    if not GuildWorkOrdersDB.orders then
        GuildWorkOrdersDB.orders = {}
    end
    
    if not GuildWorkOrdersDB.history then
        GuildWorkOrdersDB.history = {}
    end
    
    if not GuildWorkOrdersDB.syncData then
        GuildWorkOrdersDB.syncData = {
            lastSync = 0,
            onlineUsers = {}
        }
    end
    
    -- Version migration if needed
    if not GuildWorkOrdersDB.version or GuildWorkOrdersDB.version ~= "1.0.0" then
        if config.debugMode then
            print("|cff00ff00[GuildWorkOrders Debug]|r Database version updated")
        end
        GuildWorkOrdersDB.version = "1.0.0"
    end
end

-- UI Helper functions
function Config.GetWindowSize()
    return config.windowWidth or defaultConfig.windowWidth,
           config.windowHeight or defaultConfig.windowHeight
end

function Config.SetWindowSize(width, height)
    config.windowWidth = width
    config.windowHeight = height
    Config.Save()
end

function Config.GetCurrentTab()
    return config.currentTab or defaultConfig.currentTab
end

function Config.SetCurrentTab(tab)
    config.currentTab = tab
    Config.Save()
end

-- Whisper template helpers
function Config.FormatWhisperMessage(itemName, quantity, price)
    local template = config.whisperTemplate or defaultConfig.whisperTemplate
    local quantityText = quantity and (tostring(quantity) .. "x") or ""
    local priceText = price or "the price you mentioned"
    
    return string.format(template, itemName, quantityText, priceText)
end

function Config.IsDebugMode()
    return config.debugMode or false
end

function Config.ShouldAnnounceToGuild()
    return config.announceToGuild or false
end

function Config.GetAnnounceFormat()
    return config.announceFormat or "simple"
end