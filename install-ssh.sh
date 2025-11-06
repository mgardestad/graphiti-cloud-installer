#!/bin/bash

# Graphiti Cloud Installer - SSH Custom Server
# This script automates the deployment of Graphiti on any server accessible via SSH
# It connects to a remote server, copies installation files, and installs Graphiti with MCP support

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/common/utils.sh"

# SSH-specific variables
SSH_HOST=""
SSH_PORT="22"
SSH_USER=""
SSH_AUTH_METHOD=""
SSH_PASSWORD=""
SSH_KEY_PATH=""
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

# ============================================================================
# SSH Prerequisites Check
# ============================================================================

check_ssh_prerequisites() {
    log "INFO" "Checking SSH prerequisites..."
    
    # Check if ssh is installed
    if ! check_command ssh; then
        log "ERROR" "ssh is not installed"
        log "INFO" "Please install OpenSSH client"
        return 1
    fi
    
    # Check if scp is installed
    if ! check_command scp; then
        log "ERROR" "scp is not installed"
        log "INFO" "Please install OpenSSH client"
        return 1
    fi
    
    # Check ssh version
    local ssh_version
    ssh_version=$(ssh -V 2>&1 | awk '{print $1}')
    log "INFO" "SSH version: $ssh_version"
    
    log "INFO" "SSH prerequisites check completed"
    return 0
}

# ============================================================================
# SSH Configuration
# ============================================================================

configure_ssh() {
    log "INFO" "Configuring SSH connection..."
    
    # Prompt for server IP address
    SSH_HOST=$(prompt_user "Enter server IP address or hostname" "")
    
    if [ -z "$SSH_HOST" ]; then
        log "ERROR" "Server IP address is required"
        return 1
    fi
    
    log "INFO" "Target server: $SSH_HOST"
    
    # Prompt for SSH port
    SSH_PORT=$(prompt_user "Enter SSH port" "22")
    log "INFO" "SSH port: $SSH_PORT"
    
    # Prompt for SSH username
    SSH_USER=$(prompt_user "Enter SSH username" "root")
    
    if [ -z "$SSH_USER" ]; then
        log "ERROR" "SSH username is required"
        return 1
    fi
    
    log "INFO" "SSH username: $SSH_USER"
    
    # Prompt for authentication method
    echo ""
    echo "Choose SSH authentication method:"
    echo "  1) SSH key (recommended)"
    echo "  2) Password"
    echo ""
    
    local auth_choice
    auth_choice=$(prompt_user "Enter your choice (1 or 2)" "1")
    
    case "$auth_choice" in
        1)
            SSH_AUTH_METHOD="key"
            configure_ssh_key
            ;;
        2)
            SSH_AUTH_METHOD="password"
            configure_ssh_password
            ;;
        *)
            log "ERROR" "Invalid choice"
            return 1
            ;;
    esac
    
    log "INFO" "SSH configuration completed"
    return 0
}

# configure_ssh_key() - Configure SSH key authentication
configure_ssh_key() {
    log "INFO" "Configuring SSH key authentication..."
    
    # Prompt for SSH key path
    local default_key="${HOME}/.ssh/id_rsa"
    SSH_KEY_PATH=$(prompt_user "Enter path to SSH private key" "$default_key")
    
    if [ -z "$SSH_KEY_PATH" ]; then
        log "ERROR" "SSH key path is required"
        return 1
    fi
    
    # Expand tilde to home directory
    SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
    
    # Check if key file exists
    if [ ! -f "$SSH_KEY_PATH" ]; then
        log "ERROR" "SSH key file not found: $SSH_KEY_PATH"
        return 1
    fi
    
    # Check key file permissions
    local key_perms
    key_perms=$(stat -c %a "$SSH_KEY_PATH" 2>/dev/null || stat -f %A "$SSH_KEY_PATH" 2>/dev/null)
    
    if [ "$key_perms" != "600" ] && [ "$key_perms" != "400" ]; then
        log "WARNING" "SSH key has insecure permissions: $key_perms"
        log "INFO" "Fixing key permissions..."
        chmod 600 "$SSH_KEY_PATH"
    fi
    
    log "INFO" "Using SSH key: $SSH_KEY_PATH"
    return 0
}

# configure_ssh_password() - Configure SSH password authentication
configure_ssh_password() {
    log "INFO" "Configuring SSH password authentication..."
    
    # Check if sshpass is installed
    if ! check_command sshpass; then
        log "WARNING" "sshpass is not installed"
        log "INFO" "Installing sshpass for password authentication..."
        
        # Detect OS and install sshpass
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
                sudo apt-get install -y sshpass
                ;;
            centos|rhel|amzn)
                sudo yum install -y sshpass
                ;;
            darwin)
                log "ERROR" "sshpass is not available on macOS via standard package managers"
                log "INFO" "Please use SSH key authentication instead"
                return 1
                ;;
            *)
                log "ERROR" "Unsupported OS for sshpass installation: $OS"
                log "INFO" "Please install sshpass manually or use SSH key authentication"
                return 1
                ;;
        esac
    fi
    
    # Prompt for password
    SSH_PASSWORD=$(prompt_user "Enter SSH password" "" "secret")
    
    if [ -z "$SSH_PASSWORD" ]; then
        log "ERROR" "SSH password is required"
        return 1
    fi
    
    log "INFO" "Password authentication configured"
    return 0
}

# ============================================================================
# SSH Connection Test
# ============================================================================

test_ssh_connection() {
    log "INFO" "Testing SSH connection to ${SSH_USER}@${SSH_HOST}:${SSH_PORT}..."
    
    local test_command="echo 'SSH connection successful'"
    
    if [ "$SSH_AUTH_METHOD" = "key" ]; then
        # Test with SSH key
        if ssh -i "$SSH_KEY_PATH" \
            -p "$SSH_PORT" \
            $SSH_OPTS \
            "${SSH_USER}@${SSH_HOST}" \
            "$test_command" &>/dev/null; then
            log "INFO" "SSH connection test successful"
            return 0
        else
            log "ERROR" "SSH connection test failed"
            log "ERROR" "Please verify:"
            log "ERROR" "  - Server IP/hostname: $SSH_HOST"
            log "ERROR" "  - SSH port: $SSH_PORT"
            log "ERROR" "  - Username: $SSH_USER"
            log "ERROR" "  - SSH key: $SSH_KEY_PATH"
            log "ERROR" "  - Server is accessible and SSH service is running"
            return 1
        fi
    else
        # Test with password
        if sshpass -p "$SSH_PASSWORD" ssh \
            -p "$SSH_PORT" \
            $SSH_OPTS \
            "${SSH_USER}@${SSH_HOST}" \
            "$test_command" &>/dev/null; then
            log "INFO" "SSH connection test successful"
            return 0
        else
            log "ERROR" "SSH connection test failed"
            log "ERROR" "Please verify:"
            log "ERROR" "  - Server IP/hostname: $SSH_HOST"
            log "ERROR" "  - SSH port: $SSH_PORT"
            log "ERROR" "  - Username: $SSH_USER"
            log "ERROR" "  - Password is correct"
            log "ERROR" "  - Server is accessible and SSH service is running"
            return 1
        fi
    fi
}

# ============================================================================
# Execute SSH Command
# ============================================================================

ssh_exec() {
    local command="$1"
    
    if [ "$SSH_AUTH_METHOD" = "key" ]; then
        ssh -i "$SSH_KEY_PATH" \
            -p "$SSH_PORT" \
            $SSH_OPTS \
            "${SSH_USER}@${SSH_HOST}" \
            "$command"
    else
        sshpass -p "$SSH_PASSWORD" ssh \
            -p "$SSH_PORT" \
            $SSH_OPTS \
            "${SSH_USER}@${SSH_HOST}" \
            "$command"
    fi
}

# ============================================================================
# Execute SCP Command
# ============================================================================

scp_copy() {
    local source="$1"
    local destination="$2"
    
    if [ "$SSH_AUTH_METHOD" = "key" ]; then
        scp -i "$SSH_KEY_PATH" \
            -P "$SSH_PORT" \
            $SSH_OPTS \
            -r "$source" \
            "${SSH_USER}@${SSH_HOST}:${destination}"
    else
        sshpass -p "$SSH_PASSWORD" scp \
            -P "$SSH_PORT" \
            $SSH_OPTS \
            -r "$source" \
            "${SSH_USER}@${SSH_HOST}:${destination}"
    fi
}

# ============================================================================
# File Transfer to Remote Server
# ============================================================================

copy_files_to_server() {
    log "INFO" "Copying installation files to remote server..."
    
    # Create remote directory
    log "INFO" "Creating remote directory..."
    ssh_exec "mkdir -p /tmp/graphiti-installer" || {
        log "ERROR" "Failed to create remote directory"
        return 1
    }
    
    # Copy common scripts
    log "INFO" "Copying common scripts..."
    scp_copy "${SCRIPT_DIR}/common" "/tmp/graphiti-installer/" || {
        log "ERROR" "Failed to copy common scripts"
        return 1
    }
    
    # Copy docker configurations
    log "INFO" "Copying Docker configurations..."
    scp_copy "${SCRIPT_DIR}/docker" "/tmp/graphiti-installer/" || {
        log "ERROR" "Failed to copy Docker configurations"
        return 1
    }
    
    # Copy templates
    log "INFO" "Copying configuration templates..."
    scp_copy "${SCRIPT_DIR}/templates" "/tmp/graphiti-installer/" || {
        log "ERROR" "Failed to copy templates"
        return 1
    }
    
    log "INFO" "Files copied successfully"
    return 0
}

# ============================================================================
# Remote Installation Execution
# ============================================================================

execute_remote_installation() {
    log "INFO" "Executing installation on remote server..."
    
    # Create remote installation script
    local remote_script="/tmp/graphiti-installer/remote-install.sh"
    
    log "INFO" "Creating remote installation script..."
    ssh_exec "cat > $remote_script" << 'EOF'
#!/bin/bash
set -euo pipefail

cd /tmp/graphiti-installer

# Make scripts executable
chmod +x common/*.sh

# Source the installation module
source common/install-graphiti.sh

# Run installation
run_installation

echo "Installation completed on remote instance"
EOF
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to create remote installation script"
        return 1
    fi
    
    # Make script executable
    ssh_exec "chmod +x $remote_script" || {
        log "ERROR" "Failed to make remote script executable"
        return 1
    }
    
    # Execute installation
    log "INFO" "Running installation on remote server..."
    log "INFO" "This may take several minutes..."
    
    ssh_exec "sudo bash $remote_script" || {
        log "ERROR" "Remote installation failed"
        return 1
    }
    
    log "INFO" "Remote installation completed successfully"
    return 0
}

# ============================================================================
# SSH Resource Cleanup
# ============================================================================

cleanup_ssh_resource() {
    local type="$1"
    local id="$2"
    
    log "INFO" "Cleaning up SSH $type: $id"
    
    case "$type" in
        temp_files)
            ssh_exec "rm -rf /tmp/graphiti-installer" 2>/dev/null || \
                log "WARNING" "Failed to clean up temporary files: $id"
            ;;
        *)
            log "WARNING" "Unknown resource type: $type"
            ;;
    esac
}

# Override the cleanup function from utils.sh for SSH-specific cleanup
cleanup_ssh_resource_override() {
    cleanup_ssh_resource "$@"
}

# ============================================================================
# Display Installation Results
# ============================================================================

display_results() {
    log "INFO" "========================================="
    log "INFO" "Graphiti Installation Completed!"
    log "INFO" "========================================="
    log "INFO" ""
    log "INFO" "Server Details:"
    log "INFO" "  - Host: $SSH_HOST"
    log "INFO" "  - Port: $SSH_PORT"
    log "INFO" "  - User: $SSH_USER"
    log "INFO" ""
    log "INFO" "MCP Endpoint URLs:"
    log "INFO" "  - HTTP: http://${SSH_HOST}:8000/mcp/"
    log "INFO" "  - Health Check: http://${SSH_HOST}:8000/health"
    log "INFO" ""
    
    # Check if domain is configured for HTTPS
    local domain
    if [ "$SSH_AUTH_METHOD" = "key" ]; then
        domain=$(ssh -i "$SSH_KEY_PATH" \
            -p "$SSH_PORT" \
            $SSH_OPTS \
            "${SSH_USER}@${SSH_HOST}" \
            "grep '^DOMAIN_NAME=' /opt/graphiti/.env 2>/dev/null | cut -d'=' -f2" 2>/dev/null || echo "")
    else
        domain=$(sshpass -p "$SSH_PASSWORD" ssh \
            -p "$SSH_PORT" \
            $SSH_OPTS \
            "${SSH_USER}@${SSH_HOST}" \
            "grep '^DOMAIN_NAME=' /opt/graphiti/.env 2>/dev/null | cut -d'=' -f2" 2>/dev/null || echo "")
    fi
    
    if [ -n "$domain" ]; then
        log "INFO" "  - HTTPS: https://${domain}/mcp/"
    fi
    
    log "INFO" ""
    log "INFO" "Next Steps:"
    log "INFO" "  1. Configure your MCP client with the endpoint URL"
    log "INFO" "  2. Test the connection: curl http://${SSH_HOST}:8000/health"
    
    if [ "$SSH_AUTH_METHOD" = "key" ]; then
        log "INFO" "  3. View logs: ssh -i $SSH_KEY_PATH -p $SSH_PORT ${SSH_USER}@${SSH_HOST} 'docker logs graphiti-mcp'"
    else
        log "INFO" "  3. View logs: ssh -p $SSH_PORT ${SSH_USER}@${SSH_HOST} 'docker logs graphiti-mcp'"
    fi
    
    log "INFO" ""
    log "INFO" "To SSH into the server:"
    
    if [ "$SSH_AUTH_METHOD" = "key" ]; then
        log "INFO" "  ssh -i $SSH_KEY_PATH -p $SSH_PORT ${SSH_USER}@${SSH_HOST}"
    else
        log "INFO" "  ssh -p $SSH_PORT ${SSH_USER}@${SSH_HOST}"
    fi
    
    log "INFO" ""
    log "INFO" "To uninstall Graphiti:"
    log "INFO" "  ssh to the server and run: cd /opt/graphiti/docker && docker-compose down -v"
    log "INFO" "========================================="
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    log "INFO" "Starting Graphiti Cloud Installer for SSH"
    log "INFO" "========================================="
    
    # Set up cleanup trap
    trap cleanup EXIT ERR
    
    # Step 1: Check prerequisites
    check_ssh_prerequisites || {
        log "ERROR" "Prerequisites check failed"
        exit 1
    }
    
    # Step 2: Configure SSH connection
    configure_ssh || {
        log "ERROR" "SSH configuration failed"
        exit 1
    }
    
    # Step 3: Test SSH connection
    test_ssh_connection || {
        log "ERROR" "SSH connection test failed"
        exit 1
    }
    
    # Step 4: Copy installation files
    copy_files_to_server || {
        log "ERROR" "File transfer failed"
        exit 1
    }
    
    # Track temporary files for cleanup
    track_resource "temp_files" "/tmp/graphiti-installer" "ssh"
    
    # Step 5: Execute remote installation
    execute_remote_installation || {
        log "ERROR" "Remote installation failed"
        exit 1
    }
    
    # Step 6: Display results
    display_results
    
    log "INFO" "SSH installation completed successfully!"
    exit 0
}

# Run main function
main "$@"
