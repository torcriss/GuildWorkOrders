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

-- Message types (simplified for heartbeat-only)
local MSG_TYPE = {
    PING = "PING",
    PONG = "PONG",
    FULFILL_REQUEST = "FULFILL_REQ",  -- Request to fulfill an order
    FULFILL_ACCEPT = "FULFILL_ACC",   -- Creator accepts fulfillment
    FULFILL_REJECT = "FULFILL_REJ",   -- Creator rejects fulfillment  
    HEARTBEAT = "HEARTBEAT",          -- Periodic broadcast of creator's orders
    CLEAR_ALL = "CLEAR_ALL",          -- Admin clear all orders command
    CLEAR_SINGLE = "CLEAR_SINGLE"     -- Admin clear single order command
}

-- Status code mappings for heartbeat compression
local STATUS_CODES = {
    encode = {
        ["active"] = "a",
        ["pending"] = "p", 
        ["fulfilled"] = "f",
        ["cancelled"] = "c",
        ["expired"] = "e",
        ["cleared"] = "x",
        ["failed"] = "F"
    },
    decode = {
        ["a"] = "active",
        ["p"] = "pending",
        ["f"] = "fulfilled", 
        ["c"] = "cancelled",
        ["e"] = "expired",
        ["x"] = "cleared",
        ["F"] = "failed"
    }
}

-- Helper functions for heartbeat compression
local function EncodeStatus(status)
    return STATUS_CODES.encode[status] or status
end

local function DecodeStatus(code)
    return STATUS_CODES.decode[code] or code
end

local function CreateShortOrderId(order)
    -- Use first letter of player name + last 6 digits of timestamp
    local firstLetter = string.sub(order.player or "U", 1, 1)
    local shortTimestamp = string.sub(tostring(order.timestamp or 0), -6)
    return firstLetter .. shortTimestamp
end

local function GetRelativeTimestamps(order)
    local currentTime = GetCurrentTime()
    local timeAgo = math.max(0, currentTime - (order.timestamp or 0))
    local ttl = math.max(0, (order.expiresAt or 0) - currentTime)
    
    -- If order is expired, send special marker TTL=-1
    if order.expiresAt and order.expiresAt < currentTime then
        ttl = -1
    end
    
    return timeAgo, ttl
end

local function RestoreAbsoluteTimestamps(timeAgo, ttl, currentTime)
    local timestamp = currentTime - timeAgo
    local expiresAt
    
    -- Handle special marker for expired orders
    if ttl == -1 then
        -- Set expiry to 1 second ago to ensure it shows as expired
        expiresAt = currentTime - 1
    else
        expiresAt = currentTime + ttl
    end
    
    return timestamp, expiresAt
end

-- State tracking
local messageQueue = {}
local lastSendTime = 0
local syncInProgress = false
local currentSyncSession = nil

function Sync.Initialize()
    Config = addon.Config
    Database = addon.Database
    
    -- Register addon message prefix
    C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
    
    -- Online user tracking removed
    
    -- Start heartbeat system
    Sync.StartHeartbeat()
    
    if Config.IsDebugMode() then
        print("|cff00ff00[GuildWorkOrders Debug]|r Guild communication system ready - heartbeat every 3 seconds")
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
    
    -- Online user tracking removed
    
    -- Handle message based on type (heartbeat-only system)
    if msgType == MSG_TYPE.PING then
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

-- New orders are shared via heartbeat only - no immediate broadcast
-- This function kept for API compatibility but does nothing
function Sync.BroadcastNewOrder(order)
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r New order will be shared via heartbeat: %s", order.id))
    end
end

-- Order updates are shared via heartbeat only - no immediate broadcast
-- This function kept for API compatibility but does nothing
function Sync.BroadcastOrderUpdate(orderID, status, version, fulfilledBy)
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Order update will be shared via heartbeat: %s -> %s", 
            orderID, status))
    end
end

-- Removed - orders sync via heartbeat only

-- Removed - order updates sync via heartbeat only

-- Removed - order deletions handled via heartbeat only

-- Request sync from other users (disabled in heartbeat-only system)
function Sync.RequestSync()
    -- Full sync disabled - using heartbeat-only system
    if Config.IsDebugMode() then
        print("|cff00ff00[GuildWorkOrders Debug]|r Full sync disabled - orders sync via heartbeat only")
    end
end

-- Removed - full sync disabled in heartbeat-only system

-- Removed - full sync disabled in heartbeat-only system

-- Removed - full sync disabled in heartbeat-only system

-- Removed - full sync disabled in heartbeat-only system

-- Ping functionality simplified (kept for compatibility)
function Sync.SendPing()
    -- Ping functionality removed - no longer needed
    if Config.IsDebugMode() then
        print("|cff00ff00[GuildWorkOrders Debug]|r Ping functionality disabled")
    end
end

-- Handle ping message (simplified)
function Sync.HandlePing(parts, sender)
    -- Ping handling removed - no longer needed
end

-- Handle pong message (simplified)
function Sync.HandlePong(parts, sender)
    -- Pong handling removed - no longer needed
end

-- Removed - online user tracking no longer needed

-- Removed - online user tracking no longer needed

-- Removed - online user tracking no longer needed

-- Get sync status
function Sync.GetSyncStatus()
    local lastSync = GuildWorkOrdersDB.syncData.lastSync or 0
    local timeAgo = lastSync > 0 and (GetCurrentTime() - lastSync) or nil
    
    return {
        lastSync = lastSync,
        timeAgo = timeAgo,
        inProgress = syncInProgress
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
    
    local myOrders = Database.GetOrdersToHeartbeat()
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r You have %d orders to share with guild", myOrders and #myOrders or 0))
    end
    
    if not myOrders or #myOrders == 0 then
        if Config.IsDebugMode() then
            print("|cff00ff00[GuildWorkOrders Debug]|r No orders to share - skipping broadcast")
        end
        return -- No orders to broadcast
    end
    
    local currentTime = GetCurrentTime()
    local ordersToSend = {}
    
    for _, order in ipairs(myOrders) do
        -- Include active, pending orders and recently completed (30 minute window)
        if order.status == Database.STATUS.ACTIVE or 
           order.status == Database.STATUS.PENDING or
           (order.status == Database.STATUS.FULFILLED and 
            order.fulfilledAt and currentTime - order.fulfilledAt < 60) or
           (order.status == Database.STATUS.CANCELLED and 
            order.completedAt and currentTime - order.completedAt < 60) or
           (order.status == Database.STATUS.CLEARED and 
            order.clearedAt and currentTime - order.clearedAt < 60) then
            
            table.insert(ordersToSend, order)
        end
    end
    
    if #ordersToSend == 0 then
        if Config.IsDebugMode() then
            print("|cff00ff00[GuildWorkOrders Debug]|r No current orders need sharing")
        end
        return -- No relevant orders to broadcast
    end
    
    -- Sort orders by priority: ACTIVE first, then PENDING, then completed
    table.sort(ordersToSend, function(a, b)
        -- Active orders have highest priority
        if a.status == Database.STATUS.ACTIVE and b.status ~= Database.STATUS.ACTIVE then
            return true
        elseif b.status == Database.STATUS.ACTIVE and a.status ~= Database.STATUS.ACTIVE then
            return false
        end
        -- For same status, newest first
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)
    
    -- ROTATING HEARTBEAT: Send only 1 order per heartbeat
    local heartbeatIndex = GuildWorkOrdersDB.syncData.heartbeatIndex or 1
    
    -- Ensure index is within bounds
    if heartbeatIndex > #ordersToSend then
        heartbeatIndex = 1
        GuildWorkOrdersDB.syncData.heartbeatIndex = 1
    end
    
    local orderToSend = ordersToSend[heartbeatIndex]
    if Config.IsDebugMode() then
        local statusDesc = orderToSend.status == Database.STATUS.ACTIVE and "active" or 
                          orderToSend.status == Database.STATUS.PENDING and "pending" or "completed"
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Sharing order %d of %d: %s (%s)", 
            heartbeatIndex, #ordersToSend, orderToSend.itemName or "Unknown Item", statusDesc))
    end
    
    -- Move to next order for next heartbeat
    GuildWorkOrdersDB.syncData.heartbeatIndex = (heartbeatIndex % #ordersToSend) + 1
    
    -- Create single-order list for existing broadcast code
    local singleOrder = { orderToSend }
    
    -- Send the single order as a heartbeat
    local order = orderToSend
    local timeAgo, ttl = GetRelativeTimestamps(order)
    local encodedStatus = EncodeStatus(order.status)
    
    local orderStr = string.format("%s:%s:%s:%s:%d:%s:%d:%d:%d:%s:%s:%d:%s:%s",
        order.id,
        order.type,
        order.player,
        EscapeDelimiters(TruncateItemLink(order.itemLink) or ""),
        order.quantity or 0,
        EscapeDelimiters(order.price or ""),
        timeAgo,
        ttl,
        order.version or 1,
        encodedStatus,
        EscapeDelimiters(order.pendingFulfiller or ""),
        order.pendingTimestamp or 0,
        EscapeDelimiters(order.fulfilledBy or ""),
        EscapeDelimiters(order.clearedBy or "")
    )
    
    local heartbeatMessage = string.format("%s|%d|%d|%d|%s",
        MSG_TYPE.HEARTBEAT,
        PROTOCOL_VERSION,
        1, -- Single batch
        1, -- Total batches
        orderStr
    )
    
    local isValid, errorMsg = ValidateMessageSize(heartbeatMessage)
    if isValid then
        local success = Sync.QueueMessage(heartbeatMessage)
        if Config.IsDebugMode() and success then
            print("|cff00ff00[GuildWorkOrders Debug]|r Order broadcast successful")
        elseif Config.IsDebugMode() and not success then
            print("|cffFF6B6B[GuildWorkOrders Debug]|r Failed to broadcast order")
        end
    else
        if Config.IsDebugMode() then
            print(string.format("|cffFFAA00[GuildWorkOrders Debug]|r Order details too long, shortening message: %s", errorMsg))
        end
    end
    
    -- Periodic cleanup removed - using FIFO-only system
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
            if #orderParts >= 14 then
                -- Parse compressed heartbeat format with clearedBy field
                local timeAgo = tonumber(orderParts[7]) or 0
                local ttl = tonumber(orderParts[8]) or 60
                local encodedStatus = orderParts[10]
                local fulfilledBy = UnescapeDelimiters(orderParts[13])
                local clearedBy = UnescapeDelimiters(orderParts[14])
                
                -- Restore absolute timestamps
                local currentTime = GetCurrentTime()
                local timestamp, expiresAt = RestoreAbsoluteTimestamps(timeAgo, ttl, currentTime)
                
                local orderData = {
                    id = orderParts[1],
                    type = orderParts[2],
                    player = orderParts[3],
                    itemLink = UnescapeDelimiters(orderParts[4]),
                    quantity = tonumber(orderParts[5]),
                    price = UnescapeDelimiters(orderParts[6]),
                    timestamp = timestamp,
                    expiresAt = expiresAt,
                    version = tonumber(orderParts[9]) or 1,
                    status = DecodeStatus(encodedStatus),
                    pendingFulfiller = UnescapeDelimiters(orderParts[11]),
                    pendingTimestamp = tonumber(orderParts[12]) or 0,
                    fulfilledBy = fulfilledBy ~= "" and fulfilledBy or nil,
                    clearedBy = clearedBy ~= "" and clearedBy or nil
                }
                
                -- Accept heartbeat from creator OR anyone if order has completion fields (relay mode)
                -- Handle both with and without realm suffix in sender name
                local baseSenderName = strsplit("-", sender)
                local isCreator = (orderData.player == sender or orderData.player == baseSenderName)
                local hasFulfilledBy = (orderData.fulfilledBy and orderData.fulfilledBy ~= "")
                local hasClearedBy = (orderData.clearedBy and orderData.clearedBy ~= "")
                local isCancelled = (orderData.status == Database.STATUS.CANCELLED)
                
                if isCreator or hasFulfilledBy or hasClearedBy or isCancelled then
                    Sync.ProcessHeartbeatOrder(orderData, sender)
                elseif Config.IsDebugMode() then
                    print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Rejected heartbeat: sender (%s) not creator (%s) and no completion fields", 
                        sender, orderData.player))
                end
            elseif #orderParts >= 13 then
                -- Parse legacy format without clearedBy field
                local timeAgo = tonumber(orderParts[7]) or 0
                local ttl = tonumber(orderParts[8]) or 60
                local encodedStatus = orderParts[10]
                local fulfilledBy = UnescapeDelimiters(orderParts[13])
                
                -- Restore absolute timestamps
                local currentTime = GetCurrentTime()
                local timestamp, expiresAt = RestoreAbsoluteTimestamps(timeAgo, ttl, currentTime)
                
                local orderData = {
                    id = orderParts[1],
                    type = orderParts[2],
                    player = orderParts[3],
                    itemLink = UnescapeDelimiters(orderParts[4]),
                    quantity = tonumber(orderParts[5]),
                    price = UnescapeDelimiters(orderParts[6]),
                    timestamp = timestamp,
                    expiresAt = expiresAt,
                    version = tonumber(orderParts[9]) or 1,
                    status = DecodeStatus(encodedStatus),
                    pendingFulfiller = UnescapeDelimiters(orderParts[11]),
                    pendingTimestamp = tonumber(orderParts[12]) or 0,
                    fulfilledBy = fulfilledBy ~= "" and fulfilledBy or nil
                }
                
                -- Accept heartbeat from creator OR anyone if order has completion fields (relay mode)
                -- Handle both with and without realm suffix in sender name
                local baseSenderName = strsplit("-", sender)
                local isCreator = (orderData.player == sender or orderData.player == baseSenderName)
                local hasFulfilledBy = (orderData.fulfilledBy and orderData.fulfilledBy ~= "")
                local hasClearedBy = (orderData.clearedBy and orderData.clearedBy ~= "")
                local isCancelled = (orderData.status == Database.STATUS.CANCELLED)
                
                if isCreator or hasFulfilledBy or hasClearedBy or isCancelled then
                    Sync.ProcessHeartbeatOrder(orderData, sender)
                elseif Config.IsDebugMode() then
                    print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Rejected heartbeat: sender (%s) not creator (%s) and no completion fields", 
                        sender, orderData.player))
                end
            elseif #orderParts >= 12 then
                -- Handle legacy format for backward compatibility
                local orderData = {
                    id = orderParts[1],
                    type = orderParts[2],
                    player = orderParts[3],
                    itemLink = UnescapeDelimiters(orderParts[4]),
                    quantity = tonumber(orderParts[5]),
                    price = UnescapeDelimiters(orderParts[6]),
                    timestamp = tonumber(orderParts[7]) or GetCurrentTime(),
                    expiresAt = tonumber(orderParts[8]) or (GetCurrentTime() + 60),
                    version = tonumber(orderParts[9]) or 1,
                    status = orderParts[10],
                    pendingFulfiller = UnescapeDelimiters(orderParts[11]),
                    pendingTimestamp = tonumber(orderParts[12]) or 0
                }
                
                -- Accept heartbeat from creator OR for cancelled orders (legacy format)
                -- Handle both with and without realm suffix in sender name
                local baseSenderName = strsplit("-", sender)
                local isCreator = (orderData.player == sender or orderData.player == baseSenderName)
                local isCancelled = (orderData.status == Database.STATUS.CANCELLED)
                -- Note: Legacy format doesn't have fulfilledBy/clearedBy fields
                
                if isCreator or isCancelled then
                    Sync.ProcessHeartbeatOrder(orderData, sender)
                elseif Config.IsDebugMode() then
                    print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Rejected legacy heartbeat: sender (%s) not creator (%s) and not cancelled", 
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
    
    -- Additional protection: Don't allow fulfilled orders to be overwritten by active ones
    local existingOrder = GuildWorkOrdersDB.orders and GuildWorkOrdersDB.orders[orderData.id]
    if existingOrder and existingOrder.fulfilledBy and not orderData.fulfilledBy then
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Rejecting heartbeat: trying to overwrite fulfilled order %s with active status", 
                orderData.id))
        end
        return
    end
    
    -- Sync all orders (SyncOrder handles version checking and routing to appropriate storage)
    local success = Database.SyncOrder(orderData)
    if success then
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Synced order from heartbeat: %s (%s)", 
                orderData.id, orderData.status))
        end
    end
end

-- Start periodic heartbeat timer
local heartbeatTimer = nil
function Sync.StartHeartbeat()
    if heartbeatTimer then
        heartbeatTimer:Cancel()
    end
    
    -- Send heartbeat every 3 seconds (rotating through orders)
    heartbeatTimer = C_Timer.NewTicker(3, function()
        if Config.IsDebugMode() then
            print("|cff00ff00[GuildWorkOrders Debug]|r Broadcasting next order in rotation...")
        end
        Sync.SendHeartbeat()
    end)
    
    -- Send initial heartbeat after 5 seconds
    C_Timer.After(5, function()
        if Config.IsDebugMode() then
            print("|cff00ff00[GuildWorkOrders Debug]|r Starting order sharing with guild...")
        end
        Sync.SendHeartbeat()
    end)
    
    if Config.IsDebugMode() then
        print("|cff00ff00[GuildWorkOrders Debug]|r Order sharing enabled - broadcasting every 3 seconds")
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