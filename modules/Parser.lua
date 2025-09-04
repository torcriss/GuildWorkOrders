-- Parser.lua - Parse WTB/WTS messages for GuildWorkOrders
local addonName, addon = ...
addon.Parser = addon.Parser or {}
local Parser = addon.Parser

-- Local references
local Config = nil  -- Will be set in Initialize
local Database = nil

function Parser.Initialize()
    Config = addon.Config
    Database = addon.Database
end

-- Check if message is a WTB (Want To Buy) request
function Parser.IsWTBMessage(message)
    if not message then return false end
    
    -- First check if message contains item links - WTB without items doesn't make sense
    local itemLinks = Parser.ExtractItemLinks(message)
    if #itemLinks == 0 then
        return false
    end
    
    -- Convert to lowercase for case-insensitive matching
    local lowerMessage = string.lower(message)
    
    -- Check for WTB patterns
    local wtbPatterns = {
        "^wtb ",           -- "WTB [item]"
        " wtb ",           -- "... WTB [item]"
        "^w t b ",         -- "W T B [item]"
        " w t b ",         -- "... W T B [item]"
        "^lf ",            -- "LF [item]"
        " lf ",            -- "... LF [item]"
        "looking for ",    -- "looking for [item]"
        "^need ",          -- "need [item]" at start only
        " need an? ",      -- "need a/an [item]"
        "i need ",         -- "i need [item]"
        "^buying ",        -- "buying [item]"
        " i.*buying ",     -- "... I am buying [item]"
        "am buying ",      -- "I am buying [item]"
        "want to buy",     -- "want to buy [item]"
        "^iso ",           -- "ISO [item]" (In Search Of)
        " iso ",           -- "... ISO [item]"
        "anyone have",     -- "anyone have [item]"
        "anyone got",      -- "anyone got [item]"
        "does anyone have", -- "does anyone have [item]"
        "^send ",          -- "send [item]"
        "^mail ",          -- "mail [item]"
        "send your ",      -- "Send your [item]"
        "mail your ",      -- "Mail your [item]"
        " to me",          -- "[item] to me"
        " cod ",           -- "... COD [item]"
        "^cod ",           -- "COD [item]"
        " c%.o%.d ",       -- "... C.O.D [item]"
        "^c%.o%.d "        -- "C.O.D [item]"
    }
    
    for _, pattern in ipairs(wtbPatterns) do
        if string.find(lowerMessage, pattern) then
            -- Check for offering patterns that should NOT be considered WTB requests
            local offeringPatterns = {
                "anyone need",     -- "anyone need [item]" - offering items
                "anyone want",     -- "anyone want [item]" - offering items
                "who needs",       -- "who needs [item]" - offering items
                "who wants",       -- "who wants [item]" - offering items
                "does anyone need", -- "does anyone need [item]" - offering items
            }
            
            for _, offerPattern in ipairs(offeringPatterns) do
                if string.find(lowerMessage, offerPattern) then
                    return false  -- This is an offering message, not WTB
                end
            end
            
            return true
        end
    end
    
    return false
end

-- Check if message is a WTS (Want To Sell) request
function Parser.IsWTSMessage(message)
    if not message then return false end
    
    -- First check if message contains item links
    local itemLinks = Parser.ExtractItemLinks(message)
    if #itemLinks == 0 then
        return false
    end
    
    local lowerMessage = string.lower(message)
    
    -- Check for WTS patterns
    local wtsPatterns = {
        "^wts ",           -- "WTS [item]"
        " wts ",           -- "... WTS [item]"
        "^w t s ",         -- "W T S [item]"
        " w t s ",         -- "... W T S [item]"
        "^selling ",       -- "selling [item]"
        " selling ",       -- "... selling [item]"
        "^sell ",          -- "sell [item]"
        " sell ",          -- "... sell [item]"
        "for sale",        -- "[item] for sale"
        "want to sell",    -- "want to sell [item]"
        "^have ",          -- "have [item]" (at start)
        " have .* for ",   -- "have [item] for [price]"
        "anyone need",     -- "anyone need [item]" - offering
        "anyone want",     -- "anyone want [item]" - offering
        "who needs",       -- "who needs [item]" - offering
        "who wants",       -- "who wants [item]" - offering
        "does anyone need", -- "does anyone need [item]" - offering
    }
    
    for _, pattern in ipairs(wtsPatterns) do
        if string.find(lowerMessage, pattern) then
            return true
        end
    end
    
    return false
end

-- Extract item links from message
function Parser.ExtractItemLinks(message)
    local items = {}
    
    -- Extract full item links first
    for itemLink in string.gmatch(message, "|c%x+|H.-|h%[.-%]|h|r") do
        table.insert(items, itemLink)
    end
    
    -- If no item links found, try to extract item names in brackets
    if #items == 0 then
        for itemName in string.gmatch(message, "%[(.-)%]") do
            -- Create a simple item link format for display
            table.insert(items, "[" .. itemName .. "]")
        end
    end
    
    return items
end

-- Parse quantity from message
function Parser.ParseQuantity(message, itemName)
    if not message or not itemName then return nil end
    
    -- Remove the item link/name to avoid false matches
    local msgWithoutItem = string.gsub(message, "%[" .. itemName .. "%]", "")
    msgWithoutItem = string.gsub(msgWithoutItem, "|c%x+|H.-|h%[" .. itemName .. "%]|h|r", "")
    
    -- Quantity patterns (in order of specificity)
    local patterns = {
        "(%d+)x",           -- "20x"
        "x(%d+)",           -- "x20"  
        "(%d+) x",          -- "20 x"
        "x (%d+)",          -- "x 20"
        "(%d+) stacks?",    -- "20 stack" or "20 stacks"
        "(%d+) of",         -- "20 of [item]"
        "need (%d+)",       -- "need 20"
        "want (%d+)",       -- "want 20"
        "buying (%d+)",     -- "buying 20"
        "selling (%d+)",    -- "selling 20"
        "have (%d+)",       -- "have 20"
        "(%d+)$",           -- Number at end of message
        "^(%d+)",           -- Number at start of message
        " (%d+) "           -- Number surrounded by spaces
    }
    
    for _, pattern in ipairs(patterns) do
        local quantity = string.match(msgWithoutItem, pattern)
        if quantity then
            local num = tonumber(quantity)
            -- Reasonable quantity range (1-10000)
            if num and num >= 1 and num <= 10000 then
                return num
            end
        end
    end
    
    return nil
end

-- Parse price from message
function Parser.ParsePrice(message)
    if not message then return nil end
    
    -- Convert to lowercase for easier matching
    local lowerMsg = string.lower(message)
    
    -- Price patterns (in order of specificity)
    local patterns = {
        -- Gold and silver combinations
        "(%d+)g(%d+)s",                    -- "100g50s"
        "(%d+)g (%d+)s",                   -- "100g 50s"  
        "(%d+) gold (%d+) silver",        -- "100 gold 50 silver"
        "(%d+) gold (%d+) sil",           -- "100 gold 50 sil"
        
        -- Gold only
        "(%d+)g",                          -- "100g"
        "(%d+) gold",                      -- "100 gold"
        "(%d+) g ",                        -- "100 g "
        
        -- Silver only
        "(%d+)s",                          -- "50s"
        "(%d+) silver",                    -- "50 silver"
        "(%d+) sil",                       -- "50 sil"
        "(%d+) s ",                        -- "50 s "
        
        -- Copper only
        "(%d+)c",                          -- "50c"
        "(%d+) copper",                    -- "50 copper"
        "(%d+) cop",                       -- "50 cop"
    }
    
    -- Try gold+silver patterns first
    for i = 1, 4 do
        local gold, silver = string.match(lowerMsg, patterns[i])
        if gold and silver then
            return gold .. "g" .. silver .. "s"
        end
    end
    
    -- Try single currency patterns
    for i = 5, #patterns do
        local amount = string.match(lowerMsg, patterns[i])
        if amount then
            local num = tonumber(amount)
            if num and num >= 1 and num <= 999999 then -- Reasonable price range
                if i <= 7 then
                    return amount .. "g"  -- Gold patterns
                elseif i <= 11 then
                    return amount .. "s"  -- Silver patterns
                else
                    return amount .. "c"  -- Copper patterns
                end
            end
        end
    end
    
    return nil
end

-- Parse a complete WTB/WTS message
function Parser.ParseWorkOrderMessage(message, playerName, messageType)
    if not message or not playerName then return nil end
    
    -- Determine order type if not provided
    if not messageType then
        if Parser.IsWTBMessage(message) then
            messageType = Database.TYPE.WTB
        elseif Parser.IsWTSMessage(message) then
            messageType = Database.TYPE.WTS
        else
            return nil  -- Not a work order message
        end
    end
    
    -- Extract item links
    local itemLinks = Parser.ExtractItemLinks(message)
    if #itemLinks == 0 then
        return nil
    end
    
    local orders = {}
    
    -- Process each item found
    for _, itemLink in ipairs(itemLinks) do
        local itemName = string.match(itemLink, "%[(.-)%]") or itemLink
        local quantity = Parser.ParseQuantity(message, itemName)
        local price = Parser.ParsePrice(message)
        
        local orderData = {
            type = messageType,
            player = playerName,
            itemLink = itemLink,
            itemName = itemName,
            quantity = quantity,
            price = price,
            rawMessage = message
        }
        
        table.insert(orders, orderData)
    end
    
    return orders
end

-- Parse guild chat message for work orders
-- DISABLED: Guild chat parsing removed - orders now only created via addon UI/commands
--[[
function Parser.ProcessGuildMessage(message, sender)
    if not message or not sender then return end
    
    -- Don't process our own messages
    local playerName = UnitName("player")
    if sender == playerName then return end
    
    if Config.IsDebugMode() then
        print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Checking guild chat from %s: %s",
            sender, message))
    end
    
    -- Parse the message
    local orders = Parser.ParseWorkOrderMessage(message, sender)
    if not orders or #orders == 0 then
        return
    end
    
    -- Create orders in database (these come from other players via guild chat)
    for _, orderData in ipairs(orders) do
        -- Create order directly in database with sender as player
        local order = {
            id = Database.GenerateOrderID(sender),
            type = orderData.type,
            player = sender,
            realm = GetRealmName(),
            itemLink = orderData.itemLink,
            itemName = orderData.itemName,
            quantity = orderData.quantity,
            price = orderData.price,
            priceInCopper = Database.ParsePriceToCopper(orderData.price),
            message = orderData.rawMessage,
            timestamp = time(),
            expiresAt = time() + (Config.Get("orderExpiry") or 1800),
            status = Database.STATUS.ACTIVE,
            version = 1
        }
        
        -- Add to database
        if not GuildWorkOrdersDB.orders then
            GuildWorkOrdersDB.orders = {}
        end
        GuildWorkOrdersDB.orders[order.id] = order
        
        if Config.IsDebugMode() then
            print(string.format("|cff00ff00[GuildWorkOrders Debug]|r Found %s order in guild chat: %s for %s",
                orderData.type == "WTB" and "buy" or "sell", orderData.itemName, orderData.price or "negotiation"))
        end
        
        -- Trigger UI update if available
        if addon.UI and addon.UI.RefreshOrders then
            addon.UI.RefreshOrders()
        end
        
        -- Play sound if enabled
        if Config.Get("soundAlert") then
            PlaySound(SOUNDKIT.AUCTION_WINDOW_OPEN)
        end
    end
end
--]]

-- Validate order data before creation
function Parser.ValidateOrderData(orderType, itemLink, quantity, price)
    local errors = {}
    
    -- Check order type
    if orderType ~= Database.TYPE.WTB and orderType ~= Database.TYPE.WTS then
        table.insert(errors, "Invalid order type")
    end
    
    -- Check item
    if not itemLink or itemLink == "" then
        table.insert(errors, "Item is required")
    end
    
    -- Check quantity
    if quantity and (quantity < 1 or quantity > 10000) then
        table.insert(errors, "Quantity must be between 1 and 10000")
    end
    
    -- Price is optional but should be reasonable if provided
    if price then
        local copper = Database.ParsePriceToCopper(price)
        if copper < 0 or copper > 99999999 then  -- 9999g99s99c max
            table.insert(errors, "Price is not valid")
        end
    end
    
    return #errors == 0, errors
end