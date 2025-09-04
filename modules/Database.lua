-- Database.lua - Order storage and management for GuildWorkOrders
local addonName, addon = ...
addon.Database = addon.Database or {}
local Database = addon.Database

-- Local references
local Config = nil  -- Will be set in Initialize

-- Use server time for all timestamps to avoid clock sync issues
local function GetCurrentTime()
    return GetServerTime()
end

-- Order status constants
Database.STATUS = {
    ACTIVE = "active",
    PENDING = "pending",       -- Someone requested fulfillment, awaiting creator response (DEPRECATED)
    FULFILLED = "fulfilled",   -- Successfully completed
    CANCELLED = "cancelled",   -- Cancelled by user
    EXPIRED = "expired",       -- Auto-expired after 30 minutes (distinct from fulfilled)
    CLEARED = "cleared",       -- Admin cleared (synced for 24 hours)
    FAILED = "failed"          -- Fulfillment attempted but failed
}

-- Order type constants
Database.TYPE = {
    WTB = "WTB",
    WTS = "WTS"
}

-- Database limit constants
Database.LIMITS = {
    MAX_TOTAL_ORDERS = 500,
    MAX_ACTIVE_PER_USER = 10
}

-- Purge time constants (in seconds)
Database.PURGE_TIMES = {
    CLEARED_CANCELLED_EXPIRED = 14400,  -- 4 hours for cleared/cancelled/expired orders
    FULFILLED = 86400                    -- 24 hours for fulfilled orders
}

function Database.Initialize()
    Config = addon.Config
    Database.CleanupExpiredOrders()
end

-- Generate unique order ID
function Database.GenerateOrderID(playerName)
    local timestamp = GetCurrentTime()
    local random = math.random(1000, 9999)
    return string.format("%d_%s_%d", timestamp, playerName, random)
end

-- Create new order
function Database.CreateOrder(orderType, itemLink, quantity, price, message)
    local playerName = UnitName("player")
    local realm = GetRealmName()
    
    -- Check if we can create a new order (limits)
    local canCreate, errorMsg = Database.CanCreateOrder(playerName)
    if not canCreate then
        print(string.format("|cffFF6B6B[GuildWorkOrders]|r %s", errorMsg))
        return nil, errorMsg
    end
    
    -- Check if we need to purge old history to make room
    local totalCount = Database.GetTotalOrderCount()
    if totalCount >= Database.LIMITS.MAX_TOTAL_ORDERS then
        local purged = Database.PurgeNonActiveOrders(Database.LIMITS.MAX_TOTAL_ORDERS - 1)
        if purged > 0 then
            print(string.format("|cffFFAA00[GuildWorkOrders]|r Purged %d old history entries to make room for new order", purged))
        end
    end
    
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
        timestamp = GetCurrentTime(),
        expiresAt = GetCurrentTime() + (Config.Get("orderExpiry") or 1800),
        status = Database.STATUS.ACTIVE,
        version = 1
    }
    
    -- Save to database
    if not GuildWorkOrdersDB.orders then
        GuildWorkOrdersDB.orders = {}
    end
    
    GuildWorkOrdersDB.orders[order.id] = order
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Created %s order: %dx %s for %s",
            orderType == Database.TYPE.WTB and "buy" or "sell", quantity or 1, itemName, price or "negotiate"))
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
        -- Only include active orders that haven't expired, defensive filtering for any stray completed orders
        if (order.status == Database.STATUS.ACTIVE or order.status == Database.STATUS.PENDING) and 
           order.expiresAt > GetCurrentTime() and
           order.status ~= Database.STATUS.FULFILLED and
           order.status ~= Database.STATUS.CANCELLED and
           order.status ~= Database.STATUS.EXPIRED and
           order.status ~= Database.STATUS.CLEARED and
           order.status ~= Database.STATUS.FAILED then
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

-- Get player's own orders (for My Orders tab)
function Database.GetMyOrders()
    local playerName = UnitName("player")
    local myOrders = {}
    
    if not GuildWorkOrdersDB or not GuildWorkOrdersDB.orders then
        return {}
    end
    
    -- Get only my active and pending orders from the active database
    for id, order in pairs(GuildWorkOrdersDB.orders) do
        if order.player == playerName and 
           (order.status == Database.STATUS.ACTIVE or order.status == Database.STATUS.PENDING) and
           order.expiresAt > GetCurrentTime() then
            -- Clean up any corrupted item names
            Database.CleanItemName(order)
            table.insert(myOrders, order)
        end
    end
    
    -- Sort by timestamp (newest first)
    table.sort(myOrders, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)
    
    return myOrders
end

-- Get orders created by me (for heartbeat broadcasting)
function Database.GetMyCreatedOrders()
    local playerName = UnitName("player")
    local myOrders = {}
    
    -- Get active/pending orders I created
    if GuildWorkOrdersDB and GuildWorkOrdersDB.orders then
        for _, order in pairs(GuildWorkOrdersDB.orders) do
            if order.player == playerName then
                table.insert(myOrders, order)
            end
        end
    end
    
    -- Get recently completed orders I created (from history) - only within last 24 hours
    local currentTime = GetCurrentTime()
    local history = Database.GetHistory()
    for _, order in ipairs(history) do
        if order.player == playerName then
            -- Only include recently completed orders (within 24 hours)
            local timeSinceCompleted = nil
            if order.completedAt then
                timeSinceCompleted = currentTime - order.completedAt
            elseif order.fulfilledAt then
                timeSinceCompleted = currentTime - order.fulfilledAt
            elseif order.expiredAt then
                timeSinceCompleted = currentTime - order.expiredAt
            end
            
            if timeSinceCompleted and timeSinceCompleted < 1800 then -- 30 minutes
                table.insert(myOrders, order)
            end
        end
    end
    
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
        order.fulfilledAt = GetCurrentTime()
    end
    
    -- Move to history if fulfilled or cancelled
    if newStatus == Database.STATUS.FULFILLED or newStatus == Database.STATUS.CANCELLED then
        Database.MoveToHistory(order)
        GuildWorkOrdersDB.orders[orderID] = nil
    end
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Order status changed: %s -> %s%s",
            oldStatus, newStatus, fulfilledBy and (" by " .. fulfilledBy) or ""))
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

-- Complete fulfillment (only for order creators when they accept pending fulfillment)
function Database.CompleteFulfillment(orderID)
    if not GuildWorkOrdersDB.orders or not GuildWorkOrdersDB.orders[orderID] then
        return false, "Order not found"
    end
    
    local order = GuildWorkOrdersDB.orders[orderID]
    local playerName = UnitName("player")
    
    -- Only the order creator can complete fulfillment
    if order.player ~= playerName then
        return false, "You can only complete fulfillment of your own orders"
    end
    
    -- Order must be in pending state
    if order.status ~= Database.STATUS.PENDING then
        return false, "Order is not pending fulfillment"
    end
    
    -- Complete the fulfillment
    return Database.UpdateOrderStatus(orderID, Database.STATUS.FULFILLED, order.pendingFulfiller)
end

-- Request to fulfill order (sends request to creator) - DEPRECATED
function Database.RequestFulfillOrder(orderID)
    -- Use the new request system instead of direct fulfillment
    if addon.Sync then
        return addon.Sync.RequestFulfillment(orderID)
    else
        return false, "Sync system not available"
    end
end

-- Directly fulfill order (simplified flow)
function Database.DirectFulfillOrder(orderID, fulfillerName)
    if not GuildWorkOrdersDB.orders or not GuildWorkOrdersDB.orders[orderID] then
        return false, "Order not found"
    end
    
    local order = GuildWorkOrdersDB.orders[orderID]
    local playerName = UnitName("player")
    
    -- Cannot fulfill own orders
    if order.player == playerName then
        return false, "Cannot fulfill your own orders"
    end
    
    -- Check if order is still active
    if order.status ~= Database.STATUS.ACTIVE then
        if order.status == Database.STATUS.FULFILLED then
            return false, "Order already completed"
        elseif order.status == Database.STATUS.CANCELLED then
            return false, "Order was cancelled"
        elseif order.status == Database.STATUS.EXPIRED then
            return false, "Order has expired"
        else
            return false, "Order is no longer active"
        end
    end
    
    -- Check if order is expired
    if order.expiresAt and order.expiresAt < GetCurrentTime() then
        -- Set to expired and move to history
        Database.UpdateOrderStatus(orderID, Database.STATUS.EXPIRED)
        return false, "Order has expired"
    end
    
    -- Fulfill the order directly
    local success = Database.UpdateOrderStatus(orderID, Database.STATUS.FULFILLED, fulfillerName)
    if success then
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Order completed by %s", 
                fulfillerName))
        end
        return true, "Order completed successfully"
    else
        -- If update failed, mark as failed
        Database.UpdateOrderStatus(orderID, Database.STATUS.FAILED)
        return false, "Failed to complete order"
    end
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
    
    -- Preserve fulfilledBy if it exists locally but not in incoming data
    if existingOrder and existingOrder.fulfilledBy and not orderData.fulfilledBy then
        orderData.fulfilledBy = existingOrder.fulfilledBy
    end
    
    -- Route order to appropriate storage based on status
    if orderData.status == Database.STATUS.FULFILLED or 
       orderData.status == Database.STATUS.CANCELLED or 
       orderData.status == Database.STATUS.EXPIRED or
       orderData.status == Database.STATUS.CLEARED or
       orderData.status == Database.STATUS.FAILED then
        -- Completed orders go to history, remove from active orders
        Database.MoveToHistory(orderData)
        if GuildWorkOrdersDB.orders and GuildWorkOrdersDB.orders[orderData.id] then
            GuildWorkOrdersDB.orders[orderData.id] = nil
        end
    else
        -- Before putting an order back in active orders, check if we already have it as completed
        if orderData.status == Database.STATUS.ACTIVE then
            -- Check if this order is already in our history as completed
            local existingInHistory = Database.FindInHistory(orderData.id)
            if existingInHistory and (existingInHistory.status == Database.STATUS.FULFILLED or 
                                      existingInHistory.status == Database.STATUS.CANCELLED) then
                -- Don't reactivate a completed order
                if Config.IsDebugMode() then
                    print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Ignoring heartbeat for already completed order: %s", orderData.id))
                end
                return true
            end
        end
        
        -- Active/pending orders go to active orders table
        GuildWorkOrdersDB.orders[orderData.id] = orderData
    end
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Received order update: %s from %s",
            orderData.itemName or "Unknown Item", orderData.player))
    end
    
    return true
end

-- Move order to history
function Database.MoveToHistory(order)
    if not GuildWorkOrdersDB.history then
        GuildWorkOrdersDB.history = {}
    end
    
    -- Check if order already exists in history
    for i, existingOrder in ipairs(GuildWorkOrdersDB.history) do
        if existingOrder.id == order.id then
            -- Preserve existing completion date if already set
            if existingOrder.completedAt and not order.completedAt then
                order.completedAt = existingOrder.completedAt
            end
            -- Update existing entry instead of adding duplicate
            GuildWorkOrdersDB.history[i] = order
            return
        end
    end
    
    -- Add completion timestamp only if not already set
    if not order.completedAt then
        order.completedAt = GetCurrentTime()
    end
    
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

-- Find order in history by ID
function Database.FindInHistory(orderID)
    local history = GuildWorkOrdersDB.history or {}
    for _, order in ipairs(history) do
        if order.id == orderID then
            return order
        end
    end
    return nil
end

-- Get all orders unified (active + history)
function Database.GetAllOrdersUnified()
    local allOrders = {}
    
    -- Get all active orders (without filtering by status)
    if GuildWorkOrdersDB and GuildWorkOrdersDB.orders then
        for id, order in pairs(GuildWorkOrdersDB.orders) do
            -- Clean up any corrupted item names
            Database.CleanItemName(order)
            table.insert(allOrders, order)
        end
    end
    
    -- Get all history orders
    local history = GuildWorkOrdersDB.history or {}
    for _, order in ipairs(history) do
        -- Clean up any corrupted item names in history
        Database.CleanItemName(order)
        table.insert(allOrders, order)
    end
    
    -- Sort by timestamp (newest first)
    table.sort(allOrders, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)
    
    return allOrders
end

-- Clear history
function Database.ClearHistory()
    GuildWorkOrdersDB.history = {}
    return true
end

-- Broadcast cancellation of all orders to all users (admin function)
function Database.BroadcastClearAll(callback)
    if not GuildWorkOrdersDB or not GuildWorkOrdersDB.orders then
        if callback then callback() end
        return true
    end
    
    local orders = {}
    for orderID, order in pairs(GuildWorkOrdersDB.orders) do
        table.insert(orders, {id = orderID, version = (order.version or 1) + 1})
    end
    
    local totalOrders = #orders
    if totalOrders == 0 then
        print("|cff00ff00[GuildWorkOrders]|r No active orders to cancel")
        if callback then callback() end
        return true
    end
    
    print(string.format("|cffFFAA00[GuildWorkOrders]|r Broadcasting cancellation of %d orders to all users...", totalOrders))
    
    -- Broadcast cancellations with rate limiting (5 per second to avoid spam)
    local currentIndex = 1
    local broadcastTimer
    
    local function broadcastNext()
        if currentIndex <= totalOrders then
            local order = orders[currentIndex]
            
            -- Broadcast cancellation
            if addon.Sync then
                addon.Sync.BroadcastOrderUpdate(order.id, Database.STATUS.CANCELLED, order.version, "Admin Clear")
            end
            
            -- Update progress every 10 orders
            if currentIndex % 10 == 0 or currentIndex == totalOrders then
                print(string.format("|cffFFAA00[GuildWorkOrders]|r Cancelled %d/%d orders...", currentIndex, totalOrders))
            end
            
            currentIndex = currentIndex + 1
        else
            -- All orders broadcast, cleanup and callback
            if broadcastTimer then
                broadcastTimer:Cancel()
            end
            print("|cff00ff00[GuildWorkOrders]|r All order cancellations broadcast successfully")
            if callback then callback() end
        end
    end
    
    -- Start broadcasting with 200ms delay between each (5 per second)
    broadcastTimer = C_Timer.NewTicker(0.2, broadcastNext)
    
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

-- Auto-expire orders after 30 minutes (mark as EXPIRED, not FULFILLED) 
function Database.CleanupExpiredOrders()
    if not GuildWorkOrdersDB or not GuildWorkOrdersDB.orders then
        return 0
    end
    
    local currentTime = GetCurrentTime()
    local expiredCount = 0
    local toRemove = {}
    local playerName = UnitName("player")
    
    for orderID, order in pairs(GuildWorkOrdersDB.orders) do
        if order.expiresAt and order.expiresAt < currentTime then
            -- Only process expired orders that are still active or pending
            if order.status == Database.STATUS.ACTIVE or order.status == Database.STATUS.PENDING then
                -- Only the creator has authority to expire their own orders
                if order.player == playerName then
                    -- I'm the creator - I have authority to expire it
                    order.status = Database.STATUS.EXPIRED
                    order.expiredAt = currentTime
                    order.version = (order.version or 1) + 1
                    
                    -- Notify pending fulfiller that order expired
                    if order.pendingFulfiller then
                        print(string.format("|cffFFFF00[GuildWorkOrders]|r Your pending order for %s has expired", 
                            order.itemName or "item"))
                    end
                    
                    Database.MoveToHistory(order)
                    table.insert(toRemove, orderID)
                    expiredCount = expiredCount + 1
                    
                    -- Broadcast the expiration (not fulfillment)
                    if addon.Sync then
                        addon.Sync.BroadcastOrderUpdate(orderID, Database.STATUS.EXPIRED, order.version)
                    end
                    
                    -- Notify me that my order expired
                    print(string.format("|cffFFFF00[GuildWorkOrders]|r Your %s order for %s has expired after 30 minutes", 
                        order.type, order.itemName or "item"))
                        
                else
                    -- Not my order - just remove from my local view
                    -- The creator will broadcast the expiration via heartbeat
                    table.insert(toRemove, orderID)
                end
            end
        end
    end
    
    -- Remove expired orders from active list
    for _, orderID in ipairs(toRemove) do
        GuildWorkOrdersDB.orders[orderID] = nil
    end
    
    if expiredCount > 0 and Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Cleaned up %d expired orders", expiredCount))
    end
    
    -- After processing expired orders, purge old orders from history
    local purgedCount = Database.PurgeOldOrders()
    if purgedCount > 0 and Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Auto-purged %d old orders during cleanup", purgedCount))
    end
    
    return expiredCount
end

-- Purge old orders from history based on status and age
function Database.PurgeOldOrders()
    if not GuildWorkOrdersDB or not GuildWorkOrdersDB.history then
        return 0
    end
    
    local currentTime = GetCurrentTime()
    local purgedCount = 0
    local remainingHistory = {}
    
    for _, order in ipairs(GuildWorkOrdersDB.history) do
        local shouldPurge = false
        local completionTime = nil
        
        -- Determine completion time based on status
        if order.status == Database.STATUS.CLEARED then
            completionTime = order.clearedAt
        elseif order.status == Database.STATUS.CANCELLED or order.status == Database.STATUS.EXPIRED then
            completionTime = order.completedAt
        elseif order.status == Database.STATUS.FULFILLED then
            completionTime = order.fulfilledAt
        end
        
        -- Check if order should be purged based on age and status
        if completionTime then
            local timeSinceCompletion = currentTime - completionTime
            
            if order.status == Database.STATUS.FULFILLED then
                -- Purge fulfilled orders after 24 hours
                shouldPurge = timeSinceCompletion > Database.PURGE_TIMES.FULFILLED
            else
                -- Purge cleared/cancelled/expired orders after 4 hours
                shouldPurge = timeSinceCompletion > Database.PURGE_TIMES.CLEARED_CANCELLED_EXPIRED
            end
        else
            -- If no completion time, treat as old and purge after 4 hours from general completedAt
            if order.completedAt then
                local timeSinceCompleted = currentTime - order.completedAt
                shouldPurge = timeSinceCompleted > Database.PURGE_TIMES.CLEARED_CANCELLED_EXPIRED
            else
                -- No timestamp at all - keep it for now
                shouldPurge = false
            end
        end
        
        if shouldPurge then
            purgedCount = purgedCount + 1
            if Config.IsDebugMode() then
                print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Purged %s order: %s (age: %d seconds)", 
                    order.status or "unknown", order.itemName or "Unknown", 
                    completionTime and (currentTime - completionTime) or 0))
            end
        else
            table.insert(remainingHistory, order)
        end
    end
    
    -- Update history with remaining orders
    GuildWorkOrdersDB.history = remainingHistory
    
    if purgedCount > 0 and Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Purged %d old orders from history", purgedCount))
    end
    
    return purgedCount
end

-- Get total order count (active + pending + history)
function Database.GetTotalOrderCount()
    local activeCount = 0
    local historyCount = 0
    
    if GuildWorkOrdersDB and GuildWorkOrdersDB.orders then
        for _, order in pairs(GuildWorkOrdersDB.orders) do
            activeCount = activeCount + 1
        end
    end
    
    if GuildWorkOrdersDB and GuildWorkOrdersDB.history then
        historyCount = #GuildWorkOrdersDB.history
    end
    
    return activeCount + historyCount
end

-- Get active order count for a specific user
function Database.GetUserActiveOrderCount(playerName)
    if not GuildWorkOrdersDB or not GuildWorkOrdersDB.orders then
        return 0
    end
    
    local count = 0
    for _, order in pairs(GuildWorkOrdersDB.orders) do
        if order.player == playerName and 
           (order.status == Database.STATUS.ACTIVE or order.status == Database.STATUS.PENDING) then
            count = count + 1
        end
    end
    
    return count
end

-- Get total active order count
function Database.GetActiveOrderCount()
    if not GuildWorkOrdersDB or not GuildWorkOrdersDB.orders then
        return 0
    end
    
    local count = 0
    for _, order in pairs(GuildWorkOrdersDB.orders) do
        if order.status == Database.STATUS.ACTIVE or order.status == Database.STATUS.PENDING then
            count = count + 1
        end
    end
    
    return count
end

-- Get the global clear timestamp 
function Database.GetGlobalClearTimestamp()
    if not GuildWorkOrdersDB then
        GuildWorkOrdersDB = {}
    end
    if not GuildWorkOrdersDB.syncData then
        GuildWorkOrdersDB.syncData = {}
    end
    return GuildWorkOrdersDB.syncData.lastClear or 0
end

-- Set the global clear timestamp
function Database.SetGlobalClearTimestamp(timestamp, clearedBy)
    if not GuildWorkOrdersDB then
        GuildWorkOrdersDB = {}
    end
    if not GuildWorkOrdersDB.syncData then
        GuildWorkOrdersDB.syncData = {}
    end
    GuildWorkOrdersDB.syncData.lastClear = timestamp or GetCurrentTime()
    GuildWorkOrdersDB.syncData.clearedBy = clearedBy or UnitName("player")
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Set global clear timestamp: %d by %s", 
            GuildWorkOrdersDB.syncData.lastClear, GuildWorkOrdersDB.syncData.clearedBy))
    end
end

-- Get the last clear info (timestamp and who cleared)
function Database.GetLastClearInfo()
    if not GuildWorkOrdersDB or not GuildWorkOrdersDB.syncData then
        return 0, nil
    end
    return GuildWorkOrdersDB.syncData.lastClear or 0, GuildWorkOrdersDB.syncData.clearedBy
end

-- Check if an order was created before the last global clear
function Database.IsOrderPreClear(orderTimestamp)
    local clearTimestamp = Database.GetGlobalClearTimestamp()
    return clearTimestamp > 0 and (orderTimestamp or 0) < clearTimestamp
end

-- Purge non-active orders from history to make room for new orders
function Database.PurgeNonActiveOrders(targetCount)
    if not GuildWorkOrdersDB or not GuildWorkOrdersDB.history then
        return 0
    end
    
    local purgeCount = 0
    local currentTotal = Database.GetTotalOrderCount()
    local needToPurge = currentTotal - targetCount
    
    if needToPurge <= 0 then
        return 0
    end
    
    local remainingHistory = {}
    local currentTime = GetCurrentTime()
    
    -- First priority: Remove all cleared/cancelled/expired orders regardless of age
    local clearedPurged = 0
    for _, order in ipairs(GuildWorkOrdersDB.history) do
        if order.status == Database.STATUS.CLEARED or 
           order.status == Database.STATUS.CANCELLED or 
           order.status == Database.STATUS.EXPIRED then
            clearedPurged = clearedPurged + 1
            purgeCount = purgeCount + 1
        else
            table.insert(remainingHistory, order)
        end
    end
    
    -- If we still need to purge more, remove oldest fulfilled orders
    if purgeCount < needToPurge and #remainingHistory > 0 then
        -- Sort remaining history by completion time (oldest first)
        table.sort(remainingHistory, function(a, b)
            local timeA = a.fulfilledAt or a.completedAt or 0
            local timeB = b.fulfilledAt or b.completedAt or 0
            return timeA < timeB
        end)
        
        local finalHistory = {}
        local toKeep = #remainingHistory - (needToPurge - purgeCount)
        
        for i = 1, #remainingHistory do
            if i > (needToPurge - purgeCount) then
                table.insert(finalHistory, remainingHistory[i])
            else
                purgeCount = purgeCount + 1
            end
        end
        
        remainingHistory = finalHistory
    end
    
    -- Update history with remaining orders
    GuildWorkOrdersDB.history = remainingHistory
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Emergency purge: removed %d cleared/cancelled/expired + %d oldest fulfilled orders (database limit: %d)", 
            clearedPurged, purgeCount - clearedPurged, Database.LIMITS.MAX_TOTAL_ORDERS))
    end
    
    return purgeCount
end

-- Check if we can create a new order (respects all limits)
function Database.CanCreateOrder(playerName)
    -- Check per-user limit
    local userActiveCount = Database.GetUserActiveOrderCount(playerName)
    if userActiveCount >= Database.LIMITS.MAX_ACTIVE_PER_USER then
        return false, string.format("You have reached the maximum of %d active orders per user", Database.LIMITS.MAX_ACTIVE_PER_USER)
    end
    
    -- Check total active orders limit
    local totalActiveCount = Database.GetActiveOrderCount()
    if totalActiveCount >= Database.LIMITS.MAX_TOTAL_ORDERS then
        return false, string.format("Maximum of %d active orders reached. Cannot create new orders until some are completed", Database.LIMITS.MAX_TOTAL_ORDERS)
    end
    
    return true, nil
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

-- Clear a single order by admin
function Database.ClearSingleOrder(orderID, clearedBy)
    if not GuildWorkOrdersDB or not GuildWorkOrdersDB.orders then
        return false
    end
    
    if not orderID then
        return false
    end
    
    local orderFound = false
    
    -- Find and remove the order from both active orders and history
    -- Always show debug for troubleshooting
    print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Looking for order ID: %s", orderID))
    
    -- Check active orders first
    local count = 0
    for id, order in pairs(GuildWorkOrdersDB.orders or {}) do
        count = count + 1
        if count <= 3 then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Found active order ID: %s (item: %s)", id, order.itemName or "Unknown"))
        end
    end
    print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Total active orders: %d", count))
    
    -- Check history
    local historyCount = 0
    for i, order in ipairs(GuildWorkOrdersDB.history or {}) do
        historyCount = historyCount + 1
        if historyCount <= 3 then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Found history order ID: %s (item: %s)", order.id or "Unknown", order.itemName or "Unknown"))
        end
    end
    print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Total history orders: %d", historyCount))
    
    -- Try to find in active orders first
    local order = GuildWorkOrdersDB.orders[orderID]
    if order then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Clearing active order %s (%s) by admin %s", 
            orderID, order.itemName or "Unknown", clearedBy or "Unknown"))
        
        -- Mark as cleared instead of deleting
        order.status = Database.STATUS.CLEARED
        order.clearedAt = GetCurrentTime()
        order.clearedBy = clearedBy or "Admin"
        order.version = (order.version or 1) + 1
        
        -- Move to history and remove from active orders
        Database.MoveToHistory(order)
        GuildWorkOrdersDB.orders[orderID] = nil
        orderFound = true
    else
        -- Try to find in history
        if GuildWorkOrdersDB.history then
            for i = #GuildWorkOrdersDB.history, 1, -1 do
                local historyOrder = GuildWorkOrdersDB.history[i]
                if historyOrder and tostring(historyOrder.id) == tostring(orderID) then
                    print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Clearing history order %s (%s) by admin %s", 
                        orderID, historyOrder.itemName or "Unknown", clearedBy or "Unknown"))
                    
                    -- Mark as cleared instead of deleting
                    historyOrder.status = Database.STATUS.CLEARED
                    historyOrder.clearedAt = GetCurrentTime()
                    historyOrder.clearedBy = clearedBy or "Admin"
                    historyOrder.version = (historyOrder.version or 1) + 1
                    orderFound = true
                    break
                end
            end
        end
    end
    
    if orderFound then
        -- Database is automatically saved as SavedVariable
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Successfully cleared order %s", orderID))
        end
        
        return true
    else
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Order %s not found for clearing", orderID))
        end
        
        return false
    end
end