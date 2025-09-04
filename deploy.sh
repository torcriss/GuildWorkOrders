#!/bin/bash

# Deploy script for GuildWorkOrders addon
# Copies all addon files to WoW Classic Era AddOns directory

# Detect operating system
OS_TYPE=$(uname -s)

# Set source directory to current directory
SOURCE_DIR="$(pwd)"

# Set destination path based on operating system
case "$OS_TYPE" in
    "Darwin")
        # macOS
        DEST_DIR="/Applications/World of Warcraft/_classic_era_/Interface/AddOns/GuildWorkOrders"
        ;;
    "MINGW"*|"CYGWIN"*|"MSYS"*)
        # Windows (Git Bash, Cygwin, etc.)
        DEST_DIR="/c/Program Files (x86)/World of Warcraft/_classic_era_/Interface/AddOns/GuildWorkOrders"
        ;;
    *)
        # Default fallback (Linux or other)
        echo "Unsupported operating system: $OS_TYPE"
        echo "Please manually set the WoW AddOns directory path."
        exit 1
        ;;
esac

echo "Deploying GuildWorkOrders addon..."
echo "Source: $SOURCE_DIR"
echo "Destination: $DEST_DIR"

# Create destination directory if it doesn't exist
if [ ! -d "$DEST_DIR" ]; then
    echo "Creating destination directory..."
    mkdir -p "$DEST_DIR"
fi

# Copy all addon files
echo "Copying addon files..."
cp -r "$SOURCE_DIR"/* "$DEST_DIR"/

# Verify files were copied
if [ -f "$DEST_DIR/GuildWorkOrders.toc" ]; then
    echo "✓ GuildWorkOrders.toc copied"
else
    echo "✗ Failed to copy GuildWorkOrders.toc"
    exit 1
fi

if [ -f "$DEST_DIR/GuildWorkOrders.lua" ]; then
    echo "✓ GuildWorkOrders.lua copied"
else
    echo "✗ Failed to copy GuildWorkOrders.lua"
    exit 1
fi

if [ -d "$DEST_DIR/modules" ]; then
    echo "✓ modules directory copied"
    echo "  - $(ls -1 "$DEST_DIR/modules" | wc -l) module files"
else
    echo "✗ Failed to copy modules directory"
    exit 1
fi

# List copied files for verification
echo ""
echo "Deployed files:"
echo "Main files:"
find "$DEST_DIR" -maxdepth 1 -name "*.lua" -o -name "*.toc" | sort
echo ""
echo "Module files:"
find "$DEST_DIR/modules" -name "*.lua" | sort

# pCloud sync disabled for Windows environment

echo ""
echo "Deployment complete! 🚀"
echo ""
echo "To test the addon:"
echo "1. Start WoW Classic Era"
echo "2. Check AddOns list - GuildWorkOrders should be available"
echo "3. Enable the addon and enter the game"
echo "4. Type /gwo help for commands"
echo "5. Type /gwo to open the UI"
echo ""
echo "Debug commands:"
echo "  /gwo debug     - Toggle debug mode"
echo "  /gwo stats     - Show statistics"
echo "  /gwo sync      - Force sync"
echo ""