# GuildWorkOrders

A comprehensive guild-wide work order management system for World of Warcraft Classic Era.

## Features

- 🔇 **Hidden Communication** - Uses addon messages only (no guild chat spam)
- 🔄 **Auto-Synchronization** - Real-time sync between all guild members with the addon
- 🎯 **Smart Parsing** - Automatically detects WTB/WTS messages from guild chat
- 📱 **Full UI** - Tabbed interface for managing all orders
- ⚡ **Real-time Updates** - Orders update instantly across all users
- 🛡️ **Conflict Resolution** - Handles network issues and duplicate orders
- ⏰ **Auto-Expiry** - Orders automatically expire after 24 hours
- 📢 **Optional Announcements** - Can announce new orders to guild chat if desired

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
- Automatic conflict resolution handles network issues
- Rate limiting prevents flooding (max 5 messages per second)

### Order Parsing
The addon automatically detects WTB/WTS patterns in guild chat:
- **WTB patterns**: "WTB", "LF", "looking for", "need", "buying", "ISO"
- **WTS patterns**: "WTS", "selling", "for sale", "have X for", "anyone need"
- Extracts item links, quantities, and prices automatically
- Only processes messages containing actual items

### Order Management
- Orders expire after 24 hours automatically
- Players can cancel or mark their own orders as fulfilled
- Full history tracking of completed orders
- Search and filter functionality

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
    ├── Database.lua             # Order storage and management
    ├── Parser.lua               # WTB/WTS message parsing
    ├── Sync.lua                 # Guild synchronization protocol
    ├── UI.lua                   # User interface
    └── Commands.lua             # Slash command system
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

**GuildWorkOrders v1.0.0** - Making guild trading easier, one order at a time! 🛒