# Graphiti Cloud Installer

Automated installation scripts for deploying [Graphiti](https://github.com/getzep/graphiti) - a temporal knowledge graph framework for AI agents - on cloud platforms and custom servers.

## Overview

Graphiti Cloud Installer provides one-click deployment scripts that automatically set up Graphiti with MCP (Model Context Protocol) support on:

- **Google Cloud Platform (GCP)**
- **Amazon Web Services (AWS)**
- **Microsoft Azure**
- **Custom servers via SSH**
- **Localhost** with Ollama (no API keys) - see [Local Installation](#local-installation-ollama-no-api-keys)

The installer handles all dependencies, configures Docker containers, sets up the graph database (FalkorDB or Neo4j), and exposes a public MCP endpoint for integration with AI clients like Claude Desktop, Cursor, and VS Code.

## Features

- 🚀 **One-command installation** on multiple platforms
- 🐳 **Docker-based deployment** for consistency and portability
- 🔄 **Choice of graph databases**: FalkorDB (lightweight) or Neo4j (production-grade)
- 🔐 **HTTPS support** with automatic SSL certificate generation
- 🔑 **Multi-LLM support**: OpenAI, Anthropic, Google Gemini, Groq
- 🔁 **Idempotent scripts** - safe to re-run for updates
- 📊 **Health checks** and validation built-in
- 🌐 **Public MCP endpoint** for AI client integration

## Quick Start: MCP Client Configuration

After installing Graphiti on your cloud server, you'll need to configure your AI client to connect to the MCP endpoint.

### 🔒 Important: HTTP vs HTTPS

**By default, your Graphiti server uses HTTP (not HTTPS):**
- **Default URL**: `http://YOUR_SERVER_IP:8000/mcp`
- **HTTPS is optional** and requires a custom domain name

**To enable HTTPS:**
1. Own a domain name (e.g., `graphiti.yourdomain.com`)
2. Point the domain to your server IP (DNS A record)
3. Enter the domain when prompted during installation
4. The script will automatically configure Let's Encrypt SSL

**Security considerations:**
- ✅ **HTTP is fine for**: Testing, development, private networks
- ⚠️ **HTTPS recommended for**: Production, public access, sensitive data

> 💡 **Tip**: For most use cases, HTTP with IP-based access is sufficient. You can always add HTTPS later by re-running the installation and providing a domain.

---

### 📱 Client Configurations

Here are the exact configurations for popular AI clients. **Use HTTP URLs unless you configured a domain during installation.**

### 🤖 Claude Desktop

**Configuration File Location:**
- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
- **Linux**: `~/.config/Claude/claude_desktop_config.json`

**Configuration Format (HTTP - Default):**
```json
{
  "mcpServers": {
    "graphiti": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "http://YOUR_SERVER_IP:8000/mcp/",
        "--allow-http"
      ]
    }
  }
}
```

**For HTTPS (if you configured a domain):**
```json
{
  "mcpServers": {
    "graphiti": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "https://your-domain.com/mcp/"
      ]
    }
  }
}
```

> 📝 **Replace `YOUR_SERVER_IP`** with the IP address shown at the end of installation (e.g., `34.123.45.67`)
> 
> ⚠️ **Important**: The `--allow-http` flag is required for HTTP connections. Remove it when using HTTPS.
> 
> 💡 **What is mcp-remote?** It's a bridge tool that converts between the stdio protocol (used by Claude Desktop) and the HTTP/SSE protocol (used by Graphiti server)

### 💻 Cursor IDE

**Configuration File Location:**
- **macOS**: `~/Library/Application Support/Cursor/User/settings.json`
- **Windows**: `%APPDATA%\Cursor\User\settings.json`
- **Linux**: `~/.config/Cursor/User/settings.json`

**Configuration Format:**
```json
{
  "mcp.servers": {
    "graphiti": {
      "url": "http://YOUR_SERVER_IP:8000",
      "name": "Graphiti Knowledge Graph",
      "enabled": true
    }
  }
}
```

**How to configure:**
1. Open Cursor Settings (`Cmd/Ctrl + ,`)
2. Click "Open Settings (JSON)" in the top right
3. Add the `mcp.servers` configuration
4. Save and reload Cursor

### 🔷 VS Code (with GitHub Copilot)

**Configuration File Location:**
- **macOS**: `~/Library/Application Support/Code/User/settings.json`
- **Windows**: `%APPDATA%\Code\User\settings.json`
- **Linux**: `~/.config/Code/User/settings.json`

**Configuration Format:**
```json
{
  "github.copilot.advanced": {
    "mcp": {
      "enabled": true,
      "servers": {
        "graphiti": {
          "url": "http://YOUR_SERVER_IP:8000",
          "description": "Graphiti temporal knowledge graph"
        }
      }
    }
  }
}
```

**How to configure:**
1. Open VS Code Settings (`Cmd/Ctrl + ,`)
2. Click "Open Settings (JSON)" icon in the top right
3. Add the configuration above
4. Reload VS Code (`Cmd/Ctrl + Shift + P` → "Reload Window")

### 🎯 Kiro IDE

**Configuration File Location:**
- **macOS**: `~/.kiro/settings/mcp.json`
- **Windows**: `%USERPROFILE%\.kiro\settings\mcp.json`
- **Linux**: `~/.kiro/settings/mcp.json`

**Configuration Format:**
```json
{
  "mcpServers": {
    "graphiti": {
      "command": "node",
      "args": [
        "/path/to/mcp-client.js",
        "http://YOUR_SERVER_IP:8000"
      ],
      "env": {},
      "disabled": false,
      "autoApprove": []
    }
  }
}
```

**Alternative: Direct HTTP connection:**
```json
{
  "mcpServers": {
    "graphiti": {
      "url": "http://YOUR_SERVER_IP:8000/mcp",
      "transport": "http",
      "disabled": false
    }
  }
}
```

**How to configure:**
1. Open Command Palette (`Cmd/Ctrl + Shift + P`)
2. Search for "MCP: Open Configuration"
3. Add the Graphiti server configuration
4. Servers reconnect automatically on config changes

### 🌐 OpenAI API / Custom Clients

For custom integrations or OpenAI API-based clients:

**HTTP Endpoint:**
```
http://YOUR_SERVER_IP:8000/mcp
```

**Health Check:**
```bash
curl http://YOUR_SERVER_IP:8000/health
```

**Example cURL request:**
```bash
curl -X POST http://YOUR_SERVER_IP:8000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/list",
    "id": 1
  }'
```

### 🔒 HTTPS Configuration (Optional - Domain Required)

**HTTPS is only available if you provided a domain name during installation.**

During installation, you'll see this prompt:
```
Enter domain name for SSL (leave empty for IP-based access):
```

**If you left it empty** → Use HTTP URLs (examples above)
**If you entered a domain** → Use HTTPS URLs (examples below)

**HTTPS Configuration Example:**
```json
{
  "mcpServers": {
    "graphiti": {
      "url": "https://your-domain.com/mcp",
      "transport": "http"
    }
  }
}
```

**Requirements for HTTPS:**
- ✅ Own a domain name
- ✅ DNS A record pointing to your server IP
- ✅ Domain entered during installation
- ✅ Ports 80 and 443 open in firewall

**What happens with HTTPS:**
- Automatic Let's Encrypt SSL certificate
- HTTP automatically redirects to HTTPS
- Certificate auto-renewal configured
- Secure encrypted connection

### ✅ Testing Your Connection

After configuration, test the connection:

1. **Check health endpoint:**
   ```bash
   # For HTTP (default)
   curl http://YOUR_SERVER_IP:8000/health
   
   # For HTTPS (if domain configured)
   curl https://your-domain.com/health
   ```
   Expected response: `{"status": "healthy"}`

2. **Test MCP endpoint:**
   ```bash
   # For HTTP (default)
   curl http://YOUR_SERVER_IP:8000/mcp
   
   # For HTTPS (if domain configured)
   curl https://your-domain.com/mcp
   ```

3. **Ask your AI client:**
   - "Can you check if the Graphiti MCP server is connected?"
   - "Add an episode to my knowledge graph about learning Python"
   - "What do you know about my preferences?"

> 💡 **Note**: Replace `YOUR_SERVER_IP` with your actual server IP address (provided at the end of installation), or use your domain if you configured HTTPS.

### 🔧 Troubleshooting MCP Connection

**Connection refused:**
- Verify the server IP address is correct
- Check firewall allows ports 80, 443, 8000
- Ensure Docker containers are running: `docker ps`
- **Use HTTP, not HTTPS** (unless you configured a domain)

**"SSL/TLS error" or "Certificate error":**
- ❌ You're using `https://` but didn't configure a domain
- ✅ **Solution**: Use `http://YOUR_SERVER_IP:8000` instead
- HTTPS only works if you provided a domain during installation

**Authentication errors:**
- Verify your LLM API keys are configured in the server's `.env` file
- Check server logs: `docker logs graphiti-mcp`

**MCP not appearing in client:**
- Restart your AI client after configuration
- Check the configuration file syntax (valid JSON)
- Look for errors in the client's console/logs

**"How do I add HTTPS later?"**
- You need to re-run the installation script
- Provide a domain name when prompted
- Ensure DNS points to your server IP first
- Or manually configure Let's Encrypt (advanced)

## Prerequisites

### General Requirements

All installations require:
- **Operating System**: Linux (Ubuntu 20.04+, Debian 10+, CentOS 7+) or macOS
- **Bash**: Version 4.0 or higher
- **Internet Connection**: For downloading Docker images and dependencies
- **At least one LLM API Key**: See [API Key Requirements](#api-key-requirements) below

### Platform-Specific Requirements

#### Google Cloud Platform (GCP)

- **gcloud CLI**: [Installation Guide](https://cloud.google.com/sdk/docs/install)
- **GCP Account**: With billing enabled
- **Permissions**: Compute Engine API enabled, permissions to create instances and firewall rules
- **Recommended Instance**: e2-micro (shared vCPU, 1GB RAM, ~$6/month) for FalkorDB, e2-medium (shared vCPU, 4GB RAM, ~$24/month) for Neo4j

To verify gcloud installation:
```bash
gcloud --version
```

#### Amazon Web Services (AWS)

- **aws CLI**: [Installation Guide](https://aws.amazon.com/cli/)
- **AWS Account**: With active credentials
- **Permissions**: EC2 full access, VPC management permissions
- **Recommended Instance**: t3.micro (2 vCPU, 1GB RAM, ~$7.50/month) for FalkorDB, t3.medium (2 vCPU, 4GB RAM, ~$30/month) for Neo4j

To verify aws CLI installation:
```bash
aws --version
```

#### Microsoft Azure

- **az CLI**: [Installation Guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- **Azure Account**: With active subscription
- **Permissions**: Virtual Machine Contributor role or higher
- **Recommended VM**: Standard_B1s (1 vCPU, 1GB RAM, ~$7.50/month) for FalkorDB, Standard_B2s (2 vCPU, 4GB RAM, ~$30/month) for Neo4j

To verify az CLI installation:
```bash
az --version
```

#### Custom Server (SSH)

- **SSH Client**: Pre-installed on most Linux/macOS systems
- **Server Requirements**:
  - Ubuntu 20.04+ or Debian 10+ (recommended)
  - Minimum 1 vCPU, 1GB RAM for FalkorDB; 2 vCPU, 4GB RAM for Neo4j
  - 20GB available disk space
  - Ports 80, 443, 8000 accessible
  - Root or sudo access
- **SSH Access**: Password or SSH key authentication

To verify SSH client:
```bash
ssh -V
```

### API Key Requirements

You need at least one API key from the following LLM providers:

#### OpenAI
- **Sign up**: https://platform.openai.com/signup
- **Get API Key**: https://platform.openai.com/api-keys
- **Pricing**: Pay-as-you-go, starting at $0.0015/1K tokens

#### Anthropic (Claude)
- **Sign up**: https://console.anthropic.com/
- **Get API Key**: Console → Settings → API Keys
- **Pricing**: Pay-as-you-go, starting at $0.25/1M tokens

#### Google Gemini
- **Sign up**: https://makersuite.google.com/
- **Get API Key**: https://makersuite.google.com/app/apikey
- **Pricing**: Free tier available, then pay-as-you-go

#### Groq
- **Sign up**: https://console.groq.com/
- **Get API Key**: Console → API Keys
- **Pricing**: Free tier available with rate limits

**Security Best Practices for API Keys:**
- Never share your API keys publicly
- Never commit API keys to version control
- Rotate keys regularly
- Use environment variables for storage
- Monitor usage to detect unauthorized access
- Set spending limits on provider dashboards

## Installation

### Step-by-Step: Google Cloud Platform (GCP)

1. **Clone the repository**
   ```bash
   git clone https://github.com/Niels-8/graphiti-cloud-installer.git
   cd graphiti-cloud-installer
   ```

2. **Ensure gcloud CLI is authenticated**
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

3. **Run the installation script**
   ```bash
   chmod +x install-gcp.sh
   ./install-gcp.sh
   ```

4. **Follow the interactive prompts**
   - **GCP Project ID**: Enter your GCP project ID (e.g., `my-project-123`)
   - **Region**: Choose a region (e.g., `us-central1`, `europe-west1`)
   - **Instance Type**: Press Enter for default (e2-micro for cost optimization) or specify custom
   - **Database Type**: Choose `falkordb` (default) or `neo4j`
   - **API Keys**: Enter at least one LLM provider API key
   - **Domain (optional)**: Enter a domain for SSL or press Enter to skip

5. **Wait for installation to complete** (typically 5-10 minutes)
   - The script creates a Compute Engine instance
   - Configures firewall rules (ports 80, 443, 8000)
   - Installs Docker and Docker Compose
   - Deploys Graphiti and database containers
   - Runs health checks

6. **Save your MCP endpoint URL**
   ```
   ✓ Installation complete!
   MCP Endpoint: https://34.123.45.67/mcp/
   Health Check: https://34.123.45.67/health
   ```

7. **Configure your AI client** (see [MCP Client Configuration](#mcp-client-configuration))

### Step-by-Step: Amazon Web Services (AWS)

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-repo/graphiti-cloud-installer.git
   cd graphiti-cloud-installer
   ```

2. **Ensure AWS CLI is configured**
   ```bash
   aws configure
   # Enter your AWS Access Key ID, Secret Access Key, and default region
   ```

3. **Run the installation script**
   ```bash
   chmod +x install-aws.sh
   ./install-aws.sh
   ```

4. **Follow the interactive prompts**
   - **AWS Region**: Choose a region (e.g., `us-east-1`, `eu-west-1`)
   - **Instance Type**: Press Enter for default (t3.micro for cost optimization) or specify custom
   - **Key Pair**: Select an existing key pair or create a new one
   - **Database Type**: Choose `falkordb` (default) or `neo4j`
   - **API Keys**: Enter at least one LLM provider API key
   - **Domain (optional)**: Enter a domain for SSL or press Enter to skip

5. **Wait for installation to complete** (typically 5-10 minutes)
   - The script creates an EC2 instance
   - Configures security groups (ports 80, 443, 8000)
   - Installs Docker and Docker Compose
   - Deploys Graphiti and database containers
   - Runs health checks

6. **Save your MCP endpoint URL**
   ```
   ✓ Installation complete!
   MCP Endpoint: https://ec2-54-123-45-67.compute-1.amazonaws.com/mcp/
   Health Check: https://ec2-54-123-45-67.compute-1.amazonaws.com/health
   ```

7. **Configure your AI client** (see [MCP Client Configuration](#mcp-client-configuration))

### Step-by-Step: Microsoft Azure

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-repo/graphiti-cloud-installer.git
   cd graphiti-cloud-installer
   ```

2. **Ensure Azure CLI is authenticated**
   ```bash
   az login
   az account set --subscription "YOUR_SUBSCRIPTION_ID"
   ```

3. **Run the installation script**
   ```bash
   chmod +x install-azure.sh
   ./install-azure.sh
   ```

4. **Follow the interactive prompts**
   - **Resource Group**: Enter existing or new resource group name
   - **Region**: Choose a region (e.g., `eastus`, `westeurope`)
   - **VM Size**: Press Enter for default (Standard_B1s for cost optimization) or specify custom
   - **Admin Username**: Enter SSH username (default: azureuser)
   - **Database Type**: Choose `falkordb` (default) or `neo4j`
   - **API Keys**: Enter at least one LLM provider API key
   - **Domain (optional)**: Enter a domain for SSL or press Enter to skip

5. **Wait for installation to complete** (typically 5-10 minutes)
   - The script creates a resource group (if needed)
   - Creates an Azure VM
   - Configures network security groups (ports 80, 443, 8000)
   - Installs Docker and Docker Compose
   - Deploys Graphiti and database containers
   - Runs health checks

6. **Save your MCP endpoint URL**
   ```
   ✓ Installation complete!
   MCP Endpoint: https://20.123.45.67/mcp/
   Health Check: https://20.123.45.67/health
   ```

7. **Configure your AI client** (see [MCP Client Configuration](#mcp-client-configuration))

### Step-by-Step: Custom Server (SSH)

1. **Clone the repository on your local machine**
   ```bash
   git clone https://github.com/your-repo/graphiti-cloud-installer.git
   cd graphiti-cloud-installer
   ```

2. **Ensure you have SSH access to your server**
   ```bash
   # Test SSH connection
   ssh user@your-server-ip
   ```

3. **Run the installation script**
   ```bash
   chmod +x install-ssh.sh
   ./install-ssh.sh
   ```

4. **Follow the interactive prompts**
   - **Server IP Address**: Enter your server's IP address
   - **SSH Port**: Press Enter for default (22) or specify custom
   - **SSH Username**: Enter your SSH username
   - **Authentication Method**: Choose `key` or `password`
     - If `key`: Enter path to private key (e.g., `~/.ssh/id_rsa`)
     - If `password`: Enter SSH password when prompted
   - **Database Type**: Choose `falkordb` (default) or `neo4j`
   - **API Keys**: Enter at least one LLM provider API key
   - **Domain (optional)**: Enter a domain for SSL or press Enter to skip

5. **Wait for installation to complete** (typically 5-10 minutes)
   - The script connects to your server via SSH
   - Copies installation files to the server
   - Installs Docker and Docker Compose (if needed)
   - Deploys Graphiti and database containers
   - Runs health checks

6. **Save your MCP endpoint URL**
   ```
   ✓ Installation complete!
   MCP Endpoint: https://your-server-ip/mcp/
   Health Check: https://your-server-ip/health
   ```

7. **Configure your AI client** (see [MCP Client Configuration](#mcp-client-configuration))

### Local Installation (Ollama, no API keys)

Run Graphiti on your own machine with [Ollama](https://ollama.com) providing both the LLM and embeddings. You don't need cloud resources, API keys or nginx/SSL.

1. **Install Ollama and pull the models:**
   ```bash
   ollama pull gpt-oss            # LLM for entity/fact extraction
   ollama pull nomic-embed-text   # Embeddings (768 dimensions)
   ```

2. **Start Graphiti** (Docker Desktop must be running):
   ```bash
   cd docker
   docker compose -f docker-compose-local.yml up -d
   ```

3. **Connect your client** to `http://localhost:8000/mcp`. For Claude Desktop:
   ```json
   {
     "mcpServers": {
       "graphiti": {
         "command": "npx",
         "args": ["-y", "mcp-remote", "http://localhost:8000/mcp"]
       }
     }
   }
   ```

The FalkorDB browser is available at `http://localhost:3000`. Log in with host `localhost`, port `6379` and an empty username/password, then select the `default_db` graph. Ports are bound to `127.0.0.1` only.

The browser needs an `ENCRYPTION_KEY` to log in. If `.env` doesn't set one, a new key is generated on every container start, so you have to log in again after a restart. To keep sessions across restarts, set a fixed key: `echo "ENCRYPTION_KEY=$(openssl rand -hex 32)" >> .env`

**Changing models:** create a `.env` file in the repository root and restart the container:
```bash
MODEL_NAME=qwen3:latest          # Any Ollama chat model that supports structured output
EMBEDDER_MODEL=nomic-embed-text
EMBEDDER_DIMENSIONS=768          # Must match the embedding model
```

When switching embedding models, clear the graph first (`docker compose -f docker-compose-local.yml down -v`), because stored vectors with different dimensions aren't compatible.

**Performance:** each episode takes several LLM calls. On an Apple Silicon Mac with 36 GB RAM, a one-sentence episode took about 2.5 min with `gpt-oss`, 7.5 min with `qwen3` (slow because it reasons before answering) and 1.5 min with `ministral-3` (faster, but it extracted noticeably fewer facts). `add_memory` returns immediately and processing happens in the background.

**Notes:**
- The local setup uses the FalkorDB bundled inside the `zepai/knowledge-graph-mcp` image. The separate `falkordb/falkordb:latest` image is currently newer than the graphiti-core version in the MCP image, and startup fails with `Received 5 arguments to procedure 'db.idx.fulltext.createNodeIndex'`.
- `docker/config-local-ollama.yaml` is mounted over the image's `config/config.yaml`, because the server always loads that path.

### Database Selection

During installation, you'll be prompted to choose between two graph databases:

**FalkorDB (Default - Recommended for getting started)**
- Lightweight and fast startup
- Lower resource requirements (1 vCPU, 1GB RAM minimum)
- Ideal for development and small deployments
- Built on Redis with integrated web interface
- **Cost-effective**: Works well on shared-core instances (~$6-12/month)

**Neo4j (Production-grade)**
- Mature and battle-tested
- Better performance for large graphs (>100k nodes)
- Advanced administration tools
- Requires more resources (2 vCPU, 4GB RAM minimum, 8GB recommended for production)
- **Higher cost**: Requires dedicated instances (~$24-60/month)

## Configuration

### Environment Variables

After installation, your configuration is stored in `.env` in the installation directory. This file contains sensitive information and should never be committed to version control.

**Complete `.env` file structure:**

```bash
# ============================================
# LLM Provider API Keys
# ============================================
# At least one API key is required for Graphiti to function
# You can configure multiple providers and switch between them

# OpenAI
OPENAI_API_KEY=sk-proj-...

# Anthropic
ANTHROPIC_API_KEY=sk-ant-api03-...

# Google Gemini
GOOGLE_API_KEY=AIza...

# Groq (Fast inference for Llama, Mistral)
GROQ_API_KEY=gsk_...

# ============================================
# Database Configuration
# ============================================
# Choose between FalkorDB (lightweight) or Neo4j (production)
DATABASE_TYPE=falkordb

# FalkorDB Configuration (default)
FALKORDB_URI=redis://falkordb:6379

# Neo4j Configuration (alternative)
NEO4J_URI=bolt://neo4j:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=your-secure-password-here

# ============================================
# Server Configuration
# ============================================
# Maximum concurrent operations (adjust based on server resources)
SEMAPHORE_LIMIT=10

# Disable telemetry for privacy
GRAPHITI_TELEMETRY_ENABLED=false

# ============================================
# SSL/Domain Configuration
# ============================================
# Optional: Configure custom domain for HTTPS
DOMAIN_NAME=

# ============================================
# Advanced Configuration (Optional)
# ============================================
# Logging level: DEBUG, INFO, WARNING, ERROR
LOG_LEVEL=INFO

# MCP server port (default: 8000)
MCP_PORT=8000
```

### API Key Configuration Details

#### OpenAI Configuration

**How to obtain:**
1. Sign up at https://platform.openai.com/signup
2. Navigate to https://platform.openai.com/api-keys
3. Click "Create new secret key"
4. Copy the key (starts with `sk-proj-` or `sk-`)
5. Add to `.env`: `OPENAI_API_KEY=sk-proj-your-key-here`

**Pricing:** Pay-as-you-go, ~$0.01-0.03 per 1K tokens depending on model

**Rate Limits:** 
- Free tier: 3 requests/minute
- Paid tier: 3,500+ requests/minute

#### Anthropic (Claude) Configuration

**How to obtain:**
1. Sign up at https://console.anthropic.com/
2. Go to Settings → API Keys
3. Click "Create Key"
4. Copy the key (starts with `sk-ant-api03-`)
5. Add to `.env`: `ANTHROPIC_API_KEY=sk-ant-api03-your-key-here`

**Pricing:** Pay-as-you-go, ~$0.25-15 per 1M tokens depending on model

**Rate Limits:**
- Tier 1: 50 requests/minute
- Higher tiers available with usage

#### Google Gemini Configuration

**How to obtain:**
1. Go to https://makersuite.google.com/
2. Click "Get API Key"
3. Create or select a Google Cloud project
4. Copy the API key (starts with `AIza`)
5. Add to `.env`: `GOOGLE_API_KEY=AIzaYour-Key-Here`

**Pricing:** 
- Free tier: 60 requests/minute
- Paid: ~$0.125-0.50 per 1M tokens

**Rate Limits:**
- Free tier: 60 requests/minute
- Paid tier: Higher limits available

#### Groq Configuration

**How to obtain:**
1. Sign up at https://console.groq.com/
2. Navigate to API Keys section
3. Click "Create API Key"
4. Copy the key (starts with `gsk_`)
5. Add to `.env`: `GROQ_API_KEY=gsk_your-key-here`

**Pricing:** 
- Free tier available with generous limits
- Very fast inference (up to 750 tokens/second)

**Rate Limits:**
- Free tier: 30 requests/minute
- Paid tier: Higher limits available

### Switching Between LLM Providers

Graphiti automatically uses the latest recommended models for each provider. To switch providers, simply ensure the corresponding API key is set in your `.env` file. Graphiti will handle model selection automatically.

### Security Best Practices for API Keys

1. **Never commit API keys to version control**
   ```bash
   # Ensure .env is in .gitignore
   echo ".env" >> .gitignore
   ```

2. **Use environment-specific keys**
   - Development: Use separate API keys with lower rate limits
   - Production: Use dedicated keys with monitoring

3. **Rotate keys regularly**
   - Rotate every 90 days or after team member changes
   - Keep old keys active briefly during rotation

4. **Set spending limits**
   - OpenAI: Set monthly budget limits in dashboard
   - Anthropic: Configure usage alerts
   - Monitor usage regularly

5. **Restrict key permissions**
   - Use read-only keys where possible
   - Limit key scope to specific APIs

6. **Monitor for unauthorized usage**
   - Check provider dashboards regularly
   - Set up usage alerts
   - Review API logs for suspicious patterns

7. **Secure the `.env` file**
   ```bash
   # Set restrictive permissions
   chmod 600 .env
   
   # Verify permissions
   ls -la .env
   # Should show: -rw------- (only owner can read/write)
   ```

8. **Use secrets management for production**
   - AWS: AWS Secrets Manager
   - GCP: Secret Manager
   - Azure: Key Vault
   - HashiCorp Vault for multi-cloud

### Updating Configuration

To update your configuration after installation:

1. **Edit the `.env` file:**
   ```bash
   nano .env
   # or
   vim .env
   ```

2. **Restart affected containers:**
   ```bash
   # Restart all services
   docker compose restart
   
   # Or restart specific service
   docker restart graphiti-mcp
   ```

3. **Verify changes:**
   ```bash
   # Check container logs
   docker logs graphiti-mcp
   
   # Test health endpoint
   curl http://localhost:8000/health
   ```

## MCP Client Configuration

After installation, configure your AI client to connect to the Graphiti MCP server. Replace `YOUR_SERVER_IP` with the actual IP address or domain provided at the end of installation.

### Claude Desktop

Claude Desktop is a native application that supports MCP servers.

**Configuration Location:**
- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
- **Linux**: `~/.config/Claude/claude_desktop_config.json`

**Steps:**

1. Open the configuration file in a text editor:
   ```bash
   # macOS
   nano ~/Library/Application\ Support/Claude/claude_desktop_config.json
   
   # Linux
   nano ~/.config/Claude/claude_desktop_config.json
   ```

2. Add the Graphiti MCP server configuration:
   ```json
   {
     "mcpServers": {
       "graphiti": {
         "command": "npx",
         "args": [
           "mcp-remote",
           "http://YOUR_SERVER_IP:8000/mcp/",
           "--allow-http"
         ]
       }
     }
   }
   ```

3. If you already have other MCP servers configured, add Graphiti to the existing list:
   ```json
   {
     "mcpServers": {
       "existing-server": {
         "command": "npx",
         "args": ["some-other-mcp-server"]
       },
       "graphiti": {
         "command": "npx",
         "args": [
           "mcp-remote",
           "http://YOUR_SERVER_IP:8000/mcp/",
           "--allow-http"
         ]
       }
     }
   }
   ```
   
   **For HTTPS (if you configured a domain):**
   ```json
   {
     "mcpServers": {
       "graphiti": {
         "command": "npx",
         "args": [
           "mcp-remote",
           "https://your-domain.com/mcp/"
         ]
       }
     }
   }
   ```

4. Save the file and restart Claude Desktop

5. Verify the connection by asking Claude: "Can you check if the Graphiti MCP server is connected?"

**Example configuration file:** See [examples/mcp-client-configs/claude_desktop_config.json](examples/mcp-client-configs/claude_desktop_config.json)

### Cursor IDE

Cursor is an AI-powered code editor with MCP support.

**Configuration Location:**
- **macOS**: `~/Library/Application Support/Cursor/User/settings.json`
- **Windows**: `%APPDATA%\Cursor\User\settings.json`
- **Linux**: `~/.config/Cursor/User/settings.json`

**Steps:**

1. Open Cursor Settings (Cmd/Ctrl + ,)

2. Click on "Open Settings (JSON)" in the top right corner

3. Add the MCP server configuration:
   ```json
   {
     "mcp.servers": {
       "graphiti": {
         "url": "https://YOUR_SERVER_IP/mcp/",
         "name": "Graphiti Knowledge Graph",
         "enabled": true
       }
     }
   }
   ```

4. Save the file (Cursor will automatically reload)

5. Verify the connection in the Cursor MCP panel (View → MCP Servers)

**Example configuration file:** See [examples/mcp-client-configs/cursor_mcp_config.json](examples/mcp-client-configs/cursor_mcp_config.json)

### VS Code with GitHub Copilot

VS Code with GitHub Copilot can connect to MCP servers for enhanced context.

**Configuration Location:**
- **macOS**: `~/Library/Application Support/Code/User/settings.json`
- **Windows**: `%APPDATA%\Code\User\settings.json`
- **Linux**: `~/.config/Code/User/settings.json`

**Steps:**

1. Open VS Code Settings (Cmd/Ctrl + ,)

2. Click on "Open Settings (JSON)" in the top right corner

3. Add the MCP server configuration:
   ```json
   {
     "github.copilot.advanced": {
       "mcp": {
         "enabled": true,
         "servers": {
           "graphiti": {
             "url": "https://YOUR_SERVER_IP/mcp/",
             "description": "Graphiti temporal knowledge graph"
           }
         }
       }
     }
   }
   ```

4. Save the file and reload VS Code (Cmd/Ctrl + Shift + P → "Reload Window")

5. Verify the connection in the Output panel (View → Output → GitHub Copilot)

**Example configuration file:** See [examples/mcp-client-configs/vscode_mcp_settings.json](examples/mcp-client-configs/vscode_mcp_settings.json)

### Testing Your MCP Connection

After configuring your client, test the connection:

1. **Check the health endpoint:**
   ```bash
   curl https://YOUR_SERVER_IP/health
   ```
   Expected response: `{"status": "healthy"}`

2. **Test the MCP endpoint:**
   ```bash
   curl https://YOUR_SERVER_IP/mcp/
   ```
   Expected response: MCP server information

3. **Use the test script:**
   ```bash
   ./examples/test-mcp-connection.sh YOUR_SERVER_IP
   ```

4. **Ask your AI client to interact with Graphiti:**
   - "Can you add an episode to my knowledge graph about learning Python?"
   - "What do you know about my preferences?"
   - "Search my knowledge graph for information about AI"

## Architecture

```
┌─────────────────┐
│   AI Client     │
│ (Claude/Cursor) │
└────────┬────────┘
         │ MCP Protocol
         ▼
┌─────────────────┐
│  NGINX Proxy    │
│  (SSL/HTTPS)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Graphiti MCP    │
│    Server       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Graph Database │
│ FalkorDB/Neo4j  │
└─────────────────┘
```

## Troubleshooting

### Common Installation Errors

#### Error: "gcloud/aws/az command not found"

**Problem:** The required cloud CLI tool is not installed or not in PATH.

**Solution:**
- **GCP**: Install gcloud CLI from https://cloud.google.com/sdk/docs/install
- **AWS**: Install aws CLI from https://aws.amazon.com/cli/
- **Azure**: Install az CLI from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli

After installation, verify:
```bash
gcloud --version  # or aws --version, or az --version
```

#### Error: "Authentication failed"

**Problem:** Cloud credentials are not configured or have expired.

**Solution:**
```bash
# GCP
gcloud auth login
gcloud config set project YOUR_PROJECT_ID

# AWS
aws configure
# Enter your Access Key ID and Secret Access Key

# Azure
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

#### Error: "Insufficient permissions"

**Problem:** Your cloud account lacks permissions to create resources.

**Solution:**
- **GCP**: Ensure you have "Compute Engine Admin" role
- **AWS**: Ensure you have "EC2 Full Access" and "VPC Full Access"
- **Azure**: Ensure you have "Virtual Machine Contributor" role

Contact your cloud administrator to grant necessary permissions.

#### Error: "Docker installation failed"

**Problem:** The automatic Docker installation encountered an error.

**Solution:** Manually install Docker:
```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# CentOS/RHEL
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker

# Verify installation
docker --version
docker compose version
```

#### Error: "Port 8000 already in use"

**Problem:** Another service is using port 8000.

**Solution:**
```bash
# Find the process using port 8000
sudo lsof -i :8000

# Stop the conflicting service or modify docker-compose.yml to use a different port
# Edit docker/docker-compose-*.yml and change "8000:8000" to "8001:8000"
```

#### Error: "SSH connection refused"

**Problem:** Cannot connect to the remote server via SSH.

**Solution:**
1. Verify the server IP address is correct
2. Check SSH port (default 22):
   ```bash
   telnet YOUR_SERVER_IP 22
   ```
3. Verify SSH credentials:
   ```bash
   ssh -v user@YOUR_SERVER_IP
   ```
4. Check firewall allows SSH (port 22)
5. Ensure SSH service is running on the server:
   ```bash
   sudo systemctl status sshd
   ```

#### Error: "API key validation failed"

**Problem:** The provided API key is invalid or incorrectly formatted.

**Solution:**
1. Verify the API key on the provider's dashboard:
   - OpenAI: https://platform.openai.com/api-keys
   - Anthropic: https://console.anthropic.com/
   - Google: https://makersuite.google.com/app/apikey
   - Groq: https://console.groq.com/
2. Ensure there are no extra spaces or characters
3. Check that the API key has not expired
4. Verify you have sufficient credits/quota

### Runtime Issues

#### Cannot connect to MCP endpoint

**Problem:** AI client cannot reach the MCP server.

**Solution:**
1. Check that all containers are running:
   ```bash
   docker ps
   ```
   You should see: `graphiti-mcp`, `falkordb` (or `neo4j`), and `nginx-proxy`

2. Verify the health endpoint:
   ```bash
   curl http://localhost:8000/health
   ```
   Expected: `{"status": "healthy"}`

3. Check firewall rules allow ports 80, 443, and 8000:
   ```bash
   # GCP
   gcloud compute firewall-rules list
   
   # AWS
   aws ec2 describe-security-groups
   
   # Azure
   az network nsg rule list --resource-group YOUR_RG --nsg-name YOUR_NSG
   ```

4. Test from external network:
   ```bash
   curl https://YOUR_SERVER_IP/health
   ```

5. Check nginx logs:
   ```bash
   docker logs nginx-proxy
   ```

#### Database connection errors

**Problem:** Graphiti cannot connect to the graph database.

**Solution:**

**For FalkorDB:**
```bash
# Check FalkorDB container status
docker ps | grep falkordb

# View FalkorDB logs
docker logs falkordb

# Test FalkorDB connection
curl http://localhost:3000  # Web interface
docker exec -it falkordb redis-cli PING  # Should return PONG

# Restart FalkorDB
docker restart falkordb
```

**For Neo4j:**
```bash
# Check Neo4j container status
docker ps | grep neo4j

# View Neo4j logs
docker logs neo4j

# Test Neo4j connection
curl http://localhost:7474  # Neo4j Browser
docker exec -it neo4j cypher-shell -u neo4j -p YOUR_PASSWORD "RETURN 1;"

# Restart Neo4j
docker restart neo4j
```

#### High memory usage

**Problem:** Server is running out of memory.

**Solution:**
1. Check current memory usage:
   ```bash
   free -h
   docker stats
   ```

2. For FalkorDB (lighter option):
   - Minimum 1GB RAM recommended (2GB for better performance)
   - No configuration changes needed

3. For Neo4j (requires more memory):
   - Minimum 4GB RAM recommended (8GB for production)
   - Adjust heap size in `docker/docker-compose-neo4j.yml`:
     ```yaml
     environment:
       - NEO4J_dbms_memory_heap_initial__size=512m
       - NEO4J_dbms_memory_heap_max__size=2G
     ```
   - Restart containers:
     ```bash
     docker compose -f docker/docker-compose-neo4j.yml restart
     ```

4. Consider upgrading to a larger instance type

#### SSL certificate errors

**Problem:** HTTPS is not working or certificate is invalid.

**Solution:**
1. Verify domain DNS points to your server IP:
   ```bash
   nslookup YOUR_DOMAIN
   ```

2. Regenerate SSL certificate:
   ```bash
   sudo certbot --nginx -d YOUR_DOMAIN
   ```

3. Check certificate expiration:
   ```bash
   sudo certbot certificates
   ```

4. Ensure automatic renewal is enabled:
   ```bash
   sudo systemctl status certbot.timer
   ```

### Frequently Asked Questions (FAQ)

#### Q: Can I use multiple LLM providers simultaneously?

**A:** Yes! You can configure multiple API keys in your `.env` file. Graphiti will use the provider specified in `config.yaml` (default: OpenAI).

#### Q: How do I switch from FalkorDB to Neo4j?

**A:** 
1. Stop current containers: `docker compose down`
2. Backup your data if needed
3. Update `.env`: Set `DATABASE_TYPE=neo4j`
4. Start with Neo4j compose file: `docker compose -f docker/docker-compose-neo4j.yml up -d`

#### Q: Can I run this on my local machine?

**A:** Yes! Use the SSH installation method with `localhost` or `127.0.0.1` as the server IP. You'll need Docker installed locally.

#### Q: How much does it cost to run on cloud platforms?

**A:**
- **GCP**: ~$6-12/month for e2-micro/e2-small (FalkorDB), ~$24-49/month for e2-medium/e2-standard-2 (Neo4j)
- **AWS**: ~$7.50-15/month for t3.micro/t3.small (FalkorDB), ~$30-60/month for t3.medium/t3.large (Neo4j)
- **Azure**: ~$7.50-15/month for Standard_B1s/B1ms (FalkorDB), ~$30-60/month for Standard_B2s/B2ms (Neo4j)
- Plus LLM API costs (varies by usage)
- **Tip**: Use shared-core/burstable instances for significant cost savings

#### Q: Is my data secure?

**A:** Yes. Your knowledge graph data stays on your server and is never sent to third parties. Only LLM API calls go to your chosen provider. Use HTTPS and strong passwords for production.

#### Q: Can I customize the Graphiti configuration?

**A:** Yes! Edit `config.yaml` to customize:
- LLM provider and model
- Embedder settings
- Entity types
- Graph behavior

After changes, restart containers:
```bash
docker compose restart
```

#### Q: How do I backup my knowledge graph?

**A:**
```bash
# FalkorDB (Redis-based)
docker exec falkordb redis-cli SAVE
docker cp falkordb:/data/dump.rdb ./backup-$(date +%Y%m%d).rdb

# Neo4j
docker exec neo4j neo4j-admin dump --database=neo4j --to=/tmp/backup.dump
docker cp neo4j:/tmp/backup.dump ./backup-$(date +%Y%m%d).dump
```

#### Q: How do I restore from a backup?

**A:**
```bash
# FalkorDB
docker cp ./backup.rdb falkordb:/data/dump.rdb
docker restart falkordb

# Neo4j
docker cp ./backup.dump neo4j:/tmp/backup.dump
docker exec neo4j neo4j-admin load --from=/tmp/backup.dump --database=neo4j --force
docker restart neo4j
```

#### Q: Can I use a custom domain?

**A:** Yes! During installation, provide your domain name when prompted. Ensure:
1. Domain DNS A record points to your server IP
2. Ports 80 and 443 are accessible
3. The installer will automatically configure SSL with Let's Encrypt

#### Q: How do I update to the latest Graphiti version?

**A:** Re-run the installation script and choose "Update existing installation" when prompted. This will pull the latest Docker images while preserving your data and configuration.

### Getting Help

If you're still experiencing issues:

1. **Check the logs:**
   ```bash
   # Installation log
   cat /var/log/graphiti-install.log
   
   # Container logs
   docker logs graphiti-mcp
   docker logs falkordb  # or neo4j
   docker logs nginx-proxy
   ```

2. **Run the validation script:**
   ```bash
   ./common/validate.sh
   ```

3. **Search existing issues:**
   - GitHub Issues: https://github.com/your-repo/graphiti-cloud-installer/issues
   - Graphiti Issues: https://github.com/getzep/graphiti/issues

4. **Create a new issue:**
   - Include your OS and platform (GCP/AWS/Azure/SSH)
   - Include relevant log excerpts
   - Describe steps to reproduce the problem
   - Mention what you've already tried

5. **Community support:**
   - Graphiti Documentation: https://github.com/getzep/graphiti
   - MCP Protocol Docs: https://modelcontextprotocol.io/
   - Discord/Slack: [Link to community channels]

## Updating

To update an existing installation:

```bash
# Re-run the installation script
./install-<platform>.sh

# When prompted, choose "Update existing installation"
```

The update will:
- Pull the latest Graphiti Docker images
- Restart containers with new images
- Preserve your existing configuration and data

## Uninstalling

To completely remove Graphiti:

```bash
./common/uninstall.sh
```

This will:
- Stop and remove all Docker containers
- Remove Docker volumes (with confirmation)
- Remove installation files

**Note:** Cloud resources (VMs, instances) must be deleted manually through your cloud provider's console.

## Security Best Practices

1. **API Keys**: Never commit `.env` files to version control
2. **SSL/HTTPS**: Always use HTTPS for production deployments
3. **Firewall**: Restrict access to known IP addresses when possible
4. **Passwords**: Use strong passwords for Neo4j and other services
5. **Updates**: Regularly update to the latest Graphiti version

## Support

- **Graphiti Documentation**: https://github.com/getzep/graphiti
- **MCP Protocol**: https://modelcontextprotocol.io/
- **Issues**: https://github.com/your-repo/graphiti-cloud-installer/issues

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Graphiti](https://github.com/getzep/graphiti) by Zep AI
- [FalkorDB](https://www.falkordb.com/) for the lightweight graph database
- [Neo4j](https://neo4j.com/) for the production-grade graph database
- [Model Context Protocol](https://modelcontextprotocol.io/) by Anthropic
