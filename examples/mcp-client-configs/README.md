# MCP Client Configuration Examples

This directory contains example configuration files for connecting various AI clients to your Graphiti MCP server.

## 📋 Available Configurations

### Claude Desktop
- **File**: `claude_desktop_config.json`
- **Location**: 
  - macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
  - Windows: `%APPDATA%\Claude\claude_desktop_config.json`
  - Linux: `~/.config/Claude/claude_desktop_config.json`
- **Note**: Uses `npx mcp-remote` to bridge stdio and HTTP/SSE protocols

### Cursor IDE
- **File**: `cursor_settings.json`
- **Location**:
  - macOS: `~/Library/Application Support/Cursor/User/settings.json`
  - Windows: `%APPDATA%\Cursor\User\settings.json`
  - Linux: `~/.config/Cursor/User/settings.json`

### VS Code (with GitHub Copilot)
- **File**: `vscode_settings.json`
- **Location**:
  - macOS: `~/Library/Application Support/Code/User/settings.json`
  - Windows: `%APPDATA%\Code\User\settings.json`
  - Linux: `~/.config/Code/User/settings.json`

### Kiro IDE
- **File**: `kiro_mcp.json`
- **Location**:
  - macOS/Linux: `~/.kiro/settings/mcp.json`
  - Windows: `%USERPROFILE%\.kiro\settings\mcp.json`

## 🚀 How to Use

1. **Install Graphiti** on your cloud server using one of the installation scripts:
   ```bash
   ./install-gcp.sh
   # or ./install-aws.sh
   # or ./install-azure.sh
   # or ./install-ssh.sh
   ```

2. **Note your server IP** from the installation output

3. **Copy the appropriate config file** for your AI client

4. **Replace `YOUR_SERVER_IP`** with your actual server IP address

5. **Merge or replace** the configuration in your client's settings file

6. **Restart your AI client** to apply the changes

## 📝 Example: Configuring Claude Desktop

```bash
# 1. Copy the example config
cp examples/mcp-client-configs/claude_desktop_config.json ~/Library/Application\ Support/Claude/claude_desktop_config.json

# 2. Edit the file and replace YOUR_SERVER_IP
# macOS:
sed -i '' 's/YOUR_SERVER_IP/34.123.45.67/g' ~/Library/Application\ Support/Claude/claude_desktop_config.json

# Linux:
sed -i 's/YOUR_SERVER_IP/34.123.45.67/g' ~/.config/Claude/claude_desktop_config.json

# 3. Restart Claude Desktop
```

## 🔒 HTTP vs HTTPS

**By default, Graphiti uses HTTP (not HTTPS):**
- Default URL: `http://YOUR_SERVER_IP:8000/mcp/`
- Requires `--allow-http` flag for Claude Desktop
- This is fine for testing, development, and private networks

**HTTPS is optional and requires:**
1. A domain name (e.g., `graphiti.yourdomain.com`)
2. DNS A record pointing to your server IP
3. Entering the domain during installation

**Claude Desktop Configuration Examples:**

```json
// HTTP (default) - Note the --allow-http flag
{
  "mcpServers": {
    "graphiti": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "http://34.123.45.67:8000/mcp/",
        "--allow-http"
      ]
    }
  }
}

// HTTPS (if domain configured) - No --allow-http needed
{
  "mcpServers": {
    "graphiti": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "https://graphiti.mycompany.com/mcp/"
      ]
    }
  }
}
```

## ✅ Testing Your Connection

After configuration, test the connection:

```bash
# Check health endpoint
curl http://YOUR_SERVER_IP:8000/health

# Test MCP endpoint
curl http://YOUR_SERVER_IP:8000/mcp
```

Then ask your AI client:
- "Can you check if the Graphiti MCP server is connected?"
- "Add an episode to my knowledge graph about learning Python"

## 🔧 Troubleshooting

**Connection refused:**
- Verify the server IP is correct
- Check firewall allows port 8000
- Ensure Docker containers are running: `docker ps`

**MCP not appearing:**
- Restart your AI client
- Check JSON syntax is valid
- Look for errors in client logs

**Authentication errors:**
- Verify LLM API keys in server's `.env` file
- Check server logs: `docker logs graphiti-mcp`

## 📚 More Information

For detailed installation and configuration instructions, see the main [README.md](../../README.md).
