-- UI.lua - User interface for GuildWorkOrders
local addonName, addon = ...
addon.UI = addon.UI or {}
local UI = addon.UI

-- Local references
local Config = nil
local Database = nil
local Sync = nil
local Parser = nil

-- Use server time for all timestamps to avoid clock sync issues
local function GetCurrentTime()
    return GetServerTime()
end

-- UI State
local mainFrame = nil
local currentTab = "buy"
local orderRows = {}
local searchText = ""

-- Tab definitions
local TABS = {
    {id = "buy", text = "Buy Orders", tooltip = "View items players want to buy"},
    {id = "sell", text = "Sell Orders", tooltip = "View items players want to sell"},
    {id = "my", text = "My Orders", tooltip = "Manage your own orders"},
    {id = "history", text = "History", tooltip = "View completed orders"}
}

function UI.Initialize()
    Config = addon.Config
    Database = addon.Database
    Sync = addon.Sync
    Parser = addon.Parser
    
    currentTab = Config.GetCurrentTab()
    UI.CreateMainFrame()
    UI.CreateNewOrderDialog()
end

-- Create main UI frame
function UI.CreateMainFrame()
    -- Main frame
    local frame = CreateFrame("Frame", "GuildWorkOrdersFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame = frame
    
    local width, height = Config.GetWindowSize()
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    -- Note: SetMinResize/SetMaxResize not available in WoW Classic Era
    -- Users can resize manually, bounds will be enforced via SetSize limits
    
    -- Title
    frame.TitleText:SetText("Guild Work Orders")
    
    -- Make ESC key close the window
    table.insert(UISpecialFrames, "GuildWorkOrdersFrame")
    
    -- Event handlers
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() 
        frame:StopMovingOrSizing()
        UI.SaveWindowPosition()
    end)
    
    frame:SetScript("OnSizeChanged", function(self, width, height)
        Config.SetWindowSize(width, height)
        UI.RefreshOrders()
    end)
    
    frame:SetScript("OnShow", function()
        UI.RefreshOrders()
        UI.UpdateStatusBar()
    end)
    
    frame:SetScript("OnHide", function()
        UI.SaveWindowPosition()
    end)
    
    -- Resize grip
    local resizeButton = CreateFrame("Button", nil, frame)
    resizeButton:SetPoint("BOTTOMRIGHT", -6, 7)
    resizeButton:SetSize(16, 16)
    resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    
    resizeButton:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    
    resizeButton:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        UI.SaveWindowPosition()
    end)
    
    -- Create UI components
    UI.CreateTabButtons()
    UI.CreateSearchBar()
    UI.CreateOrderList()
    UI.CreateStatusBar()
    
    frame:Hide()
end

-- Create tab buttons
function UI.CreateTabButtons()
    local previousTab = nil
    
    for i, tabInfo in ipairs(TABS) do
        local tab = CreateFrame("Button", nil, mainFrame)
        tab:SetSize(120, 25)
        
        if previousTab then
            tab:SetPoint("LEFT", previousTab, "RIGHT", 2, 0)
        else
            tab:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 15, -30)
        end
        
        -- Normal texture
        tab:SetNormalTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab")
        tab:GetNormalTexture():SetTexCoord(0.01, 0.15, 0.01, 0.7)
        
        -- Highlight texture
        tab:SetHighlightTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab")
        tab:GetHighlightTexture():SetTexCoord(0.02, 0.15, 0.02, 0.7)
        tab:GetHighlightTexture():SetAlpha(0.4)
        
        -- Text
        local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER", 0, 2)
        text:SetText(tabInfo.text)
        tab.text = text
        tab.tabId = tabInfo.id
        
        -- Click handler
        tab:SetScript("OnClick", function()
            UI.SelectTab(tabInfo.id)
        end)
        
        -- Tooltip
        tab:SetScript("OnEnter", function()
            GameTooltip:SetOwner(tab, "ANCHOR_BOTTOM")
            GameTooltip:SetText(tabInfo.tooltip)
            GameTooltip:Show()
        end)
        tab:SetScript("OnLeave", GameTooltip_Hide)
        
        previousTab = tab
    end
    
    -- Update tab appearance
    UI.UpdateTabAppearance()
end

-- Update tab visual state
function UI.UpdateTabAppearance()
    for i, child in ipairs({mainFrame:GetChildren()}) do
        if child.tabId then
            if child.tabId == currentTab then
                child:GetNormalTexture():SetVertexColor(1, 1, 1)
                child.text:SetTextColor(1, 1, 1)
            else
                child:GetNormalTexture():SetVertexColor(0.6, 0.6, 0.6)
                child.text:SetTextColor(0.8, 0.8, 0.8)
            end
        end
    end
end

-- Select tab
function UI.SelectTab(tabId)
    if currentTab ~= tabId then
        currentTab = tabId
        Config.SetCurrentTab(tabId)
        UI.UpdateTabAppearance()
        UI.CreateColumnHeaders()  -- Recreate headers for new tab
        UI.RefreshOrders()
    end
end

-- Create search bar
function UI.CreateSearchBar()
    -- Search container
    local searchBar = CreateFrame("Frame", nil, mainFrame)
    searchBar:SetPoint("TOPLEFT", 15, -60)
    searchBar:SetPoint("TOPRIGHT", -15, -60)
    searchBar:SetHeight(25)
    
    -- Search label
    local searchLabel = searchBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("LEFT", 5, 0)
    searchLabel:SetText("Search:")
    
    -- Search box
    local searchBox = CreateFrame("EditBox", nil, searchBar, "InputBoxTemplate")
    searchBox:SetSize(200, 25)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText()
        UI.RefreshOrders()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        UI.RefreshOrders()
    end)
    
    -- Clear button
    local clearBtn = CreateFrame("Button", nil, searchBox)
    clearBtn:SetSize(16, 16)
    clearBtn:SetPoint("RIGHT", -2, 0)
    clearBtn:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    clearBtn:SetAlpha(0.5)
    clearBtn:SetScript("OnClick", function()
        searchBox:SetText("")
        searchText = ""
        UI.RefreshOrders()
    end)
    clearBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Clear search")
        GameTooltip:Show()
    end)
    clearBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(0.5)
        GameTooltip:Hide()
    end)
    
    -- New order button
    local newOrderBtn = CreateFrame("Button", nil, searchBar, "UIPanelButtonTemplate")
    newOrderBtn:SetSize(100, 25)
    newOrderBtn:SetPoint("RIGHT", -5, 0)
    newOrderBtn:SetText("New Order")
    newOrderBtn:SetScript("OnClick", function()
        UI.ShowNewOrderDialog()
    end)
    
    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, searchBar, "UIPanelButtonTemplate")
    refreshBtn:SetSize(70, 25)
    refreshBtn:SetPoint("RIGHT", newOrderBtn, "LEFT", -5, 0)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        UI.RefreshOrders()
        Sync.SendPing()  -- Refresh online users
    end)
    
    UI.searchBox = searchBox
end

-- Create scrollable order list
function UI.CreateOrderList()
    -- Create scrollable list
    local scrollFrame = CreateFrame("ScrollFrame", nil, mainFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -110)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(content)
    content:SetSize(scrollFrame:GetWidth(), 1)
    
    UI.scrollFrame = scrollFrame
    UI.listContent = content
    
    -- Column headers
    UI.CreateColumnHeaders()
end

-- Clear existing column headers
function UI.ClearColumnHeaders()
    if not mainFrame then return end
    
    -- Store reference to headers for proper cleanup
    if not UI.columnHeaders then
        UI.columnHeaders = {}
    end
    
    -- Remove existing headers
    for _, header in ipairs(UI.columnHeaders) do
        if header then
            header:Hide()
            header:SetParent(nil)
        end
    end
    
    -- Clear the table
    UI.columnHeaders = {}
end

-- Create column headers
function UI.CreateColumnHeaders()
    -- Clear existing headers first
    UI.ClearColumnHeaders()
    local headers
    
    if currentTab == "history" then
        headers = {
            {text = "Type", width = 50, x = 10},
            {text = "Item", width = 160, x = 70},
            {text = "Qty", width = 40, x = 245},
            {text = "Price", width = 60, x = 300},
            {text = "Buyer", width = 70, x = 375},
            {text = "Seller", width = 70, x = 460},
            {text = "Time", width = 50, x = 545},
            {text = "Status", width = 70, x = 610},
            {text = "Completed (Server)", width = 90, x = 695}
        }
    else
        headers = {
            {text = "Type", width = 50, x = 10},
            {text = "Item", width = 160, x = 70},
            {text = "Qty", width = 40, x = 245},
            {text = "Price", width = 60, x = 300},
            {text = "Buyer", width = 70, x = 375},
            {text = "Seller", width = 70, x = 460},
            {text = "Time", width = 50, x = 545},
            {text = "Action", width = 60, x = 610}
        }
    end
    
    for _, header in ipairs(headers) do
        local label = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", header.x, -90)
        label:SetText("|cffFFD700" .. header.text .. "|r")
        label.isHeaderLabel = true  -- Mark for cleanup
        
        -- Store reference for proper cleanup
        table.insert(UI.columnHeaders, label)
    end
end

-- Create order row
function UI.CreateOrderRow(order, index)
    if not UI.listContent then return nil end
    local row = CreateFrame("Button", nil, UI.listContent)
    row:SetSize(UI.listContent:GetWidth() - 20, 30)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * 40)
    
    -- Background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if index % 2 == 0 then
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
    else
        bg:SetColorTexture(0.15, 0.15, 0.15, 0.3)
    end
    
    -- Highlight on hover
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.3, 0.3, 0.3, 0.3)
    
    -- Type column (WTB/WTS)
    local typeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    typeText:SetPoint("LEFT", 10, 0)
    typeText:SetWidth(50)
    typeText:SetJustifyH("LEFT")
    if order.type == Database.TYPE.WTB then
        typeText:SetText("|cffff8080WTB|r")  -- Light red for Want To Buy
    elseif order.type == Database.TYPE.WTS then
        typeText:SetText("|cff80ff80WTS|r")  -- Light green for Want To Sell
    else
        typeText:SetText("|cffFFD700?|r")    -- Gold for unknown type
    end
    
    -- Item link/name
    local item = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    item:SetPoint("LEFT", 70, 0)
    item:SetWidth(160)
    item:SetJustifyH("LEFT")
    
    -- Extract and display item name with defensive fallbacks
    local displayName = order.itemName
    
    -- If no itemName or it looks like raw data, try to extract it
    if not displayName or string.find(displayName, "Hitem:") then
        if order.itemLink then
            if string.find(order.itemLink, "|H") then
                -- Proper item link - extract name from brackets
                displayName = string.match(order.itemLink, "%[(.-)%]")
            end
            
            -- If still no name, try to extract from item ID
            if not displayName then
                local itemId = string.match(order.itemLink, "Hitem:(%d+)")
                if itemId then
                    displayName = "Item " .. itemId
                end
            end
        end
        
        -- Final fallback
        if not displayName then
            displayName = "Unknown Item"
        end
    end
    
    item:SetText(displayName)
    
    -- Make item link clickable if it's a real item link
    if order.itemLink and string.find(order.itemLink, "|H") then
        row:SetScript("OnEnter", function()
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(order.itemLink)
            GameTooltip:AddLine("Click to link in chat", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnClick", function()
            if ChatFrame1EditBox:IsVisible() then
                ChatFrame1EditBox:Insert(order.itemLink)
            end
        end)
    end
    
    -- Quantity
    local qty = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    qty:SetPoint("LEFT", 245, 0)
    local qtyText = order.quantity
    if not qtyText or qtyText == "" or qtyText == 0 then
        qty:SetText("?")
    else
        qty:SetText(tostring(qtyText))
    end
    
    -- Price with color coding
    local price = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    price:SetPoint("LEFT", 300, 0)
    local priceText = order.price
    if not priceText or priceText == "" then
        price:SetText("?")
    elseif string.find(priceText, "g") then
        price:SetText("|cffFFD700" .. priceText .. "|r")
    elseif string.find(priceText, "s") then
        price:SetText("|cffC0C0C0" .. priceText .. "|r")
    else
        price:SetText("|cffB87333" .. priceText .. "|r")
    end
    
    -- Buyer column (who wants to buy)
    local buyer = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buyer:SetPoint("LEFT", 375, 0)
    buyer:SetWidth(70)
    buyer:SetJustifyH("LEFT")
    
    -- Seller column (who wants to sell)
    local seller = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    seller:SetPoint("LEFT", 460, 0)
    seller:SetWidth(70)
    seller:SetJustifyH("LEFT")
    
    -- Set buyer/seller based on order type and fulfillment status
    local playerName = order.player or "Unknown"
    if string.len(playerName) > 10 then
        playerName = string.sub(playerName, 1, 8) .. "..."
    end
    
    local fulfilledByName = order.fulfilledBy or ""
    if string.len(fulfilledByName) > 10 then
        fulfilledByName = string.sub(fulfilledByName, 1, 8) .. "..."
    end
    
    if order.type == Database.TYPE.WTB then
        -- WTB order: original player is the buyer, fulfilledBy is the seller
        buyer:SetText("|cff00ff00" .. playerName .. "|r")
        if order.fulfilledBy and order.fulfilledBy ~= "" then
            seller:SetText("|cff00ff00" .. fulfilledByName .. "|r")
        else
            seller:SetText("|cff888888-|r")
        end
    else
        -- WTS order: original player is the seller, fulfilledBy is the buyer
        seller:SetText("|cff00ff00" .. playerName .. "|r")
        if order.fulfilledBy and order.fulfilledBy ~= "" then
            buyer:SetText("|cff00ff00" .. fulfilledByName .. "|r")
        else
            buyer:SetText("|cff888888-|r")
        end
    end
    
    -- Time ago / TTL countdown
    local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetPoint("LEFT", 545, 0)
    timeText:SetWidth(60)
    timeText:SetJustifyH("CENTER")
    
    -- Show TTL countdown for active orders, "-" for completed orders
    if order.status == Database.STATUS.ACTIVE and order.expiresAt then
        local timeLeft = order.expiresAt - GetCurrentTime()
        if timeLeft > 0 then
            local ttlText, color = UI.GetTTLDisplay(timeLeft)
            timeText:SetText(color .. ttlText .. "|r")
        else
            timeText:SetText("|cffff0000Expired|r")
        end
    elseif order.status == Database.STATUS.FULFILLED or order.status == Database.STATUS.CANCELLED or order.status == Database.STATUS.EXPIRED then
        -- Show "-" for completed orders to avoid timestamp fluctuations
        timeText:SetText("|cff888888-|r")
    else
        -- Show time ago for other statuses (like PENDING)
        timeText:SetText("|cff888888" .. UI.GetTimeAgo(order.timestamp) .. "|r")
    end
    
    -- Handle history tab differently
    if currentTab == "history" then
        -- Status column for history
        local statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        statusText:SetPoint("LEFT", 610, 0)
        statusText:SetWidth(70)
        statusText:SetJustifyH("LEFT")
        if order.status == Database.STATUS.FULFILLED then
            statusText:SetText("|cff00ff00Completed|r")
        elseif order.status == Database.STATUS.CANCELLED then
            statusText:SetText("|cffff0000Cancelled|r")
        else
            statusText:SetText("|cffFFD700" .. (order.status or "Unknown") .. "|r")
        end
        
        -- Completion timestamp column for history
        local completedText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        completedText:SetPoint("LEFT", 695, 0)
        completedText:SetWidth(90)  -- Increased width for date/time format
        completedText:SetJustifyH("LEFT")
        if order.completedAt then
            completedText:SetText("|cff888888" .. UI.FormatDateTime(order.completedAt) .. "|r")
        else
            completedText:SetText("|cff888888-|r")
        end
    else
        local playerName = UnitName("player")
        
        -- Handle My Orders tab differently - show status for completed orders
        if currentTab == "my" and (order.status == Database.STATUS.FULFILLED or order.status == Database.STATUS.CANCELLED) then
            -- Show status instead of action button for completed orders
            local statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            statusText:SetPoint("LEFT", 610, 0)
            statusText:SetWidth(70)
            statusText:SetJustifyH("LEFT")
            if order.status == Database.STATUS.FULFILLED then
                statusText:SetText("|cff00ff00Completed|r")
            elseif order.status == Database.STATUS.CANCELLED then
                statusText:SetText("|cffff8080Cancelled|r")
            else
                statusText:SetText("|cffFFD700" .. (order.status or "Unknown") .. "|r")
            end
        else
            -- Action button for active tabs
            local actionBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            actionBtn:SetSize(80, 20)  -- Increased width for new button states
            actionBtn:SetPoint("LEFT", 610, 0)
            
            -- Store button reference in row for later updates
            row.actionButton = actionBtn
            
            -- Set up click handler for different scenarios
            actionBtn:SetScript("OnClick", function()
                if order.player == playerName then
                    -- Own order
                    if order.status == Database.STATUS.PENDING and order.pendingFulfiller then
                        -- Complete the pending fulfillment
                        local success = Database.CompleteFulfillment(order.id)
                        if success then
                            print(string.format("|cff00ff00[GuildWorkOrders]|r Order completed! %s fulfilled your order.", order.pendingFulfiller))
                            UI.RefreshOrders()
                        else
                            print("|cffff0000[GuildWorkOrders]|r Failed to complete order")
                        end
                    else
                        -- Cancel order
                        UI.ConfirmCancelOrder(order)
                    end
                else
                    -- Others' orders - use new request system
                    if order.type == Database.TYPE.WTB then
                        UI.ConfirmSellToOrder(order)
                    elseif order.type == Database.TYPE.WTS then
                        UI.ConfirmBuyFromOrder(order)
                    end
                end
            end)
            
            -- Initialize button state using new system
            UI.UpdateOrderRowButton(row, order)
        end
    end
    
    row.order = order
    row.orderID = order.id  -- Store order ID for button state tracking
    return row
end

-- Get time ago string
function UI.GetTimeAgo(timestamp)
    if not timestamp then return "?" end
    
    local now = GetCurrentTime()
    local diff = now - timestamp
    
    if diff < 60 then
        return "Now"
    elseif diff < 3600 then
        return math.floor(diff / 60) .. "m"
    elseif diff < 86400 then
        return math.floor(diff / 3600) .. "h"
    else
        return math.floor(diff / 86400) .. "d"
    end
end

-- Get TTL display with color coding
function UI.GetTTLDisplay(secondsLeft)
    if secondsLeft <= 0 then
        return "Expired", "|cffff0000"
    end
    
    local hours = math.floor(secondsLeft / 3600)
    local minutes = math.floor((secondsLeft % 3600) / 60)
    
    local text, color
    
    if hours >= 12 then
        -- More than 12 hours - show hours, green
        text = hours .. "h"
        color = "|cff00ff00"  -- Green
    elseif hours >= 2 then
        -- 2-12 hours - show hours and minutes, yellow
        if minutes > 0 then
            text = hours .. "h" .. minutes .. "m"
        else
            text = hours .. "h"
        end
        color = "|cffFFD700"  -- Yellow/Gold
    elseif hours >= 1 then
        -- 1-2 hours - show hours and minutes, orange
        text = hours .. "h" .. minutes .. "m"
        color = "|cffFFA500"  -- Orange
    else
        -- Less than 1 hour - show minutes, red
        text = minutes .. "m"
        color = "|cffff0000"  -- Red
    end
    
    return text, color
end

-- Format timestamp as date only (no time to avoid sync precision issues)
function UI.FormatDateTime(timestamp)
    if not timestamp then return "-" end
    
    -- Calculate days difference using simple day calculation
    local currentTime = GetServerTime()
    local daysDiff = math.floor((currentTime - timestamp) / 86400)
    
    if daysDiff == 0 then
        return "Today"
    elseif daysDiff == 1 then
        return "Yesterday"
    elseif daysDiff > 1 then
        return string.format("%d days ago", daysDiff)
    else
        -- Future date (shouldn't happen for completed orders)
        return string.format("%d days", -daysDiff)
    end
end

-- Refresh order display
function UI.RefreshOrders()
    if not mainFrame or not mainFrame:IsShown() or not UI.listContent then return end
    
    -- Recreate headers to ensure correct columns for current tab
    UI.CreateColumnHeaders()
    
    -- Clear existing rows
    for _, row in ipairs(orderRows) do
        row:Hide()
    end
    orderRows = {}
    
    -- Get orders based on current tab
    local orders = UI.GetFilteredOrders()
    
    -- Create/update rows
    for i, order in ipairs(orders) do
        local row = UI.CreateOrderRow(order, i)
        table.insert(orderRows, row)
    end
    
    -- Update scroll frame height
    local height = #orders * 40 + 50
    UI.listContent:SetHeight(math.max(height, UI.scrollFrame:GetHeight()))
end

-- Get filtered orders based on current tab and search
function UI.GetFilteredOrders()
    local orders = {}
    
    if currentTab == "buy" then
        orders = Database.GetOrdersByType(Database.TYPE.WTB)
    elseif currentTab == "sell" then
        orders = Database.GetOrdersByType(Database.TYPE.WTS)
    elseif currentTab == "my" then
        orders = Database.GetMyOrders()
    elseif currentTab == "history" then
        orders = Database.GetHistory()
    else
        orders = Database.GetAllOrders()
    end
    
    -- Apply search filter
    if searchText and searchText ~= "" then
        local filtered = {}
        local lowerSearch = string.lower(searchText)
        
        for _, order in ipairs(orders) do
            local itemName = string.lower(order.itemName or "")
            if string.find(itemName, lowerSearch, 1, true) then
                table.insert(filtered, order)
            end
        end
        
        orders = filtered
    end
    
    return orders
end

-- Create status bar
function UI.CreateStatusBar()
    local statusBar = CreateFrame("Frame", nil, mainFrame)
    statusBar:SetPoint("BOTTOMLEFT", 10, 10)
    statusBar:SetPoint("BOTTOMRIGHT", -10, 10)
    statusBar:SetHeight(20)
    
    -- Background
    local bg = statusBar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
    
    -- Online users indicator
    local onlineText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    onlineText:SetPoint("LEFT", 5, 0)
    onlineText:SetText("|cff00ff00• Online: 0|r")
    UI.onlineText = onlineText
    
    -- Make clickable for details
    local onlineButton = CreateFrame("Button", nil, statusBar)
    onlineButton:SetPoint("LEFT", 0, 0)
    onlineButton:SetSize(100, 20)
    onlineButton:SetScript("OnEnter", function()
        UI.ShowOnlineTooltip(onlineButton)
    end)
    onlineButton:SetScript("OnLeave", GameTooltip_Hide)
    
    -- Sync status
    local syncText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    syncText:SetPoint("LEFT", onlineText, "RIGHT", 20, 0)
    syncText:SetText("Last sync: Never")
    UI.syncText = syncText
    
    
    -- Order count
    local countText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("RIGHT", -5, 0)
    countText:SetText("Orders: 0")
    UI.countText = countText
end

-- Update status bar
function UI.UpdateStatusBar()
    if not UI.onlineText then return end
    
    -- Update online count
    local onlineCount = Sync.GetOnlineUserCount()
    UI.onlineText:SetText(string.format("|cff00ff00• Online: %d|r", onlineCount))
    
    -- Update sync status
    local syncStatus = Sync.GetSyncStatus()
    local syncText = "Never"
    if syncStatus.lastSync > 0 then
        local timeAgo = UI.GetTimeAgo(syncStatus.lastSync)
        if timeAgo == "Now" then
            syncText = timeAgo
        else
            syncText = timeAgo .. " ago"
        end
    end
    if syncStatus.inProgress then
        syncText = "|cffFFD700Syncing...|r"
    end
    UI.syncText:SetText("Last sync: " .. syncText)
    
    
    -- Update order count (always show active orders count)
    local activeOrders = Database.GetAllOrders()  -- Gets only active orders
    UI.countText:SetText("Active Orders: " .. #activeOrders)
end

-- Show online users tooltip
function UI.ShowOnlineTooltip(frame)
    GameTooltip:SetOwner(frame, "ANCHOR_TOPLEFT")
    GameTooltip:SetText("GuildWorkOrders Users Online")
    
    local users = Sync.GetOnlineUsers()
    local count = 0
    for user, info in pairs(users) do
        GameTooltip:AddLine(string.format("%s (v%d)", user, info.version))
        count = count + 1
    end
    
    if count == 0 then
        GameTooltip:AddLine("|cff888888No other users online|r")
    end
    
    GameTooltip:Show()
end

-- Confirm cancel order
function UI.ConfirmCancelOrder(order)
    StaticPopupDialogs["GWO_CANCEL_ORDER"] = {
        text = "Cancel this work order?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            Database.CancelOrder(order.id)
            Sync.BroadcastOrderUpdate(order.id, Database.STATUS.CANCELLED, (order.version or 1) + 1)
            UI.RefreshOrders()
            print("|cff00ff00[GuildWorkOrders]|r Order cancelled")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    
    StaticPopup_Show("GWO_CANCEL_ORDER")
end

-- Whisper player about order
function UI.WhisperPlayer(order)
    if not order.player then return end
    
    local message = Config.FormatWhisperMessage(
        order.itemName,
        order.quantity,
        order.price
    )
    
    SendChatMessage(message, "WHISPER", nil, order.player)
    print(string.format("|cff00ff00[GuildWorkOrders]|r Whispered %s about %s",
        order.player, order.itemName))
end

-- Save window position
function UI.SaveWindowPosition()
    if mainFrame then
        local point, _, _, x, y = mainFrame:GetPoint()
        -- Save position logic could be added here if needed
    end
end

-- Create new order dialog
function UI.CreateNewOrderDialog()
    local dialog = CreateFrame("Frame", "GWONewOrderDialog", UIParent, "BasicFrameTemplateWithInset")
    dialog:SetSize(600, 350)
    dialog:SetPoint("CENTER")
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function() dialog:StartMoving() end)
    dialog:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)
    dialog:SetFrameStrata("DIALOG")
    dialog.TitleText:SetText("Create Work Order")
    
    -- Order type radio buttons
    local buyRadio = CreateFrame("CheckButton", nil, dialog, "UIRadioButtonTemplate")
    buyRadio:SetPoint("TOPLEFT", 30, -40)
    buyRadio:SetChecked(true)
    local buyLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buyLabel:SetPoint("LEFT", buyRadio, "RIGHT", 5, 0)
    buyLabel:SetText("Want to Buy (WTB)")
    
    local sellRadio = CreateFrame("CheckButton", nil, dialog, "UIRadioButtonTemplate")
    sellRadio:SetPoint("TOPLEFT", 30, -70)
    local sellLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sellLabel:SetPoint("LEFT", sellRadio, "RIGHT", 5, 0)
    sellLabel:SetText("Want to Sell (WTS)")
    
    -- Radio button logic
    buyRadio:SetScript("OnClick", function()
        buyRadio:SetChecked(true)
        sellRadio:SetChecked(false)
    end)
    sellRadio:SetScript("OnClick", function()
        sellRadio:SetChecked(true)
        buyRadio:SetChecked(false)
    end)
    
    -- Item input (shift-click or drag-and-drop area)
    local itemLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemLabel:SetPoint("TOPLEFT", 30, -110)
    itemLabel:SetText("Item (Shift-click or Drag):")
    
    -- Create an EditBox that can receive both text input and drag events
    local itemInput = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    itemInput:SetSize(350, 25)
    itemInput:SetPoint("LEFT", itemLabel, "RIGHT", 10, 0)
    itemInput:SetText("")
    itemInput:SetAutoFocus(false)
    itemInput:SetMaxLetters(50)
    itemInput:RegisterForDrag("LeftButton")
    itemInput:EnableMouse(true)
    
    -- Add tooltip for shift-click functionality
    itemInput:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Item Selection", 1, 1, 1)
        GameTooltip:AddLine("• Shift-click items from chat or bags", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("• Drag items from your bags", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("• Type item names manually", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    itemInput:SetScript("OnLeave", GameTooltip_Hide)
    
    -- Store the actual item link separately from display text
    itemInput.itemLink = nil
    
    -- Drag and drop handlers
    itemInput:SetScript("OnReceiveDrag", function(self)
        local cursorType, itemID, itemLink = GetCursorInfo()
        if cursorType == "item" and itemLink then
            local itemName = string.match(itemLink, "%[(.-)%]")
            if itemName then
                self:SetText(itemName)
                self.itemLink = itemLink
                ClearCursor() -- Clear the dragged item from cursor
                print("|cff00ff00[GuildWorkOrders]|r Selected item: " .. itemName)
            elseif string.find(itemLink, "Hitem:") then
                -- Handle corrupted item links
                local itemId = string.match(itemLink, "Hitem:(%d+)")
                if itemId then
                    local fallbackName = "Item " .. itemId
                    self:SetText(fallbackName)
                    self.itemLink = itemLink
                    ClearCursor()
                    print("|cff00ff00[GuildWorkOrders]|r Selected item: " .. fallbackName .. " (corrupted drag link)")
                end
            end
        end
    end)
    
    
    -- Also handle mouse up for drag completion
    itemInput:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            local cursorType, itemID, itemLink = GetCursorInfo()
            if cursorType == "item" and itemLink then
                local itemName = string.match(itemLink, "%[(.-)%]")
                if itemName then
                    self:SetText(itemName)
                    self.itemLink = itemLink
                    ClearCursor()
                    print("|cff00ff00[GuildWorkOrders]|r Selected item: " .. itemName)
                elseif string.find(itemLink, "Hitem:") then
                    -- Handle corrupted item links
                    local itemId = string.match(itemLink, "Hitem:(%d+)")
                    if itemId then
                        local fallbackName = "Item " .. itemId
                        self:SetText(fallbackName)
                        self.itemLink = itemLink
                        ClearCursor()
                        print("|cff00ff00[GuildWorkOrders]|r Selected item: " .. fallbackName .. " (corrupted mouseup link)")
                    end
                end
            end
        end
    end)
    
    -- Clear button for item selection
    local clearBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    clearBtn:SetSize(50, 20)
    clearBtn:SetPoint("LEFT", itemInput, "RIGHT", 5, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        itemInput:SetText("")
        itemInput.itemLink = nil
    end)
    
    -- Quantity input
    local qtyLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    qtyLabel:SetPoint("TOPLEFT", 30, -145)
    qtyLabel:SetText("Quantity:")
    
    local qtyInput = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    qtyInput:SetSize(80, 25)
    qtyInput:SetPoint("LEFT", qtyLabel, "RIGHT", 10, 0)
    qtyInput:SetAutoFocus(false)
    qtyInput:SetNumeric(true)
    qtyInput:SetMaxLetters(5)
    
    -- Price input
    local priceLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    priceLabel:SetPoint("TOPLEFT", 30, -180)
    priceLabel:SetText("Price:")
    
    local priceInput = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    priceInput:SetSize(250, 25)
    priceInput:SetPoint("LEFT", priceLabel, "RIGHT", 10, 0)
    priceInput:SetAutoFocus(false)
    priceInput:SetMaxLetters(20)
    
    -- Announce to guild checkbox
    local announceCheck = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
    announceCheck:SetPoint("TOPLEFT", 30, -215)
    announceCheck:SetChecked(Config.ShouldAnnounceToGuild())
    local announceLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    announceLabel:SetPoint("LEFT", announceCheck, "RIGHT", 5, 0)
    announceLabel:SetText("Also announce in guild chat")
    
    -- Create button
    local createBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    createBtn:SetSize(100, 25)
    createBtn:SetPoint("BOTTOMLEFT", 50, 20)
    createBtn:SetText("Create Order")
    createBtn:SetScript("OnClick", function()
        UI.CreateOrderFromDialog(dialog, buyRadio, itemInput, qtyInput, priceInput, announceCheck)
    end)
    
    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancelBtn:SetSize(100, 25)
    cancelBtn:SetPoint("BOTTOMRIGHT", -50, 20)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        dialog:Hide()
    end)
    
    
    
    -- No special cleanup needed for drag-only functionality
    
    -- Store reference to item input for easy access
    dialog.itemInput = itemInput
    
    -- Hook ChatEdit_InsertLink to capture shift-clicks when dialog is open
    if not UI.chatEditHooked then
        UI.chatEditHooked = true
        local origChatEdit_InsertLink = ChatEdit_InsertLink
        ChatEdit_InsertLink = function(text)
            if UI.newOrderDialog and UI.newOrderDialog:IsVisible() and text then
                local itemName = string.match(text, "%[(.-)%]")
                if itemName and UI.newOrderDialog.itemInput then
                    UI.newOrderDialog.itemInput:SetText(itemName)
                    UI.newOrderDialog.itemInput.itemLink = text
                    print("|cff00ff00[GuildWorkOrders]|r Selected item: " .. itemName)
                    return true
                elseif text and string.find(text, "Hitem:") then
                    -- Handle corrupted item links without brackets
                    local itemId = string.match(text, "Hitem:(%d+)")
                    if itemId and UI.newOrderDialog.itemInput then
                        local fallbackName = "Item " .. itemId
                        UI.newOrderDialog.itemInput:SetText(fallbackName)
                        UI.newOrderDialog.itemInput.itemLink = text
                        print("|cff00ff00[GuildWorkOrders]|r Selected item: " .. fallbackName .. " (corrupted link)")
                        return true
                    end
                end
            end
            return origChatEdit_InsertLink(text)
        end
    end
    
    dialog:Hide()
    UI.newOrderDialog = dialog
end

-- Show new order dialog
function UI.ShowNewOrderDialog()
    if UI.newOrderDialog then
        -- Reset the item selection when dialog opens
        if UI.newOrderDialog.itemInput then
            UI.newOrderDialog.itemInput:SetText("")
            UI.newOrderDialog.itemInput.itemLink = nil
        end
        UI.newOrderDialog:Show()
    end
end

-- Create order from dialog
function UI.CreateOrderFromDialog(dialog, buyRadio, itemInput, qtyInput, priceInput, announceCheck)
    local orderType = buyRadio:GetChecked() and Database.TYPE.WTB or Database.TYPE.WTS
    local itemLink = itemInput.itemLink
    local quantity = tonumber(qtyInput:GetText())
    local price = priceInput:GetText()
    
    -- Validate that an item was selected
    if not itemLink then
        print("|cffff0000[GuildWorkOrders]|r Please select an item by shift-clicking or dragging it to the item field")
        return
    end
    
    -- Validate input
    local isValid, errors = Parser.ValidateOrderData(orderType, itemLink, quantity, price)
    if not isValid then
        print("|cffff0000[GuildWorkOrders]|r " .. table.concat(errors, ", "))
        return
    end
    
    -- Create the order
    local order = Database.CreateOrder(orderType, itemLink, quantity, price)
    if order then
        -- Broadcast to other users
        Sync.BroadcastNewOrder(order)
        
        -- Announce to guild if requested
        if announceCheck:GetChecked() then
            local itemText = order.itemLink or order.itemName or "Unknown Item"
            local message
            if price and price ~= "" then
                message = string.format("%s %s%s for %s",
                    orderType,
                    quantity and (tostring(quantity) .. "x ") or "",
                    itemText,
                    price
                )
            else
                message = string.format("%s %s%s",
                    orderType,
                    quantity and (tostring(quantity) .. "x ") or "",
                    itemText
                )
            end
            SendChatMessage(message, "GUILD")
        end
        
        -- Close dialog and refresh
        dialog:Hide()
        UI.RefreshOrders()
        UI.UpdateStatusBar()  -- Update counter after creating order
        UI.SelectTab("my")  -- Switch to My Orders tab
        
        print(string.format("|cff00ff00[GuildWorkOrders]|r Created %s order for %s", orderType, order.itemName or "Unknown Item"))
    end
end

-- Public interface
function UI.Show()
    if mainFrame then
        mainFrame:Show()
    end
end

function UI.Hide()
    if mainFrame then
        mainFrame:Hide()
    end
end

function UI.Toggle()
    if mainFrame then
        if mainFrame:IsShown() then
            UI.Hide()
        else
            UI.Show()
        end
    end
end

function UI.IsShown()
    return mainFrame and mainFrame:IsShown()
end

-- Confirmation dialog for canceling own order
function UI.ConfirmCancelOrder(order)
    StaticPopupDialogs["GWO_CANCEL_ORDER"] = {
        text = string.format("Cancel your %s order for %s?", 
            order.type == Database.TYPE.WTB and "buy" or "sell",
            order.itemName or "item"),
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            local success = Database.CancelOrder(order.id)
            if success then
                Sync.BroadcastOrderUpdate(order.id, Database.STATUS.CANCELLED, (order.version or 1) + 1)
                print(string.format("|cff00ff00[GuildWorkOrders]|r Cancelled order: %s", order.itemName))
                UI.RefreshOrders()
                UI.UpdateStatusBar()  -- Update counter after cancelling
            else
                print("|cffff0000[GuildWorkOrders]|r Failed to cancel order")
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("GWO_CANCEL_ORDER")
end

-- Request to fulfill a buy order (sell to buyer)
function UI.ConfirmSellToOrder(order)
    local priceText = order.price and (" for " .. order.price) or " (price negotiable)"
    local qtyText = order.quantity and (tostring(order.quantity) .. "x ") or ""
    
    StaticPopupDialogs["GWO_SELL_TO_ORDER"] = {
        text = string.format("Request to sell %s%s to %s%s?\n\nThis will send a fulfillment request to %s.", 
            qtyText,
            order.itemName or "item",
            order.player or "player",
            priceText,
            order.player or "player"),
        button1 = "Send Request",
        button2 = "Cancel",
        OnAccept = function()
            -- Send fulfillment request using new system
            local success, errorMsg = Database.RequestFulfillOrder(order.id)
            if success then
                print(string.format("|cff00ff00[GuildWorkOrders]|r Fulfillment request sent to %s. Waiting for response...", order.player))
                
                -- Disable the button and show pending status
                UI.SetButtonPending(order.id, "Requesting...")
                
                -- Set timeout for request
                C_Timer.After(10, function()
                    UI.SetButtonTimeout(order.id, "Request timed out - try again")
                end)
            else
                print(string.format("|cffff0000[GuildWorkOrders]|r %s", errorMsg or "Failed to send request"))
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("GWO_SELL_TO_ORDER")
end

-- Request to fulfill a sell order (buy from seller)
function UI.ConfirmBuyFromOrder(order)
    local priceText = order.price and (" for " .. order.price) or " (price negotiable)"
    local qtyText = order.quantity and (tostring(order.quantity) .. "x ") or ""
    
    StaticPopupDialogs["GWO_BUY_FROM_ORDER"] = {
        text = string.format("Request to buy %s%s from %s%s?\n\nThis will send a fulfillment request to %s.", 
            qtyText,
            order.itemName or "item",
            order.player or "player",
            priceText,
            order.player or "player"),
        button1 = "Send Request",
        button2 = "Cancel",
        OnAccept = function()
            -- Send fulfillment request using new system
            local success, errorMsg = Database.RequestFulfillOrder(order.id)
            if success then
                print(string.format("|cff00ff00[GuildWorkOrders]|r Fulfillment request sent to %s. Waiting for response...", order.player))
                
                -- Disable the button and show pending status
                UI.SetButtonPending(order.id, "Requesting...")
                
                -- Set timeout for request
                C_Timer.After(10, function()
                    UI.SetButtonTimeout(order.id, "Request timed out - try again")
                end)
            else
                print(string.format("|cffff0000[GuildWorkOrders]|r %s", errorMsg or "Failed to send request"))
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("GWO_BUY_FROM_ORDER")
end

-- ============================================================================
-- BUTTON STATE MANAGEMENT FOR NEW REQUEST SYSTEM
-- ============================================================================

-- Track pending button states
local pendingButtons = {}

-- Set button to pending state
function UI.SetButtonPending(orderID, text)
    pendingButtons[orderID] = {
        state = "pending",
        text = text or "Requesting...",
        timestamp = GetCurrentTime()
    }
    UI.RefreshOrderButtonState(orderID)
end

-- Set button to timeout state  
function UI.SetButtonTimeout(orderID, text)
    if pendingButtons[orderID] and pendingButtons[orderID].state == "pending" then
        pendingButtons[orderID] = {
            state = "timeout",
            text = text or "Timed out",
            timestamp = GetCurrentTime()
        }
        UI.RefreshOrderButtonState(orderID)
        
        -- Clear timeout after 3 seconds
        C_Timer.After(3, function()
            if pendingButtons[orderID] and pendingButtons[orderID].state == "timeout" then
                pendingButtons[orderID] = nil
                UI.RefreshOrderButtonState(orderID)
            end
        end)
    end
end

-- Handle fulfillment response from sync system
function UI.HandleFulfillmentResponse(orderID, response, sender, reason)
    if response == "accepted" then
        pendingButtons[orderID] = {
            state = "accepted",
            text = "✓ Accepted - Contact " .. sender,
            timestamp = GetCurrentTime()
        }
        UI.RefreshOrderButtonState(orderID)
        
    elseif response == "rejected" then
        pendingButtons[orderID] = {
            state = "rejected", 
            text = reason or "Request rejected",
            timestamp = GetCurrentTime()
        }
        UI.RefreshOrderButtonState(orderID)
        
        -- Clear rejection message after 5 seconds
        C_Timer.After(5, function()
            if pendingButtons[orderID] and pendingButtons[orderID].state == "rejected" then
                pendingButtons[orderID] = nil
                UI.RefreshOrderButtonState(orderID)
            end
        end)
    end
end

-- Refresh specific order button state
function UI.RefreshOrderButtonState(orderID)
    -- Find the order row and update its button
    for _, row in ipairs(orderRows) do
        if row.orderID == orderID then
            UI.UpdateOrderRowButton(row, row.order)
            break
        end
    end
end

-- Update order row button based on current state
function UI.UpdateOrderRowButton(row, order)
    if not row.actionButton then return end
    
    local playerName = UnitName("player")
    local buttonState = pendingButtons[order.id]
    
    -- Check if this is my own order
    if order.player == playerName then
        if order.status == Database.STATUS.PENDING and order.pendingFulfiller then
            -- My order has a pending fulfillment - show complete button
            row.actionButton:SetText("Complete Trade")
            row.actionButton:SetEnabled(true)
            row.actionButton:Show()
        else
            -- My order - show cancel/status
            row.actionButton:SetText("Cancel")
            row.actionButton:SetEnabled(true) 
            row.actionButton:Show()
        end
        return
    end
    
    -- Check button state for pending requests
    if buttonState then
        if buttonState.state == "pending" then
            row.actionButton:SetText(buttonState.text)
            row.actionButton:SetEnabled(false)
            row.actionButton:Show()
        elseif buttonState.state == "accepted" then
            row.actionButton:SetText(buttonState.text)
            row.actionButton:SetEnabled(false)  -- Keep disabled, just info
            row.actionButton:Show()
        elseif buttonState.state == "rejected" or buttonState.state == "timeout" then
            row.actionButton:SetText(buttonState.text)
            row.actionButton:SetEnabled(false)
            row.actionButton:Show()
        end
        return
    end
    
    -- Default button state based on order status
    if order.status == Database.STATUS.ACTIVE then
        -- Check if order is expired
        if order.expiresAt and order.expiresAt < GetCurrentTime() then
            row.actionButton:SetText("Expired")
            row.actionButton:SetEnabled(false)
            row.actionButton:Show()
        else
            -- Active order - show buy/sell button
            if order.type == Database.TYPE.WTB then
                row.actionButton:SetText("Sell")
                row.actionButton:SetEnabled(true)
            else
                row.actionButton:SetText("Buy")
                row.actionButton:SetEnabled(true)
            end
            row.actionButton:Show()
        end
    elseif order.status == Database.STATUS.PENDING then
        row.actionButton:SetText("Pending...")
        row.actionButton:SetEnabled(false)
        row.actionButton:Show()
    elseif order.status == Database.STATUS.EXPIRED then
        row.actionButton:SetText("Expired")
        row.actionButton:SetEnabled(false)
        row.actionButton:Show()
    elseif order.status == Database.STATUS.FULFILLED then
        row.actionButton:SetText("Completed")
        row.actionButton:SetEnabled(false)
        row.actionButton:Show()
    else
        row.actionButton:Hide()
    end
end