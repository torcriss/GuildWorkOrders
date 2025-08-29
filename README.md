# GuildWorkOrders

A comprehensive guild-wide work order management system for World of Warcraft Classic Era.

## Features

- 🔇 **Hidden Communication** - Uses addon messages only (no guild chat spam)
- 🔄 **Auto-Synchronization** - Real-time sync between all guild members with the addon
- 🎯 **Smart Parsing** - Automatically detects WTB/WTS messages from guild chat
- 📱 **Enhanced UI** - Tabbed interface with type column and improved order management
- ⚡ **Real-time Updates** - Orders update instantly across all users with heartbeat system
- 🛡️ **Advanced Sync Protocol** - Robust message validation and conflict resolution
- ⏰ **Auto-Expiry** - Orders automatically expire after 24 hours
- 📢 **Optional Announcements** - Can announce new orders to guild chat if desired
- 🏷️ **Database Limits** - Smart order limits (200 total, 10 per user) with automatic cleanup
- 🔧 **Message Size Optimization** - Efficient encoding prevents sync failures with any item type
- 📊 **Status Indicators** - Real-time display of your orders and database usage

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

**GuildWorkOrders v2.1.1** - Making guild trading easier, one order at a time! 🛒

## Recent Updates (v2.1.1)

### ✨ Major Enhancements
- **🔧 Message Size Optimization** - Fixed sync failures with legendary items and long names
- **🏷️ Database Limits** - Added smart limits (200 total orders, 10 per user) with automatic cleanup
- **📊 Status Indicators** - Real-time display of order counts: "My Active: X/10 | Total Orders: X/200"
- **🛡️ Enhanced Sync Protocol** - Robust message validation prevents all sync failures
- **⚡ Improved UI Responsiveness** - Better order creation/cancellation feedback

### 🔧 Technical Improvements
- Efficient escape sequences reduce message size by 60%+ 
- Heartbeat system ensures reliable guild-wide synchronization
- Automatic purging of old orders when approaching limits
- Color-coded limit warnings (red at limit, orange near limit)
- Graceful handling of oversized orders with user notifications

### 🐛 Bug Fixes
- Fixed sync failures with items containing special characters
- Resolved UI refresh issues when creating/cancelling orders  
- Fixed message queue validation errors
- Improved error handling and user feedback