# GuildWorkOrders

A comprehensive guild-wide work order management system for World of Warcraft Classic Era.

## Features

- 🔇 **Hidden Communication** - Uses addon messages only (no guild chat spam)
- 🔄 **Auto-Synchronization** - Real-time sync between all guild members with the addon
- 🎯 **Smart Parsing** - Automatically detects WTB/WTS messages from guild chat
- 📱 **Enhanced UI** - Tabbed interface with type column and improved order management
- ⚡ **Real-time Updates** - Orders update instantly across all users with heartbeat system
- 🛡️ **Six-State Lifecycle** - Robust order management with proper state transitions
- 🔐 **Admin Clear System** - Password-protected guild-wide order clearing with full tracking
- ⏰ **1-Minute Order Lifecycle** - Orders automatically expire after 1 minute for rapid turnover
- 📢 **Optional Announcements** - Can announce new orders to guild chat if desired
- 🔧 **Automatic Cleanup** - Smart cleanup system prevents database bloat
- 📊 **Status Indicators** - Real-time display of your orders and database usage
- 💬 **Whisper Integration** - One-click whisper button for completed orders between buyers and sellers

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
/gwo fulfill 2                         # Mark your order #2 as completed
/gwo sync                              # Force sync with guild
/gwo help                              # Show all commands
```

### Admin Management
Access the password-protected admin clear system:

**Full Clear (All Orders):**
- **Admin Button** - Red "Admin" button in the UI status bar
- **Password**: `0000` (hashed and secured)
- **Two-Step Process**: Password entry + final confirmation
- **Global Effect**: Clears ALL orders for ALL guild members
- **Full Tracking**: Shows "Last clear: X ago by PlayerName" in status bar
- **Offline Protection**: Users who missed the clear get updated when they return

**Single Order Clear:**
- **Individual "X" Buttons** - Red "X" button next to each order on all tabs
- **Same Password**: Uses `0000` password with same security system
- **Selective Clearing**: Remove specific problematic orders without affecting others
- **Universal Access**: Available on Buy Orders, Sell Orders, My Orders, and History tabs
- **Smart Positioning**: Buttons positioned to avoid overlapping columns

**Security Features**:
- Failed attempt lockout (30 seconds after 3 tries)
- Password authentication for all admin actions
- Multiple confirmation dialogs with warnings
- Real-time status updates across all guild members

## How It Works

### Six-State Order Lifecycle
GuildWorkOrders uses a sophisticated 6-state system for order management:

1. **ACTIVE** - Newly created orders, visible to all players
2. **EXPIRED** - Orders that exceeded the 1-minute time limit
3. **CANCELLED** - Orders manually cancelled by the player
4. **COMPLETED** - Orders marked as fulfilled by the player  
5. **CLEARED** - Orders removed by admin action
6. **PURGED** - Internal cleanup state before permanent deletion

**State Transitions:**
- Active orders automatically expire after 1 minute
- Non-active orders (expired/cancelled/completed/cleared) transition to PURGED after 2 minutes
- PURGED orders are deleted after broadcasting for 4 minutes total
- All state changes sync instantly across all guild members

### Synchronization
- Orders are synchronized between guild members using hidden addon messages
- No guild chat spam - all communication is invisible to non-addon users
- **3-Second Heartbeat System** - Continuous rotating broadcasts ensure all users stay synchronized
- **Instant New Order Sync** - New orders broadcast immediately to all users
- **Advanced State Management** - Proper handling of all 6 order states with timestamps
- **Network Reliability** - Two-stage deletion with PURGED state prevents data loss
- **Rate Limiting** - Prevents flooding (max 5 messages per second with intelligent batching)

### Order Parsing
The addon automatically detects WTB/WTS patterns in guild chat:
- **WTB patterns**: "WTB", "LF", "looking for", "need", "buying", "ISO"
- **WTS patterns**: "WTS", "selling", "for sale", "have X for", "anyone need"
- Extracts item links, quantities, and prices automatically
- Only processes messages containing actual items

### Order Management
- **Rapid Turnover** - 1-minute order lifecycle for active trading
- **Automatic Cleanup** - Time-based cleanup prevents database bloat
- **Order Actions** - Players can cancel or mark their own orders as completed
- **Full History** - Complete tracking of completed orders with status details
- **Advanced Search** - Search and filter functionality with real-time updates
- **Admin Clear System** - Password-protected clearing with timestamp tracking

## Configuration

Access configuration via `/gwo config` or through the UI:

- **announceToGuild** - Announce new orders to guild chat (default: false)
- **autoSync** - Auto-sync on login (default: true)
- **soundAlert** - Play sound for new orders (default: true)
- **debugMode** - Enable debug logging (default: false)
- **orderExpiry** - Order expiry time in seconds (default: 60 = 1 minute)

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
    ├── Database.lua             # Six-state order management system
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

**GuildWorkOrders v4.1.0** - Making guild trading easier, one order at a time! 🛒

## Recent Updates (v4.1.0)

### 💬 New Whisper Integration
- **Whisper Button for Completed Orders** - One-click whisper button appears for completed orders
- **Smart Message Formatting** - Clean whisper messages with item name, quantity, and price details
- **Bidirectional Communication** - Both buyers and sellers can whisper each other about completed trades
- **Graceful Fallbacks** - Handles missing quantity or price information elegantly
- **All Tabs Support** - Whisper button available in All Orders, My Orders, and filtered tabs

## Previous Updates (v4.0.1)

### 🐛 Critical Bug Fixes
- **Fixed Order Expiration for Offline Creators** - Non-creators can now expire orders from offline players
- **Fixed Expired Order Relay** - Expired orders are now properly relayed by all guild members  
- **Fixed PURGED Order Sync Loop** - Prevents infinite delete/re-sync cycles with timestamp checks
- **Fixed PURGED Order Relay** - PURGED orders from all players are now relayed for proper network cleanup
- **Fixed Initialization Crash** - Added nil checks for Config during startup to prevent crashes

### ⚡ Enhanced Network Reliability
- **Offline Creator Support** - Orders continue their lifecycle even when creator goes offline
- **Improved PURGED Order Handling** - Better network-wide propagation of cleanup states
- **Timestamp-Based Rejection** - PURGED orders older than 4 minutes are rejected to prevent re-sync
- **Robust State Management** - All order states now transition properly regardless of creator status

## Previous Updates (v4.0.0)

### 🚀 Six-State Order Lifecycle System
- **Complete System Overhaul** - Revolutionary 6-state order management system
- **ACTIVE → EXPIRED/CANCELLED/COMPLETED/CLEARED → PURGED → Deleted** - Proper state transitions
- **1-Minute Order Lifecycle** - Orders expire after 1 minute for rapid turnover
- **Two-Stage Deletion** - PURGED state ensures network-wide order removal reliability
- **Heartbeat-Only Synchronization** - Continuous 3-second rotating broadcasts eliminate sync gaps

### ⚡ Enhanced Network Protocol  
- **19-Field Heartbeat Messages** - Complete order state with all timestamps
- **Instant State Propagation** - All order changes sync immediately across guild members
- **Network Reliability** - PURGED orders broadcast for 4 minutes total before deletion
- **Zero Data Loss** - Robust conflict resolution prevents order desynchronization
- **Automatic Cleanup** - 30-second periodic cleanup timer maintains system health

### 🎨 Improved User Experience
- **Real-Time Status Updates** - Orders update instantly in UI across all users
- **Hidden PURGED Orders** - Clean UI experience while maintaining network reliability
- **Status Consistency** - All users see identical order states and timing
- **Enhanced Debug System** - Comprehensive logging for troubleshooting network issues

### 🛠️ Technical Improvements
- **Single Database Architecture** - Simplified from dual database to unified order storage
- **Timestamp-Based State Management** - Precise order lifecycle tracking with multiple timestamps
- **Legacy Compatibility Removed** - Clean implementation without backward compatibility overhead
- **Performance Optimized** - Efficient cleanup cycles and reduced memory footprint

### 🐛 Critical Bug Fixes
- **Fixed Cancelled Orders Not Syncing** - Orders cancelled by one user now immediately sync to all users
- **Fixed Expired Orders Disappearing** - Expired orders properly display across all guild members
- **Fixed Heartbeat Reception Issues** - Resolved heartbeats being sent but not received
- **Fixed Orders Not Purging** - Added missing periodic cleanup timer for proper order lifecycle
- **Fixed PURGED Orders Never Deleting** - Complete timestamp tracking for reliable deletion
- **Fixed UI Not Updating** - Added refresh calls after all cleanup cycles

## Previous Updates

See git history for complete changelog of previous versions.