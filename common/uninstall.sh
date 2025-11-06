#!/bin/bash

# Graphiti Uninstall Script
# This script removes Graphiti installation including Docker containers, volumes, and files
# Usage: ./uninstall.sh [--keep-data] [--force]

set -euo pipefail

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Installation directory
readonly INSTALL_DIR="${INSTALL_DIR:-/opt/graphiti}"
readonly DOCKER_DIR="${INSTALL_DIR}/docker"

# Parse command line arguments
KEEP_DATA=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --keep-data)
            KEEP_DATA=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --keep-data    Keep database volumes (preserve data)"
            echo "  --force        Skip confirmation prompts"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# Confirmation Functions
# ============================================================================

# confirm_uninstall() - Ask user to confirm uninstallation
confirm_uninstall() {
    if [ "$FORCE" = true ]; then
        log "INFO" "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    echo ""
    echo "=========================================="
    echo "  Graphiti Uninstall"
    echo "=========================================="
    echo ""
    echo "This will remove:"
    echo "  - All Graphiti Docker containers"
    echo "  - Graphiti installation files"
    
    if [ "$KEEP_DATA" = false ]; then
        echo "  - All database volumes (YOUR DATA WILL BE LOST)"
    else
        echo "  - Database volumes will be PRESERVED"
    fi
    
    echo ""
    echo "Installation directory: $INSTALL_DIR"
    echo ""
    
    local response
    response=$(prompt_user "Are you sure you want to continue? (yes/no)" "no")
    
    if [[ ! "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
        log "INFO" "Uninstall cancelled by user"
        exit 0
    fi
    
    return 0
}

# ============================================================================
# Container Removal Functions
# ============================================================================

# stop_and_remove_containers() - Stop and remove all Graphiti containers
stop_and_remove_containers() {
    log "INFO" "Stopping and removing Docker containers..."
    
    local containers_found=false
    
    # Try to use docker-compose if available
    if [ -d "$DOCKER_DIR" ]; then
        cd "$DOCKER_DIR"
        
        for compose_file in docker-compose-falkordb.yml docker-compose-neo4j.yml; do
            if [ -f "$compose_file" ]; then
                log "INFO" "Stopping containers from $compose_file..."
                
                if [ "$KEEP_DATA" = true ]; then
                    # Stop and remove containers but keep volumes
                    docker-compose -f "$compose_file" down 2>/dev/null || true
                else
                    # Stop and remove containers and volumes
                    docker-compose -f "$compose_file" down -v 2>/dev/null || true
                fi
                
                containers_found=true
            fi
        done
    fi
    
    # Fallback: manually stop and remove containers by name
    log "INFO" "Checking for containers by name..."
    for container in graphiti-mcp falkordb neo4j nginx-proxy; do
        if docker ps -a 2>/dev/null | grep -q "$container"; then
            log "INFO" "Stopping and removing container: $container"
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
            containers_found=true
        fi
    done
    
    if [ "$containers_found" = false ]; then
        log "INFO" "No Graphiti containers found"
    else
        log "INFO" "Containers removed successfully"
    fi
    
    return 0
}

# ============================================================================
# Volume Removal Functions
# ============================================================================

# remove_volumes() - Remove Docker volumes
remove_volumes() {
    if [ "$KEEP_DATA" = true ]; then
        log "INFO" "Skipping volume removal (--keep-data flag set)"
        return 0
    fi
    
    log "INFO" "Removing Docker volumes..."
    
    local volumes_found=false
    
    # List of volume patterns to remove
    local volume_patterns=(
        "falkordb-data"
        "neo4j-data"
        "neo4j-logs"
        "neo4j-import"
        "neo4j-plugins"
    )
    
    for pattern in "${volume_patterns[@]}"; do
        # Find volumes matching the pattern
        local volumes
        volumes=$(docker volume ls -q 2>/dev/null | grep "$pattern" || true)
        
        if [ -n "$volumes" ]; then
            for volume in $volumes; do
                log "INFO" "Removing volume: $volume"
                docker volume rm "$volume" 2>/dev/null || {
                    log "WARNING" "Failed to remove volume: $volume (may be in use)"
                }
                volumes_found=true
            done
        fi
    done
    
    if [ "$volumes_found" = false ]; then
        log "INFO" "No Graphiti volumes found"
    else
        log "INFO" "Volumes removed successfully"
    fi
    
    return 0
}

# ============================================================================
# File Removal Functions
# ============================================================================

# remove_installation_files() - Remove Graphiti installation directory
remove_installation_files() {
    log "INFO" "Removing installation files..."
    
    if [ ! -d "$INSTALL_DIR" ]; then
        log "INFO" "Installation directory not found: $INSTALL_DIR"
        return 0
    fi
    
    # Create a backup of configuration files before removal
    if [ -f "${INSTALL_DIR}/.env" ] || [ -f "${INSTALL_DIR}/config.yaml" ]; then
        local backup_dir="/tmp/graphiti-backup-$(date +%Y%m%d_%H%M%S)"
        log "INFO" "Creating backup of configuration files: $backup_dir"
        
        mkdir -p "$backup_dir"
        cp "${INSTALL_DIR}/.env" "$backup_dir/" 2>/dev/null || true
        cp "${INSTALL_DIR}/config.yaml" "$backup_dir/" 2>/dev/null || true
        
        log "INFO" "Configuration backup saved to: $backup_dir"
    fi
    
    # Remove installation directory
    log "INFO" "Removing directory: $INSTALL_DIR"
    sudo rm -rf "$INSTALL_DIR"
    
    log "INFO" "Installation files removed successfully"
    return 0
}

# ============================================================================
# SSL Certificate Cleanup Functions
# ============================================================================

# remove_ssl_certificates() - Remove Let's Encrypt certificates
remove_ssl_certificates() {
    log "INFO" "Checking for SSL certificates..."
    
    # Check if certbot is installed
    if ! check_command certbot; then
        log "INFO" "certbot not found, skipping SSL certificate removal"
        return 0
    fi
    
    # List certificates
    local certs
    certs=$(sudo certbot certificates 2>/dev/null | grep "Certificate Name:" | awk '{print $3}' || true)
    
    if [ -z "$certs" ]; then
        log "INFO" "No SSL certificates found"
        return 0
    fi
    
    log "INFO" "Found SSL certificates:"
    echo "$certs"
    
    if [ "$FORCE" = false ]; then
        local response
        response=$(prompt_user "Do you want to remove SSL certificates? (y/n)" "n")
        
        if [[ ! "$response" =~ ^[Yy] ]]; then
            log "INFO" "Skipping SSL certificate removal"
            return 0
        fi
    fi
    
    # Remove each certificate
    while IFS= read -r cert; do
        if [ -n "$cert" ]; then
            log "INFO" "Removing certificate: $cert"
            sudo certbot delete --non-interactive --cert-name "$cert" 2>/dev/null || {
                log "WARNING" "Failed to remove certificate: $cert"
            }
        fi
    done <<< "$certs"
    
    log "INFO" "SSL certificates removed"
    return 0
}

# ============================================================================
# Cloud Resource Instructions
# ============================================================================

# show_cloud_cleanup_instructions() - Display instructions for cloud resource cleanup
show_cloud_cleanup_instructions() {
    log "INFO" "Displaying cloud resource cleanup instructions..."
    
    echo ""
    echo "=========================================="
    echo "  Cloud Resource Cleanup"
    echo "=========================================="
    echo ""
    echo "If you deployed Graphiti on a cloud platform, you may want to delete"
    echo "the cloud resources to avoid ongoing charges."
    echo ""
    echo "GCP (Google Cloud Platform):"
    echo "  1. List instances: gcloud compute instances list"
    echo "  2. Delete instance: gcloud compute instances delete INSTANCE_NAME --zone=ZONE"
    echo "  3. Delete firewall rules: gcloud compute firewall-rules delete RULE_NAME"
    echo ""
    echo "AWS (Amazon Web Services):"
    echo "  1. List instances: aws ec2 describe-instances"
    echo "  2. Terminate instance: aws ec2 terminate-instances --instance-ids INSTANCE_ID"
    echo "  3. Delete security group: aws ec2 delete-security-group --group-id GROUP_ID"
    echo ""
    echo "Azure (Microsoft Azure):"
    echo "  1. List VMs: az vm list"
    echo "  2. Delete VM: az vm delete --name VM_NAME --resource-group RESOURCE_GROUP"
    echo "  3. Delete resource group: az group delete --name RESOURCE_GROUP"
    echo ""
    echo "SSH (Custom Server):"
    echo "  - No cloud resources to delete"
    echo "  - Graphiti has been removed from your server"
    echo ""
    
    return 0
}

# ============================================================================
# Main Uninstall Function
# ============================================================================

# main() - Execute uninstall workflow
main() {
    log "INFO" "Starting Graphiti uninstall..."
    
    # Step 1: Confirm uninstallation
    confirm_uninstall
    
    # Step 2: Stop and remove containers
    stop_and_remove_containers || {
        log "ERROR" "Failed to remove containers"
        return 1
    }
    
    # Step 3: Remove volumes (if not keeping data)
    remove_volumes || {
        log "ERROR" "Failed to remove volumes"
        return 1
    }
    
    # Step 4: Remove installation files
    remove_installation_files || {
        log "ERROR" "Failed to remove installation files"
        return 1
    }
    
    # Step 5: Remove SSL certificates (optional)
    remove_ssl_certificates || {
        log "WARNING" "SSL certificate removal failed, but continuing..."
    }
    
    # Step 6: Show cloud cleanup instructions
    show_cloud_cleanup_instructions
    
    echo ""
    echo "=========================================="
    echo "  Uninstall Complete"
    echo "=========================================="
    echo ""
    log "INFO" "Graphiti has been successfully uninstalled"
    
    if [ "$KEEP_DATA" = true ]; then
        log "INFO" "Database volumes were preserved"
        log "INFO" "To remove volumes manually, run: docker volume prune"
    fi
    
    log "INFO" "Uninstall completed successfully"
    return 0
}

# Execute main function
main "$@"
