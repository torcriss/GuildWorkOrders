# GuildWorkOrders

A comprehensive guild-wide work order management system for World of Warcraft Classic Era.

## Features

- 🔇 **Hidden Communication** - Uses addon messages only (no guild chat spam)
- 🔄 **Auto-Synchronization** - Real-time sync between all guild members with the addon
- 🎯 **Smart Parsing** - Automatically detects WTB/WTS messages from guild chat
- 📱 **Enhanced UI** - Tabbed interface with type column and improved order management
- ⚡ **Real-time Updates** - Orders update instantly across all users with heartbeat system
- 🛡️ **Advanced Sync Protocol** - Robust message validation and conflict resolution
- 🔐 **Admin Clear System** - Password-protected guild-wide order clearing with full tracking
- ⏰ **Auto-Expiry** - Orders automatically expire after 24 hours
- 📢 **Optional Announcements** - Can announce new orders to guild chat if desired
- 🏷️ **Database Limits** - Smart order limits (200 total, 10 per user) with automatic cleanup
- 🔧 **Message Size Optimization** - Efficient encoding prevents sync failures with any item type
- 📊 **Status Indicators** - Real-time display of your orders, database usage, and admin actions

## Installation

1. Download the latest release
2. Extract to your `World of Warcraft\_classic_era_\Interface\AddOns\` directory
3. Enable "GuildWorkOrders" in the AddOns menu
4. Reload your UI or restart WoW

## Usage

### Main Interface
- `/gwo` or `/workorders` - Open the main UI
- Browse through tabs: **Buy Orders** | **Sell Orders** | **My Orders** | **History**
- Use the search box to find specific items
- Click "New Order" to create WTB/WTS orders
- Click "Whisper" to contact players about their orders

### Quick Commands
```
/gwo post WTB [Iron Ore] 20 5g        # Quick post a buy order
/gwo post WTS [Copper Bar] 100 2g     # Quick post a sell order
/gwo list                              # Show all active orders
/gwo list WTB                          # Show only buy orders
/gwo search Iron                       # Search for Iron-related orders
/gwo my                                # Show your orders
/gwo stats                             # Show statistics
```

### Management Commands
```
/gwo cancel 1                          # Cancel your order #1
/gwo fulfill 2                         # Mark your order #2 as fulfilled
/gwo sync                              # Force sync with guild
/gwo help                              # Show all commands
```

### Admin Management
Access the password-protected admin clear system:
- **Admin Button** - Red "Admin" button in the UI status bar
- **Password**: `0000` (hashed and secured)
- **Two-Step Process**: Password entry + final confirmation
- **Global Effect**: Clears ALL orders for ALL guild members
- **Full Tracking**: Shows "Last clear: X ago by PlayerName" in status bar
- **Offline Protection**: Users who missed the clear get updated when they return

**Security Features**:
- Failed attempt lockout (30 seconds after 3 tries)
- Password characters hidden during input
- Multiple confirmation dialogs with warnings
- Real-time status updates across all guild members

## How It Works

### Synchronization
- Orders are synchronized between guild members using hidden addon messages
- No guild chat spam - all communication is invisible to non-addon users
- **Heartbeat System** - Periodic broadcasts ensure all users stay synchronized
- **Advanced Conflict Resolution** - Version-based conflict resolution with timestamps
- **Message Size Validation** - Prevents sync failures with legendary items and long names  
- **Rate Limiting** - Prevents flooding (max 5 messages per second with intelligent batching)

### Order Parsing
The addon automatically detects WTB/WTS patterns in guild chat:
- **WTB patterns**: "WTB", "LF", "looking for", "need", "buying", "ISO"
- **WTS patterns**: "WTS", "selling", "for sale", "have X for", "anyone need"
- Extracts item links, quantities, and prices automatically
- Only processes messages containing actual items

### Order Management
- **Smart Limits** - Maximum 200 total orders, 10 active orders per user
- **Automatic Cleanup** - Purges old history when database approaches limits
- **Order Expiration** - Orders expire after 24 hours automatically
- **Order Actions** - Players can cancel or mark their own orders as fulfilled
- **Full History** - Complete tracking of completed orders with status details
- **Advanced Search** - Search and filter functionality with real-time updates
- **Admin Clear System** - Password-protected global clearing with timestamp tracking

## Configuration

Access configuration via `/gwo config` or through the UI:

- **announceToGuild** - Announce new orders to guild chat (default: false)
- **autoSync** - Auto-sync on login (default: true)
- **soundAlert** - Play sound for new orders (default: true)
- **debugMode** - Enable debug logging (default: false)
- **orderExpiry** - Order expiry time in seconds (default: 86400 = 24 hours)

## Requirements

- World of Warcraft Classic Era (Interface 11507)
- Must be in a guild to use synchronization features
- Other guild members need the addon for full functionality

## API

Other addons can interact with GuildWorkOrders:

```lua
-- Check if available
if _G.GuildWorkOrders and _G.GuildWorkOrders.IsAvailable() then
    -- Get order count
    local count = _G.GuildWorkOrders.GetOrderCount()
    
    -- Create an order
    local success, orderID = _G.GuildWorkOrders.CreateOrder("WTB", "[Iron Ore]", 20, "5g")
    
    -- Search orders
    local orders = _G.GuildWorkOrders.SearchOrders("Iron")
    
    -- Show/hide UI
    _G.GuildWorkOrders.ShowUI()
    _G.GuildWorkOrders.HideUI()
end
```

## Development

### File Structure
```
GuildWorkOrders/
├── GuildWorkOrders.toc          # Addon manifest
├── GuildWorkOrders.lua          # Main initialization
├── deploy.sh                    # Development deployment script
└── modules/
    ├── Config.lua               # Configuration management
    ├── Database.lua             # Order storage with smart limits
    ├── Parser.lua               # WTB/WTS message parsing
    ├── Sync.lua                 # Advanced guild synchronization protocol
    ├── UI.lua                   # Enhanced user interface with status indicators
    ├── Commands.lua             # Slash command system
    └── Minimap.lua              # Minimap integration
```

### Building
Use the included `deploy.sh` script for development deployment:
```bash
./deploy.sh
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly in-game
5. Submit a pull request

## Support

- Report issues on GitHub
- Join our Discord for community support
- Check the wiki for advanced usage tips

## License

MIT License - see LICENSE file for details

---

**GuildWorkOrders v2.2.1** - Making guild trading easier, one order at a time! 🛒

## Recent Updates (v2.2.1)

### 🛠️ Minor Fixes
- **Fixed Item Field Tooltip** - Removed incorrect "Type item names manually" suggestion
- **Improved User Experience** - Tooltip now only shows functional item selection methods
- **UI Polish** - Better guidance for new users on how to select items

## Previous Updates (v2.2.0)

### 🔐 Password-Protected Admin System
- **Admin Clear Button** - Secure admin clear functionality in UI with password protection
- **Hashed Password Security** - Password "0000" stored as hash, not visible in code
- **Two-Step Verification** - Password entry + final confirmation dialog
- **Failed Attempt Protection** - 30-second lockout after 3 failed attempts
- **Global Clear Tracking** - Shows "Last clear: X ago by PlayerName" in status bar

### 🛡️ Advanced Sync Protocol
- **CLEAR_ALL Messages** - New message type for admin clear events
- **Offline User Protection** - Missed admin clears applied when users return online
- **Pre-Clear Filtering** - Prevents old orders from repopulating after clears
- **Clear Timestamp Validation** - All sync handlers check clear events

### 🎨 Enhanced User Interface
- **Status Bar Improvements** - Last clear indicator with user attribution
- **Column Header Updates** - "Time"→"Remaining", "Completed (Server)"→"Date"
- **Admin Button Styling** - Red-tinted button with hover effects and tooltips
- **Fixed Text Overlap** - Proper spacing for all status bar elements
- **Password Dialogs** - Masked input fields with security warnings

### 🔧 Security & UX Improvements
- **Removed Slash Command** - `/gwo clear` removed for better security
- **Progressive Warnings** - Multiple confirmation steps for admin actions
- **Real-Time Updates** - Status changes visible immediately across all users
- **Rate-Limited Broadcasting** - 5 messages/second for admin clear events

### ⚡ Technical Optimizations
- **Memory-Efficient Hashing** - Custom djb2 algorithm implementation  
- **Enhanced Conflict Resolution** - Robust handling of clear event timing
- **Minimap Button Fixes** - Improved toggle functionality and positioning
- **Debug Output Reduction** - Cleaner console output for better UX