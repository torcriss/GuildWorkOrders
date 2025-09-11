# GuildWorkOrders

A comprehensive guild-wide work order management system for World of Warcraft Classic Era.

## Features

- 🔇 **Hidden Communication** - Uses addon messages only (no guild chat spam)
- 🔄 **Auto-Synchronization** - Real-time sync between all guild members with the addon
- 🎯 **Smart Parsing** - Automatically detects WTB/WTS messages from guild chat
- 📱 **Simplified UI** - Single comprehensive interface showing all orders with enhanced layout
- 📢 **Guild Chat G Button** - One-click guild announcements for ACTIVE/EXPIRED orders
- ⚡ **Real-time Updates** - Orders update instantly across all users with 3-second heartbeat system
- 🛡️ **Six-State Lifecycle** - Robust order management with proper state transitions
- 🔐 **Heartbeat Admin Clear** - Guild-wide order clearing via heartbeat relay system
- ⏰ **12-Hour Order Lifecycle** - Orders automatically expire after 12 hours for realistic trading
- 🔧 **Automatic Cleanup** - Smart cleanup system prevents database bloat
- 📊 **Status Indicators** - Real-time display of your orders and database usage
- 💬 **Whisper Integration** - One-click whisper button for completed orders between buyers and sellers

## Installation

1. Download the latest release from GitHub
2. Extract to your `World of Warcraft\_classic_era_\Interface\AddOns\` directory
3. Enable "GuildWorkOrders" in the AddOns menu
4. Reload your UI or restart WoW

## Usage

### Main Interface
- `/gwo` or `/workorders` - Open the simplified UI
- Single comprehensive view showing all orders with Type, Item, Player, Quantity, Price, Time, Status, Action columns
- Use the search box to find specific items
- Click "New Order" to create WTB/WTS orders
- Click "G" button to announce ACTIVE/EXPIRED orders to guild chat
- Click "Whisper" to contact players about their completed orders
- Action buttons for canceling your orders or fulfilling others' orders

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
/gwo debug                             # Toggle debug mode
/gwo config                            # Open configuration
```

### Admin Management
The admin clear system has been enhanced to use the heartbeat relay network:

**Admin Clear (All Orders):**
- **Admin Button** - Red "Admin" button in the UI status bar
- **Heartbeat-Based** - Uses the heartbeat relay system for reliable propagation
- **Network Resilient** - Orders marked as CLEARED propagate even if admin goes offline
- **Global Effect** - All orders transition to CLEARED status across all guild members
- **Full Tracking** - Shows "Last clear: X ago by PlayerName" in status bar

**Key Benefits:**
- No immediate broadcast flooding
- Leverages existing heartbeat infrastructure
- More reliable than previous immediate broadcast system
- Orders propagate through established 3-second heartbeat cycle

## How It Works

### Six-State Order Lifecycle
GuildWorkOrders uses a sophisticated 6-state system for order management:

1. **ACTIVE** - Newly created orders, visible to all players
2. **EXPIRED** - Orders that exceeded the 12-hour time limit
3. **CANCELLED** - Orders manually cancelled by the player
4. **COMPLETED** - Orders marked as fulfilled by the player  
5. **CLEARED** - Orders removed by admin action via heartbeat system
6. **PURGED** - Internal cleanup state before permanent deletion

**State Transitions:**
- Active orders automatically expire after 12 hours
- Non-active orders (expired/cancelled/completed/cleared) transition to PURGED after 18 hours
- PURGED orders are deleted after broadcasting for 24 hours total
- All state changes sync instantly across all guild members

### Synchronization
- Orders are synchronized between guild members using hidden addon messages
- No guild chat spam - all communication is invisible to non-addon users
- **3-Second Heartbeat System** - Continuous rotating broadcasts ensure all users stay synchronized
- **Instant New Order Sync** - New orders broadcast immediately to all users
- **Advanced State Management** - Proper handling of all 6 order states with timestamps
- **Network Reliability** - Two-stage deletion with PURGED state prevents data loss
- **Rate Limiting** - Prevents flooding with intelligent batching and timing

### Order Parsing
The addon automatically detects WTB/WTS patterns in guild chat:
- **WTB patterns**: "WTB", "LF", "looking for", "need", "buying", "ISO"
- **WTS patterns**: "WTS", "selling", "for sale", "have X for", "anyone need"
- Extracts item links, quantities, and prices automatically
- Only processes messages containing actual items

### Order Management
- **Realistic Timing** - 12-hour order lifecycle for production trading
- **Automatic Cleanup** - Time-based cleanup prevents database bloat
- **Order Actions** - Players can cancel or mark their own orders as completed
- **Full History** - Complete tracking of completed orders with status details
- **Advanced Search** - Search and filter functionality with real-time updates
- **Heartbeat Admin Clear** - Network-resilient clearing via heartbeat relay system

## Configuration

Access configuration via `/gwo config` or through the UI:

- **announceToGuild** - Announce new orders to guild chat (default: false)
- **autoSync** - Auto-sync on login (default: true)
- **soundAlert** - Play sound for new orders (default: true)
- **debugMode** - Enable debug logging (default: false)
- **orderExpiry** - Order expiry time in seconds (default: 43200 = 12 hours)
- **syncTimeout** - Sync timeout in seconds (default: 30)

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
    ├── Sync.lua                 # 3-second heartbeat synchronization protocol
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
- Check the wiki for advanced usage tips

## License

MIT License - see LICENSE file for details

---

**GuildWorkOrders v4.5.0** - Making guild trading easier with enhanced UI and guild chat integration! 🛒

## Recent Updates (v4.5.0)

### 📢 New Guild Chat "G" Button
- **Quick Announce** - New "G" button in Action column for ACTIVE and EXPIRED orders
- **Smart Positioning** - 25x20 button positioned next to action buttons
- **Message Format** - Uses same WTB/WTS format as "Also announce guild chat" feature
- **Tooltip Support** - Helpful tooltip explaining functionality
- **Status Aware** - Only appears for orders that can be announced

### 🎨 Simplified Interface  
- **Single View** - Removed Buy Orders, Sell Orders, and My Orders tabs
- **Unified Display** - All orders now shown in one comprehensive table
- **Better Layout** - Optimized positioning with Type, Item, Player, Quantity, Price, Time, Status, Action columns
- **Streamlined Navigation** - No more tab switching required
- **Cleaner Experience** - All functionality accessible from single interface

### 🛡️ Enhanced Admin Clear System
- **Heartbeat-Based Admin Clear** - Admin clear now uses the heartbeat relay system instead of immediate broadcast
- **Network Resilient** - Orders marked as CLEARED propagate through heartbeat system even when admin goes offline
- **Better Synchronization** - All players receive cleared orders through the established 3-second heartbeat relay network
- **Removed Legacy Broadcast** - Eliminated immediate CLEAR_ALL message type for cleaner architecture

### 🔧 Improved Conflict Resolution
- **Status Priority System** - When versions are equal, higher priority status wins (CLEARED=3, COMPLETED=3, CANCELLED/EXPIRED=2, ACTIVE=1, PURGED=4)
- **Version Conflict Fix** - Resolved issues where same version orders with different statuses caused conflicts
- **Enhanced Debug Logging** - Added comprehensive debug messages for troubleshooting sync issues
- **Cleaner Message Handling** - Removed unused CLEAR_ALL message handlers and functions

### 🐛 Bug Fixes
- **Fixed UI Syntax Error** - Resolved Lua syntax error from tab removal process
- **Cleaned Up Code** - Removed obsolete tab functions and duplicate code blocks
- **Improved Status Transitions** - Better handling of status changes through heartbeat system
- **Fixed Orphaned Code** - Removed duplicate action button logic that caused syntax errors

## Previous Updates (v4.4.0)

### ⚡ Enhanced Synchronization
- **3-Second Heartbeat System** - Optimized network traffic with faster 3-second intervals for better responsiveness
- **Improved Conflict Resolution** - Better handling of version conflicts with status priority system
- **Enhanced Debug Logging** - Comprehensive debug messages for troubleshooting sync issues

## Previous Updates (v4.3.0)

### ⚙️ Production-Ready Configuration
- **12-Hour Order Lifecycle** - Orders now expire after 12 hours for realistic trading
- **Extended Cleanup Cycles** - Non-active orders transition to PURGED after 18 hours
- **24-Hour Broadcast Window** - PURGED orders broadcast for 24 hours before deletion
- **Optimized for Guild Use** - All timing settings adjusted for production guild environments

## Previous Updates (v4.2.0)

### 💬 New Whisper Integration
- **Whisper Button for Completed Orders** - One-click whisper button appears for completed orders
- **Smart Message Formatting** - Clean whisper messages with item name, quantity, and price details
- **Bidirectional Communication** - Both buyers and sellers can whisper each other about completed trades
- **Graceful Fallbacks** - Handles missing quantity or price information elegantly
- **All Tabs Support** - Whisper button available in All Orders, My Orders, and filtered tabs

## Previous Updates (v4.1.0)

### 🐛 Critical Bug Fixes
- **Fixed Order Expiration for Offline Creators** - Non-creators can now expire orders from offline players
- **Fixed Expired Order Relay** - Expired orders are now properly relayed by all guild members  
- **Fixed PURGED Order Sync Loop** - Prevents infinite delete/re-sync cycles with timestamp checks
- **Fixed PURGED Order Relay** - PURGED orders from all players are now relayed for proper network cleanup
- **Fixed Initialization Crash** - Added nil checks for Config during startup to prevent crashes

### ⚡ Enhanced Network Reliability
- **Offline Creator Support** - Orders continue their lifecycle even when creator goes offline
- **Improved PURGED Order Handling** - Better network-wide propagation of cleanup states
- **Timestamp-Based Rejection** - PURGED orders older than 24 hours are rejected to prevent re-sync
- **Robust State Management** - All order states now transition properly regardless of creator status

## Previous Updates (v4.0.0)

### 🚀 Six-State Order Lifecycle System
- **Complete System Overhaul** - Revolutionary 6-state order management system
- **ACTIVE → EXPIRED/CANCELLED/COMPLETED/CLEARED → PURGED → Deleted** - Proper state transitions
- **12-Hour Order Lifecycle** - Orders expire after 12 hours for realistic trading
- **Two-Stage Deletion** - PURGED state ensures network-wide order removal reliability
- **Heartbeat-Only Synchronization** - Continuous rotating broadcasts eliminate sync gaps

### ⚡ Enhanced Network Protocol  
- **19-Field Heartbeat Messages** - Complete order state with all timestamps
- **Instant State Propagation** - All order changes sync immediately across guild members
- **Network Reliability** - PURGED orders broadcast for 24 hours total before deletion
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