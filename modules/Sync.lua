-- Sync.lua - Guild synchronization for GuildWorkOrders
local addonName, addon = ...
addon.Sync = addon.Sync or {}
local Sync = addon.Sync

-- Local references
local Config = nil
local Database = nil

-- Use server time for all timestamps to avoid clock sync issues
local function GetCurrentTime()
    return GetServerTime()
end

-- Constants
local ADDON_PREFIX = "GWO_"
local PROTOCOL_VERSION = 1
local MESSAGE_DELAY = 0.2  -- 200ms between messages (5 per second)
local SYNC_TIMEOUT = 30    -- 30 seconds
local BATCH_SIZE = 1       -- Orders per batch (reduced to ensure messages stay under size limit)
local MAX_HEARTBEAT_ORDERS = 10  -- Max orders per heartbeat (for performance)
local MAX_MESSAGE_SIZE = 250      -- WoW addon message size limit (255 - 5 byte safety margin)
local MAX_ITEMLINK_SIZE = 120     -- Maximum item link length in sync messages (increased due to more efficient escaping)

-- Message types
local MSG_TYPE = {
    NEW_ORDER = "NEW",
    UPDATE_ORDER = "UPDATE", 
    DELETE_ORDER = "DELETE",
    SYNC_REQUEST = "SYNC_REQ",
    SYNC_INFO = "SYNC_INFO",
    SYNC_BATCH = "SYNC_BATCH", 
    SYNC_ACK = "SYNC_ACK",
    PING = "PING",
    PONG = "PONG",
    FULFILL_REQUEST = "FULFILL_REQ",  -- Request to fulfill an order
    FULFILL_ACCEPT = "FULFILL_ACC",   -- Creator accepts fulfillment
    FULFILL_REJECT = "FULFILL_REJ",   -- Creator rejects fulfillment  
    HEARTBEAT = "HEARTBEAT",          -- Periodic broadcast of creator's orders
    CLEAR_ALL = "CLEAR_ALL",          -- Admin clear all orders command
    CLEAR_SINGLE = "CLEAR_SINGLE"     -- Admin clear single order command
}

-- State tracking
local messageQueue = {}
local lastSendTime = 0
local onlineUsers = {}
local syncInProgress = false
local currentSyncSession = nil

function Sync.Initialize()
    Config = addon.Config
    Database = addon.Database
    
    -- Register addon message prefix
    C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
    
    -- Clean up expired online users
    Sync.CleanupOnlineUsers()
    
    -- Start heartbeat system
    Sync.StartHeartbeat()
    
    if Config.IsDebugMode() then
        print("|cff00ff00[GuildWorkOrders Debug]|r Sync module initialized with heartbeat")
    end
end

-- Queue message for sending with rate limiting
function Sync.QueueMessage(message, target)
    -- Validate message size before queueing
    local isValid, error = ValidateMessageSize(message)
    if not isValid then
        if Config.IsDebugMode() then
            print(string.format("|cffFF6B6B[GuildWorkOrders Debug]|r Message rejected: %s", error))
        end
        return false
    end
    
    table.insert(messageQueue, {
        message = message,
        target = target,
        timestamp = GetTime()
    })
    Sync.ProcessQueue()
    return true
end

-- Process message queue with rate limiting
function Sync.ProcessQueue()
    if #messageQueue == 0 then return end
    
    local now = GetTime()
    if now - lastSendTime >= MESSAGE_DELAY then
        local msg = table.remove(messageQueue, 1)
        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, msg.message, "GUILD", msg.target)
        lastSendTime = now
        
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Sent: %s", 
                string.sub(msg.message, 1, 50) .. (#msg.message > 50 and "..." or "")))
        end
        
        -- Schedule next message
        if #messageQueue > 0 then
            C_Timer.After(MESSAGE_DELAY, Sync.ProcessQueue)
        end
    end
end

-- Handle incoming addon messages
function Sync.OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= ADDON_PREFIX then return end
    
    -- Ignore own messages - handle both with and without realm suffix
    -- Exception: Allow own CLEAR_SINGLE and CLEAR_ALL messages to process locally
    local playerName = UnitName("player")
    local playerWithRealm = playerName .. "-" .. GetRealmName()
    local isOwnMessage = (sender == playerName or sender == playerWithRealm)
    
    local parts = {strsplit("|", message)}
    local msgType = parts[1]
    local isAdminClearMessage = (msgType == MSG_TYPE.CLEAR_SINGLE or msgType == MSG_TYPE.CLEAR_ALL)
    
    if isOwnMessage and not isAdminClearMessage then 
        return 
    end
    
    local version = tonumber(parts[2]) or 1
    
    -- Version check
    if version > PROTOCOL_VERSION then
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r %s using newer version (%d vs %d)",
                sender, version, PROTOCOL_VERSION))
        end
    end
    
    -- Update online user
    onlineUsers[sender] = {
        lastSeen = GetCurrentTime(),
        version = version
    }
    
    -- Handle message based on type
    if msgType == MSG_TYPE.NEW_ORDER then
        Sync.HandleNewOrder(parts, sender)
    elseif msgType == MSG_TYPE.UPDATE_ORDER then
        Sync.HandleUpdateOrder(parts, sender)
    elseif msgType == MSG_TYPE.DELETE_ORDER then
        Sync.HandleDeleteOrder(parts, sender)
    elseif msgType == MSG_TYPE.SYNC_REQUEST then
        Sync.HandleSyncRequest(parts, sender)
    elseif msgType == MSG_TYPE.SYNC_INFO then
        Sync.HandleSyncInfo(parts, sender)
    elseif msgType == MSG_TYPE.SYNC_BATCH then
        Sync.HandleSyncBatch(parts, sender)
    elseif msgType == MSG_TYPE.SYNC_ACK then
        Sync.HandleSyncAck(parts, sender)
    elseif msgType == MSG_TYPE.PING then
        Sync.HandlePing(parts, sender)
    elseif msgType == MSG_TYPE.PONG then
        Sync.HandlePong(parts, sender)
    elseif msgType == MSG_TYPE.FULFILL_REQUEST then
        Sync.HandleFulfillRequest(parts, sender)
    elseif msgType == MSG_TYPE.FULFILL_ACCEPT then
        Sync.HandleFulfillAccept(parts, sender)
    elseif msgType == MSG_TYPE.FULFILL_REJECT then
        Sync.HandleFulfillReject(parts, sender)
    elseif msgType == MSG_TYPE.HEARTBEAT then
        Sync.HandleHeartbeat(parts, sender)
    elseif msgType == MSG_TYPE.CLEAR_ALL then
        Sync.HandleClearAll(parts, sender)
    elseif msgType == MSG_TYPE.CLEAR_SINGLE then
        Sync.HandleClearSingle(parts, sender)
    end
end

-- Escape special characters in strings for sync messages
local function EscapeDelimiters(str)
    if not str then return "" end
    str = string.gsub(str, "|", "~P~")   -- |  -> ~P~ (1->3 chars instead of 1->8)
    str = string.gsub(str, ":", "~C~")   -- :  -> ~C~ (1->3 chars instead of 1->9)  
    str = string.gsub(str, ";", "~S~")   -- ;  -> ~S~ (1->3 chars instead of 1->12)
    return str
end

-- Unescape special characters from sync messages  
local function UnescapeDelimiters(str)
    if not str then return "" end
    str = string.gsub(str, "~P~", "|")
    str = string.gsub(str, "~C~", ":")
    str = string.gsub(str, "~S~", ";")
    return str
end

-- Truncate item link for sync messages while preserving essential info
local function TruncateItemLink(itemLink)
    if not itemLink then return "" end
    
    -- If it's already short enough, return as-is
    if string.len(itemLink) <= MAX_ITEMLINK_SIZE then
        return itemLink
    end
    
    -- Try to extract item name from brackets for shortened version
    local itemName = string.match(itemLink, "%[(.-)%]")
    if itemName then
        -- Create a shortened version with just the name
        if string.len(itemName) <= MAX_ITEMLINK_SIZE - 10 then
            return "[" .. itemName .. "]"
        else
            -- Even the name is too long, truncate it
            return "[" .. string.sub(itemName, 1, MAX_ITEMLINK_SIZE - 13) .. "...]"
        end
    end
    
    -- Fallback: try to extract item ID for minimal representation
    local itemId = string.match(itemLink, "Hitem:(%d+)")
    if itemId then
        return "Item " .. itemId
    end
    
    -- Last resort: truncate the string
    return string.sub(itemLink, 1, MAX_ITEMLINK_SIZE - 3) .. "..."
end

-- Validate message size before sending
function ValidateMessageSize(message)
    if not message then return false, "Empty message" end
    
    local messageSize = string.len(message)
    if messageSize > MAX_MESSAGE_SIZE then
        return false, string.format("Message too large: %d bytes (max %d)", messageSize, MAX_MESSAGE_SIZE)
    end
    
    return true, nil
end

-- Broadcast new order
function Sync.BroadcastNewOrder(order)
    local message = string.format("%s|%d|%s|%s|%s|%s|%d|%s|%d|%d|%d",
        MSG_TYPE.NEW_ORDER,
        PROTOCOL_VERSION,
        order.id,
        order.type,
        order.player,
        EscapeDelimiters(TruncateItemLink(order.itemLink) or ""),
        order.quantity or 0,
        EscapeDelimiters(order.price or ""),
        order.timestamp,
        order.expiresAt,
        order.version or 1
    )
    
    Sync.QueueMessage(message)
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Broadcasting new order: %s", order.id))
    end
end

-- Broadcast order update
function Sync.BroadcastOrderUpdate(orderID, status, version, fulfilledBy)
    local message = string.format("%s|%d|%s|%s|%d|%s",
        MSG_TYPE.UPDATE_ORDER,
        PROTOCOL_VERSION,
        orderID,
        status,
        version or 1,
        fulfilledBy or ""
    )
    
    Sync.QueueMessage(message)
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Broadcasting order update: %s -> %s%s", 
            orderID, status, fulfilledBy and (" by " .. fulfilledBy) or ""))
    end
end

-- Handle new order message
function Sync.HandleNewOrder(parts, sender)
    if #parts < 11 then
        if Config.IsDebugMode() then
            print("|cff00ff00[GuildWorkOrders Debug]|r Invalid NEW_ORDER message format")
        end
        return
    end
    
    local orderData = {
        id = parts[3],
        type = parts[4],
        player = parts[5],
        itemLink = UnescapeDelimiters(parts[6]),
        quantity = tonumber(parts[7]),
        price = UnescapeDelimiters(parts[8]),
        timestamp = tonumber(parts[9]) or GetCurrentTime(),
        expiresAt = tonumber(parts[10]) or (GetCurrentTime() + 86400),
        version = tonumber(parts[11]) or 1,
        status = Database.STATUS.ACTIVE
    }
    
    -- Check if this order was created before the last global clear
    if Database.IsOrderPreClear(orderData.timestamp) then
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Ignoring pre-clear order: %s (timestamp: %d)", 
                orderData.id, orderData.timestamp))
        end
        return
    end
    
    -- Extract item name from item link for proper display
    if orderData.itemLink and string.find(orderData.itemLink, "|H") then
        orderData.itemName = string.match(orderData.itemLink, "%[(.-)%]")
        if not orderData.itemName then
            -- If extraction fails, try to get item name from item ID
            local itemId = string.match(orderData.itemLink, "Hitem:(%d+)")
            if itemId then
                orderData.itemName = "Item " .. itemId
            else
                orderData.itemName = "Unknown Item"
            end
        end
    else
        -- If not a proper item link, try to extract item ID or use as plain text
        if orderData.itemLink and string.find(orderData.itemLink, "Hitem:") then
            local itemId = string.match(orderData.itemLink, "Hitem:(%d+)")
            if itemId then
                orderData.itemName = "Item " .. itemId
            else
                orderData.itemName = "Unknown Item"
            end
        else
            orderData.itemName = orderData.itemLink or "Unknown Item"
        end
    end
    
    -- Validate order data
    if not orderData.id or not orderData.type or not orderData.player then
        if Config.IsDebugMode() then
            print("|cff00ff00[GuildWorkOrders Debug]|r Invalid order data in NEW_ORDER")
        end
        return
    end
    
    -- Parse item name from link
    if orderData.itemLink then
        orderData.itemName = string.match(orderData.itemLink, "%[(.-)%]") or orderData.itemLink
        orderData.priceInCopper = Database.ParsePriceToCopper(orderData.price)
    end
    
    -- Sync to database
    local success = Database.SyncOrder(orderData)
    if success and addon.UI and addon.UI.RefreshOrders then
        addon.UI.RefreshOrders()
        if addon.UI.UpdateStatusBar then
            addon.UI.UpdateStatusBar()  -- Update counter when new order synced
        end
    end
end

-- Handle order update message
function Sync.HandleUpdateOrder(parts, sender)
    if #parts < 5 then return end
    
    local orderID = parts[3]
    local status = parts[4]
    local version = tonumber(parts[5]) or 1
    local fulfilledBy = parts[6] ~= "" and parts[6] or nil
    
    -- Find existing order
    if GuildWorkOrdersDB.orders and GuildWorkOrdersDB.orders[orderID] then
        local existingOrder = GuildWorkOrdersDB.orders[orderID]
        
        -- Version check
        if version > (existingOrder.version or 1) then
            Database.UpdateOrderStatus(orderID, status, fulfilledBy)
            
            -- Notify the original order creator if their order was fulfilled by someone else
            if status == Database.STATUS.FULFILLED and fulfilledBy and existingOrder.player == UnitName("player") then
                print(string.format("|cff00ff00[GuildWorkOrders]|r Your %s order for %s has been fulfilled by %s! Contact them to arrange the trade.",
                    existingOrder.type, existingOrder.itemName or "item", fulfilledBy))
            end
            
            if addon.UI and addon.UI.RefreshOrders then
                addon.UI.RefreshOrders()
                if addon.UI.UpdateStatusBar then
                    addon.UI.UpdateStatusBar()  -- Update counter when order status changes
                end
            end
        end
    end
end

-- Handle delete order message
function Sync.HandleDeleteOrder(parts, sender)
    if #parts < 3 then return end
    
    local orderID = parts[3]
    
    if GuildWorkOrdersDB.orders and GuildWorkOrdersDB.orders[orderID] then
        GuildWorkOrdersDB.orders[orderID] = nil
        if addon.UI and addon.UI.RefreshOrders then
            addon.UI.RefreshOrders()
            if addon.UI.UpdateStatusBar then
                addon.UI.UpdateStatusBar()  -- Update counter when order deleted
            end
        end
    end
end

-- Request sync from other users
function Sync.RequestSync()
    local message = string.format("%s|%d|%d|%d",
        MSG_TYPE.SYNC_REQUEST,
        PROTOCOL_VERSION,
        GuildWorkOrdersDB.syncData.lastSync or 0,
        Database.GetGlobalClearTimestamp()
    )
    
    Sync.QueueMessage(message)
    
    -- Set up timeout
    syncInProgress = true
    C_Timer.After(SYNC_TIMEOUT, function()
        if syncInProgress then
            syncInProgress = false
            if Config.IsDebugMode() then
                print("|cff00ff00[GuildWorkOrders Debug]|r Sync request timed out")
            end
            -- Update UI when sync times out
            if addon.UI and addon.UI.UpdateStatusBar then
                addon.UI.UpdateStatusBar()
            end
        end
    end)
    
    if Config.IsDebugMode() then
        print("|cff00ff00[GuildWorkOrders Debug]|r Requesting sync from guild")
    end
end

-- Handle sync request
function Sync.HandleSyncRequest(parts, sender)
    local theirLastSync = tonumber(parts[3]) or 0
    local theirClearTimestamp = tonumber(parts[4]) or 0
    local myClearTimestamp = Database.GetGlobalClearTimestamp()
    
    -- If their clear timestamp is older than mine, send them a clear all message first
    if theirClearTimestamp < myClearTimestamp then
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Sending clear event to %s (their: %d, mine: %d)", 
                sender, theirClearTimestamp, myClearTimestamp))
        end
        
        local _, clearedBy = Database.GetLastClearInfo()
        local clearMessage = string.format("%s|%d|%d|%s",
            MSG_TYPE.CLEAR_ALL,
            PROTOCOL_VERSION,
            myClearTimestamp,
            clearedBy or UnitName("player")
        )
        Sync.QueueMessage(clearMessage, sender)
        return
    end
    
    local orders = Database.ExportOrdersForSync()
    
    -- Filter orders newer than their last sync
    local ordersToSend = {}
    for orderID, order in pairs(orders) do
        if order.timestamp > theirLastSync then
            table.insert(ordersToSend, order)
        end
    end
    
    if #ordersToSend == 0 then
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r No new orders to sync to %s", sender))
        end
        return
    end
    
    -- Send sync info
    local batches = math.ceil(#ordersToSend / BATCH_SIZE)
    local syncID = GetCurrentTime() .. "_" .. math.random(1000, 9999)
    
    local infoMessage = string.format("%s|%d|%s|%d|%d",
        MSG_TYPE.SYNC_INFO,
        PROTOCOL_VERSION,
        syncID,
        batches,
        #ordersToSend
    )
    
    Sync.QueueMessage(infoMessage, sender)
    
    -- Send batches
    for batchNum = 1, batches do
        local startIdx = (batchNum - 1) * BATCH_SIZE + 1
        local endIdx = math.min(batchNum * BATCH_SIZE, #ordersToSend)
        
        local batchData = {}
        local skippedCount = 0
        
        for i = startIdx, endIdx do
            local order = ordersToSend[i]
            local orderStr = string.format("%s:%s:%s:%s:%d:%s:%d:%d:%d",
                order.id,
                order.type,
                order.player,
                EscapeDelimiters(TruncateItemLink(order.itemLink) or ""),
                order.quantity or 0,
                EscapeDelimiters(order.price or ""),
                order.timestamp,
                order.expiresAt,
                order.version or 1
            )
            
            -- Check if adding this order would make the message too large
            local testBatch = table.concat(batchData, ";")
            if testBatch ~= "" then testBatch = testBatch .. ";" end
            testBatch = testBatch .. orderStr
            
            local testMessage = string.format("%s|%d|%s|%d|%d|%s",
                MSG_TYPE.SYNC_BATCH, PROTOCOL_VERSION, syncID, batchNum, batches, testBatch)
            
            local isValid, errorMsg = ValidateMessageSize(testMessage)
            if isValid then
                table.insert(batchData, orderStr)
            else
                skippedCount = skippedCount + 1
                if Config.IsDebugMode() then
                    print(string.format("|cffFFAA00[GuildWorkOrders Debug]|r Skipping oversized order in sync batch: %s (%s)",
                        order.id, order.itemName or "Unknown Item"))
                end
            end
        end
        
        if skippedCount > 0 and not Config.IsDebugMode() then
            print(string.format("|cffFFAA00[GuildWorkOrders]|r Warning: %d orders skipped in sync due to size limits", skippedCount))
        end
        
        -- Only send batch if it has orders
        if #batchData > 0 then
            local batchMessage = string.format("%s|%d|%s|%d|%d|%s",
                MSG_TYPE.SYNC_BATCH,
                PROTOCOL_VERSION,
                syncID,
                batchNum,
                batches,
                table.concat(batchData, ";")
            )
            
            Sync.QueueMessage(batchMessage, sender)
        end
    end
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Sending %d orders in %d batches to %s",
            #ordersToSend, batches, sender))
    end
end

-- Handle sync info
function Sync.HandleSyncInfo(parts, sender)
    if #parts < 5 then return end
    
    local syncID = parts[3]
    local totalBatches = tonumber(parts[4])
    local totalOrders = tonumber(parts[5])
    
    currentSyncSession = {
        id = syncID,
        sender = sender,
        totalBatches = totalBatches,
        totalOrders = totalOrders,
        receivedBatches = {},
        startTime = GetTime()
    }
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Starting sync: %d orders in %d batches from %s",
            totalOrders, totalBatches, sender))
    end
end

-- Handle sync batch
function Sync.HandleSyncBatch(parts, sender)
    if #parts < 6 or not currentSyncSession then return end
    
    local syncID = parts[3]
    local batchNum = tonumber(parts[4])
    local totalBatches = tonumber(parts[5])
    local batchData = parts[6]
    
    -- Verify sync session
    if syncID ~= currentSyncSession.id or sender ~= currentSyncSession.sender then
        return
    end
    
    -- Mark batch as received
    currentSyncSession.receivedBatches[batchNum] = true
    
    -- Process orders in batch
    local orderCount = 0
    for orderStr in string.gmatch(batchData, "[^;]+") do
        local orderParts = {strsplit(":", orderStr)}
        if #orderParts >= 9 then
            local orderData = {
                id = orderParts[1],
                type = orderParts[2],
                player = orderParts[3],
                itemLink = UnescapeDelimiters(orderParts[4]),
                quantity = tonumber(orderParts[5]),
                price = UnescapeDelimiters(orderParts[6]),
                timestamp = tonumber(orderParts[7]),
                expiresAt = tonumber(orderParts[8]),
                version = tonumber(orderParts[9]) or 1,
                status = Database.STATUS.ACTIVE
            }
            
            -- Parse item name and price
            if orderData.itemLink then
                orderData.itemName = string.match(orderData.itemLink, "%[(.-)%]") or orderData.itemLink
                orderData.priceInCopper = Database.ParsePriceToCopper(orderData.price)
            end
            
            -- Check if this order was created before the last global clear
            if not Database.IsOrderPreClear(orderData.timestamp) then
                Database.SyncOrder(orderData)
            elseif Config.IsDebugMode() then
                print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Ignoring pre-clear sync batch order: %s (timestamp: %d)", 
                    orderData.id, orderData.timestamp))
            end
            orderCount = orderCount + 1
        end
    end
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Processed batch %d/%d: %d orders",
            batchNum, totalBatches, orderCount))
    end
    
    -- Check if sync is complete
    local receivedAll = true
    for i = 1, totalBatches do
        if not currentSyncSession.receivedBatches[i] then
            receivedAll = false
            break
        end
    end
    
    if receivedAll then
        -- Send acknowledgment
        local ackMessage = string.format("%s|%d|%s|%d",
            MSG_TYPE.SYNC_ACK,
            PROTOCOL_VERSION,
            syncID,
            currentSyncSession.totalOrders
        )
        
        Sync.QueueMessage(ackMessage, sender)
        
        -- Update last sync time
        GuildWorkOrdersDB.syncData.lastSync = GetCurrentTime()
        
        -- Clean up and refresh UI
        currentSyncSession = nil
        syncInProgress = false
        
        if addon.UI and addon.UI.RefreshOrders then
            addon.UI.RefreshOrders()
            if addon.UI.UpdateStatusBar then
                addon.UI.UpdateStatusBar()  -- Update counter after sync complete
            end
        end
        
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Sync complete: received all %d batches",
                totalBatches))
        end
    end
end

-- Handle sync acknowledgment
function Sync.HandleSyncAck(parts, sender)
    if Config.IsDebugMode() then
        local ordersReceived = parts[4] or "unknown"
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r %s acknowledged sync: %s orders received",
            sender, ordersReceived))
    end
end

-- Send ping to discover online users
function Sync.SendPing()
    local message = string.format("%s|%d",
        MSG_TYPE.PING,
        PROTOCOL_VERSION
    )
    
    Sync.QueueMessage(message)
    
    if Config.IsDebugMode() then
        print("|cff00ff00[GuildWorkOrders Debug]|r Sending ping")
    end
end

-- Handle ping message
function Sync.HandlePing(parts, sender)
    local message = string.format("%s|%d",
        MSG_TYPE.PONG,
        PROTOCOL_VERSION
    )
    
    Sync.QueueMessage(message, sender)
end

-- Handle pong message
function Sync.HandlePong(parts, sender)
    onlineUsers[sender] = {
        lastSeen = GetCurrentTime(),
        version = tonumber(parts[2]) or 1
    }
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Received pong from %s", sender))
    end
end

-- Clean up offline users
function Sync.CleanupOnlineUsers()
    local currentTime = GetCurrentTime()
    local toRemove = {}
    
    for playerName, userData in pairs(onlineUsers) do
        if currentTime - userData.lastSeen > 300 then  -- 5 minutes
            table.insert(toRemove, playerName)
        end
    end
    
    for _, playerName in ipairs(toRemove) do
        onlineUsers[playerName] = nil
    end
end

-- Get online user count
function Sync.GetOnlineUserCount()
    Sync.CleanupOnlineUsers()
    local count = 0
    for _ in pairs(onlineUsers) do
        count = count + 1
    end
    return count
end

-- Get online users list
function Sync.GetOnlineUsers()
    Sync.CleanupOnlineUsers()
    return onlineUsers
end

-- Get sync status
function Sync.GetSyncStatus()
    local lastSync = GuildWorkOrdersDB.syncData.lastSync or 0
    local timeAgo = lastSync > 0 and (GetCurrentTime() - lastSync) or nil
    
    return {
        lastSync = lastSync,
        timeAgo = timeAgo,
        inProgress = syncInProgress,
        onlineUsers = Sync.GetOnlineUserCount()
    }
end

-- ============================================================================
-- FULFILLMENT REQUEST/RESPONSE SYSTEM
-- ============================================================================

-- Send fulfillment request
function Sync.RequestFulfillment(orderID)
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
        return false, "Order is no longer active"
    end
    
    -- Check if order is expired
    if order.expiresAt and order.expiresAt < GetCurrentTime() then
        return false, "Order has expired"
    end
    
    local message = string.format("%s|%d|%s|%s|%d",
        MSG_TYPE.FULFILL_REQUEST,
        PROTOCOL_VERSION,
        orderID,
        playerName,
        GetCurrentTime()
    )
    
    Sync.QueueMessage(message, order.player)
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Requesting fulfillment of order %s from %s", 
            orderID, order.player))
    end
    
    return true
end

-- Handle fulfillment request (Creator receives this)
function Sync.HandleFulfillRequest(parts, sender)
    if #parts < 5 then return end
    
    local orderID = parts[3]
    local requester = parts[4] 
    local requestTime = tonumber(parts[5]) or GetCurrentTime()
    
    -- Check if this is my order
    if not GuildWorkOrdersDB.orders or not GuildWorkOrdersDB.orders[orderID] then
        -- Order not found, reject
        Sync.SendFulfillReject(orderID, requester, "Order not found")
        return
    end
    
    local order = GuildWorkOrdersDB.orders[orderID]
    local playerName = UnitName("player")
    
    -- Only I can accept fulfillment of my orders
    if order.player ~= playerName then
        return -- Ignore, not my order
    end
    
    -- Check if order is still available
    if order.status == Database.STATUS.PENDING then
        -- Already have a pending fulfillment
        Sync.SendFulfillReject(orderID, requester, "Order is already being fulfilled by " .. (order.pendingFulfiller or "someone"))
        return
    elseif order.status ~= Database.STATUS.ACTIVE then
        Sync.SendFulfillReject(orderID, requester, "Order is no longer active")
        return
    end
    
    -- Check expiration
    if order.expiresAt and order.expiresAt < time() then
        Sync.SendFulfillReject(orderID, requester, "Order has expired")
        return
    end
    
    -- Accept the fulfillment request
    order.status = Database.STATUS.PENDING
    order.pendingFulfiller = requester
    order.pendingTimestamp = requestTime
    order.version = (order.version or 1) + 1
    
    -- Send acceptance
    Sync.SendFulfillAccept(orderID, requester)
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Accepted fulfillment request from %s for order %s", 
            requester, orderID))
    end
    
    -- Refresh UI
    if addon.UI and addon.UI.RefreshOrders then
        addon.UI.RefreshOrders()
    end
end

-- Send fulfillment acceptance
function Sync.SendFulfillAccept(orderID, requester)
    local message = string.format("%s|%d|%s|%s",
        MSG_TYPE.FULFILL_ACCEPT,
        PROTOCOL_VERSION,
        orderID,
        requester
    )
    
    Sync.QueueMessage(message, requester)
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Sent fulfillment acceptance to %s for order %s", 
            requester, orderID))
    end
end

-- Send fulfillment rejection
function Sync.SendFulfillReject(orderID, requester, reason)
    local message = string.format("%s|%d|%s|%s|%s",
        MSG_TYPE.FULFILL_REJECT,
        PROTOCOL_VERSION,
        orderID,
        requester,
        EscapeDelimiters(reason or "")
    )
    
    Sync.QueueMessage(message, requester)
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Sent fulfillment rejection to %s for order %s: %s", 
            requester, orderID, reason))
    end
end

-- Handle fulfillment acceptance (Requester receives this)
function Sync.HandleFulfillAccept(parts, sender)
    if #parts < 4 then return end
    
    local orderID = parts[3]
    local requester = parts[4]
    local playerName = UnitName("player")
    
    -- Check if this is for me
    if requester ~= playerName then
        return -- Not for me
    end
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Fulfillment accepted by %s for order %s", 
            sender, orderID))
    end
    
    -- Update UI to show acceptance
    if addon.UI and addon.UI.HandleFulfillmentResponse then
        addon.UI.HandleFulfillmentResponse(orderID, "accepted", sender)
    end
    
    -- Show notification
    print(string.format("|cff00ff00[GuildWorkOrders]|r Your fulfillment request was accepted! Contact %s to arrange the trade.", sender))
end

-- Handle fulfillment rejection (Requester receives this) 
function Sync.HandleFulfillReject(parts, sender)
    if #parts < 5 then return end
    
    local orderID = parts[3]
    local requester = parts[4]
    local reason = UnescapeDelimiters(parts[5])
    local playerName = UnitName("player")
    
    -- Check if this is for me
    if requester ~= playerName then
        return -- Not for me
    end
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Fulfillment rejected by %s for order %s: %s", 
            sender, orderID, reason))
    end
    
    -- Update UI to show rejection
    if addon.UI and addon.UI.HandleFulfillmentResponse then
        addon.UI.HandleFulfillmentResponse(orderID, "rejected", sender, reason)
    end
    
    -- Show notification
    print(string.format("|cff00ff00[GuildWorkOrders]|r Fulfillment request rejected: %s", reason))
end

-- ============================================================================
-- HEARTBEAT SYSTEM
-- ============================================================================

-- Send heartbeat with my orders (periodic broadcast)
function Sync.SendHeartbeat()
    if not Database then return end
    
    local myOrders = Database.GetMyCreatedOrders()
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Found %d my orders for heartbeat", myOrders and #myOrders or 0))
    end
    
    if not myOrders or #myOrders == 0 then
        if Config.IsDebugMode() then
            print("|cff00ff00[GuildWorkOrders Debug]|r Heartbeat skipped: no orders to broadcast")
        end
        return -- No orders to broadcast
    end
    
    local currentTime = GetCurrentTime()
    local ordersToSend = {}
    
    for _, order in ipairs(myOrders) do
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Order %s status: %s", order.id or "unknown", order.status or "unknown"))
        end
        
        -- Include active, pending orders and recently completed (24 hour window)
        if order.status == Database.STATUS.ACTIVE or 
           order.status == Database.STATUS.PENDING or
           (order.status == Database.STATUS.EXPIRED and 
            order.expiredAt and currentTime - order.expiredAt < 86400) or
           (order.status == Database.STATUS.FULFILLED and 
            order.fulfilledAt and currentTime - order.fulfilledAt < 86400) or
           (order.status == Database.STATUS.CANCELLED and 
            order.completedAt and currentTime - order.completedAt < 86400) then
            
            table.insert(ordersToSend, order)
            if Config.IsDebugMode() then
                print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Including order %s in heartbeat", order.id or "unknown"))
            end
        end
    end
    
    if #ordersToSend == 0 then
        if Config.IsDebugMode() then
            print("|cff00ff00[GuildWorkOrders Debug]|r No orders passed filtering for heartbeat")
        end
        return -- No relevant orders to broadcast
    end
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Proceeding to send heartbeat with %d orders", #ordersToSend))
    end
    
    -- Sort orders by priority: PENDING first, then newest ACTIVE
    table.sort(ordersToSend, function(a, b)
        -- Pending orders have highest priority
        if a.status == Database.STATUS.PENDING and b.status ~= Database.STATUS.PENDING then
            return true
        elseif b.status == Database.STATUS.PENDING and a.status ~= Database.STATUS.PENDING then
            return false
        end
        -- For same status, newest first
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)
    
    -- Limit to most important orders for performance
    if #ordersToSend > MAX_HEARTBEAT_ORDERS then
        local limited = {}
        for i = 1, MAX_HEARTBEAT_ORDERS do
            table.insert(limited, ordersToSend[i])
        end
        ordersToSend = limited
    end
    
    -- Send orders in batches (like sync system does)
    local batches = math.ceil(#ordersToSend / BATCH_SIZE)
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Creating %d batches for heartbeat", batches))
    end
    
    for batchNum = 1, batches do
        local startIdx = (batchNum - 1) * BATCH_SIZE + 1
        local endIdx = math.min(batchNum * BATCH_SIZE, #ordersToSend)
        
        local batchData = {}
        local skippedCount = 0
        
        for i = startIdx, endIdx do
            local order = ordersToSend[i]
            local orderStr = string.format("%s:%s:%s:%s:%d:%s:%d:%d:%d:%s:%s:%d",
                order.id,
                order.type,
                order.player,
                EscapeDelimiters(TruncateItemLink(order.itemLink) or ""),
                order.quantity or 0,
                EscapeDelimiters(order.price or ""),
                order.timestamp,
                order.expiresAt,
                order.version or 1,
                order.status,
                EscapeDelimiters(order.pendingFulfiller or ""),
                order.pendingTimestamp or 0
            )
            
            -- Removed verbose debug logging for order strings
            
            -- Check if adding this order would make the message too large
            local testBatch = table.concat(batchData, ";")
            if testBatch ~= "" then testBatch = testBatch .. ";" end
            testBatch = testBatch .. orderStr
            
            local testMessage = string.format("%s|%d|%d|%d|%s",
                MSG_TYPE.HEARTBEAT, PROTOCOL_VERSION, batchNum, batches, testBatch)
            
            -- Removed verbose debug logging for test messages
            
            local isValid, errorMsg = ValidateMessageSize(testMessage)
            if isValid then
                table.insert(batchData, orderStr)
            else
                skippedCount = skippedCount + 1
                if Config.IsDebugMode() then
                    print(string.format("|cffFFAA00[GuildWorkOrders Debug]|r Skipping oversized order in heartbeat: %s (%s)",
                        order.id, order.itemName or "Unknown Item"))
                end
            end
        end
        
        if skippedCount > 0 and not Config.IsDebugMode() then
            print(string.format("|cffFFAA00[GuildWorkOrders]|r Warning: %d orders skipped in heartbeat due to size limits", skippedCount))
        end
        
        -- Only send batch if it has orders
        if #batchData > 0 then
            local batchMessage = string.format("%s|%d|%d|%d|%s",
                MSG_TYPE.HEARTBEAT,
                PROTOCOL_VERSION,
                batchNum,
                batches,
                table.concat(batchData, ";")
            )
            
            if Config.IsDebugMode() then
                print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Sending batch %d/%d with %d orders", 
                    batchNum, batches, #batchData))
            end
            
            local success = Sync.QueueMessage(batchMessage)
            if Config.IsDebugMode() and not success then
                print(string.format("|cffFF6B6B[GuildWorkOrders Debug]|r Failed to queue batch %d", batchNum))
            end
        else
            if Config.IsDebugMode() then
                print(string.format("|cffFFAA00[GuildWorkOrders Debug]|r Batch %d/%d has no orders to send", 
                    batchNum, batches))
            end
        end
    end
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Sent heartbeat with %d orders", #ordersToSend))
    end
    
    -- Also cleanup expired orders during heartbeat
    Database.CleanupExpiredOrders()
end

-- Handle heartbeat messages
function Sync.HandleHeartbeat(parts, sender)
    if #parts < 5 then return end
    
    local batchNum = tonumber(parts[3]) or 1
    local totalBatches = tonumber(parts[4]) or 1
    local batchData = parts[5]
    
    -- Parse batch of orders
    local orderStrings = {strsplit(";", batchData)}
    
    for _, orderStr in ipairs(orderStrings) do
        if orderStr and orderStr ~= "" then
            local orderParts = {strsplit(":", orderStr)}
            if #orderParts >= 12 then
                local orderData = {
                    id = orderParts[1],
                    type = orderParts[2],
                    player = orderParts[3],
                    itemLink = UnescapeDelimiters(orderParts[4]),
                    quantity = tonumber(orderParts[5]),
                    price = UnescapeDelimiters(orderParts[6]),
                    timestamp = tonumber(orderParts[7]) or GetCurrentTime(),
                    expiresAt = tonumber(orderParts[8]) or (GetCurrentTime() + 86400),
                    version = tonumber(orderParts[9]) or 1,
                    status = orderParts[10],
                    pendingFulfiller = UnescapeDelimiters(orderParts[11]),
                    pendingTimestamp = tonumber(orderParts[12]) or 0
                }
                
                -- Only accept heartbeat from the order creator
                -- Handle both with and without realm suffix in sender name
                local baseSenderName = strsplit("-", sender)
                if orderData.player == sender or orderData.player == baseSenderName then
                    Sync.ProcessHeartbeatOrder(orderData, sender)
                elseif Config.IsDebugMode() then
                    print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Rejected heartbeat: order creator (%s) != sender (%s)", 
                        orderData.player, sender))
                end
            end
        end
    end
    
    -- Refresh UI after processing batch
    if addon.UI and addon.UI.RefreshOrders then
        addon.UI.RefreshOrders()
        if addon.UI.UpdateStatusBar then
            addon.UI.UpdateStatusBar()
        end
    end
end

-- Process individual order from heartbeat
function Sync.ProcessHeartbeatOrder(orderData, sender)
    -- Extract item name from item link
    if orderData.itemLink and string.find(orderData.itemLink, "|H") then
        orderData.itemName = string.match(orderData.itemLink, "%[(.-)%]")
        if not orderData.itemName then
            local itemId = string.match(orderData.itemLink, "Hitem:(%d+)")
            if itemId then
                orderData.itemName = "Item " .. itemId
            else
                orderData.itemName = "Unknown Item"
            end
        end
    else
        if orderData.itemLink and string.find(orderData.itemLink, "Hitem:") then
            local itemId = string.match(orderData.itemLink, "Hitem:(%d+)")
            if itemId then
                orderData.itemName = "Item " .. itemId
            else
                orderData.itemName = "Unknown Item"
            end
        else
            orderData.itemName = orderData.itemLink or "Unknown Item"
        end
    end
    
    -- Add price in copper for sorting
    orderData.priceInCopper = Database.ParsePriceToCopper(orderData.price)
    
    -- Check if this order was created before the last global clear
    if Database.IsOrderPreClear(orderData.timestamp) then
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Ignoring pre-clear heartbeat order: %s (timestamp: %d)", 
                orderData.id, orderData.timestamp))
        end
        return
    end
    
    -- Sync all orders (including completed ones) to ensure status consistency
    local success = Database.SyncOrder(orderData)
    if success then
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Synced order from heartbeat: %s (%s)", 
                orderData.id, orderData.status))
        end
        
        -- For completed orders, move to history and remove from active orders
        if orderData.status == Database.STATUS.EXPIRED or 
           orderData.status == Database.STATUS.FULFILLED or 
           orderData.status == Database.STATUS.CANCELLED then
            
            -- Move to history if not already there
            Database.MoveToHistory(orderData)
            
            -- Remove from active orders
            if GuildWorkOrdersDB.orders and GuildWorkOrdersDB.orders[orderData.id] then
                GuildWorkOrdersDB.orders[orderData.id] = nil
            end
        end
    end
end

-- Start periodic heartbeat timer
local heartbeatTimer = nil
function Sync.StartHeartbeat()
    if heartbeatTimer then
        heartbeatTimer:Cancel()
    end
    
    -- Send heartbeat every 30 seconds
    heartbeatTimer = C_Timer.NewTicker(30, function()
        if Config.IsDebugMode() then
            print("|cff00ff00[GuildWorkOrders Debug]|r Heartbeat timer triggered")
        end
        Sync.SendHeartbeat()
    end)
    
    -- Send initial heartbeat after 5 seconds
    C_Timer.After(5, function()
        if Config.IsDebugMode() then
            print("|cff00ff00[GuildWorkOrders Debug]|r Initial heartbeat triggered")
        end
        Sync.SendHeartbeat()
    end)
    
    if Config.IsDebugMode() then
        print("|cff00ff00[GuildWorkOrders Debug]|r Started heartbeat system")
    end
end

-- Stop heartbeat timer
function Sync.StopHeartbeat()
    if heartbeatTimer then
        heartbeatTimer:Cancel()
        heartbeatTimer = nil
        
        if Config.IsDebugMode() then
            print("|cff00ff00[GuildWorkOrders Debug]|r Stopped heartbeat system")
        end
    end
end

-- Handle admin clear all command
function Sync.HandleClearAll(parts, sender)
    if #parts < 3 then return end
    
    local clearTimestamp = tonumber(parts[3])
    local clearedBy = parts[4] or sender
    if not clearTimestamp then return end
    
    local currentClearTimestamp = Database.GetGlobalClearTimestamp()
    
    -- Only process if this is a newer clear event
    if clearTimestamp > currentClearTimestamp then
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Received admin clear from %s (timestamp: %d)", clearedBy, clearTimestamp))
        end
        
        -- Set the new clear timestamp with clearer's name
        Database.SetGlobalClearTimestamp(clearTimestamp, clearedBy)
        
        -- Clear all orders and history (like ClearAllData does)
        if GuildWorkOrdersDB then
            if GuildWorkOrdersDB.orders then
                GuildWorkOrdersDB.orders = {}
            end
            if GuildWorkOrdersDB.history then
                GuildWorkOrdersDB.history = {}
            end
        end
        
        -- Refresh UI
        if addon.UI and addon.UI.RefreshOrders then
            addon.UI.RefreshOrders()
            if addon.UI.UpdateStatusBar then
                addon.UI.UpdateStatusBar()
            end
        end
        
        print("|cffFFAA00[GuildWorkOrders]|r All orders have been cleared by guild admin")
    end
end

-- Broadcast clear all command to guild
function Sync.BroadcastClearAll(callback)
    local clearTimestamp = GetCurrentTime()
    local clearedBy = UnitName("player")
    Database.SetGlobalClearTimestamp(clearTimestamp, clearedBy)
    
    local message = string.format("%s|%d|%d|%s",
        MSG_TYPE.CLEAR_ALL,
        PROTOCOL_VERSION,
        clearTimestamp,
        clearedBy
    )
    
    Sync.QueueMessage(message)
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Broadcasting clear all (timestamp: %d, by: %s)", clearTimestamp, clearedBy))
    end
    
    -- Call callback immediately for now - in a real implementation you might want to wait for confirmations
    if callback then
        callback()
    end
end

-- Handle single order clear from another user
function Sync.HandleClearSingle(parts, sender)
    if #parts < 3 then return end
    
    local orderID = parts[3]
    local clearedBy = parts[4] or sender
    if not orderID then return end
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Received single order clear from %s (order: %s)", clearedBy, orderID))
    end
    
    -- Clear the specific order (ensure orderID is string for proper matching)
    if Database then
        Database.ClearSingleOrder(tostring(orderID), clearedBy)
    end
    
    -- Refresh UI
    if addon.UI and addon.UI.RefreshOrders then
        addon.UI.RefreshOrders()
        if addon.UI.UpdateStatusBar then
            addon.UI.UpdateStatusBar()
        end
    end
    
    print(string.format("|cffFFAA00[GuildWorkOrders]|r Order cleared by admin: %s", clearedBy))
end

-- Broadcast single order clear command to guild
function Sync.BroadcastClearSingle(orderID, callback)
    local clearedBy = UnitName("player")
    
    local message = string.format("%s|%d|%s|%s",
        MSG_TYPE.CLEAR_SINGLE,
        PROTOCOL_VERSION,
        orderID,
        clearedBy
    )
    
    Sync.QueueMessage(message)
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Broadcasting single clear (order: %s, by: %s)", orderID, clearedBy))
    end
    
    -- Call callback immediately
    if callback then
        callback()
    end
end