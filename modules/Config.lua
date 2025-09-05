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
    -- REMOVED: maxHistory - using single database
    orderExpiry = 60,             -- 1 minute in seconds (TESTING)
    debugMode = false,            -- Debug output
    soundAlert = true,            -- Play sound on new orders
    whisperTemplate = "Is your %s still available? I'm interested in %s for %s.",  -- %s = item, quantity, price
    
    -- UI settings
    windowWidth = 700,
    windowHeight = 500,
    currentTab = "buy",
    
    -- Minimap settings
    showMinimapButton = true,
    minimapButtonAngle = 45,
    
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
        print("|cff00ff00[GuildWorkOrders Debug]|r Settings loaded from saved data")
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
    
    -- REMOVED: history initialization - using single database
    
    if not GuildWorkOrdersDB.syncData then
        GuildWorkOrdersDB.syncData = {
            lastSync = 0,
            onlineUsers = {},
            heartbeatIndex = 1  -- For rotating through orders in heartbeat
        }
    end
    
    -- Initialize heartbeat index if missing
    if not GuildWorkOrdersDB.syncData.heartbeatIndex then
        GuildWorkOrdersDB.syncData.heartbeatIndex = 1
    end
    
    -- Config migration: Update orderExpiry from 24 hours to 1 minute (TESTING)
    if GuildWorkOrdersDB.config and (GuildWorkOrdersDB.config.orderExpiry == 86400 or GuildWorkOrdersDB.config.orderExpiry == 1800 or GuildWorkOrdersDB.config.orderExpiry == 180) then
        GuildWorkOrdersDB.config.orderExpiry = 60
        config.orderExpiry = 60  -- Update in-memory config too
        if config.debugMode then
            print("|cff00ff00[GuildWorkOrders Debug]|r Updated order expiry time to 1 minute for testing")
        end
    end
    
    -- Version migration if needed
    if not GuildWorkOrdersDB.version or GuildWorkOrdersDB.version ~= "1.0.0" then
        if config.debugMode then
            print("|cff00ff00[GuildWorkOrders Debug]|r Database structure upgraded")
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

-- Simple hash function for password verification
local function SimpleHash(str)
    if not str or str == "" then return 0 end
    
    local hash = 5381
    for i = 1, string.len(str) do
        local char = string.byte(str, i)
        hash = ((hash * 33) + char) % 2147483647 -- Keep within 32-bit signed int range
    end
    return hash
end

-- Pre-computed hash for admin password "0000"
local ADMIN_HASH = 2088252487

-- Verify admin password
function Config.VerifyAdminPassword(password)
    local hash = SimpleHash(password or "")
    return hash == ADMIN_HASH
end

-- Failed attempt tracking
local failedAttempts = 0
local lastFailTime = 0

function Config.CheckAdminAccess(password)
    local currentTime = GetTime()
    
    -- Check lockout (30 seconds after 3 failed attempts)
    if failedAttempts >= 3 and (currentTime - lastFailTime) < 30 then
        return false, string.format("Too many failed attempts. Try again in %d seconds.", 
            math.ceil(30 - (currentTime - lastFailTime)))
    end
    
    -- Reset attempts after lockout expires
    if failedAttempts >= 3 and (currentTime - lastFailTime) >= 30 then
        failedAttempts = 0
    end
    
    -- Verify password
    if Config.VerifyAdminPassword(password) then
        failedAttempts = 0
        return true
    else
        failedAttempts = failedAttempts + 1
        lastFailTime = currentTime
        return false, "Incorrect password"
    end
end