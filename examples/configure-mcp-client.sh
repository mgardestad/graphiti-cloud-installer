#!/bin/bash

# MCP Client Configuration Helper
# This script helps configure MCP clients with your Graphiti server IP

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Graphiti MCP Client Configuration Helper${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Prompt for server IP
read -p "Enter your Graphiti server IP address: " SERVER_IP

if [ -z "$SERVER_IP" ]; then
    echo -e "${RED}Error: Server IP is required${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Server IP: $SERVER_IP${NC}"
echo ""

# Prompt for client type
echo "Select your AI client:"
echo "  1) Claude Desktop"
echo "  2) Cursor IDE"
echo "  3) VS Code (with GitHub Copilot)"
echo "  4) Kiro IDE"
echo "  5) Show all configurations"
echo ""

read -p "Enter your choice (1-5): " CHOICE

case "$CHOICE" in
    1)
        CLIENT="Claude Desktop"
        CONFIG_FILE="claude_desktop_config.json"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            DEST_PATH="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            DEST_PATH="$HOME/.config/Claude/claude_desktop_config.json"
        else
            DEST_PATH="%APPDATA%\\Claude\\claude_desktop_config.json"
        fi
        ;;
    2)
        CLIENT="Cursor IDE"
        CONFIG_FILE="cursor_settings.json"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            DEST_PATH="$HOME/Library/Application Support/Cursor/User/settings.json"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            DEST_PATH="$HOME/.config/Cursor/User/settings.json"
        else
            DEST_PATH="%APPDATA%\\Cursor\\User\\settings.json"
        fi
        ;;
    3)
        CLIENT="VS Code"
        CONFIG_FILE="vscode_settings.json"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            DEST_PATH="$HOME/Library/Application Support/Code/User/settings.json"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            DEST_PATH="$HOME/.config/Code/User/settings.json"
        else
            DEST_PATH="%APPDATA%\\Code\\User\\settings.json"
        fi
        ;;
    4)
        CLIENT="Kiro IDE"
        CONFIG_FILE="kiro_mcp.json"
        if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "linux-gnu"* ]]; then
            DEST_PATH="$HOME/.kiro/settings/mcp.json"
        else
            DEST_PATH="%USERPROFILE%\\.kiro\\settings\\mcp.json"
        fi
        ;;
    5)
        echo ""
        echo -e "${YELLOW}=== All Configurations ===${NC}"
        echo ""
        
        for config in claude_desktop_config.json cursor_settings.json vscode_settings.json kiro_mcp.json; do
            echo -e "${GREEN}$config:${NC}"
            sed "s/YOUR_SERVER_IP/$SERVER_IP/g" "$(dirname "$0")/mcp-client-configs/$config"
            echo ""
        done
        
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${YELLOW}Configuration for $CLIENT:${NC}"
echo ""

# Generate configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/mcp-client-configs/$CONFIG_FILE"

if [ ! -f "$CONFIG_PATH" ]; then
    echo -e "${RED}Error: Configuration file not found: $CONFIG_PATH${NC}"
    exit 1
fi

# Replace SERVER_IP and display
sed "s/YOUR_SERVER_IP/$SERVER_IP/g" "$CONFIG_PATH"

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Copy the configuration above"
echo "2. Open your client's configuration file:"
echo -e "   ${GREEN}$DEST_PATH${NC}"
echo "3. Merge or replace with the configuration above"
echo "4. Restart your AI client"
echo ""
echo -e "${YELLOW}Or use this command to copy automatically:${NC}"
echo ""

if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "mkdir -p \"$(dirname "$DEST_PATH")\""
    echo "sed 's/YOUR_SERVER_IP/$SERVER_IP/g' \"$CONFIG_PATH\" > \"$DEST_PATH\""
else
    echo "Copy manually on Windows"
fi

echo ""
echo -e "${YELLOW}Test your connection:${NC}"
echo "  curl http://$SERVER_IP:8000/health"
echo ""
echo -e "${GREEN}Done!${NC}"
