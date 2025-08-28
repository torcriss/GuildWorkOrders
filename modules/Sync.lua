-- Sync.lua - Guild synchronization for GuildWorkOrders
local addonName, addon = ...
addon.Sync = addon.Sync or {}
local Sync = addon.Sync

-- Local references
local Config = nil
local Database = nil

-- Constants
local ADDON_PREFIX = "GWO_"
local PROTOCOL_VERSION = 1
local MESSAGE_DELAY = 0.2  -- 200ms between messages (5 per second)
local SYNC_TIMEOUT = 30    -- 30 seconds
local BATCH_SIZE = 5       -- Orders per batch

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
    PONG = "PONG"
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
    
    if Config.IsDebugMode() then
        print("|cff00ff00[GuildWorkOrders Debug]|r Sync module initialized")
    end
end

-- Queue message for sending with rate limiting
function Sync.QueueMessage(message, target)
    table.insert(messageQueue, {
        message = message,
        target = target,
        timestamp = GetTime()
    })
    Sync.ProcessQueue()
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
    if sender == UnitName("player") then return end  -- Ignore own messages
    
    local parts = {strsplit("|", message)}
    local msgType = parts[1]
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
        lastSeen = time(),
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
    end
end

-- Broadcast new order
function Sync.BroadcastNewOrder(order)
    local message = string.format("%s|%d|%s|%s|%s|%s|%d|%s|%d|%d|%d",
        MSG_TYPE.NEW_ORDER,
        PROTOCOL_VERSION,
        order.id,
        order.type,
        order.player,
        order.itemLink or "",
        order.quantity or 0,
        order.price or "",
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
function Sync.BroadcastOrderUpdate(orderID, status, version)
    local message = string.format("%s|%d|%s|%s|%d",
        MSG_TYPE.UPDATE_ORDER,
        PROTOCOL_VERSION,
        orderID,
        status,
        version or 1
    )
    
    Sync.QueueMessage(message)
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Broadcasting order update: %s -> %s", 
            orderID, status))
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
        itemLink = parts[6],
        quantity = tonumber(parts[7]),
        price = parts[8],
        timestamp = tonumber(parts[9]),
        expiresAt = tonumber(parts[10]),
        version = tonumber(parts[11]) or 1,
        status = Database.STATUS.ACTIVE
    }
    
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
    end
end

-- Handle order update message
function Sync.HandleUpdateOrder(parts, sender)
    if #parts < 5 then return end
    
    local orderID = parts[3]
    local status = parts[4]
    local version = tonumber(parts[5]) or 1
    
    -- Find existing order
    if GuildWorkOrdersDB.orders and GuildWorkOrdersDB.orders[orderID] then
        local existingOrder = GuildWorkOrdersDB.orders[orderID]
        
        -- Version check
        if version > (existingOrder.version or 1) then
            Database.UpdateOrderStatus(orderID, status)
            if addon.UI and addon.UI.RefreshOrders then
                addon.UI.RefreshOrders()
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
        end
    end
end

-- Request sync from other users
function Sync.RequestSync()
    local message = string.format("%s|%d|%d",
        MSG_TYPE.SYNC_REQUEST,
        PROTOCOL_VERSION,
        GuildWorkOrdersDB.syncData.lastSync or 0
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
        end
    end)
    
    if Config.IsDebugMode() then
        print("|cff00ff00[GuildWorkOrders Debug]|r Requesting sync from guild")
    end
end

-- Handle sync request
function Sync.HandleSyncRequest(parts, sender)
    local theirLastSync = tonumber(parts[3]) or 0
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
    local syncID = time() .. "_" .. math.random(1000, 9999)
    
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
        for i = startIdx, endIdx do
            local order = ordersToSend[i]
            local orderStr = string.format("%s:%s:%s:%s:%d:%s:%d:%d:%d",
                order.id,
                order.type,
                order.player,
                order.itemLink or "",
                order.quantity or 0,
                order.price or "",
                order.timestamp,
                order.expiresAt,
                order.version or 1
            )
            table.insert(batchData, orderStr)
        end
        
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
                itemLink = orderParts[4],
                quantity = tonumber(orderParts[5]),
                price = orderParts[6],
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
            
            Database.SyncOrder(orderData)
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
        GuildWorkOrdersDB.syncData.lastSync = time()
        
        -- Clean up and refresh UI
        currentSyncSession = nil
        syncInProgress = false
        
        if addon.UI and addon.UI.RefreshOrders then
            addon.UI.RefreshOrders()
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
        lastSeen = time(),
        version = tonumber(parts[2]) or 1
    }
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Received pong from %s", sender))
    end
end

-- Clean up offline users
function Sync.CleanupOnlineUsers()
    local currentTime = time()
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
    local timeAgo = lastSync > 0 and (time() - lastSync) or nil
    
    return {
        lastSync = lastSync,
        timeAgo = timeAgo,
        inProgress = syncInProgress,
        onlineUsers = Sync.GetOnlineUserCount()
    }
end