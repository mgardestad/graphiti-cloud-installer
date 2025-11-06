#!/bin/bash

# Graphiti Installation Module
# Core installation logic shared across all platforms
# This script provides functions to install Docker, setup Graphiti, configure environment,
# select database, start services, and verify installation

set -euo pipefail

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Installation directories
readonly INSTALL_DIR="${INSTALL_DIR:-/opt/graphiti}"
readonly DOCKER_DIR="${INSTALL_DIR}/docker"
readonly TEMPLATES_DIR="${SCRIPT_DIR}/../templates"

# ============================================================================
# Docker Compose Helper
# ============================================================================

# docker_compose_cmd() - Get the correct docker compose command
# Returns "docker compose" (v2) or "docker-compose" (v1)
docker_compose_cmd() {
    if docker compose version &> /dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    else
        log "ERROR" "Docker Compose not found"
        return 1
    fi
}

# ============================================================================
# Docker Installation Functions
# ============================================================================

# install_docker() - Install Docker and Docker Compose
# This function detects the OS and installs Docker accordingly
# Supports: Ubuntu, Debian, CentOS, RHEL, Amazon Linux
install_docker() {
    log "INFO" "Starting Docker installation..."
    
    # Check if Docker is already installed
    if check_command docker; then
        local docker_version
        docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        log "INFO" "Docker is already installed (version: $docker_version)"
        
        # Check if Docker daemon is running
        if ! docker ps &> /dev/null; then
            log "WARNING" "Docker daemon is not running, attempting to start..."
            sudo systemctl start docker || {
                log "ERROR" "Failed to start Docker daemon"
                return 1
            }
        fi
    else
        log "INFO" "Docker not found, installing..."
        
        # Detect OS
        if [ -f /etc/os-release ]; then
            source /etc/os-release
            OS=$ID
        else
            log "ERROR" "Cannot detect OS, /etc/os-release not found"
            return 1
        fi
        
        case "$OS" in
            ubuntu|debian)
                install_docker_debian
                ;;
            centos|rhel|amzn)
                install_docker_rhel
                ;;
            *)
                log "ERROR" "Unsupported OS: $OS"
                return 1
                ;;
        esac
    fi
    
    # Check if Docker Compose is installed
    if docker compose version &> /dev/null; then
        log "INFO" "Docker Compose is already installed"
    elif check_command docker-compose; then
        log "INFO" "Docker Compose (v1) is installed"
        # Create alias for v2 syntax
        alias docker-compose='docker compose'
    else
        log "INFO" "Installing Docker Compose..."
        install_docker_compose
    fi
    
    # Add current user to docker group
    if ! groups | grep -q docker; then
        log "INFO" "Adding current user to docker group..."
        sudo usermod -aG docker "$USER" || log "WARNING" "Failed to add user to docker group"
    fi
    
    # Enable Docker service
    sudo systemctl enable docker
    sudo systemctl start docker
    
    log "INFO" "Docker installation completed successfully"
    return 0
}

# install_docker_debian() - Install Docker on Debian/Ubuntu
install_docker_debian() {
    log "INFO" "Installing Docker on Debian/Ubuntu..."
    
    # Update package index
    sudo apt-get update
    
    # Install prerequisites
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    log "INFO" "Docker installed successfully on Debian/Ubuntu"
}

# install_docker_rhel() - Install Docker on RHEL/CentOS/Amazon Linux
install_docker_rhel() {
    log "INFO" "Installing Docker on RHEL/CentOS/Amazon Linux..."
    
    # Install prerequisites
    sudo yum install -y yum-utils
    
    # Add Docker repository
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    # Install Docker Engine
    sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    log "INFO" "Docker installed successfully on RHEL/CentOS"
}

# install_docker_compose() - Install Docker Compose standalone
install_docker_compose() {
    log "INFO" "Installing Docker Compose standalone..."
    
    local compose_version="v2.24.0"
    local compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)"
    
    sudo curl -L "$compose_url" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    log "INFO" "Docker Compose installed successfully"
}

# ============================================================================
# Installation Detection Functions
# ============================================================================

# detect_existing_installation() - Check if Graphiti is already installed
# This function checks for existing Docker containers and Graphiti files
# Returns:
#   0 if existing installation found
#   1 if no installation found
detect_existing_installation() {
    log "INFO" "Checking for existing Graphiti installation..."
    
    local has_containers=false
    local has_files=false
    local installation_type=""
    
    # Check if Docker containers are running
    if check_command docker && docker ps &> /dev/null; then
        if docker ps -a | grep -q "graphiti-mcp"; then
            has_containers=true
            log "INFO" "Found existing Graphiti Docker containers"
            
            # Determine which database is being used
            if docker ps -a | grep -q "neo4j"; then
                installation_type="neo4j"
                log "INFO" "Detected Neo4j database"
            elif docker ps -a | grep -q "falkordb"; then
                installation_type="falkordb"
                log "INFO" "Detected FalkorDB database"
            fi
        fi
    fi
    
    # Check if Graphiti files exist
    if [ -d "$INSTALL_DIR" ]; then
        has_files=true
        log "INFO" "Found existing Graphiti installation directory: $INSTALL_DIR"
        
        # Check for configuration files
        if [ -f "${INSTALL_DIR}/.env" ]; then
            log "INFO" "Found existing .env configuration"
            
            # Try to determine database type from .env if not already detected
            if [ -z "$installation_type" ] && grep -q "^DATABASE_TYPE=" "${INSTALL_DIR}/.env"; then
                installation_type=$(grep "^DATABASE_TYPE=" "${INSTALL_DIR}/.env" | cut -d'=' -f2)
                log "INFO" "Database type from .env: $installation_type"
            fi
        fi
        
        if [ -f "${INSTALL_DIR}/config.yaml" ]; then
            log "INFO" "Found existing config.yaml"
        fi
    fi
    
    # Export installation type for use by other functions
    if [ -n "$installation_type" ]; then
        export EXISTING_DATABASE_TYPE="$installation_type"
    fi
    
    # Return status
    if [ "$has_containers" = true ] || [ "$has_files" = true ]; then
        log "INFO" "Existing installation detected"
        return 0
    else
        log "INFO" "No existing installation found"
        return 1
    fi
}

# prompt_installation_action() - Ask user what to do with existing installation
# This function prompts the user to update, reinstall, or cancel
# Returns:
#   "update" - Update existing installation
#   "reinstall" - Remove and reinstall
#   "cancel" - Cancel installation
prompt_installation_action() {
    log "INFO" "Existing Graphiti installation detected"
    
    echo ""
    echo "An existing Graphiti installation was found."
    echo "What would you like to do?"
    echo ""
    echo "  1) Update - Pull latest images and restart (preserves data and config)"
    echo "  2) Reinstall - Remove everything and start fresh"
    echo "  3) Cancel - Exit without making changes"
    echo ""
    
    local choice
    choice=$(prompt_user "Enter your choice (1, 2, or 3)" "1")
    
    case "$choice" in
        1|u|U|update)
            echo "update"
            ;;
        2|r|R|reinstall)
            echo "reinstall"
            ;;
        3|c|C|cancel|*)
            echo "cancel"
            ;;
    esac
}

# ============================================================================
# Graphiti Setup Functions
# ============================================================================

# setup_graphiti() - Clone Graphiti repo and copy files
# This function sets up the Graphiti installation directory structure
setup_graphiti() {
    log "INFO" "Setting up Graphiti installation..."
    
    # Check for existing installation
    if detect_existing_installation; then
        local action
        action=$(prompt_installation_action)
        
        case "$action" in
            update)
                log "INFO" "Updating existing installation..."
                export INSTALLATION_MODE="update"
                return 0
                ;;
            reinstall)
                log "INFO" "Reinstalling - removing existing installation..."
                export INSTALLATION_MODE="reinstall"
                
                # Stop and remove containers
                stop_existing_containers
                
                # Remove installation directory
                log "INFO" "Removing installation directory..."
                sudo rm -rf "$INSTALL_DIR"
                ;;
            cancel)
                log "INFO" "Installation cancelled by user"
                exit 0
                ;;
        esac
    else
        export INSTALLATION_MODE="fresh"
    fi
    
    # Create directory structure (for fresh install or reinstall)
    if [ "$INSTALLATION_MODE" != "update" ]; then
        log "INFO" "Creating directory structure..."
        sudo mkdir -p "$INSTALL_DIR"
        sudo mkdir -p "${DOCKER_DIR}/nginx/ssl"
        sudo chown -R "$USER:$USER" "$INSTALL_DIR"
        
        # Copy Docker configuration files
        log "INFO" "Copying Docker configuration files..."
        cp -r "${SCRIPT_DIR}/../docker/"* "${DOCKER_DIR}/"
        
        # Copy templates
        log "INFO" "Copying configuration templates..."
        cp "${TEMPLATES_DIR}/.env.template" "${INSTALL_DIR}/.env.template"
        cp "${TEMPLATES_DIR}/config.yaml.template" "${INSTALL_DIR}/config.yaml"
    fi
    
    log "INFO" "Graphiti setup completed successfully"
    return 0
}

# stop_existing_containers() - Stop and remove existing Docker containers
# This function stops all Graphiti-related containers
stop_existing_containers() {
    log "INFO" "Stopping existing Docker containers..."
    
    # Try to stop containers using docker-compose if compose files exist
    if [ -d "$DOCKER_DIR" ]; then
        cd "$DOCKER_DIR"
        
        # Try both compose files
        for compose_file in docker-compose-falkordb.yml docker-compose-neo4j.yml; do
            if [ -f "$compose_file" ]; then
                log "INFO" "Stopping containers from $compose_file..."
                docker-compose -f "$compose_file" down -v 2>/dev/null || true
            fi
        done
    fi
    
    # Fallback: stop containers by name
    log "INFO" "Stopping containers by name..."
    for container in graphiti-mcp falkordb neo4j nginx-proxy; do
        if docker ps -a | grep -q "$container"; then
            log "INFO" "Stopping container: $container"
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
        fi
    done
    
    log "INFO" "Existing containers stopped"
}

# ============================================================================
# Environment Configuration Functions
# ============================================================================

# configure_env() - Create .env from template with user input
# This function prompts the user for API keys and configuration
configure_env() {
    log "INFO" "Configuring environment variables..."
    
    local env_file="${INSTALL_DIR}/.env"
    local source_env="/tmp/graphiti-installer/.env"
    
    # In update mode, preserve existing configuration
    if [ "${INSTALLATION_MODE:-fresh}" = "update" ]; then
        if [ -f "$env_file" ]; then
            log "INFO" "Update mode: Preserving existing .env configuration"
            return 0
        else
            log "WARNING" "Update mode but no .env found, creating new configuration"
        fi
    fi
    
    # Check if .env already exists (for fresh/reinstall modes)
    if [ -f "$env_file" ]; then
        log "INFO" "Existing .env file found"
        local response
        response=$(prompt_user "Do you want to keep existing configuration? (y/n)" "y")
        
        if [[ "$response" =~ ^[Yy] ]]; then
            log "INFO" "Keeping existing .env configuration"
            return 0
        fi
    fi
    
    # Check if we have a pre-configured .env from the installer
    if [ -f "$source_env" ]; then
        log "INFO" "Using pre-configured .env file from installer"
        cp "$source_env" "$env_file"
        log "INFO" "✓ API keys configured from local .env file"
        
        # Configure additional server settings
        local semaphore_limit="10"
        local domain=""
        
        if [ -t 0 ]; then
            # Interactive mode
            semaphore_limit=$(prompt_user "Enter semaphore limit" "10")
            domain=$(prompt_user "Enter domain name for SSL (leave empty for IP-based access)" "")
        else
            # Non-interactive mode - use defaults
            log "INFO" "Non-interactive mode: Using default semaphore limit (10)"
            log "INFO" "Non-interactive mode: No domain configured (HTTP only)"
        fi
        
        # Add or update semaphore limit if not already in file
        if grep -q "^SEMAPHORE_LIMIT=" "$env_file"; then
            sed -i "s|^SEMAPHORE_LIMIT=.*|SEMAPHORE_LIMIT=${semaphore_limit}|" "$env_file"
        else
            echo "SEMAPHORE_LIMIT=${semaphore_limit}" >> "$env_file"
        fi
        if [ -n "$domain" ]; then
            if grep -q "^DOMAIN_NAME=" "$env_file"; then
                sed -i "s|^DOMAIN_NAME=.*|DOMAIN_NAME=${domain}|" "$env_file"
            else
                echo "DOMAIN_NAME=${domain}" >> "$env_file"
            fi
        fi
        
        return 0
    fi
    
    # Fallback: Start with template and prompt for keys (for SSH installations)
    log "INFO" "No pre-configured .env found, using interactive configuration"
    cp "${INSTALL_DIR}/.env.template" "$env_file"
    
    log "INFO" "Please provide API keys for LLM providers (at least one is required)"
    log "INFO" "Press Enter to skip a provider"
    
    # Prompt for API keys
    local openai_key anthropic_key google_key groq_key
    local has_valid_key=false
    
    # OpenAI
    openai_key=$(prompt_user "Enter OpenAI API key (starts with sk-)" "" "secret")
    if [ -n "$openai_key" ]; then
        if validate_api_key "openai" "$openai_key"; then
            sed -i "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=${openai_key}|" "$env_file"
            has_valid_key=true
        fi
    fi
    
    # Anthropic
    anthropic_key=$(prompt_user "Enter Anthropic API key (starts with sk-ant-)" "" "secret")
    if [ -n "$anthropic_key" ]; then
        if validate_api_key "anthropic" "$anthropic_key"; then
            sed -i "s|^ANTHROPIC_API_KEY=.*|ANTHROPIC_API_KEY=${anthropic_key}|" "$env_file"
            has_valid_key=true
        fi
    fi
    
    # Google
    google_key=$(prompt_user "Enter Google API key" "" "secret")
    if [ -n "$google_key" ]; then
        if validate_api_key "google" "$google_key"; then
            sed -i "s|^GOOGLE_API_KEY=.*|GOOGLE_API_KEY=${google_key}|" "$env_file"
            has_valid_key=true
        fi
    fi
    
    # Groq
    groq_key=$(prompt_user "Enter Groq API key (starts with gsk_)" "" "secret")
    if [ -n "$groq_key" ]; then
        if validate_api_key "groq" "$groq_key"; then
            sed -i "s|^GROQ_API_KEY=.*|GROQ_API_KEY=${groq_key}|" "$env_file"
            has_valid_key=true
        fi
    fi
    
    # Check if at least one API key was provided
    if [ "$has_valid_key" = false ]; then
        log "ERROR" "At least one valid API key is required"
        return 1
    fi
    
    # Configure server settings
    local semaphore_limit
    semaphore_limit=$(prompt_user "Enter semaphore limit" "10")
    sed -i "s|^SEMAPHORE_LIMIT=.*|SEMAPHORE_LIMIT=${semaphore_limit}|" "$env_file"
    
    # Ask about domain for SSL
    local domain
    domain=$(prompt_user "Enter domain name for SSL (leave empty for IP-based access)" "")
    if [ -n "$domain" ]; then
        sed -i "s|^DOMAIN_NAME=.*|DOMAIN_NAME=${domain}|" "$env_file"
    fi
    
    log "INFO" "Environment configuration completed successfully"
    return 0
}

# ============================================================================
# Database Selection Functions
# ============================================================================

# select_database() - Prompt user for FalkorDB or Neo4j
# This function lets the user choose which graph database to use
select_database() {
    log "INFO" "Selecting graph database..."
    
    # In update mode, use existing database type
    if [ "${INSTALLATION_MODE:-fresh}" = "update" ]; then
        if [ -n "${EXISTING_DATABASE_TYPE:-}" ]; then
            log "INFO" "Update mode: Using existing database type: $EXISTING_DATABASE_TYPE"
            export DATABASE_TYPE="$EXISTING_DATABASE_TYPE"
            return 0
        elif grep -q "^DATABASE_TYPE=" "${INSTALL_DIR}/.env" 2>/dev/null; then
            DATABASE_TYPE=$(grep "^DATABASE_TYPE=" "${INSTALL_DIR}/.env" | cut -d'=' -f2)
            log "INFO" "Update mode: Using database type from .env: $DATABASE_TYPE"
            export DATABASE_TYPE
            return 0
        else
            log "WARNING" "Update mode but cannot determine database type, prompting user"
        fi
    fi
    
    # Check if running non-interactively (e.g., via SSH command)
    local choice="1"  # Default to FalkorDB
    
    if [ -t 0 ]; then
        # Interactive mode - prompt user
        echo ""
        echo "Choose a graph database:"
        echo "  1) FalkorDB (default, lightweight, fast startup)"
        echo "  2) Neo4j (production-ready, better for large graphs)"
        echo ""
        
        choice=$(prompt_user "Enter your choice (1 or 2)" "1")
    else
        # Non-interactive mode - use default
        log "INFO" "Non-interactive mode detected, using default database (FalkorDB)"
    fi
    
    case "$choice" in
        1)
            log "INFO" "Selected FalkorDB"
            echo "DATABASE_TYPE=falkordb" >> "${INSTALL_DIR}/.env"
            export DATABASE_TYPE="falkordb"
            ;;
        2)
            log "INFO" "Selected Neo4j"
            echo "DATABASE_TYPE=neo4j" >> "${INSTALL_DIR}/.env"
            export DATABASE_TYPE="neo4j"
            
            # Configure Neo4j password
            local neo4j_password
            neo4j_password=$(prompt_user "Enter Neo4j password" "graphiti123" "secret")
            sed -i "s|^NEO4J_PASSWORD=.*|NEO4J_PASSWORD=${neo4j_password}|" "${INSTALL_DIR}/.env"
            
            # Update config.yaml for Neo4j
            sed -i 's|provider: "falkordb"|provider: "neo4j"|' "${INSTALL_DIR}/config.yaml"
            ;;
        *)
            log "WARNING" "Invalid choice, defaulting to FalkorDB"
            echo "DATABASE_TYPE=falkordb" >> "${INSTALL_DIR}/.env"
            export DATABASE_TYPE="falkordb"
            ;;
    esac
    
    log "INFO" "Database selection completed"
    return 0
}

# ============================================================================
# Service Management Functions
# ============================================================================

# update_installation() - Update existing Graphiti installation
# This function pulls latest images and restarts containers while preserving data
update_installation() {
    log "INFO" "Updating Graphiti installation..."
    
    # Determine which docker-compose file to use
    local compose_file
    if [ "${DATABASE_TYPE:-falkordb}" = "neo4j" ]; then
        compose_file="${DOCKER_DIR}/docker-compose-neo4j.yml"
        log "INFO" "Using Neo4j configuration"
    else
        compose_file="${DOCKER_DIR}/docker-compose-falkordb.yml"
        log "INFO" "Using FalkorDB configuration"
    fi
    
    # Check if compose file exists
    if [ ! -f "$compose_file" ]; then
        log "ERROR" "Docker Compose file not found: $compose_file"
        return 1
    fi
    
    cd "$DOCKER_DIR"
    
    # Backup current .env and config.yaml
    log "INFO" "Backing up configuration files..."
    cp "${INSTALL_DIR}/.env" "${INSTALL_DIR}/.env.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    cp "${INSTALL_DIR}/config.yaml" "${INSTALL_DIR}/config.yaml.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    # Pull latest images
    log "INFO" "Pulling latest Docker images..."
    docker-compose -f "$compose_file" pull
    
    # Stop containers (but keep volumes)
    log "INFO" "Stopping containers..."
    docker-compose -f "$compose_file" stop
    
    # Remove old containers
    log "INFO" "Removing old containers..."
    docker-compose -f "$compose_file" rm -f
    
    # Start services with new images
    log "INFO" "Starting services with updated images..."
    docker-compose -f "$compose_file" up -d
    
    # Wait for services to be ready
    log "INFO" "Waiting for services to start..."
    sleep 10
    
    log "INFO" "Update completed successfully"
    log "INFO" "Configuration backups saved with timestamp"
    return 0
}

# start_services() - Launch Docker containers with selected database
# This function starts the appropriate Docker Compose configuration
start_services() {
    log "INFO" "Starting Graphiti services..."
    
    # If in update mode, use update function instead
    if [ "${INSTALLATION_MODE:-fresh}" = "update" ]; then
        update_installation
        return $?
    fi
    
    # Determine which docker-compose file to use
    local compose_file
    if [ "${DATABASE_TYPE:-falkordb}" = "neo4j" ]; then
        compose_file="${DOCKER_DIR}/docker-compose-neo4j.yml"
        log "INFO" "Using Neo4j configuration"
    else
        compose_file="${DOCKER_DIR}/docker-compose-falkordb.yml"
        log "INFO" "Using FalkorDB configuration"
    fi
    
    # Check if compose file exists
    if [ ! -f "$compose_file" ]; then
        log "ERROR" "Docker Compose file not found: $compose_file"
        return 1
    fi
    
    # Get docker compose command
    local compose_cmd
    compose_cmd=$(docker_compose_cmd) || return 1
    
    # Stop any existing containers
    log "INFO" "Stopping any existing containers..."
    cd "$DOCKER_DIR"
    $compose_cmd -f "$compose_file" down 2>/dev/null || true
    
    # Pull latest images
    log "INFO" "Pulling Docker images..."
    $compose_cmd -f "$compose_file" pull
    
    # Start services
    log "INFO" "Starting Docker containers..."
    $compose_cmd -f "$compose_file" up -d
    
    # Wait for services to be ready
    log "INFO" "Waiting for services to start..."
    sleep 10
    
    log "INFO" "Services started successfully"
    return 0
}

# ============================================================================
# Installation Verification Functions
# ============================================================================

# verify_installation() - Check all services are running
# This function verifies that Docker containers are up and healthy
verify_installation() {
    log "INFO" "Verifying installation..."
    
    cd "$DOCKER_DIR"
    
    # Check if graphiti-mcp container is running
    if ! docker ps | grep -q graphiti-mcp; then
        log "ERROR" "graphiti-mcp container is not running"
        docker ps -a | grep graphiti-mcp || log "ERROR" "Container not found"
        return 1
    fi
    log "INFO" "✓ graphiti-mcp container is running"
    
    # Check database container
    if [ "${DATABASE_TYPE:-falkordb}" = "neo4j" ]; then
        if ! docker ps | grep -q neo4j; then
            log "ERROR" "neo4j container is not running"
            return 1
        fi
        log "INFO" "✓ neo4j container is running"
    else
        if ! docker ps | grep -q falkordb; then
            log "ERROR" "falkordb container is not running"
            return 1
        fi
        log "INFO" "✓ falkordb container is running"
    fi
    
    # Check nginx container
    if ! docker ps | grep -q nginx-proxy; then
        log "WARNING" "nginx-proxy container is not running"
    else
        log "INFO" "✓ nginx-proxy container is running"
    fi
    
    log "INFO" "Installation verification completed successfully"
    return 0
}

# ============================================================================
# SSL/HTTPS Configuration Functions
# ============================================================================

# setup_ssl() - Configure HTTPS with Let's Encrypt certificates
# This function installs certbot and configures SSL for the provided domain
setup_ssl() {
    log "INFO" "Setting up SSL/HTTPS configuration..."
    
    # Check if domain is configured
    local domain
    domain=$(grep "^DOMAIN_NAME=" "${INSTALL_DIR}/.env" | cut -d'=' -f2)
    
    if [ -z "$domain" ]; then
        log "WARNING" "No domain configured, skipping SSL setup"
        log "INFO" "MCP will be accessible via HTTP only"
        return 0
    fi
    
    log "INFO" "Configuring SSL for domain: $domain"
    
    # Install certbot
    install_certbot || {
        log "ERROR" "Failed to install certbot"
        return 1
    }
    
    # Generate SSL certificates
    generate_ssl_certificates "$domain" || {
        log "ERROR" "Failed to generate SSL certificates"
        return 1
    }
    
    # Configure nginx with SSL
    configure_nginx_ssl "$domain" || {
        log "ERROR" "Failed to configure nginx with SSL"
        return 1
    }
    
    # Setup automatic renewal
    setup_cert_renewal || {
        log "ERROR" "Failed to setup certificate renewal"
        return 1
    }
    
    log "INFO" "SSL configuration completed successfully"
    return 0
}

# install_certbot() - Install certbot for Let's Encrypt
install_certbot() {
    log "INFO" "Installing certbot..."
    
    # Check if certbot is already installed
    if check_command certbot; then
        log "INFO" "certbot is already installed"
        return 0
    fi
    
    # Detect OS and install certbot
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        OS=$ID
    else
        log "ERROR" "Cannot detect OS"
        return 1
    fi
    
    case "$OS" in
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y certbot python3-certbot-nginx
            ;;
        centos|rhel|amzn)
            sudo yum install -y certbot python3-certbot-nginx
            ;;
        *)
            log "ERROR" "Unsupported OS for certbot installation: $OS"
            return 1
            ;;
    esac
    
    log "INFO" "certbot installed successfully"
    return 0
}

# generate_ssl_certificates() - Generate Let's Encrypt certificates
generate_ssl_certificates() {
    local domain="$1"
    
    log "INFO" "Generating SSL certificates for $domain..."
    
    # Check if certificates already exist
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        log "INFO" "Certificates already exist for $domain"
        local response
        response=$(prompt_user "Do you want to renew certificates? (y/n)" "n")
        
        if [[ "$response" =~ ^[Yy] ]]; then
            sudo certbot renew --force-renewal
        fi
        return 0
    fi
    
    # Get email for Let's Encrypt notifications
    local email
    email=$(prompt_user "Enter email for Let's Encrypt notifications" "")
    
    if [ -z "$email" ]; then
        log "ERROR" "Email is required for Let's Encrypt"
        return 1
    fi
    
    # Stop nginx temporarily to allow certbot to bind to port 80
    log "INFO" "Stopping nginx temporarily..."
    cd "$DOCKER_DIR"
    docker-compose -f "docker-compose-${DATABASE_TYPE:-falkordb}.yml" stop nginx-proxy 2>/dev/null || true
    
    # Generate certificates using standalone mode
    sudo certbot certonly --standalone \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        -d "$domain" || {
        log "ERROR" "Failed to generate certificates"
        # Restart nginx
        docker-compose -f "docker-compose-${DATABASE_TYPE:-falkordb}.yml" start nginx-proxy 2>/dev/null || true
        return 1
    }
    
    # Copy certificates to nginx directory
    log "INFO" "Copying certificates to nginx directory..."
    sudo cp "/etc/letsencrypt/live/$domain/fullchain.pem" "${DOCKER_DIR}/nginx/ssl/"
    sudo cp "/etc/letsencrypt/live/$domain/privkey.pem" "${DOCKER_DIR}/nginx/ssl/"
    sudo chown -R "$USER:$USER" "${DOCKER_DIR}/nginx/ssl/"
    
    log "INFO" "SSL certificates generated successfully"
    return 0
}

# configure_nginx_ssl() - Configure nginx with SSL certificates
configure_nginx_ssl() {
    local domain="$1"
    
    log "INFO" "Configuring nginx with SSL..."
    
    local nginx_conf="${DOCKER_DIR}/nginx/nginx.conf"
    
    # Backup original config
    cp "$nginx_conf" "${nginx_conf}.bak"
    
    # Create SSL-enabled nginx configuration
    cat > "$nginx_conf" << 'EOF'
events {
    worker_connections 1024;
}

http {
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=mcp_limit:10m rate=10r/s;
    
    # Upstream for Graphiti MCP
    upstream graphiti_mcp {
        server graphiti-mcp:8000;
    }
    
    # HTTP server - redirect to HTTPS
    server {
        listen 80;
        server_name _;
        
        location / {
            return 301 https://$host$request_uri;
        }
    }
    
    # HTTPS server
    server {
        listen 443 ssl http2;
        server_name _;
        
        # SSL certificates
        ssl_certificate /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/privkey.pem;
        
        # SSL configuration
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;
        
        # Security headers
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        
        # MCP endpoint
        location /mcp/ {
            limit_req zone=mcp_limit burst=20 nodelay;
            
            proxy_pass http://graphiti_mcp/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Timeouts
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
        
        # Health check endpoint
        location /health {
            proxy_pass http://graphiti_mcp/health;
            proxy_set_header Host $host;
            access_log off;
        }
    }
}
EOF
    
    log "INFO" "nginx configured with SSL"
    
    # Restart nginx with new configuration
    log "INFO" "Restarting nginx..."
    cd "$DOCKER_DIR"
    docker-compose -f "docker-compose-${DATABASE_TYPE:-falkordb}.yml" restart nginx-proxy
    
    log "INFO" "nginx SSL configuration completed"
    return 0
}

# setup_cert_renewal() - Setup automatic certificate renewal
setup_cert_renewal() {
    log "INFO" "Setting up automatic certificate renewal..."
    
    # Create renewal hook script
    local renewal_hook="/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh"
    
    sudo mkdir -p "$(dirname "$renewal_hook")"
    
    sudo tee "$renewal_hook" > /dev/null << EOF
#!/bin/bash
# Reload nginx after certificate renewal

DOCKER_DIR="${DOCKER_DIR}"
DATABASE_TYPE="${DATABASE_TYPE:-falkordb}"

# Copy new certificates
cp /etc/letsencrypt/live/*/fullchain.pem \${DOCKER_DIR}/nginx/ssl/
cp /etc/letsencrypt/live/*/privkey.pem \${DOCKER_DIR}/nginx/ssl/

# Restart nginx container
cd "\${DOCKER_DIR}"
docker-compose -f "docker-compose-\${DATABASE_TYPE}.yml" restart nginx-proxy

echo "Certificates renewed and nginx reloaded"
EOF
    
    sudo chmod +x "$renewal_hook"
    
    # Test renewal (dry run)
    log "INFO" "Testing certificate renewal..."
    sudo certbot renew --dry-run || {
        log "WARNING" "Certificate renewal test failed, but continuing..."
    }
    
    log "INFO" "Automatic certificate renewal configured"
    log "INFO" "Certificates will be renewed automatically by certbot"
    
    return 0
}

# ============================================================================
# Main Installation Function
# ============================================================================

# run_installation() - Execute full installation workflow
# This is the main entry point called by platform-specific scripts
run_installation() {
    log "INFO" "Starting Graphiti installation workflow..."
    
    # Step 1: Install Docker
    install_docker || {
        log "ERROR" "Docker installation failed"
        return 1
    }
    
    # Step 2: Setup Graphiti
    setup_graphiti || {
        log "ERROR" "Graphiti setup failed"
        return 1
    }
    
    # Step 3: Configure environment
    configure_env || {
        log "ERROR" "Environment configuration failed"
        return 1
    }
    
    # Step 4: Select database
    select_database || {
        log "ERROR" "Database selection failed"
        return 1
    }
    
    # Step 5: Start services
    start_services || {
        log "ERROR" "Failed to start services"
        return 1
    }
    
    # Step 6: Setup SSL (if domain is configured)
    setup_ssl || {
        log "WARNING" "SSL setup failed, but continuing with HTTP"
    }
    
    # Step 7: Verify installation
    verify_installation || {
        log "ERROR" "Installation verification failed"
        return 1
    }
    
    log "INFO" "Graphiti installation completed successfully!"
    return 0
}

log "INFO" "Graphiti installation module loaded successfully"
