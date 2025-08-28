-- UI.lua - User interface for GuildWorkOrders
local addonName, addon = ...
addon.UI = addon.UI or {}
local UI = addon.UI

-- Local references
local Config = nil
local Database = nil
local Sync = nil
local Parser = nil

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
    frame:SetMinResize(600, 400)
    frame:SetMaxResize(900, 700)
    
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
        UI.RefreshOrders()
    end
end

-- Create search bar
function UI.CreateSearchBar()
    -- Search container
    local searchBar = CreateFrame("Frame", nil, mainFrame)
    searchBar:SetPoint("TOPLEFT", 15, -65)
    searchBar:SetPoint("TOPRIGHT", -15, -65)
    searchBar:SetHeight(30)
    
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
    scrollFrame:SetPoint("TOPLEFT", 15, -105)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(content)
    content:SetSize(scrollFrame:GetWidth(), 1)
    
    UI.scrollFrame = scrollFrame
    UI.listContent = content
    
    -- Column headers
    UI.CreateColumnHeaders()
end

-- Create column headers
function UI.CreateColumnHeaders()
    local headers = {
        {text = "Item", width = 200, x = 10},
        {text = "Qty", width = 50, x = 215},
        {text = "Price", width = 80, x = 270},
        {text = "Player", width = 100, x = 355},
        {text = "Time", width = 80, x = 460},
        {text = "Action", width = 60, x = 545}
    }
    
    for _, header in ipairs(headers) do
        local label = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", header.x, -85)
        label:SetText("|cffFFD700" .. header.text .. "|r")
    end
end

-- Create order row
function UI.CreateOrderRow(order, index)
    local row = CreateFrame("Button", nil, UI.listContent)
    row:SetSize(UI.listContent:GetWidth() - 20, 30)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * 35)
    
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
    
    -- Item link/name
    local item = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    item:SetPoint("LEFT", 10, 0)
    item:SetWidth(190)
    item:SetJustifyH("LEFT")
    
    -- Make item link clickable if it's a real item link
    if order.itemLink and string.find(order.itemLink, "|H") then
        item:SetText(order.itemLink)
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
    else
        item:SetText(order.itemName or "Unknown")
    end
    
    -- Quantity
    local qty = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    qty:SetPoint("LEFT", 215, 0)
    qty:SetText(order.quantity or "?")
    
    -- Price with color coding
    local price = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    price:SetPoint("LEFT", 270, 0)
    local priceText = order.price or "?"
    if string.find(priceText, "g") then
        price:SetText("|cffFFD700" .. priceText .. "|r")
    elseif string.find(priceText, "s") then
        price:SetText("|cffC0C0C0" .. priceText .. "|r")
    else
        price:SetText("|cffB87333" .. priceText .. "|r")
    end
    
    -- Player name
    local player = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    player:SetPoint("LEFT", 355, 0)
    player:SetText("|cff00ff00" .. (order.player or "Unknown") .. "|r")
    
    -- Time ago
    local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetPoint("LEFT", 460, 0)
    timeText:SetText("|cff888888" .. UI.GetTimeAgo(order.timestamp) .. "|r")
    
    -- Action button
    local actionBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    actionBtn:SetSize(60, 20)
    actionBtn:SetPoint("LEFT", 545, 0)
    
    local playerName = UnitName("player")
    if order.player == playerName then
        -- Own order - can cancel/fulfill
        if currentTab == "history" then
            actionBtn:Hide()
        else
            actionBtn:SetText("Cancel")
            actionBtn:SetScript("OnClick", function()
                UI.ConfirmCancelOrder(order)
            end)
        end
    else
        -- Others' orders - whisper them
        actionBtn:SetText("Whisper")
        actionBtn:SetScript("OnClick", function()
            UI.WhisperPlayer(order)
        end)
    end
    
    row.order = order
    return row
end

-- Get time ago string
function UI.GetTimeAgo(timestamp)
    if not timestamp then return "?" end
    
    local now = time()
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

-- Refresh order display
function UI.RefreshOrders()
    if not mainFrame or not mainFrame:IsShown() then return end
    
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
    local height = #orders * 35 + 50
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
    syncText:SetPoint("CENTER", 0, 0)
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
        syncText = UI.GetTimeAgo(syncStatus.lastSync) .. " ago"
    end
    if syncStatus.inProgress then
        syncText = "|cffFFD700Syncing...|r"
    end
    UI.syncText:SetText("Last sync: " .. syncText)
    
    -- Update order count
    local orders = UI.GetFilteredOrders()
    UI.countText:SetText("Orders: " .. #orders)
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
    dialog:SetSize(400, 300)
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
    
    -- Item input
    local itemLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemLabel:SetPoint("TOPLEFT", 30, -110)
    itemLabel:SetText("Item:")
    
    local itemInput = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    itemInput:SetSize(250, 25)
    itemInput:SetPoint("LEFT", itemLabel, "RIGHT", 10, 0)
    itemInput:SetAutoFocus(false)
    
    -- Quantity input
    local qtyLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    qtyLabel:SetPoint("TOPLEFT", 30, -145)
    qtyLabel:SetText("Quantity:")
    
    local qtyInput = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    qtyInput:SetSize(60, 25)
    qtyInput:SetPoint("LEFT", qtyLabel, "RIGHT", 10, 0)
    qtyInput:SetAutoFocus(false)
    qtyInput:SetNumeric(true)
    qtyInput:SetMaxLetters(5)
    
    -- Price input
    local priceLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    priceLabel:SetPoint("TOPLEFT", 30, -180)
    priceLabel:SetText("Price:")
    
    local priceInput = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    priceInput:SetSize(150, 25)
    priceInput:SetPoint("LEFT", priceLabel, "RIGHT", 10, 0)
    priceInput:SetAutoFocus(false)
    
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
    
    dialog:Hide()
    UI.newOrderDialog = dialog
end

-- Show new order dialog
function UI.ShowNewOrderDialog()
    if UI.newOrderDialog then
        UI.newOrderDialog:Show()
    end
end

-- Create order from dialog
function UI.CreateOrderFromDialog(dialog, buyRadio, itemInput, qtyInput, priceInput, announceCheck)
    local orderType = buyRadio:GetChecked() and Database.TYPE.WTB or Database.TYPE.WTS
    local itemText = itemInput:GetText()
    local quantity = tonumber(qtyInput:GetText())
    local price = priceInput:GetText()
    
    -- Validate input
    local isValid, errors = Parser.ValidateOrderData(orderType, itemText, quantity, price)
    if not isValid then
        print("|cffff0000[GuildWorkOrders]|r " .. table.concat(errors, ", "))
        return
    end
    
    -- Create the order
    local order = Database.CreateOrder(orderType, itemText, quantity, price)
    if order then
        -- Broadcast to other users
        Sync.BroadcastNewOrder(order)
        
        -- Announce to guild if requested
        if announceCheck:GetChecked() then
            local message = string.format("%s %s%s for %s",
                orderType,
                quantity and (tostring(quantity) .. "x ") or "",
                itemText,
                price or "negotiable"
            )
            SendChatMessage(message, "GUILD")
        end
        
        -- Close dialog and refresh
        dialog:Hide()
        UI.RefreshOrders()
        UI.SelectTab("my")  -- Switch to My Orders tab
        
        print(string.format("|cff00ff00[GuildWorkOrders]|r Created %s order for %s", orderType, itemText))
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