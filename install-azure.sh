#!/bin/bash

# Graphiti Cloud Installer - Microsoft Azure
# This script automates the deployment of Graphiti on Azure Virtual Machines
# It creates a VM, configures network security groups, and installs Graphiti with MCP support

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/common/utils.sh"

# Azure-specific variables
AZURE_RESOURCE_GROUP=""
AZURE_REGION=""
AZURE_VM_NAME="graphiti-mcp-vm"
AZURE_VM_SIZE="Standard_B1s"  # 1 vCPU, 1GB RAM - Lowest cost option
AZURE_IMAGE="Ubuntu2204"
AZURE_NSG_NAME="graphiti-mcp-nsg"
AZURE_VNET_NAME="graphiti-mcp-vnet"
AZURE_SUBNET_NAME="graphiti-mcp-subnet"
AZURE_PUBLIC_IP_NAME="graphiti-mcp-ip"
AZURE_NIC_NAME="graphiti-mcp-nic"
AZURE_VM_IP=""
AZURE_SSH_KEY_PATH="${HOME}/.ssh/graphiti-azure-key"

# ============================================================================
# Azure Prerequisites Check
# ============================================================================

check_azure_prerequisites() {
    log "INFO" "Checking Azure prerequisites..."
    
    # Check if az CLI is installed
    if ! check_command az; then
        log "ERROR" "az CLI is not installed"
        log "INFO" "Please install az CLI from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        return 1
    fi
    
    # Check az CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log "INFO" "az CLI version: $az_version"
    
    log "INFO" "Azure prerequisites check completed"
    return 0
}

# ============================================================================
# Azure Authentication
# ============================================================================

authenticate_azure() {
    log "INFO" "Authenticating with Microsoft Azure..."
    
    # Check if already authenticated
    local current_account
    current_account=$(az account show --query user.name -o tsv 2>/dev/null || echo "")
    
    if [ -n "$current_account" ]; then
        log "INFO" "Already authenticated as: $current_account"
        
        local subscription_name
        subscription_name=$(az account show --query name -o tsv 2>/dev/null || echo "")
        log "INFO" "Current subscription: $subscription_name"
        
        local response
        response=$(prompt_user "Do you want to use this account? (y/n)" "y")
        
        if [[ ! "$response" =~ ^[Yy] ]]; then
            log "INFO" "Initiating new authentication..."
            az login || {
                log "ERROR" "Authentication failed"
                return 1
            }
        fi
    else
        log "INFO" "No active account found, initiating authentication..."
        az login || {
            log "ERROR" "Authentication failed"
            return 1
        }
    fi
    
    log "INFO" "Azure authentication successful"
    return 0
}

# ============================================================================
# Azure Configuration
# ============================================================================

configure_azure() {
    log "INFO" "Configuring Azure deployment..."
    
    # Prompt for resource group
    AZURE_RESOURCE_GROUP=$(prompt_user "Enter Azure resource group name" "graphiti-mcp-rg")
    
    # Prompt for region
    log "INFO" "Common Azure regions:"
    log "INFO" "  - eastus (East US)"
    log "INFO" "  - westus2 (West US 2)"
    log "INFO" "  - westeurope (West Europe)"
    log "INFO" "  - southeastasia (Southeast Asia)"
    AZURE_REGION=$(prompt_user "Enter Azure region" "eastus")
    
    # Validate that the region exists and is available
    log "INFO" "Validating Azure region: $AZURE_REGION..."
    if az account list-locations --query "[?name=='$AZURE_REGION'].name" --output tsv 2>/dev/null | grep -q "$AZURE_REGION"; then
        log "INFO" "Using Azure region: $AZURE_REGION"
    else
        log "WARNING" "Region $AZURE_REGION may not be valid or accessible"
        log "INFO" "Attempting to list available regions..."
        az account list-locations --query '[].name' --output tsv 2>/dev/null | head -20 || true
        log "WARNING" "Continuing with region: $AZURE_REGION"
    fi
    
    # Prompt for VM name
    AZURE_VM_NAME=$(prompt_user "Enter VM name" "$AZURE_VM_NAME")
    
    # Prompt for VM size
    # B-series burstable VMs for cost optimization:
    # Standard_B1s: ~7.50 USD/month (1 vCPU, 1GB RAM) - Best for FalkorDB
    # Standard_B1ms: ~15 USD/month (1 vCPU, 2GB RAM) - Good for FalkorDB
    # Standard_B2s: ~30 USD/month (2 vCPU, 4GB RAM) - Good for Neo4j
    log "INFO" "Recommended VM sizes (B-series burstable for cost optimization):"
    log "INFO" "  - Standard_B1s (1 vCPU, 1GB RAM, ~7.50 USD/month) - Best for FalkorDB"
    log "INFO" "  - Standard_B1ms (1 vCPU, 2GB RAM, ~15 USD/month) - Good for FalkorDB"
    log "INFO" "  - Standard_B2s (2 vCPU, 4GB RAM, ~30 USD/month) - Good for Neo4j"
    log "INFO" "  - Standard_B2ms (2 vCPU, 8GB RAM, ~60 USD/month) - Production Neo4j"
    AZURE_VM_SIZE=$(prompt_user "Enter VM size" "$AZURE_VM_SIZE")
    
    log "INFO" "Azure configuration completed"
    return 0
}

# ============================================================================
# Create or Get Resource Group
# ============================================================================

setup_resource_group() {
    log "INFO" "Setting up resource group..."
    
    # Check if resource group exists
    if az group show --name "$AZURE_RESOURCE_GROUP" &>/dev/null; then
        log "INFO" "Resource group '$AZURE_RESOURCE_GROUP' already exists"
        
        local response
        response=$(prompt_user "Do you want to (u)se existing or (c)ancel?" "u")
        
        case "$response" in
            u|U|use)
                log "INFO" "Using existing resource group"
                return 0
                ;;
            c|C|cancel|*)
                log "INFO" "Operation cancelled by user"
                exit 0
                ;;
        esac
    fi
    
    # Create resource group
    log "INFO" "Creating resource group: $AZURE_RESOURCE_GROUP"
    
    az group create \
        --name "$AZURE_RESOURCE_GROUP" \
        --location "$AZURE_REGION" || {
        log "ERROR" "Failed to create resource group"
        return 1
    }
    
    # Track resource for cleanup
    track_resource "resource_group" "$AZURE_RESOURCE_GROUP" "azure"
    
    log "INFO" "Resource group created successfully"
    return 0
}

# ============================================================================
# Setup SSH Key
# ============================================================================

setup_ssh_key() {
    log "INFO" "Setting up SSH key..."
    
    # Check if SSH key already exists
    if [ -f "$AZURE_SSH_KEY_PATH" ]; then
        log "INFO" "SSH key already exists: $AZURE_SSH_KEY_PATH"
        
        local response
        response=$(prompt_user "Do you want to (u)se existing or (c)reate new key?" "u")
        
        case "$response" in
            u|U|use)
                log "INFO" "Using existing SSH key"
                return 0
                ;;
            c|C|create)
                log "INFO" "Creating new SSH key..."
                rm -f "$AZURE_SSH_KEY_PATH" "${AZURE_SSH_KEY_PATH}.pub"
                ;;
            *)
                log "INFO" "Using existing SSH key"
                return 0
                ;;
        esac
    fi
    
    # Create SSH key
    log "INFO" "Generating SSH key pair..."
    
    mkdir -p "${HOME}/.ssh"
    
    ssh-keygen -t rsa -b 4096 -f "$AZURE_SSH_KEY_PATH" -N "" -C "graphiti-azure-key" || {
        log "ERROR" "Failed to generate SSH key"
        return 1
    }
    
    chmod 600 "$AZURE_SSH_KEY_PATH"
    chmod 644 "${AZURE_SSH_KEY_PATH}.pub"
    
    log "INFO" "SSH key created: $AZURE_SSH_KEY_PATH"
    return 0
}

# ============================================================================
# Create Network Security Group
# ============================================================================

create_network_security_group() {
    log "INFO" "Creating network security group..."
    
    # Check if NSG already exists
    if az network nsg show \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_NSG_NAME" &>/dev/null; then
        log "INFO" "Network security group '$AZURE_NSG_NAME' already exists"
        return 0
    fi
    
    # Create NSG
    log "INFO" "Creating NSG: $AZURE_NSG_NAME"
    
    az network nsg create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_NSG_NAME" \
        --location "$AZURE_REGION" || {
        log "ERROR" "Failed to create network security group"
        return 1
    }
    
    # Track resource for cleanup
    track_resource "nsg" "$AZURE_NSG_NAME" "azure"
    
    log "INFO" "Network security group created successfully"
    
    # Add security rules
    log "INFO" "Configuring security rules..."
    
    # SSH (port 22)
    az network nsg rule create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --nsg-name "$AZURE_NSG_NAME" \
        --name "AllowSSH" \
        --priority 1000 \
        --source-address-prefixes '*' \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 22 \
        --access Allow \
        --protocol Tcp \
        --description "Allow SSH" || log "WARNING" "Failed to add SSH rule"
    
    # HTTP (port 80)
    az network nsg rule create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --nsg-name "$AZURE_NSG_NAME" \
        --name "AllowHTTP" \
        --priority 1001 \
        --source-address-prefixes '*' \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 80 \
        --access Allow \
        --protocol Tcp \
        --description "Allow HTTP" || log "WARNING" "Failed to add HTTP rule"
    
    # HTTPS (port 443)
    az network nsg rule create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --nsg-name "$AZURE_NSG_NAME" \
        --name "AllowHTTPS" \
        --priority 1002 \
        --source-address-prefixes '*' \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 443 \
        --access Allow \
        --protocol Tcp \
        --description "Allow HTTPS" || log "WARNING" "Failed to add HTTPS rule"
    
    # MCP (port 8000)
    az network nsg rule create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --nsg-name "$AZURE_NSG_NAME" \
        --name "AllowMCP" \
        --priority 1003 \
        --source-address-prefixes '*' \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 8000 \
        --access Allow \
        --protocol Tcp \
        --description "Allow MCP" || log "WARNING" "Failed to add MCP rule"
    
    log "INFO" "Security rules configured successfully"
    return 0
}

# ============================================================================
# Create Virtual Network
# ============================================================================

create_virtual_network() {
    log "INFO" "Creating virtual network..."
    
    # Check if VNet already exists
    if az network vnet show \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_VNET_NAME" &>/dev/null; then
        log "INFO" "Virtual network '$AZURE_VNET_NAME' already exists"
        return 0
    fi
    
    # Create VNet with subnet
    log "INFO" "Creating VNet: $AZURE_VNET_NAME"
    
    az network vnet create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_VNET_NAME" \
        --location "$AZURE_REGION" \
        --address-prefix 10.0.0.0/16 \
        --subnet-name "$AZURE_SUBNET_NAME" \
        --subnet-prefix 10.0.1.0/24 || {
        log "ERROR" "Failed to create virtual network"
        return 1
    }
    
    # Track resource for cleanup
    track_resource "vnet" "$AZURE_VNET_NAME" "azure"
    
    log "INFO" "Virtual network created successfully"
    return 0
}

# ============================================================================
# Create Public IP Address
# ============================================================================

create_public_ip() {
    log "INFO" "Creating public IP address..."
    
    # Check if public IP already exists
    if az network public-ip show \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_PUBLIC_IP_NAME" &>/dev/null; then
        log "INFO" "Public IP '$AZURE_PUBLIC_IP_NAME' already exists"
        
        AZURE_VM_IP=$(az network public-ip show \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --name "$AZURE_PUBLIC_IP_NAME" \
            --query ipAddress -o tsv)
        
        log "INFO" "Public IP address: $AZURE_VM_IP"
        return 0
    fi
    
    # Create public IP
    log "INFO" "Creating public IP: $AZURE_PUBLIC_IP_NAME"
    
    az network public-ip create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_PUBLIC_IP_NAME" \
        --location "$AZURE_REGION" \
        --allocation-method Static \
        --sku Standard || {
        log "ERROR" "Failed to create public IP"
        return 1
    }
    
    # Track resource for cleanup
    track_resource "public_ip" "$AZURE_PUBLIC_IP_NAME" "azure"
    
    # Get IP address
    AZURE_VM_IP=$(az network public-ip show \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_PUBLIC_IP_NAME" \
        --query ipAddress -o tsv)
    
    log "INFO" "Public IP address: $AZURE_VM_IP"
    return 0
}

# ============================================================================
# Create Network Interface
# ============================================================================

create_network_interface() {
    log "INFO" "Creating network interface..."
    
    # Check if NIC already exists
    if az network nic show \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_NIC_NAME" &>/dev/null; then
        log "INFO" "Network interface '$AZURE_NIC_NAME' already exists"
        return 0
    fi
    
    # Create NIC
    log "INFO" "Creating NIC: $AZURE_NIC_NAME"
    
    az network nic create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_NIC_NAME" \
        --location "$AZURE_REGION" \
        --vnet-name "$AZURE_VNET_NAME" \
        --subnet "$AZURE_SUBNET_NAME" \
        --public-ip-address "$AZURE_PUBLIC_IP_NAME" \
        --network-security-group "$AZURE_NSG_NAME" || {
        log "ERROR" "Failed to create network interface"
        return 1
    }
    
    # Track resource for cleanup
    track_resource "nic" "$AZURE_NIC_NAME" "azure"
    
    log "INFO" "Network interface created successfully"
    return 0
}

# ============================================================================
# Create Azure VM
# ============================================================================

create_azure_vm() {
    log "INFO" "Creating Azure VM..."
    
    # Check if VM already exists
    if az vm show \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_VM_NAME" &>/dev/null; then
        log "WARNING" "VM '$AZURE_VM_NAME' already exists"
        
        local response
        response=$(prompt_user "Do you want to (u)se existing, (d)elete and recreate, or (c)ancel?" "u")
        
        case "$response" in
            u|U|use)
                log "INFO" "Using existing VM"
                
                # Get VM state
                local vm_state
                vm_state=$(az vm get-instance-view \
                    --resource-group "$AZURE_RESOURCE_GROUP" \
                    --name "$AZURE_VM_NAME" \
                    --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv)
                
                log "INFO" "VM state: $vm_state"
                
                # Start VM if stopped
                if [[ "$vm_state" == *"deallocated"* ]] || [[ "$vm_state" == *"stopped"* ]]; then
                    log "INFO" "Starting VM..."
                    az vm start \
                        --resource-group "$AZURE_RESOURCE_GROUP" \
                        --name "$AZURE_VM_NAME" || {
                        log "ERROR" "Failed to start VM"
                        return 1
                    }
                fi
                
                return 0
                ;;
            d|D|delete)
                log "INFO" "Deleting existing VM..."
                az vm delete \
                    --resource-group "$AZURE_RESOURCE_GROUP" \
                    --name "$AZURE_VM_NAME" \
                    --yes || {
                    log "ERROR" "Failed to delete existing VM"
                    return 1
                }
                
                log "INFO" "Waiting for VM deletion to complete..."
                sleep 10
                ;;
            c|C|cancel|*)
                log "INFO" "Operation cancelled by user"
                exit 0
                ;;
        esac
    fi
    
    # Create VM
    log "INFO" "Creating VM: $AZURE_VM_NAME"
    log "INFO" "  - VM size: $AZURE_VM_SIZE"
    log "INFO" "  - Image: $AZURE_IMAGE"
    log "INFO" "  - Region: $AZURE_REGION"
    
    az vm create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_VM_NAME" \
        --location "$AZURE_REGION" \
        --size "$AZURE_VM_SIZE" \
        --image "$AZURE_IMAGE" \
        --nics "$AZURE_NIC_NAME" \
        --ssh-key-values "@${AZURE_SSH_KEY_PATH}.pub" \
        --admin-username azureuser \
        --os-disk-size-gb 50 \
        --storage-sku Standard_LRS || {
        log "ERROR" "Failed to create VM"
        return 1
    }
    
    # Track resource for cleanup
    track_resource "vm" "$AZURE_VM_NAME" "azure"
    
    log "INFO" "VM created successfully"
    
    # Wait for VM to be ready
    log "INFO" "Waiting for VM to be ready..."
    sleep 30
    
    log "INFO" "VM is ready"
    log "INFO" "VM IP address: $AZURE_VM_IP"
    
    return 0
}

# ============================================================================
# File Transfer to Azure VM
# ============================================================================

copy_files_to_azure() {
    log "INFO" "Copying installation files to Azure VM..."
    
    # Wait for SSH to be ready
    log "INFO" "Waiting for SSH to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if ssh -i "$AZURE_SSH_KEY_PATH" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 \
            "azureuser@${AZURE_VM_IP}" \
            "echo 'SSH ready'" &>/dev/null; then
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
    ssh -i "$AZURE_SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "azureuser@${AZURE_VM_IP}" \
        "mkdir -p /tmp/graphiti-installer" || {
        log "ERROR" "Failed to create remote directory"
        return 1
    }
    
    # Copy common scripts
    log "INFO" "Copying common scripts..."
    scp -i "$AZURE_SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -r "${SCRIPT_DIR}/common" \
        "azureuser@${AZURE_VM_IP}:/tmp/graphiti-installer/" || {
        log "ERROR" "Failed to copy common scripts"
        return 1
    }
    
    # Copy docker configurations
    log "INFO" "Copying Docker configurations..."
    scp -i "$AZURE_SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -r "${SCRIPT_DIR}/docker" \
        "azureuser@${AZURE_VM_IP}:/tmp/graphiti-installer/" || {
        log "ERROR" "Failed to copy Docker configurations"
        return 1
    }
    
    # Copy templates
    log "INFO" "Copying configuration templates..."
    scp -i "$AZURE_SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -r "${SCRIPT_DIR}/templates" \
        "azureuser@${AZURE_VM_IP}:/tmp/graphiti-installer/" || {
        log "ERROR" "Failed to copy templates"
        return 1
    }
    
    # Copy local .env file
    log "INFO" "Copying local .env file with API keys..."
    scp -i "$AZURE_SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "${SCRIPT_DIR}/.env" \
        "azureuser@${AZURE_VM_IP}:/tmp/graphiti-installer/.env" || {
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
    log "INFO" "Executing installation on remote VM..."
    
    # Create remote installation script
    local remote_script="/tmp/graphiti-installer/remote-install.sh"
    
    log "INFO" "Creating remote installation script..."
    ssh -i "$AZURE_SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "azureuser@${AZURE_VM_IP}" \
        "cat > $remote_script" << 'EOF'
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
    ssh -i "$AZURE_SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "azureuser@${AZURE_VM_IP}" \
        "chmod +x $remote_script" || {
        log "ERROR" "Failed to make remote script executable"
        return 1
    }
    
    # Execute installation
    log "INFO" "Running installation on remote VM..."
    log "INFO" "This may take several minutes..."
    
    ssh -i "$AZURE_SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "azureuser@${AZURE_VM_IP}" \
        "sudo bash $remote_script" || {
        log "ERROR" "Remote installation failed"
        return 1
    }
    
    log "INFO" "Remote installation completed successfully"
    return 0
}

# ============================================================================
# Azure Resource Cleanup
# ============================================================================

cleanup_azure_resource() {
    local type="$1"
    local id="$2"
    
    log "INFO" "Cleaning up Azure $type: $id"
    
    case "$type" in
        vm)
            az vm delete \
                --resource-group "$AZURE_RESOURCE_GROUP" \
                --name "$id" \
                --yes 2>/dev/null || log "WARNING" "Failed to delete VM: $id"
            ;;
        nic)
            az network nic delete \
                --resource-group "$AZURE_RESOURCE_GROUP" \
                --name "$id" 2>/dev/null || log "WARNING" "Failed to delete NIC: $id"
            ;;
        public_ip)
            az network public-ip delete \
                --resource-group "$AZURE_RESOURCE_GROUP" \
                --name "$id" 2>/dev/null || log "WARNING" "Failed to delete public IP: $id"
            ;;
        vnet)
            az network vnet delete \
                --resource-group "$AZURE_RESOURCE_GROUP" \
                --name "$id" 2>/dev/null || log "WARNING" "Failed to delete VNet: $id"
            ;;
        nsg)
            az network nsg delete \
                --resource-group "$AZURE_RESOURCE_GROUP" \
                --name "$id" 2>/dev/null || log "WARNING" "Failed to delete NSG: $id"
            ;;
        resource_group)
            az group delete \
                --name "$id" \
                --yes 2>/dev/null || log "WARNING" "Failed to delete resource group: $id"
            ;;
        *)
            log "WARNING" "Unknown resource type: $type"
            ;;
    esac
}

# Override the cleanup function from utils.sh for Azure-specific cleanup
cleanup_azure_resource_override() {
    cleanup_azure_resource "$@"
}

# ============================================================================
# Display Installation Results
# ============================================================================

display_results() {
    log "INFO" "========================================="
    log "INFO" "Graphiti Installation Completed!"
    log "INFO" "========================================="
    log "INFO" ""
    log "INFO" "VM Details:"
    log "INFO" "  - Name: $AZURE_VM_NAME"
    log "INFO" "  - IP Address: $AZURE_VM_IP"
    log "INFO" "  - Region: $AZURE_REGION"
    log "INFO" "  - VM Size: $AZURE_VM_SIZE"
    log "INFO" "  - Resource Group: $AZURE_RESOURCE_GROUP"
    log "INFO" ""
    log "INFO" "MCP Endpoint URLs:"
    log "INFO" "  - HTTP: http://${AZURE_VM_IP}:8000/mcp/"
    log "INFO" "  - Health Check: http://${AZURE_VM_IP}:8000/health"
    log "INFO" ""
    
    # Check if domain is configured for HTTPS
    local domain
    domain=$(ssh -i "$AZURE_SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "azureuser@${AZURE_VM_IP}" \
        "grep '^DOMAIN_NAME=' /opt/graphiti/.env 2>/dev/null | cut -d'=' -f2" 2>/dev/null || echo "")
    
    if [ -n "$domain" ]; then
        log "INFO" "  - HTTPS: https://${domain}/mcp/"
    fi
    
    log "INFO" ""
    log "INFO" "Next Steps:"
    log "INFO" "  1. Configure your MCP client with the endpoint URL"
    log "INFO" "  2. Test the connection: curl http://${AZURE_VM_IP}:8000/health"
    log "INFO" "  3. View logs: ssh -i $AZURE_SSH_KEY_PATH azureuser@${AZURE_VM_IP} 'docker logs graphiti-mcp'"
    log "INFO" ""
    log "INFO" "To SSH into the VM:"
    log "INFO" "  ssh -i $AZURE_SSH_KEY_PATH azureuser@${AZURE_VM_IP}"
    log "INFO" ""
    log "INFO" "To delete the VM:"
    log "INFO" "  az vm delete --resource-group $AZURE_RESOURCE_GROUP --name $AZURE_VM_NAME --yes"
    log "INFO" ""
    log "INFO" "To delete the entire resource group:"
    log "INFO" "  az group delete --name $AZURE_RESOURCE_GROUP --yes"
    log "INFO" "========================================="
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    log "INFO" "Starting Graphiti Cloud Installer for Azure"
    log "INFO" "========================================="
    
    # Set up cleanup trap
    trap cleanup EXIT ERR
    
    # Step 1: Check prerequisites
    check_azure_prerequisites || {
        log "ERROR" "Prerequisites check failed"
        exit 1
    }
    
    # Step 2: Authenticate with Azure
    authenticate_azure || {
        log "ERROR" "Azure authentication failed"
        exit 1
    }
    
    # Step 2.5: Validate local .env file
    log "INFO" "Validating local .env file..."
    validate_local_env "${SCRIPT_DIR}/.env" || {
        log "ERROR" "Local .env validation failed"
        log "INFO" "Please create a .env file in the project root with at least one API key"
        exit 1
    }
    
    # Step 3: Configure Azure deployment
    configure_azure || {
        log "ERROR" "Azure configuration failed"
        exit 1
    }
    
    # Step 4: Setup resource group
    setup_resource_group || {
        log "ERROR" "Resource group setup failed"
        exit 1
    }
    
    # Step 5: Setup SSH key
    setup_ssh_key || {
        log "ERROR" "SSH key setup failed"
        exit 1
    }
    
    # Step 6: Create network security group
    create_network_security_group || {
        log "ERROR" "Network security group creation failed"
        exit 1
    }
    
    # Step 7: Create virtual network
    create_virtual_network || {
        log "ERROR" "Virtual network creation failed"
        exit 1
    }
    
    # Step 8: Create public IP
    create_public_ip || {
        log "ERROR" "Public IP creation failed"
        exit 1
    }
    
    # Step 9: Create network interface
    create_network_interface || {
        log "ERROR" "Network interface creation failed"
        exit 1
    }
    
    # Step 10: Create Azure VM
    create_azure_vm || {
        log "ERROR" "VM creation failed"
        exit 1
    }
    
    # Step 11: Copy installation files
    copy_files_to_azure || {
        log "ERROR" "File transfer failed"
        exit 1
    }
    
    # Step 12: Execute remote installation
    execute_remote_installation || {
        log "ERROR" "Remote installation failed"
        exit 1
    }
    
    # Step 13: Display results
    display_results
    
    log "INFO" "Azure installation completed successfully!"
    exit 0
}

# Run main function
main "$@"
