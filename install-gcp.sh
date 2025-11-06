#!/bin/bash

# Graphiti Cloud Installer - Google Cloud Platform (GCP)
# This script automates the deployment of Graphiti on GCP Compute Engine
# It creates a VM instance, configures firewall rules, and installs Graphiti with MCP support

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/common/utils.sh"

# GCP-specific variables
GCP_PROJECT_ID=""
GCP_REGION=""
GCP_ZONE=""
GCP_INSTANCE_NAME="graphiti-mcp-instance"
GCP_MACHINE_TYPE="e2-micro"  # 0.25-2 vCPU shared, 1GB RAM - Lowest cost option
GCP_IMAGE_FAMILY="ubuntu-2204-lts"
GCP_IMAGE_PROJECT="ubuntu-os-cloud"
GCP_FIREWALL_RULE_NAME="graphiti-mcp-allow"
GCP_INSTANCE_IP=""

# ============================================================================
# GCP Prerequisites Check
# ============================================================================

check_gcp_prerequisites() {
    log "INFO" "Checking GCP prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! check_command gcloud; then
        log "ERROR" "gcloud CLI is not installed"
        log "INFO" "Please install gcloud CLI from: https://cloud.google.com/sdk/docs/install"
        return 1
    fi
    
    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(core)" 2>/dev/null || echo "unknown")
    log "INFO" "gcloud CLI version: $gcloud_version"
    
    log "INFO" "GCP prerequisites check completed"
    return 0
}

# ============================================================================
# GCP Authentication
# ============================================================================

authenticate_gcp() {
    log "INFO" "Authenticating with Google Cloud Platform..."
    
    # Check if already authenticated
    local current_account
    current_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || echo "")
    
    if [ -n "$current_account" ]; then
        log "INFO" "Already authenticated as: $current_account"
        local response
        response=$(prompt_user "Do you want to use this account? (y/n)" "y")
        
        if [[ ! "$response" =~ ^[Yy] ]]; then
            log "INFO" "Initiating new authentication..."
            gcloud auth login || {
                log "ERROR" "Authentication failed"
                return 1
            }
        fi
    else
        log "INFO" "No active account found, initiating authentication..."
        gcloud auth login || {
            log "ERROR" "Authentication failed"
            return 1
        }
    fi
    
    log "INFO" "GCP authentication successful"
    return 0
}

# ============================================================================
# GCP Project Configuration
# ============================================================================

configure_gcp_project() {
    log "INFO" "Configuring GCP project..."
    
    # Get current project
    local current_project
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [ -n "$current_project" ]; then
        log "INFO" "Current project: $current_project"
        GCP_PROJECT_ID=$(prompt_user "Enter GCP project ID" "$current_project")
    else
        GCP_PROJECT_ID=$(prompt_user "Enter GCP project ID" "")
    fi
    
    if [ -z "$GCP_PROJECT_ID" ]; then
        log "ERROR" "Project ID is required"
        return 1
    fi
    
    # Set project
    gcloud config set project "$GCP_PROJECT_ID" || {
        log "ERROR" "Failed to set project: $GCP_PROJECT_ID"
        return 1
    }
    
    log "INFO" "Using GCP project: $GCP_PROJECT_ID"
    
    # Prompt for region
    log "INFO" "Common GCP regions: us-central1, us-east1, europe-west1, asia-east1"
    GCP_REGION=$(prompt_user "Enter GCP region" "us-central1")
    
    # Get first available zone in the region
    log "INFO" "Finding available zones in $GCP_REGION..."
    GCP_ZONE=$(gcloud compute zones list --filter="name:${GCP_REGION}" --format="value(name)" --limit=1 2>/dev/null || echo "${GCP_REGION}-b")
    
    if [ -z "$GCP_ZONE" ]; then
        log "WARNING" "Could not find zones for region $GCP_REGION, using ${GCP_REGION}-b"
        GCP_ZONE="${GCP_REGION}-b"
    fi
    
    log "INFO" "Using zone: $GCP_ZONE"
    
    # Prompt for instance name
    GCP_INSTANCE_NAME=$(prompt_user "Enter instance name" "$GCP_INSTANCE_NAME")
    
    # Prompt for machine type 
    # Shared-core instances for cost optimization:
    # e2-micro: ~6 USD/month (0.25-2 vCPU shared, 1GB RAM) - Best for FalkorDB
    # e2-small: ~12 USD/month (0.5-2 vCPU shared, 2GB RAM) - Good for FalkorDB
    # e2-medium: ~24 USD/month (1-2 vCPU shared, 4GB RAM) - Good for Neo4j
    log "INFO" "Recommended machine types (shared-core for cost optimization):"
    log "INFO" "  - e2-micro (0.25-2 vCPU shared, 1GB RAM, ~6 USD/month) - Best for FalkorDB"
    log "INFO" "  - e2-small (0.5-2 vCPU shared, 2GB RAM, ~12 USD/month) - Good for FalkorDB"
    log "INFO" "  - e2-medium (1-2 vCPU shared, 4GB RAM, ~24 USD/month) - Good for Neo4j"
    log "INFO" "  - e2-standard-2 (2 vCPU, 8GB RAM, ~49 USD/month) - Production Neo4j"
    GCP_MACHINE_TYPE=$(prompt_user "Enter machine type" "$GCP_MACHINE_TYPE")
    
    log "INFO" "GCP project configuration completed"
    return 0
}

# ============================================================================
# GCP Compute Engine Instance Creation
# ============================================================================

create_gcp_instance() {
    log "INFO" "Creating GCP Compute Engine instance..."
    
    # Check if instance already exists
    if gcloud compute instances describe "$GCP_INSTANCE_NAME" --zone="$GCP_ZONE" &>/dev/null; then
        log "WARNING" "Instance '$GCP_INSTANCE_NAME' already exists"
        local response
        response=$(prompt_user "Do you want to (u)se existing, (d)elete and recreate, or (c)ancel?" "u")
        
        case "$response" in
            u|U|use)
                log "INFO" "Using existing instance"
                GCP_INSTANCE_IP=$(gcloud compute instances describe "$GCP_INSTANCE_NAME" \
                    --zone="$GCP_ZONE" \
                    --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
                log "INFO" "Instance IP: $GCP_INSTANCE_IP"
                return 0
                ;;
            d|D|delete)
                log "INFO" "Deleting existing instance..."
                gcloud compute instances delete "$GCP_INSTANCE_NAME" \
                    --zone="$GCP_ZONE" \
                    --quiet || {
                    log "ERROR" "Failed to delete existing instance"
                    return 1
                }
                ;;
            c|C|cancel|*)
                log "INFO" "Operation cancelled by user"
                exit 0
                ;;
        esac
    fi
    
    # Create instance
    log "INFO" "Creating instance: $GCP_INSTANCE_NAME"
    log "INFO" "Machine type: $GCP_MACHINE_TYPE"
    log "INFO" "Zone: $GCP_ZONE"
    
    gcloud compute instances create "$GCP_INSTANCE_NAME" \
        --zone="$GCP_ZONE" \
        --machine-type="$GCP_MACHINE_TYPE" \
        --image-family="$GCP_IMAGE_FAMILY" \
        --image-project="$GCP_IMAGE_PROJECT" \
        --boot-disk-size=50GB \
        --boot-disk-type=pd-standard \
        --tags=graphiti-mcp \
        --metadata=enable-oslogin=FALSE \
        --scopes=cloud-platform || {
        log "ERROR" "Failed to create instance"
        return 1
    }
    
    # Track resource for cleanup
    track_resource "instance" "$GCP_INSTANCE_NAME" "gcp"
    
    log "INFO" "Instance created successfully"
    
    # Wait for instance to be ready
    log "INFO" "Waiting for instance to be ready..."
    sleep 30
    
    # Get instance IP
    GCP_INSTANCE_IP=$(gcloud compute instances describe "$GCP_INSTANCE_NAME" \
        --zone="$GCP_ZONE" \
        --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
    
    if [ -z "$GCP_INSTANCE_IP" ]; then
        log "ERROR" "Failed to get instance IP address"
        return 1
    fi
    
    log "INFO" "Instance IP address: $GCP_INSTANCE_IP"
    
    return 0
}

# ============================================================================
# GCP Firewall Configuration
# ============================================================================

configure_gcp_firewall() {
    log "INFO" "Configuring GCP firewall rules..."
    
    # Check if firewall rule already exists
    if gcloud compute firewall-rules describe "$GCP_FIREWALL_RULE_NAME" &>/dev/null; then
        log "INFO" "Firewall rule '$GCP_FIREWALL_RULE_NAME' already exists"
        return 0
    fi
    
    # Create firewall rule to allow ports 80, 443, 8000
    log "INFO" "Creating firewall rule: $GCP_FIREWALL_RULE_NAME"
    
    gcloud compute firewall-rules create "$GCP_FIREWALL_RULE_NAME" \
        --direction=INGRESS \
        --priority=1000 \
        --network=default \
        --action=ALLOW \
        --rules=tcp:80,tcp:443,tcp:8000 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=graphiti-mcp \
        --description="Allow HTTP, HTTPS, and MCP traffic for Graphiti" || {
        log "ERROR" "Failed to create firewall rule"
        return 1
    }
    
    # Track resource for cleanup
    track_resource "firewall" "$GCP_FIREWALL_RULE_NAME" "gcp"
    
    log "INFO" "Firewall rule created successfully"
    return 0
}

# ============================================================================
# File Transfer to GCP Instance
# ============================================================================

copy_files_to_gcp() {
    log "INFO" "Copying installation files to GCP instance..."
    
    # Wait for SSH to be ready
    log "INFO" "Waiting for SSH to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if gcloud compute ssh "$GCP_INSTANCE_NAME" \
            --zone="$GCP_ZONE" \
            --command="echo 'SSH ready'" &>/dev/null; then
            log "INFO" "SSH connection established"
            break
        fi
        
        attempt=$((attempt + 1))
        log "INFO" "Waiting for SSH... (attempt $attempt/$max_attempts)"
        sleep 10
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log "ERROR" "SSH connection timeout"
        return 1
    fi
    
    # Create remote directory
    log "INFO" "Creating remote directory..."
    gcloud compute ssh "$GCP_INSTANCE_NAME" \
        --zone="$GCP_ZONE" \
        --command="mkdir -p /tmp/graphiti-installer" || {
        log "ERROR" "Failed to create remote directory"
        return 1
    }
    
    # Copy common scripts
    log "INFO" "Copying common scripts..."
    gcloud compute scp --recurse \
        "${SCRIPT_DIR}/common" \
        "$GCP_INSTANCE_NAME:/tmp/graphiti-installer/" \
        --zone="$GCP_ZONE" || {
        log "ERROR" "Failed to copy common scripts"
        return 1
    }
    
    # Copy docker configurations
    log "INFO" "Copying Docker configurations..."
    gcloud compute scp --recurse \
        "${SCRIPT_DIR}/docker" \
        "$GCP_INSTANCE_NAME:/tmp/graphiti-installer/" \
        --zone="$GCP_ZONE" || {
        log "ERROR" "Failed to copy Docker configurations"
        return 1
    }
    
    # Copy templates
    log "INFO" "Copying configuration templates..."
    gcloud compute scp --recurse \
        "${SCRIPT_DIR}/templates" \
        "$GCP_INSTANCE_NAME:/tmp/graphiti-installer/" \
        --zone="$GCP_ZONE" || {
        log "ERROR" "Failed to copy templates"
        return 1
    }
    
    # Copy local .env file
    log "INFO" "Copying local .env file with API keys..."
    gcloud compute scp \
        "${SCRIPT_DIR}/.env" \
        "$GCP_INSTANCE_NAME:/tmp/graphiti-installer/.env" \
        --zone="$GCP_ZONE" || {
        log "ERROR" "Failed to copy .env file"
        return 1
    }
    
    log "INFO" "Files copied successfully"
    return 0
}

# ============================================================================
# Remote Installation Execution
# ============================================================================

execute_remote_installation() {
    log "INFO" "Executing installation on remote instance..."
    
    # Create remote installation script
    local remote_script="/tmp/graphiti-installer/remote-install.sh"
    
    log "INFO" "Creating remote installation script..."
    gcloud compute ssh "$GCP_INSTANCE_NAME" \
        --zone="$GCP_ZONE" \
        --command="cat > $remote_script" << 'EOF'
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
    
    # Make script executable
    gcloud compute ssh "$GCP_INSTANCE_NAME" \
        --zone="$GCP_ZONE" \
        --command="chmod +x $remote_script" || {
        log "ERROR" "Failed to make remote script executable"
        return 1
    }
    
    # Execute installation
    log "INFO" "Running installation on remote instance..."
    log "INFO" "This may take several minutes..."
    
    gcloud compute ssh "$GCP_INSTANCE_NAME" \
        --zone="$GCP_ZONE" \
        --command="sudo bash $remote_script" || {
        log "ERROR" "Remote installation failed"
        return 1
    }
    
    log "INFO" "Remote installation completed successfully"
    return 0
}

# ============================================================================
# GCP Resource Cleanup
# ============================================================================

cleanup_gcp_resource() {
    local type="$1"
    local id="$2"
    
    log "INFO" "Cleaning up GCP $type: $id"
    
    case "$type" in
        instance)
            gcloud compute instances delete "$id" \
                --zone="$GCP_ZONE" \
                --quiet 2>/dev/null || log "WARNING" "Failed to delete instance: $id"
            ;;
        firewall)
            gcloud compute firewall-rules delete "$id" \
                --quiet 2>/dev/null || log "WARNING" "Failed to delete firewall rule: $id"
            ;;
        *)
            log "WARNING" "Unknown resource type: $type"
            ;;
    esac
}

# Override the cleanup function from utils.sh for GCP-specific cleanup
cleanup_gcp_resource_override() {
    cleanup_gcp_resource "$@"
}

# ============================================================================
# Display Installation Results
# ============================================================================

display_results() {
    log "INFO" "========================================="
    log "INFO" "Graphiti Installation Completed!"
    log "INFO" "========================================="
    log "INFO" ""
    log "INFO" "Instance Details:"
    log "INFO" "  - Name: $GCP_INSTANCE_NAME"
    log "INFO" "  - IP Address: $GCP_INSTANCE_IP"
    log "INFO" "  - Zone: $GCP_ZONE"
    log "INFO" ""
    log "INFO" "MCP Endpoint URLs:"
    log "INFO" "  - HTTP: http://${GCP_INSTANCE_IP}:8000/mcp/"
    log "INFO" "  - Health Check: http://${GCP_INSTANCE_IP}:8000/health"
    log "INFO" ""
    
    # Check if domain is configured for HTTPS
    local domain
    domain=$(gcloud compute ssh "$GCP_INSTANCE_NAME" \
        --zone="$GCP_ZONE" \
        --command="grep '^DOMAIN_NAME=' /opt/graphiti/.env 2>/dev/null | cut -d'=' -f2" 2>/dev/null || echo "")
    
    if [ -n "$domain" ]; then
        log "INFO" "  - HTTPS: https://${domain}/mcp/"
    fi
    
    log "INFO" ""
    log "INFO" "Next Steps:"
    log "INFO" "  1. Configure your MCP client with the endpoint URL"
    log "INFO" "  2. Test the connection: curl http://${GCP_INSTANCE_IP}:8000/health"
    log "INFO" "  3. View logs: gcloud compute ssh $GCP_INSTANCE_NAME --zone=$GCP_ZONE --command='docker logs graphiti-mcp'"
    log "INFO" ""
    log "INFO" "To SSH into the instance:"
    log "INFO" "  gcloud compute ssh $GCP_INSTANCE_NAME --zone=$GCP_ZONE"
    log "INFO" ""
    log "INFO" "To delete the instance:"
    log "INFO" "  gcloud compute instances delete $GCP_INSTANCE_NAME --zone=$GCP_ZONE"
    log "INFO" "========================================="
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    log "INFO" "Starting Graphiti Cloud Installer for GCP"
    log "INFO" "========================================="
    
    # Set up cleanup trap
    trap cleanup EXIT ERR
    
    # Step 1: Check prerequisites
    check_gcp_prerequisites || {
        log "ERROR" "Prerequisites check failed"
        exit 1
    }
    
    # Step 2: Authenticate with GCP
    authenticate_gcp || {
        log "ERROR" "GCP authentication failed"
        exit 1
    }
    
    # Step 2.5: Validate local .env file
    log "INFO" "Validating local .env file..."
    validate_local_env "${SCRIPT_DIR}/.env" || {
        log "ERROR" "Local .env validation failed"
        log "INFO" "Please create a .env file in the project root with at least one API key"
        exit 1
    }
    
    # Step 3: Configure GCP project
    configure_gcp_project || {
        log "ERROR" "GCP project configuration failed"
        exit 1
    }
    
    # Step 4: Configure firewall rules
    configure_gcp_firewall || {
        log "ERROR" "Firewall configuration failed"
        exit 1
    }
    
    # Step 5: Create GCP instance
    create_gcp_instance || {
        log "ERROR" "Instance creation failed"
        exit 1
    }
    
    # Step 6: Copy installation files
    copy_files_to_gcp || {
        log "ERROR" "File transfer failed"
        exit 1
    }
    
    # Step 7: Execute remote installation
    execute_remote_installation || {
        log "ERROR" "Remote installation failed"
        exit 1
    }
    
    # Step 8: Display results
    display_results
    
    log "INFO" "GCP installation completed successfully!"
    exit 0
}

# Run main function
main "$@"
