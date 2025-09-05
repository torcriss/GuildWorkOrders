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
    COMPLETED = "completed",   -- Successfully completed
    CANCELLED = "cancelled",   -- Cancelled by user
    EXPIRED = "expired",       -- Automatically expired due to time
    CLEARED = "cleared",       -- Admin cleared
    PURGED = "purged"          -- Marked for deletion, broadcasting for sync
}

-- Order type constants
Database.TYPE = {
    WTB = "WTB",
    WTS = "WTS"
}

-- Database limit constants removed - no limits on order count

-- Purge time constants (in seconds)
Database.PURGE_TIMES = {
    NON_ACTIVE = 120,       -- 2 minutes for all non-active orders (cancelled, expired, cleared, completed)
    PURGE_BROADCAST = 240   -- 4 minutes broadcast time for PURGED orders (2x purge time)
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
    
    -- Cleanup old completed orders before creating new one
    Database.CleanupOldOrders()
    
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
        expiresAt = GetCurrentTime() + (Config.Get("orderExpiry") or 60),
        status = Database.STATUS.ACTIVE,
        version = 1
    }
    
    -- Save to database
    if not GuildWorkOrdersDB.orders then
        GuildWorkOrdersDB.orders = {}
    end
    
    GuildWorkOrdersDB.orders[order.id] = order
    
    if Config.IsDebugMode() then
        print(string.format("|cffAAAAFF[GWO Debug]|r Created %s order: %dx %s for %s",
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

-- Get all active orders from single database
function Database.GetAllOrders()
    if not GuildWorkOrdersDB or not GuildWorkOrdersDB.orders then
        return {}
    end
    
    local orders = {}
    for id, order in pairs(GuildWorkOrdersDB.orders) do
        -- Only include active orders (single source of truth)
        if order.status == Database.STATUS.ACTIVE then
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
    
    -- Get all my orders from single database (active and completed, exclude PURGED)
    for id, order in pairs(GuildWorkOrdersDB.orders) do
        if order.player == playerName and order.status ~= Database.STATUS.PURGED then
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

-- REMOVED: GetMyCreatedOrders - using GetOrdersToHeartbeat instead

-- Get orders to broadcast via heartbeat (created by me, completed by me, OR any completed order for relay)
function Database.GetOrdersToHeartbeat()
    local playerName = UnitName("player")
    local ordersToShare = {}
    
    -- Get all relevant orders from single database
    local currentTime = GetCurrentTime()
    if GuildWorkOrdersDB and GuildWorkOrdersDB.orders then
        for _, order in pairs(GuildWorkOrdersDB.orders) do
            local shouldShare = false
            
            -- Share ALL orders I created until purged
            if order.player == playerName then
                shouldShare = true
            end
            
            -- Share orders I completed or ANY non-active orders for relay
            if order.completedBy == playerName or -- Orders I completed
               order.completedBy or -- ANY completed orders (relay mode)
               order.clearedBy or -- ANY cleared orders (relay mode) 
               order.status == Database.STATUS.CANCELLED or -- ANY cancelled orders (relay mode)
               order.status == Database.STATUS.EXPIRED then -- ANY expired orders (relay mode)
                shouldShare = true
            end
            
            if shouldShare then
                table.insert(ordersToShare, order)
            end
        end
    end
    
    return ordersToShare
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
function Database.UpdateOrderStatus(orderID, newStatus, completedBy)
    if not GuildWorkOrdersDB.orders or not GuildWorkOrdersDB.orders[orderID] then
        return false
    end
    
    local order = GuildWorkOrdersDB.orders[orderID]
    local oldStatus = order.status
    order.status = newStatus
    order.version = (order.version or 1) + 1
    
    -- Track who completed the order
    if newStatus == Database.STATUS.COMPLETED and completedBy then
        order.completedBy = completedBy
        order.completedAt = GetCurrentTime()
    end
    
    -- Track completion timestamps
    if newStatus == Database.STATUS.CANCELLED then
        order.cancelledAt = GetCurrentTime()
    elseif newStatus == Database.STATUS.EXPIRED then
        order.expiredAt = GetCurrentTime()
    end
    
    -- Orders stay in single database - no moving to history needed
    
    if Config.IsDebugMode() then
        print(string.format("|cffAAAAFF[GWO Debug]|r Order status: %s -> %s%s",
            oldStatus, newStatus, completedBy and (" by " .. completedBy) or ""))
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
    
    -- PENDING status removed from system - order completion proceeds without pending state
    
    -- Complete the fulfillment
    return Database.UpdateOrderStatus(orderID, Database.STATUS.COMPLETED, order.pendingFulfiller)
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
        if order.status == Database.STATUS.COMPLETED then
            return false, "Order already completed"
        elseif order.status == Database.STATUS.CANCELLED then
            return false, "Order was cancelled"
        else
            return false, "Order is no longer active"
        end
    end
    
    -- Check if order is expired
    if order.expiresAt and order.expiresAt < GetCurrentTime() then
        -- Set to expired and move to history
        Database.UpdateOrderStatus(orderID, Database.STATUS.CANCELLED)
        return false, "Order has expired"
    end
    
    -- Fulfill the order directly
    local success = Database.UpdateOrderStatus(orderID, Database.STATUS.COMPLETED, fulfillerName)
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
    
    -- Preserve completedBy if it exists locally but not in incoming data
    if existingOrder and existingOrder.completedBy and not orderData.completedBy then
        orderData.completedBy = existingOrder.completedBy
    end
    
    -- Preserve status timestamps if they exist locally but not in incoming data
    if existingOrder then
        if existingOrder.cancelledAt and not orderData.cancelledAt then
            orderData.cancelledAt = existingOrder.cancelledAt
        end
        if existingOrder.expiredAt and not orderData.expiredAt then
            orderData.expiredAt = existingOrder.expiredAt
        end
        if existingOrder.completedAt and not orderData.completedAt then
            orderData.completedAt = existingOrder.completedAt
        end
        if existingOrder.clearedAt and not orderData.clearedAt then
            orderData.clearedAt = existingOrder.clearedAt
        end
        if existingOrder.purgedAt and not orderData.purgedAt then
            orderData.purgedAt = existingOrder.purgedAt
        end
    end
    
    -- All orders stay in single database regardless of status
    GuildWorkOrdersDB.orders[orderData.id] = orderData
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Received order update: %s from %s",
            orderData.itemName or "Unknown Item", orderData.player))
    end
    
    return true
end

-- REMOVED: MoveToHistory - orders stay in single database

-- REMOVED: GetHistory - using single database

-- REMOVED: FindInHistory - using single database

-- Get all orders from single database
function Database.GetAllOrdersUnified()
    local allOrders = {}
    
    -- Get all active orders (without filtering by status)
    if GuildWorkOrdersDB and GuildWorkOrdersDB.orders then
        for id, order in pairs(GuildWorkOrdersDB.orders) do
            -- Exclude PURGED orders from UI
            if order.status ~= Database.STATUS.PURGED then
                -- Clean up any corrupted item names
                Database.CleanItemName(order)
                table.insert(allOrders, order)
            end
        end
    end
    
    -- Single database - no history to merge
    
    -- Sort by timestamp (newest first)
    table.sort(allOrders, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)
    
    return allOrders
end

-- Clear history
-- REMOVED: ClearHistory - using single database

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
        print("|cff00ff00[GWO]|r No active orders to cancel")
        if callback then callback() end
        return true
    end
    
    print(string.format("|cffFFAA00[GWO]|r Broadcasting cancellation of %d orders to all users...", totalOrders))
    
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
                print(string.format("|cffFFAA00[GWO]|r Cancelled %d/%d orders...", currentIndex, totalOrders))
            end
            
            currentIndex = currentIndex + 1
        else
            -- All orders broadcast, cleanup and callback
            if broadcastTimer then
                broadcastTimer:Cancel()
            end
            print("|cff00ff00[GWO]|r All order cancellations broadcast successfully")
            if callback then callback() end
        end
    end
    
    -- Start broadcasting with 200ms delay between each (5 per second)
    broadcastTimer = C_Timer.NewTicker(0.2, broadcastNext)
    
    return true
end

-- Clear all database data (orders only, keep config)
function Database.ClearAllData()
    if not GuildWorkOrdersDB then
        return false
    end
    
    -- Clear all orders from single database but preserve config and sync data structure
    GuildWorkOrdersDB.orders = {}
    
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

-- Cleanup old completed orders based on their specific timestamps
function Database.CleanupOldOrders()
    if not GuildWorkOrdersDB or not GuildWorkOrdersDB.orders then
        return 0
    end
    
    local currentTime = GetCurrentTime()
    local removedCount = 0
    local ordersToRemove = {}
    
    for orderID, order in pairs(GuildWorkOrdersDB.orders) do
        local shouldTransitionToPurged = false
        local shouldDelete = false
        
        -- Add fallback timestamps for legacy orders that have status but missing timestamps
        if order.status == Database.STATUS.EXPIRED and not order.expiredAt then
            order.expiredAt = order.timestamp or (currentTime - Database.PURGE_TIMES.NON_ACTIVE - 1)
        end
        if order.status == Database.STATUS.CANCELLED and not order.cancelledAt then
            order.cancelledAt = order.timestamp or (currentTime - Database.PURGE_TIMES.NON_ACTIVE - 1)
        end
        if order.status == Database.STATUS.COMPLETED and not order.completedAt then
            order.completedAt = order.timestamp or (currentTime - Database.PURGE_TIMES.NON_ACTIVE - 1)
        end
        if order.status == Database.STATUS.CLEARED and not order.clearedAt then
            order.clearedAt = order.timestamp or (currentTime - Database.PURGE_TIMES.NON_ACTIVE - 1)
        end
        
        -- Check if non-active orders should transition to PURGED (after 2 minutes)
        if order.status == Database.STATUS.CANCELLED and order.cancelledAt then
            shouldTransitionToPurged = (currentTime - order.cancelledAt) > Database.PURGE_TIMES.NON_ACTIVE
        elseif order.status == Database.STATUS.CLEARED and order.clearedAt then
            shouldTransitionToPurged = (currentTime - order.clearedAt) > Database.PURGE_TIMES.NON_ACTIVE
        elseif order.status == Database.STATUS.EXPIRED and order.expiredAt then
            shouldTransitionToPurged = (currentTime - order.expiredAt) > Database.PURGE_TIMES.NON_ACTIVE
        elseif order.status == Database.STATUS.COMPLETED and order.completedAt then
            shouldTransitionToPurged = (currentTime - order.completedAt) > Database.PURGE_TIMES.NON_ACTIVE
        elseif order.status == Database.STATUS.PURGED and order.purgedAt then
            -- PURGED orders should be deleted after broadcast period (4 minutes)
            shouldDelete = (currentTime - order.purgedAt) > Database.PURGE_TIMES.PURGE_BROADCAST
        end
        
        if shouldTransitionToPurged then
            -- Transition to PURGED state (first time hitting purge time)
            order.status = Database.STATUS.PURGED
            order.purgedAt = GetCurrentTime()
            order.version = (order.version or 1) + 1
            removedCount = removedCount + 1  -- Count transitions as cleanup activity
            
            if Config.IsDebugMode() then
                print(string.format("|cffAAAAFF[GWO Debug]|r Order transitioned to PURGED: %s", order.itemName or orderID))
            end
        elseif shouldDelete then
            -- Delete PURGED orders after broadcast period
            table.insert(ordersToRemove, orderID)
        end
    end
    
    -- Remove orders that completed their broadcast period
    for _, orderID in ipairs(ordersToRemove) do
        if Config.IsDebugMode() then
            local order = GuildWorkOrdersDB.orders[orderID]
            print(string.format("|cffAAAAFF[GWO Debug]|r Order permanently deleted: %s", order and order.itemName or orderID))
        end
        GuildWorkOrdersDB.orders[orderID] = nil
        removedCount = removedCount + 1
    end
    
    if Config.IsDebugMode() and removedCount > 0 then
        print(string.format("|cffAAAAFF[GWO Debug]|r Cleaned up %d old orders", removedCount))
    end
    
    return removedCount
end

-- Auto-expire orders after 1 minute (mark as EXPIRED, not COMPLETED) 
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
            -- Only process expired orders that are still active
            if order.status == Database.STATUS.ACTIVE then
                -- Only the creator has authority to expire their own orders
                if order.player == playerName then
                    -- Notify pending fulfiller that order expired
                    if order.pendingFulfiller then
                        local ttlMinutes = math.floor((Config.Get("orderExpiry") or 60) / 60)
                        print(string.format("|cffFFFF00[GWO]|r Your order for %s expired after %d minute%s", 
                            order.itemName or "item", ttlMinutes, ttlMinutes == 1 and "" or "s"))
                    end
                    
                    -- Use UpdateOrderStatus to properly handle the expiry
                    Database.UpdateOrderStatus(orderID, Database.STATUS.EXPIRED)
                    
                    -- Order status is updated in single database with expiredAt timestamp
                    
                    expiredCount = expiredCount + 1
                    
                    -- Broadcast the expiration
                    if addon.Sync then
                        addon.Sync.BroadcastOrderUpdate(orderID, Database.STATUS.EXPIRED, order.version or 1)
                    end
                    
                    -- Notify me that my order expired
                    local ttlMinutes = math.floor((Config.Get("orderExpiry") or 60) / 60)
                    local timeText = ttlMinutes > 1 and string.format("%d minutes", ttlMinutes) or "1 minute"
                    print(string.format("|cffFFFF00[GWO]|r Your %s order for %s has expired after %s", 
                        order.type, order.itemName or "item", timeText))
                        
                else
                    -- Not my order - let heartbeat system handle the expiration update
                    -- Don't delete locally, rely on sync from creator
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
    
    -- Purging removed - using FIFO-only system
    
    return expiredCount
end

-- REMOVED: Old purging system - replaced with CleanupOldOrders

-- Get total order count from single database
function Database.GetTotalOrderCount()
    local totalCount = 0
    
    if GuildWorkOrdersDB and GuildWorkOrdersDB.orders then
        for _, order in pairs(GuildWorkOrdersDB.orders) do
            -- Exclude PURGED orders from total count
            if order.status ~= Database.STATUS.PURGED then
                totalCount = totalCount + 1
            end
        end
    end
    
    return totalCount
end

-- Get active order count for a specific user

-- Get total active order count
function Database.GetActiveOrderCount()
    if not GuildWorkOrdersDB or not GuildWorkOrdersDB.orders then
        return 0
    end
    
    local count = 0
    for _, order in pairs(GuildWorkOrdersDB.orders) do
        if order.status == Database.STATUS.ACTIVE then
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

-- REMOVED: PurgeNonActiveOrders - using CleanupOldOrders instead

-- REMOVED: FIFO display limit function - no order count limits

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
    local allOrders = 0
    local completedOrders = 0
    
    -- Count all orders from single database
    if GuildWorkOrdersDB and GuildWorkOrdersDB.orders then
        for _, order in pairs(GuildWorkOrdersDB.orders) do
            allOrders = allOrders + 1
            if order.status ~= Database.STATUS.ACTIVE then
                completedOrders = completedOrders + 1
            end
        end
    end
    
    local stats = {
        activeOrders = #activeOrders,
        totalOrders = allOrders,
        completedOrders = completedOrders,
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
    
    -- Find the order in single database
    local order = GuildWorkOrdersDB.orders[orderID]
    if order then
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Clearing order %s (%s) by admin %s", 
                orderID, order.itemName or "Unknown", clearedBy or "Unknown"))
        end
        
        -- Mark as cleared (order stays in database)
        order.status = Database.STATUS.CLEARED
        order.clearedAt = GetCurrentTime()
        order.clearedBy = clearedBy or "Admin"
        order.version = (order.version or 1) + 1
        orderFound = true
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