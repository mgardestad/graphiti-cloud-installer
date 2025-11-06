#!/bin/bash

# Common utility functions for Graphiti Cloud Installer
# Provides logging, validation, user interaction, and cleanup functionality

set -euo pipefail

# Color codes for terminal output
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Log file location - try /var/log first, fallback to /tmp
if [ -w /var/log ] || sudo -n true 2>/dev/null; then
    readonly LOG_FILE="${LOG_FILE:-/var/log/graphiti-install.log}"
else
    readonly LOG_FILE="${LOG_FILE:-/tmp/graphiti-install.log}"
fi

# Maximum log file size (10MB)
readonly MAX_LOG_SIZE=$((10 * 1024 * 1024))

# Number of rotated log files to keep
readonly LOG_ROTATION_COUNT=5

# Array to track created resources for cleanup
declare -a CREATED_RESOURCES=()

# Track script execution for stack traces
declare -a CALL_STACK=()

# ============================================================================
# Logging Functions
# ============================================================================

# rotate_log() - Rotate log file if it exceeds maximum size
# This function is called automatically before writing to log
rotate_log() {
    # Check if log file exists and get its size
    if [ -f "$LOG_FILE" ]; then
        local log_size
        log_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
        
        # Rotate if size exceeds maximum
        if [ "$log_size" -gt "$MAX_LOG_SIZE" ]; then
            # Rotate existing log files
            for i in $(seq $((LOG_ROTATION_COUNT - 1)) -1 1); do
                if [ -f "${LOG_FILE}.$i" ]; then
                    if [ -w "$(dirname "$LOG_FILE")" ]; then
                        mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i + 1))" 2>/dev/null || \
                            sudo mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i + 1))" 2>/dev/null || true
                    fi
                fi
            done
            
            # Move current log to .1
            if [ -w "$(dirname "$LOG_FILE")" ]; then
                mv "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || \
                    sudo mv "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
            fi
            
            # Create new log file
            touch "$LOG_FILE" 2>/dev/null || sudo touch "$LOG_FILE" 2>/dev/null || true
        fi
    fi
}

# log() - Formatted logging with levels (INFO, WARNING, ERROR, DEBUG)
# Usage: log "INFO" "Message to log"
# Arguments:
#   $1 - Log level (INFO, WARNING, ERROR, DEBUG)
#   $2 - Message to log
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Get caller information for better debugging
    local caller_info=""
    if [ "${BASH_SOURCE[2]:-}" != "" ]; then
        local caller_file="${BASH_SOURCE[2]##*/}"
        local caller_line="${BASH_LINENO[1]}"
        local caller_func="${FUNCNAME[2]:-main}"
        caller_info=" [$caller_file:$caller_line:$caller_func]"
    fi
    
    # Determine color based on level
    local color=""
    case "$level" in
        INFO)
            color="$GREEN"
            ;;
        WARNING)
            color="$YELLOW"
            ;;
        ERROR)
            color="$RED"
            ;;
        DEBUG)
            color="$BLUE"
            ;;
        *)
            color="$NC"
            ;;
    esac
    
    # Print to console with color (skip DEBUG unless DEBUG mode is enabled)
    if [ "$level" != "DEBUG" ] || [ "${DEBUG:-0}" = "1" ]; then
        echo -e "${color}[${level}]${NC} ${message}"
    fi
    
    # Rotate log if needed
    rotate_log
    
    # Write to log file without color codes
    if [ -w "$LOG_FILE" ]; then
        echo "[${timestamp}] [${level}]${caller_info} ${message}" >> "$LOG_FILE"
    else
        # Try with sudo if we don't have write permission
        echo "[${timestamp}] [${level}]${caller_info} ${message}" | sudo tee -a "$LOG_FILE" > /dev/null 2>&1 || true
    fi
}

# log_command() - Log a command and its output
# Usage: log_command "description" command args...
# Arguments:
#   $1 - Description of the command
#   $@ - Command and arguments to execute
log_command() {
    local description="$1"
    shift
    
    log "INFO" "Executing: $description"
    log "DEBUG" "Command: $*"
    
    # Execute command and capture output
    local output
    local exit_code
    
    if output=$("$@" 2>&1); then
        exit_code=0
        log "DEBUG" "Command succeeded"
        if [ -n "$output" ]; then
            log "DEBUG" "Output: $output"
        fi
    else
        exit_code=$?
        log "ERROR" "Command failed with exit code $exit_code"
        if [ -n "$output" ]; then
            log "ERROR" "Output: $output"
        fi
    fi
    
    return $exit_code
}

# ============================================================================
# Command Validation Functions
# ============================================================================

# check_command() - Verify if a command is available in PATH
# Usage: check_command "docker" || { log "ERROR" "Docker not found"; exit 1; }
# Arguments:
#   $1 - Command name to check
# Returns:
#   0 if command exists, 1 otherwise
check_command() {
    local cmd="$1"
    
    if command -v "$cmd" &> /dev/null; then
        log "INFO" "Command '$cmd' found"
        return 0
    else
        log "WARNING" "Command '$cmd' not found"
        return 1
    fi
}

# ============================================================================
# User Interaction Functions
# ============================================================================

# prompt_user() - Interactive user input with optional default value
# Usage: 
#   prompt_user "Enter your name" "default_name"
#   result=$(prompt_user "Enter API key")
# Arguments:
#   $1 - Prompt message
#   $2 - Default value (optional)
#   $3 - Secret mode flag (optional, "secret" to hide input)
# Returns:
#   User input via stdout
prompt_user() {
    local prompt="$1"
    local default="${2:-}"
    local secret="${3:-}"
    local user_input
    
    # Build prompt string
    local prompt_str="$prompt"
    if [ -n "$default" ]; then
        prompt_str="$prompt [$default]"
    fi
    prompt_str="$prompt_str: "
    
    # Read input (with or without echo)
    if [ "$secret" = "secret" ]; then
        read -s -r -p "$prompt_str" user_input
        echo "" # New line after hidden input
    else
        read -r -p "$prompt_str" user_input
    fi
    
    # Use default if input is empty
    if [ -z "$user_input" ] && [ -n "$default" ]; then
        user_input="$default"
    fi
    
    echo "$user_input"
}

# ============================================================================
# Input Validation Functions
# ============================================================================

# validate_not_empty() - Validate that input is not empty
# Usage: validate_not_empty "$input" "Field name" || return 1
# Arguments:
#   $1 - Input value to validate
#   $2 - Field name for error message
# Returns:
#   0 if valid, 1 if empty
validate_not_empty() {
    local value="$1"
    local field_name="$2"
    
    if [ -z "$value" ]; then
        log "ERROR" "$field_name cannot be empty"
        return 1
    fi
    
    return 0
}

# validate_ip_address() - Validate IP address format
# Usage: validate_ip_address "$ip" || return 1
# Arguments:
#   $1 - IP address to validate
# Returns:
#   0 if valid, 1 if invalid
validate_ip_address() {
    local ip="$1"
    
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log "ERROR" "Invalid IP address format: $ip"
        return 1
    fi
    
    # Check each octet is between 0-255
    local IFS='.'
    local -a octets=($ip)
    
    for octet in "${octets[@]}"; do
        if [ "$octet" -gt 255 ]; then
            log "ERROR" "Invalid IP address: $ip (octet $octet > 255)"
            return 1
        fi
    done
    
    log "INFO" "IP address format is valid: $ip"
    return 0
}

# validate_port() - Validate port number
# Usage: validate_port "$port" || return 1
# Arguments:
#   $1 - Port number to validate
# Returns:
#   0 if valid, 1 if invalid
validate_port() {
    local port="$1"
    
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        log "ERROR" "Invalid port number: $port (must be numeric)"
        return 1
    fi
    
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log "ERROR" "Invalid port number: $port (must be between 1-65535)"
        return 1
    fi
    
    log "INFO" "Port number is valid: $port"
    return 0
}

# validate_domain() - Validate domain name format
# Usage: validate_domain "$domain" || return 1
# Arguments:
#   $1 - Domain name to validate
# Returns:
#   0 if valid, 1 if invalid
validate_domain() {
    local domain="$1"
    
    if [ -z "$domain" ]; then
        return 0  # Empty domain is allowed (means no SSL)
    fi
    
    # Basic domain validation
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log "ERROR" "Invalid domain name format: $domain"
        return 1
    fi
    
    log "INFO" "Domain name format is valid: $domain"
    return 0
}

# validate_file_exists() - Validate that a file exists
# Usage: validate_file_exists "$file_path" "File description" || return 1
# Arguments:
#   $1 - File path to check
#   $2 - File description for error message
# Returns:
#   0 if file exists, 1 if not
validate_file_exists() {
    local file_path="$1"
    local description="$2"
    
    if [ ! -f "$file_path" ]; then
        log "ERROR" "$description not found: $file_path"
        return 1
    fi
    
    log "INFO" "$description found: $file_path"
    return 0
}

# validate_directory_exists() - Validate that a directory exists
# Usage: validate_directory_exists "$dir_path" "Directory description" || return 1
# Arguments:
#   $1 - Directory path to check
#   $2 - Directory description for error message
# Returns:
#   0 if directory exists, 1 if not
validate_directory_exists() {
    local dir_path="$1"
    local description="$2"
    
    if [ ! -d "$dir_path" ]; then
        log "ERROR" "$description not found: $dir_path"
        return 1
    fi
    
    log "INFO" "$description found: $dir_path"
    return 0
}

# ============================================================================
# Environment File Validation Functions
# ============================================================================

# validate_local_env() - Validate local .env file has at least one API key
# Usage: validate_local_env "/path/to/.env" || exit 1
# Arguments:
#   $1 - Path to .env file
# Returns:
#   0 if valid, 1 if invalid or missing
validate_local_env() {
    local env_file="$1"
    
    # Check if .env file exists
    if [ ! -f "$env_file" ]; then
        log "ERROR" "Local .env file not found: $env_file"
        log "INFO" "Please create a .env file with at least one API key"
        log "INFO" "Example:"
        log "INFO" "  OPENAI_API_KEY=sk-..."
        log "INFO" "  ANTHROPIC_API_KEY=sk-ant-..."
        log "INFO" "  GOOGLE_API_KEY=AIza..."
        log "INFO" "  GROQ_API_KEY=gsk_..."
        return 1
    fi
    
    log "INFO" "Found local .env file: $env_file"
    
    # Check for at least one API key
    local has_key=false
    
    # Check OpenAI
    if grep -q "^OPENAI_API_KEY=sk-" "$env_file" 2>/dev/null; then
        local key_value
        key_value=$(grep "^OPENAI_API_KEY=" "$env_file" | cut -d'=' -f2)
        if [ -n "$key_value" ] && [ "$key_value" != "sk-" ]; then
            log "INFO" "✓ Found OpenAI API key"
            has_key=true
        fi
    fi
    
    # Check Anthropic
    if grep -q "^ANTHROPIC_API_KEY=sk-ant-" "$env_file" 2>/dev/null; then
        local key_value
        key_value=$(grep "^ANTHROPIC_API_KEY=" "$env_file" | cut -d'=' -f2)
        if [ -n "$key_value" ] && [ "$key_value" != "sk-ant-" ]; then
            log "INFO" "✓ Found Anthropic API key"
            has_key=true
        fi
    fi
    
    # Check Google
    if grep -q "^GOOGLE_API_KEY=AIza" "$env_file" 2>/dev/null; then
        local key_value
        key_value=$(grep "^GOOGLE_API_KEY=" "$env_file" | cut -d'=' -f2)
        if [ -n "$key_value" ] && [ "$key_value" != "AIza" ]; then
            log "INFO" "✓ Found Google API key"
            has_key=true
        fi
    fi
    
    # Check Groq
    if grep -q "^GROQ_API_KEY=gsk_" "$env_file" 2>/dev/null; then
        local key_value
        key_value=$(grep "^GROQ_API_KEY=" "$env_file" | cut -d'=' -f2)
        if [ -n "$key_value" ] && [ "$key_value" != "gsk_" ]; then
            log "INFO" "✓ Found Groq API key"
            has_key=true
        fi
    fi
    
    if [ "$has_key" = false ]; then
        log "ERROR" "No valid API keys found in .env file"
        log "ERROR" "At least one API key is required:"
        log "ERROR" "  - OPENAI_API_KEY=sk-..."
        log "ERROR" "  - ANTHROPIC_API_KEY=sk-ant-..."
        log "ERROR" "  - GOOGLE_API_KEY=AIza..."
        log "ERROR" "  - GROQ_API_KEY=gsk_..."
        return 1
    fi
    
    log "INFO" "✓ Local .env file is valid"
    return 0
}

# ============================================================================
# API Key Validation Functions
# ============================================================================

# validate_api_key() - Validate API key format for different providers
# Usage: validate_api_key "openai" "sk-1234567890abcdef" || log "ERROR" "Invalid key"
# Arguments:
#   $1 - Provider name (openai, anthropic, google, groq)
#   $2 - API key to validate
# Returns:
#   0 if valid, 1 otherwise
validate_api_key() {
    local provider="$1"
    local api_key="$2"
    
    # Check if key is empty
    if [ -z "$api_key" ]; then
        log "WARNING" "API key for $provider is empty"
        return 1
    fi
    
    # Validate based on provider
    case "$provider" in
        openai)
            # OpenAI keys start with "sk-" and are typically 48+ characters
            if [[ "$api_key" =~ ^sk-[A-Za-z0-9_-]{32,}$ ]]; then
                log "INFO" "OpenAI API key format is valid"
                return 0
            else
                log "ERROR" "Invalid OpenAI API key format (should start with 'sk-')"
                return 1
            fi
            ;;
        anthropic)
            # Anthropic keys start with "sk-ant-" and are typically 100+ characters
            if [[ "$api_key" =~ ^sk-ant-[A-Za-z0-9_-]{32,}$ ]]; then
                log "INFO" "Anthropic API key format is valid"
                return 0
            else
                log "ERROR" "Invalid Anthropic API key format (should start with 'sk-ant-')"
                return 1
            fi
            ;;
        google)
            # Google API keys are typically 39 characters alphanumeric
            if [[ "$api_key" =~ ^[A-Za-z0-9_-]{20,}$ ]]; then
                log "INFO" "Google API key format is valid"
                return 0
            else
                log "ERROR" "Invalid Google API key format"
                return 1
            fi
            ;;
        groq)
            # Groq keys start with "gsk_" and are typically 50+ characters
            if [[ "$api_key" =~ ^gsk_[A-Za-z0-9]{32,}$ ]]; then
                log "INFO" "Groq API key format is valid"
                return 0
            else
                log "ERROR" "Invalid Groq API key format (should start with 'gsk_')"
                return 1
            fi
            ;;
        *)
            log "WARNING" "Unknown provider '$provider', skipping validation"
            return 0
            ;;
    esac
}

# ============================================================================
# Resource Tracking Functions
# ============================================================================

# track_resource() - Add a resource to the cleanup list
# Usage: track_resource "instance" "i-1234567890abcdef" "aws"
# Arguments:
#   $1 - Resource type (instance, firewall, security_group, volume, etc.)
#   $2 - Resource ID
#   $3 - Platform (gcp, aws, azure, ssh)
track_resource() {
    local resource_type="$1"
    local resource_id="$2"
    local platform="$3"
    
    CREATED_RESOURCES+=("${platform}:${resource_type}:${resource_id}")
    log "INFO" "Tracking resource: ${platform}:${resource_type}:${resource_id}"
}

# ============================================================================
# Cleanup Functions
# ============================================================================

# cleanup() - Error handling and resource cleanup
# Usage: trap cleanup EXIT ERR
# This function is called automatically on script exit or error
cleanup() {
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log "ERROR" "Installation failed with exit code $exit_code"
        
        # Print stack trace
        print_stack_trace
        
        log "INFO" "Starting cleanup of created resources..."
        
        # Cleanup tracked resources
        if [ ${#CREATED_RESOURCES[@]} -gt 0 ]; then
            log "INFO" "Found ${#CREATED_RESOURCES[@]} resources to clean up"
            
            for resource in "${CREATED_RESOURCES[@]}"; do
                IFS=':' read -r platform type id <<< "$resource"
                log "INFO" "Cleaning up ${platform} ${type}: ${id}"
                
                case "$platform" in
                    gcp)
                        cleanup_gcp_resource "$type" "$id"
                        ;;
                    aws)
                        cleanup_aws_resource "$type" "$id"
                        ;;
                    azure)
                        cleanup_azure_resource "$type" "$id"
                        ;;
                    ssh)
                        cleanup_ssh_resource "$type" "$id"
                        ;;
                    *)
                        log "WARNING" "Unknown platform: $platform"
                        ;;
                esac
            done
        else
            log "INFO" "No resources to clean up"
        fi
        
        log "ERROR" "Installation failed. Check log file: $LOG_FILE"
        log "ERROR" "For support, please provide the log file and error details"
    else
        log "INFO" "Script completed successfully"
    fi
}

# print_stack_trace() - Print call stack for debugging
# This function prints the function call stack when an error occurs
print_stack_trace() {
    log "ERROR" "Stack trace:"
    
    local frame=0
    while caller $frame; do
        ((frame++))
    done | while read -r line func file; do
        log "ERROR" "  at $func ($file:$line)"
    done
}

# error_exit() - Exit with error message and cleanup
# Usage: error_exit "Error message" [exit_code]
# Arguments:
#   $1 - Error message
#   $2 - Exit code (optional, defaults to 1)
error_exit() {
    local message="$1"
    local code="${2:-1}"
    
    log "ERROR" "$message"
    exit "$code"
}

# check_exit_code() - Check command exit code and exit on failure
# Usage: check_exit_code $? "Error message"
# Arguments:
#   $1 - Exit code to check
#   $2 - Error message if exit code is non-zero
check_exit_code() {
    local exit_code="$1"
    local message="$2"
    
    if [ "$exit_code" -ne 0 ]; then
        log "ERROR" "$message (exit code: $exit_code)"
        return "$exit_code"
    fi
    
    return 0
}

# Platform-specific cleanup functions (to be implemented by platform scripts)
cleanup_gcp_resource() {
    local type="$1"
    local id="$2"
    log "INFO" "GCP cleanup: $type $id (implement in install-gcp.sh)"
}

cleanup_aws_resource() {
    local type="$1"
    local id="$2"
    log "INFO" "AWS cleanup: $type $id (implement in install-aws.sh)"
}

cleanup_azure_resource() {
    local type="$1"
    local id="$2"
    log "INFO" "Azure cleanup: $type $id (implement in install-azure.sh)"
}

cleanup_ssh_resource() {
    local type="$1"
    local id="$2"
    log "INFO" "SSH cleanup: $type $id (implement in install-ssh.sh)"
}

# ============================================================================
# Initialization
# ============================================================================

# Initialize log file
init_logging() {
    # Try to create log file
    if touch "$LOG_FILE" 2>/dev/null; then
        log "INFO" "Log file initialized: $LOG_FILE"
    elif sudo touch "$LOG_FILE" 2>/dev/null; then
        sudo chmod 666 "$LOG_FILE" 2>/dev/null || true
        log "INFO" "Log file initialized with sudo: $LOG_FILE"
    else
        # Fallback to /tmp if we can't create in /var/log
        LOG_FILE="/tmp/graphiti-install.log"
        touch "$LOG_FILE" 2>/dev/null || {
            echo "ERROR: Cannot create log file at $LOG_FILE"
            return 1
        }
        log "WARNING" "Using fallback log location: $LOG_FILE"
    fi
    
    # Write log header
    log "INFO" "========================================="
    log "INFO" "Graphiti Cloud Installer"
    log "INFO" "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
    log "INFO" "Log file: $LOG_FILE"
    log "INFO" "User: $(whoami)"
    log "INFO" "Hostname: $(hostname)"
    log "INFO" "OS: $(uname -s) $(uname -r)"
    log "INFO" "========================================="
    
    return 0
}

# Initialize logging
init_logging || {
    echo "ERROR: Failed to initialize logging"
    exit 1
}

log "INFO" "Utility functions loaded successfully"
