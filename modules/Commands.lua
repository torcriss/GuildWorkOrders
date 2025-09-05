-- Commands.lua - Slash commands for GuildWorkOrders
local addonName, addon = ...
addon.Commands = addon.Commands or {}
local Commands = addon.Commands

-- Local references
local Config = nil
local Database = nil
local UI = nil
local Sync = nil
local Parser = nil

-- Command list for help
local COMMAND_LIST = {
    {cmd = "", desc = "Open the work orders window"},
    {cmd = "minimap", desc = "Toggle minimap button"},
    {cmd = "sync", desc = "Force sync with guild members"},
    {cmd = "debug", desc = "Toggle debug mode"},
    {cmd = "stats", desc = "Show addon statistics"}
}

function Commands.Initialize()
    Config = addon.Config
    Database = addon.Database
    UI = addon.UI
    Sync = addon.Sync
    Parser = addon.Parser
    
    -- Register only /gwo slash command
    SLASH_GWO1 = "/gwo"
    SlashCmdList["GWO"] = Commands.HandleSlashCommand
    
    if Config.IsDebugMode() then
        print("|cff00ff00[GuildWorkOrders Debug]|r Commands module initialized")
    end
end

-- Main slash command handler
function Commands.HandleSlashCommand(input)
    local cmd = input and string.lower(input) or ""
    
    if cmd == "minimap" then
        Commands.ToggleMinimapButton()
    elseif cmd == "sync" then
        Commands.ForceSync()
    elseif cmd == "debug" then
        Commands.ToggleDebug()
    elseif cmd == "stats" then
        Commands.ShowStats()
    elseif cmd == "help" then
        Commands.ShowHelp()
    else
        Commands.ShowUI()
    end
end

-- Show help
function Commands.ShowHelp()
    print("|cff00ff00[GuildWorkOrders]|r Available commands:")
    for _, cmd in ipairs(COMMAND_LIST) do
        print(string.format("  |cffFFD700/gwo %s|r - %s", cmd.cmd, cmd.desc))
    end
end

-- UI commands
function Commands.ShowUI()
    if UI then
        UI.Show()
    else
        print("|cffff0000[GuildWorkOrders]|r UI not available")
    end
end

function Commands.HideUI()
    if UI then
        UI.Hide()
    end
end


function Commands.ToggleUI()
    if UI then
        UI.Toggle()
    else
        Commands.ShowUI()
    end
end

-- Post order command
function Commands.PostOrder(args)
    -- Parse: post WTB [Iron Ore] 20 5g
    if #args < 3 then
        print("|cffff0000[GuildWorkOrders]|r Usage: /gwo post <WTB/WTS> [item] <quantity> <price>")
        print("  Example: /gwo post WTB [Iron Ore] 20 5g")
        return
    end
    
    local orderType = string.upper(args[2])
    if orderType ~= "WTB" and orderType ~= "WTS" then
        print("|cffff0000[GuildWorkOrders]|r Order type must be WTB or WTS")
        return
    end
    
    -- Find item name in brackets
    local fullText = table.concat(args, " ", 3)
    local itemName = string.match(fullText, "%[(.-)%]")
    if not itemName then
        print("|cffff0000[GuildWorkOrders]|r Item must be in brackets: [Item Name]")
        return
    end
    
    -- Parse quantity and price from remaining text
    local remaining = string.gsub(fullText, "%[" .. itemName .. "%]", "")
    remaining = string.gsub(remaining, "^%s+", "") -- trim leading spaces
    
    local parts = {strsplit(" ", remaining)}
    local quantity = tonumber(parts[1])
    local price = parts[2]
    
    if not quantity or quantity < 1 then
        print("|cffff0000[GuildWorkOrders]|r Invalid quantity")
        return
    end
    
    -- Create the order
    local itemLink = "[" .. itemName .. "]"
    local isValid, errors = Parser.ValidateOrderData(orderType, itemLink, quantity, price)
    if not isValid then
        print("|cffff0000[GuildWorkOrders]|r " .. table.concat(errors, ", "))
        return
    end
    
    local order = Database.CreateOrder(orderType, itemLink, quantity, price)
    if order then
        Sync.BroadcastNewOrder(order)
        
        -- Announce to guild if configured
        if Config.ShouldAnnounceToGuild() then
            local message = string.format("%s %dx %s for %s",
                orderType, quantity, itemLink, price or "negotiable")
            SendChatMessage(message, "GUILD")
        end
        
        print(string.format("|cff00ff00[GuildWorkOrders]|r Created %s order: %dx %s for %s",
            orderType, quantity, itemName, price or "negotiable"))
    end
end

-- List orders
function Commands.ListOrders(orderType)
    local orders = {}
    
    if orderType then
        orderType = string.upper(orderType)
        if orderType == "WTB" then
            orders = Database.GetOrdersByType(Database.TYPE.WTB)
        elseif orderType == "WTS" then
            orders = Database.GetOrdersByType(Database.TYPE.WTS)
        else
            print("|cffff0000[GuildWorkOrders]|r Invalid type. Use WTB or WTS")
            return
        end
    else
        orders = Database.GetAllOrders()
    end
    
    if #orders == 0 then
        print("|cff00ff00[GuildWorkOrders]|r No orders found")
        return
    end
    
    local typeText = orderType or "All"
    print(string.format("|cff00ff00[GuildWorkOrders]|r %s Orders (%d):", typeText, #orders))
    
    for i, order in ipairs(orders) do
        if i <= 10 then  -- Limit to 10 for chat
            local qtyText = order.quantity and (tostring(order.quantity) .. "x ") or ""
            local priceText = order.price and (" for " .. order.price) or ""
            local timeAgo = UI and UI.GetTimeAgo(order.timestamp) or "?"
            
            print(string.format("  %d. |cff%s%s|r %s%s%s - %s (%s)",
                i,
                order.type == Database.TYPE.WTB and "ff8080" or "80ff80",
                order.type,
                qtyText,
                order.itemName or "Unknown",
                priceText,
                order.player,
                timeAgo
            ))
        end
    end
    
    if #orders > 10 then
        print(string.format("|cff888888... and %d more (use UI for full list)|r", #orders - 10))
    end
end

-- Search orders
function Commands.SearchOrders(searchText)
    if not searchText or searchText == "" then
        print("|cffff0000[GuildWorkOrders]|r Usage: /gwo search <item name>")
        return
    end
    
    local orders = Database.SearchOrders(searchText)
    
    if #orders == 0 then
        print(string.format("|cff00ff00[GuildWorkOrders]|r No orders found for '%s'", searchText))
        return
    end
    
    print(string.format("|cff00ff00[GuildWorkOrders]|r Search results for '%s' (%d):", searchText, #orders))
    
    for i, order in ipairs(orders) do
        if i <= 5 then  -- Limit search results
            local qtyText = order.quantity and (tostring(order.quantity) .. "x ") or ""
            local priceText = order.price and (" for " .. order.price) or ""
            local timeAgo = UI and UI.GetTimeAgo(order.timestamp) or "?"
            
            print(string.format("  |cff%s%s|r %s%s%s - %s (%s)",
                order.type == Database.TYPE.WTB and "ff8080" or "80ff80",
                order.type,
                qtyText,
                order.itemName or "Unknown",
                priceText,
                order.player,
                timeAgo
            ))
        end
    end
    
    if #orders > 5 then
        print(string.format("|cff888888... and %d more (use UI for full list)|r", #orders - 5))
    end
end

-- List my orders
function Commands.ListMyOrders()
    local orders = Database.GetMyOrders()
    
    if #orders == 0 then
        print("|cff00ff00[GuildWorkOrders]|r You have no active orders")
        return
    end
    
    print(string.format("|cff00ff00[GuildWorkOrders]|r Your Orders (%d):", #orders))
    
    for i, order in ipairs(orders) do
        local qtyText = order.quantity and (tostring(order.quantity) .. "x ") or ""
        local priceText = order.price and (" for " .. order.price) or ""
        local timeAgo = UI and UI.GetTimeAgo(order.timestamp) or "?"
        
        print(string.format("  %d. |cff%s%s|r %s%s%s (%s)",
            i,
            order.type == Database.TYPE.WTB and "ff8080" or "80ff80",
            order.type,
            qtyText,
            order.itemName or "Unknown",
            priceText,
            timeAgo
        ))
    end
end

-- Cancel order
function Commands.CancelOrder(orderNum)
    local orderIndex = tonumber(orderNum)
    if not orderIndex then
        print("|cffff0000[GuildWorkOrders]|r Usage: /gwo cancel <order number>")
        print("Use '/gwo my' to see your orders with numbers")
        return
    end
    
    local myOrders = Database.GetMyOrders()
    if orderIndex < 1 or orderIndex > #myOrders then
        print("|cffff0000[GuildWorkOrders]|r Invalid order number")
        return
    end
    
    local order = myOrders[orderIndex]
    local success = Database.CancelOrder(order.id)
    
    if success then
        Sync.BroadcastOrderUpdate(order.id, Database.STATUS.CANCELLED, (order.version or 1) + 1)
        print(string.format("|cff00ff00[GuildWorkOrders]|r Cancelled order: %s", order.itemName))
        
        if UI then
            UI.RefreshOrders()
        end
    else
        print("|cffff0000[GuildWorkOrders]|r Failed to cancel order")
    end
end

-- Fulfill order
function Commands.FulfillOrder(orderNum)
    local orderIndex = tonumber(orderNum)
    if not orderIndex then
        print("|cffff0000[GuildWorkOrders]|r Usage: /gwo fulfill <order number>")
        print("Use '/gwo my' to see your orders with numbers")
        return
    end
    
    local myOrders = Database.GetMyOrders()
    if orderIndex < 1 or orderIndex > #myOrders then
        print("|cffff0000[GuildWorkOrders]|r Invalid order number")
        return
    end
    
    local order = myOrders[orderIndex]
    local success = Database.FulfillOrder(order.id)
    
    if success then
        Sync.BroadcastOrderUpdate(order.id, Database.STATUS.FULFILLED, (order.version or 1) + 1)
        print(string.format("|cff00ff00[GuildWorkOrders]|r Fulfilled order: %s", order.itemName))
        
        if UI then
            UI.RefreshOrders()
        end
    else
        print("|cffff0000[GuildWorkOrders]|r Failed to fulfill order")
    end
end

-- Force sync
function Commands.ForceSync()
    if Sync then
        -- Full sync disabled - heartbeat-only system
        print("|cff00ff00[GuildWorkOrders]|r Orders sync automatically via heartbeat every 3 seconds")
    else
        print("|cffff0000[GuildWorkOrders]|r Sync not available")
    end
end

-- Toggle debug mode
function Commands.ToggleDebug()
    if Config then
        local currentDebug = Config.Get("debugMode") or false
        Config.Set("debugMode", not currentDebug)
        local newState = not currentDebug and "enabled" or "disabled"
        print(string.format("|cff00ff00[GuildWorkOrders]|r Debug mode %s", newState))
    else
        print("|cffff0000[GuildWorkOrders]|r Config not available")
    end
end

-- Show statistics
function Commands.ShowStats()
    local stats = Database.GetStats()
    local syncStatus = Sync and Sync.GetSyncStatus() or {}
    
    print("|cff00ff00[GuildWorkOrders]|r Statistics:")
    print(string.format("  Active Orders: %d", stats.activeOrders))
    print(string.format("  - WTB Orders: %d", stats.wtbOrders))
    print(string.format("  - WTS Orders: %d", stats.wtsOrders))
    print(string.format("  - My Orders: %d", stats.myActiveOrders))
    print(string.format("  History: %d orders", stats.totalHistory))
    
    -- Online user count removed
    
    if syncStatus.lastSync and syncStatus.lastSync > 0 then
        local timeAgo = UI and UI.GetTimeAgo(syncStatus.lastSync) or "?"
        print(string.format("  Last Sync: %s ago", timeAgo))
    else
        print("  Last Sync: Never")
    end
end

-- Clear history
function Commands.ClearHistory()
    StaticPopupDialogs["GWO_CLEAR_HISTORY_CMD"] = {
        text = "Clear all order history?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            Database.ClearHistory()
            print("|cff00ff00[GuildWorkOrders]|r Order history cleared")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    
    StaticPopup_Show("GWO_CLEAR_HISTORY_CMD")
end

-- Configuration commands
function Commands.HandleConfig(args)
    if #args == 1 then
        -- Show current config
        print("|cff00ff00[GuildWorkOrders]|r Current Configuration:")
        local settings = {
            "enabled", "announceToGuild", "announceFormat", "autoSync",
            "debugMode", "soundAlert", "orderExpiry"
        }
        
        for _, setting in ipairs(settings) do
            local value = Config.Get(setting)
            print(string.format("  %s: %s", setting, tostring(value)))
        end
    elseif #args == 3 then
        -- Set config value
        local setting = args[2]
        local value = args[3]
        
        -- Convert value types
        if value == "true" then
            value = true
        elseif value == "false" then
            value = false
        elseif tonumber(value) then
            value = tonumber(value)
        end
        
        Config.Set(setting, value)
        print(string.format("|cff00ff00[GuildWorkOrders]|r Set %s = %s", setting, tostring(value)))
    else
        print("|cffff0000[GuildWorkOrders]|r Usage:")
        print("  /gwo config - Show current settings")
        print("  /gwo config <setting> <value> - Change setting")
    end
end

-- Reset configuration
function Commands.ResetConfig()
    StaticPopupDialogs["GWO_RESET_CONFIG"] = {
        text = "Reset all configuration to defaults?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            Config.Reset()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    
    StaticPopup_Show("GWO_RESET_CONFIG")
end

-- Toggle debug mode
function Commands.ToggleDebug()
    local currentDebug = Config.Get("debugMode")
    Config.Set("debugMode", not currentDebug)
    
    local status = Config.Get("debugMode") and "enabled" or "disabled"
    print(string.format("|cff00ff00[GuildWorkOrders]|r Debug mode %s", status))
end

-- Show version
function Commands.ShowVersion()
    print("|cff00ff00[GuildWorkOrders]|r Version 2.1.0")
    print("  WoW Classic Era Interface 11507")
    if Config.IsDebugMode() then
        local syncStatus = Sync and Sync.GetSyncStatus() or {}
        print(string.format("  Protocol Version: %d", 1))
        print(string.format("  Online Users: %d", syncStatus.onlineUsers or 0))
    end
end

-- Toggle minimap button
function Commands.ToggleMinimapButton()
    local Minimap = addon.Minimap
    if not Minimap then
        print("|cffff0000[GuildWorkOrders]|r Minimap module not available")
        return
    end
    
    if Minimap.IsShown() then
        Minimap.Hide()
        Config.Set("showMinimapButton", false)
        print("|cff00ff00[GuildWorkOrders]|r Minimap button hidden")
    else
        Minimap.Show()
        Config.Set("showMinimapButton", true)
        print("|cff00ff00[GuildWorkOrders]|r Minimap button shown")
    end
end

