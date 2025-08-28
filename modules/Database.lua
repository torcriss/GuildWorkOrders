-- Database.lua - Order storage and management for GuildWorkOrders
local addonName, addon = ...
addon.Database = addon.Database or {}
local Database = addon.Database

-- Local references
local Config = nil  -- Will be set in Initialize

-- Order status constants
Database.STATUS = {
    ACTIVE = "active",
    FULFILLED = "fulfilled", 
    CANCELLED = "cancelled",
    EXPIRED = "expired"
}

-- Order type constants
Database.TYPE = {
    WTB = "WTB",
    WTS = "WTS"
}

function Database.Initialize()
    Config = addon.Config
    Database.CleanupExpiredOrders()
end

-- Generate unique order ID
function Database.GenerateOrderID(playerName)
    local timestamp = time()
    local random = math.random(1000, 9999)
    return string.format("%d_%s_%d", timestamp, playerName, random)
end

-- Create new order
function Database.CreateOrder(orderType, itemLink, quantity, price, message)
    local playerName = UnitName("player")
    local realm = GetRealmName()
    
    -- Parse item name from link
    local itemName = itemLink
    if string.find(itemLink, "|H") then
        -- Extract item name from properly formatted item link
        itemName = string.match(itemLink, "%[(.-)%]")
        if not itemName then
            -- If extraction fails, try to get item name from item ID
            local itemId = string.match(itemLink, "Hitem:(%d+)")
            if itemId then
                itemName = "Item " .. itemId -- Fallback name
            else
                itemName = "Unknown Item" -- Complete fallback
            end
        end
    else
        -- If not a proper item link, try to extract item ID or use as plain text
        if itemLink and string.find(itemLink, "Hitem:") then
            local itemId = string.match(itemLink, "Hitem:(%d+)")
            if itemId then
                itemName = "Item " .. itemId
            else
                itemName = "Unknown Item"
            end
        end
    end
    
    -- Convert price to copper for sorting
    local priceInCopper = Database.ParsePriceToCopper(price)
    
    local order = {
        id = Database.GenerateOrderID(playerName),
        type = orderType,
        player = playerName,
        realm = realm,
        itemLink = itemLink,
        itemName = itemName,
        quantity = quantity,
        price = price,
        priceInCopper = priceInCopper,
        message = message or "",
        timestamp = time(),
        expiresAt = time() + (Config.Get("orderExpiry") or 86400),
        status = Database.STATUS.ACTIVE,
        version = 1
    }
    
    -- Save to database
    if not GuildWorkOrdersDB.orders then
        GuildWorkOrdersDB.orders = {}
    end
    
    GuildWorkOrdersDB.orders[order.id] = order
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Created order: %s %s %s for %s",
            orderType, quantity or "?", itemName, price or "?"))
    end
    
    return order
end

-- Clean up corrupted item names
function Database.CleanItemName(order)
    if not order then return end
    
    -- If itemName is missing or looks corrupted, try to fix it
    if not order.itemName or string.find(order.itemName, "Hitem:") then
        if order.itemLink then
            if string.find(order.itemLink, "|H") then
                -- Proper item link - extract name from brackets
                order.itemName = string.match(order.itemLink, "%[(.-)%]")
            end
            
            -- If still no name, try to extract from item ID
            if not order.itemName then
                local itemId = string.match(order.itemLink, "Hitem:(%d+)")
                if itemId then
                    order.itemName = "Item " .. itemId
                end
            end
        end
        
        -- Final fallback
        if not order.itemName then
            order.itemName = "Unknown Item"
        end
    end
end

-- Get all orders
function Database.GetAllOrders()
    if not GuildWorkOrdersDB or not GuildWorkOrdersDB.orders then
        return {}
    end
    
    local orders = {}
    for id, order in pairs(GuildWorkOrdersDB.orders) do
        -- Only include active orders that haven't expired
        if order.status == Database.STATUS.ACTIVE and order.expiresAt > time() then
            -- Clean up any corrupted item names
            Database.CleanItemName(order)
            table.insert(orders, order)
        end
    end
    
    -- Sort by timestamp (newest first)
    table.sort(orders, function(a, b)
        return a.timestamp > b.timestamp
    end)
    
    return orders
end

-- Get orders by type (WTB/WTS)
function Database.GetOrdersByType(orderType)
    local allOrders = Database.GetAllOrders()
    local filteredOrders = {}
    
    for _, order in ipairs(allOrders) do
        if order.type == orderType then
            table.insert(filteredOrders, order)
        end
    end
    
    return filteredOrders
end

-- Get player's own orders
function Database.GetMyOrders()
    local playerName = UnitName("player")
    local myOrders = {}
    
    -- Get active orders
    local allOrders = Database.GetAllOrders()
    for _, order in ipairs(allOrders) do
        if order.player == playerName then
            table.insert(myOrders, order)
        end
    end
    
    -- Get completed/cancelled orders from history
    local history = Database.GetHistory()
    for _, order in ipairs(history) do
        if order.player == playerName then
            table.insert(myOrders, order)
        end
    end
    
    -- Sort by timestamp (newest first)
    table.sort(myOrders, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)
    
    return myOrders
end

-- Search orders by item name
function Database.SearchOrders(searchText)
    if not searchText or searchText == "" then
        return Database.GetAllOrders()
    end
    
    local allOrders = Database.GetAllOrders()
    local results = {}
    local lowerSearch = string.lower(searchText)
    
    for _, order in ipairs(allOrders) do
        local itemName = string.lower(order.itemName or "")
        if string.find(itemName, lowerSearch, 1, true) then
            table.insert(results, order)
        end
    end
    
    return results
end

-- Update order status
function Database.UpdateOrderStatus(orderID, newStatus, fulfilledBy)
    if not GuildWorkOrdersDB.orders or not GuildWorkOrdersDB.orders[orderID] then
        return false
    end
    
    local order = GuildWorkOrdersDB.orders[orderID]
    local oldStatus = order.status
    order.status = newStatus
    order.version = (order.version or 1) + 1
    
    -- Track who fulfilled the order
    if newStatus == Database.STATUS.FULFILLED and fulfilledBy then
        order.fulfilledBy = fulfilledBy
        order.fulfilledAt = time()
    end
    
    -- Move to history if fulfilled or cancelled
    if newStatus == Database.STATUS.FULFILLED or newStatus == Database.STATUS.CANCELLED then
        Database.MoveToHistory(order)
        GuildWorkOrdersDB.orders[orderID] = nil
    end
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Order %s status: %s -> %s%s",
            orderID, oldStatus, newStatus, fulfilledBy and (" by " .. fulfilledBy) or ""))
    end
    
    return true
end

-- Cancel order (only own orders)
function Database.CancelOrder(orderID)
    if not GuildWorkOrdersDB.orders or not GuildWorkOrdersDB.orders[orderID] then
        return false, "Order not found"
    end
    
    local order = GuildWorkOrdersDB.orders[orderID]
    local playerName = UnitName("player")
    
    if order.player ~= playerName then
        return false, "You can only cancel your own orders"
    end
    
    return Database.UpdateOrderStatus(orderID, Database.STATUS.CANCELLED)
end

-- Fulfill order (only own orders)
function Database.FulfillOrder(orderID)
    if not GuildWorkOrdersDB.orders or not GuildWorkOrdersDB.orders[orderID] then
        return false, "Order not found"
    end
    
    local order = GuildWorkOrdersDB.orders[orderID]
    local playerName = UnitName("player")
    
    if order.player == playerName then
        return false, "You cannot fulfill your own orders"
    end
    
    return Database.UpdateOrderStatus(orderID, Database.STATUS.FULFILLED, playerName)
end

-- Add or update order from sync
function Database.SyncOrder(orderData)
    if not orderData or not orderData.id then
        return false
    end
    
    if not GuildWorkOrdersDB.orders then
        GuildWorkOrdersDB.orders = {}
    end
    
    local existingOrder = GuildWorkOrdersDB.orders[orderData.id]
    
    -- Conflict resolution: use version number, fall back to timestamp
    if existingOrder then
        local existingVersion = existingOrder.version or 1
        local newVersion = orderData.version or 1
        
        if newVersion < existingVersion then
            -- Incoming data is older, ignore
            return false
        elseif newVersion == existingVersion and (existingOrder.timestamp or 0) >= (orderData.timestamp or 0) then
            -- Same version but not newer, ignore
            return false
        end
    end
    
    -- Accept the order
    GuildWorkOrdersDB.orders[orderData.id] = orderData
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Synced order: %s from %s",
            orderData.id, orderData.player))
    end
    
    return true
end

-- Move order to history
function Database.MoveToHistory(order)
    if not GuildWorkOrdersDB.history then
        GuildWorkOrdersDB.history = {}
    end
    
    -- Add completion timestamp
    order.completedAt = time()
    
    table.insert(GuildWorkOrdersDB.history, 1, order)
    
    -- Maintain history limit
    local maxHistory = Config.Get("maxHistory") or 100
    while #GuildWorkOrdersDB.history > maxHistory do
        table.remove(GuildWorkOrdersDB.history)
    end
end

-- Get order history
function Database.GetHistory()
    local history = GuildWorkOrdersDB.history or {}
    
    -- Clean up any corrupted item names in history
    for _, order in ipairs(history) do
        Database.CleanItemName(order)
    end
    
    return history
end

-- Clear history
function Database.ClearHistory()
    GuildWorkOrdersDB.history = {}
    return true
end

-- Clear all database data (orders, history, keep config)
function Database.ClearAllData()
    if not GuildWorkOrdersDB then
        return false
    end
    
    -- Clear orders and history but preserve config and sync data structure
    GuildWorkOrdersDB.orders = {}
    GuildWorkOrdersDB.history = {}
    
    -- Reset sync data but keep structure
    if GuildWorkOrdersDB.syncData then
        GuildWorkOrdersDB.syncData.lastSync = 0
        GuildWorkOrdersDB.syncData.onlineUsers = {}
    end
    
    return true
end

-- Completely reset database (including config)
function Database.ResetDatabase()
    GuildWorkOrdersDB = {
        config = {},
        orders = {},
        history = {},
        syncData = {
            lastSync = 0,
            onlineUsers = {}
        },
        version = addon.version or "2.1.0"
    }
    
    -- Reload config defaults
    if addon.Config then
        addon.Config.Load()
    end
    
    return true
end

-- Auto-complete expired orders (fulfill after 24 hours)
function Database.CleanupExpiredOrders()
    if not GuildWorkOrdersDB or not GuildWorkOrdersDB.orders then
        return 0
    end
    
    local currentTime = time()
    local completedCount = 0
    local toRemove = {}
    
    for orderID, order in pairs(GuildWorkOrdersDB.orders) do
        if order.expiresAt and order.expiresAt < currentTime and order.status == Database.STATUS.ACTIVE then
            -- Auto-complete the order after 24 hours
            order.status = Database.STATUS.FULFILLED
            order.completedAt = currentTime
            Database.MoveToHistory(order)
            table.insert(toRemove, orderID)
            completedCount = completedCount + 1
            
            -- Broadcast the auto-completion
            if addon.Sync then
                addon.Sync.BroadcastOrderUpdate(orderID, Database.STATUS.FULFILLED, (order.version or 1) + 1)
            end
        end
    end
    
    -- Remove auto-completed orders from active list
    for _, orderID in ipairs(toRemove) do
        GuildWorkOrdersDB.orders[orderID] = nil
    end
    
    if completedCount > 0 and Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Auto-completed %d orders after 24 hours", completedCount))
    end
    
    return completedCount
end

-- Helper function to parse price string to copper
function Database.ParsePriceToCopper(priceStr)
    if not priceStr then return 0 end
    
    local copper = 0
    local lowerPrice = string.lower(priceStr)
    
    -- Extract gold
    local gold = string.match(lowerPrice, "(%d+)g")
    if gold then
        copper = copper + (tonumber(gold) * 10000)
    end
    
    -- Extract silver
    local silver = string.match(lowerPrice, "(%d+)s")
    if silver then
        copper = copper + (tonumber(silver) * 100)
    end
    
    -- Extract copper
    local copperMatch = string.match(lowerPrice, "(%d+)c")
    if copperMatch then
        copper = copper + tonumber(copperMatch)
    end
    
    return copper
end

-- Get statistics
function Database.GetStats()
    local activeOrders = Database.GetAllOrders()
    local history = Database.GetHistory()
    
    local stats = {
        activeOrders = #activeOrders,
        totalHistory = #history,
        myActiveOrders = #Database.GetMyOrders(),
        wtbOrders = #Database.GetOrdersByType(Database.TYPE.WTB),
        wtsOrders = #Database.GetOrdersByType(Database.TYPE.WTS)
    }
    
    return stats
end

-- Export orders for sync
function Database.ExportOrdersForSync()
    return GuildWorkOrdersDB.orders or {}
end