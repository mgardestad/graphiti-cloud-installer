#!/bin/bash

# Graphiti Cloud Installer - Amazon Web Services (AWS)
# This script automates the deployment of Graphiti on AWS EC2
# It creates an EC2 instance, configures security groups, and installs Graphiti with MCP support

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/common/utils.sh"

# AWS-specific variables
AWS_REGION=""
AWS_INSTANCE_TYPE="t3.micro"  # 2 vCPU, 1GB RAM - Lowest cost option
AWS_INSTANCE_NAME="graphiti-mcp-instance"
AWS_AMI_ID=""
AWS_KEY_NAME="graphiti-mcp-key"
AWS_SECURITY_GROUP_NAME="graphiti-mcp-sg"
AWS_SECURITY_GROUP_ID=""
AWS_INSTANCE_ID=""
AWS_INSTANCE_IP=""

# ============================================================================
# AWS Prerequisites Check
# ============================================================================

check_aws_prerequisites() {
    log "INFO" "Checking AWS prerequisites..."
    
    # Check if aws CLI is installed
    if ! check_command aws; then
        log "ERROR" "aws CLI is not installed"
        log "INFO" "Please install aws CLI from: https://aws.amazon.com/cli/"
        return 1
    fi
    
    # Check aws CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2 || echo "unknown")
    log "INFO" "aws CLI version: $aws_version"
    
    log "INFO" "AWS prerequisites check completed"
    return 0
}

# ============================================================================
# AWS Authentication
# ============================================================================

authenticate_aws() {
    log "INFO" "Authenticating with Amazon Web Services..."
    
    # Check if AWS credentials are configured
    if aws sts get-caller-identity &>/dev/null; then
        local account_id
        local user_arn
        account_id=$(aws sts get-caller-identity --query Account --output text)
        user_arn=$(aws sts get-caller-identity --query Arn --output text)
        
        log "INFO" "Already authenticated"
        log "INFO" "  - Account ID: $account_id"
        log "INFO" "  - User/Role: $user_arn"
        
        local response
        response=$(prompt_user "Do you want to use these credentials? (y/n)" "y")
        
        if [[ ! "$response" =~ ^[Yy] ]]; then
            log "INFO" "Please configure AWS credentials using 'aws configure'"
            log "INFO" "You will need:"
            log "INFO" "  - AWS Access Key ID"
            log "INFO" "  - AWS Secret Access Key"
            log "INFO" "  - Default region"
            
            aws configure || {
                log "ERROR" "AWS configuration failed"
                return 1
            }
        fi
    else
        log "INFO" "No AWS credentials found"
        log "INFO" "Please configure AWS credentials using 'aws configure'"
        log "INFO" "You will need:"
        log "INFO" "  - AWS Access Key ID"
        log "INFO" "  - AWS Secret Access Key"
        log "INFO" "  - Default region"
        
        aws configure || {
            log "ERROR" "AWS configuration failed"
            return 1
        }
    fi
    
    log "INFO" "AWS authentication successful"
    return 0
}

# ============================================================================
# AWS Configuration
# ============================================================================

configure_aws() {
    log "INFO" "Configuring AWS deployment..."
    
    # Get current default region
    local current_region
    current_region=$(aws configure get region 2>/dev/null || echo "")
    
    # Prompt for region
    log "INFO" "Common AWS regions:"
    log "INFO" "  - us-east-1 (N. Virginia)"
    log "INFO" "  - us-west-2 (Oregon)"
    log "INFO" "  - eu-west-1 (Ireland)"
    log "INFO" "  - ap-southeast-1 (Singapore)"
    
    if [ -n "$current_region" ]; then
        AWS_REGION=$(prompt_user "Enter AWS region" "$current_region")
    else
        AWS_REGION=$(prompt_user "Enter AWS region" "us-east-1")
    fi
    
    # Validate that the region exists and is available
    log "INFO" "Validating AWS region: $AWS_REGION..."
    if aws ec2 describe-regions --region-names "$AWS_REGION" &>/dev/null; then
        log "INFO" "Using AWS region: $AWS_REGION"
    else
        log "WARNING" "Region $AWS_REGION may not be valid or accessible"
        log "INFO" "Attempting to list available regions..."
        aws ec2 describe-regions --query 'Regions[].RegionName' --output text 2>/dev/null || true
        log "WARNING" "Continuing with region: $AWS_REGION"
    fi
    
    # Prompt for instance type
    # Burstable instances for cost optimization:
    # t3.micro: ~7.50 USD/month (2 vCPU, 1GB RAM) - Best for FalkorDB
    # t3.small: ~15 USD/month (2 vCPU, 2GB RAM) - Good for FalkorDB
    # t3.medium: ~30 USD/month (2 vCPU, 4GB RAM) - Good for Neo4j
    log "INFO" "Recommended instance types (burstable for cost optimization):"
    log "INFO" "  - t3.micro (2 vCPU, 1GB RAM, ~7.50 USD/month) - Best for FalkorDB"
    log "INFO" "  - t3.small (2 vCPU, 2GB RAM, ~15 USD/month) - Good for FalkorDB"
    log "INFO" "  - t3.medium (2 vCPU, 4GB RAM, ~30 USD/month) - Good for Neo4j"
    log "INFO" "  - t3.large (2 vCPU, 8GB RAM, ~60 USD/month) - Production Neo4j"

    AWS_INSTANCE_TYPE=$(prompt_user "Enter instance type" "$AWS_INSTANCE_TYPE")
    
    # Prompt for instance name
    AWS_INSTANCE_NAME=$(prompt_user "Enter instance name" "$AWS_INSTANCE_NAME")
    
    log "INFO" "AWS configuration completed"
    return 0
}

# ============================================================================
# Get Latest Ubuntu AMI
# ============================================================================

get_ubuntu_ami() {
    log "INFO" "Finding latest Ubuntu 22.04 LTS AMI..."
    
    # Get latest Ubuntu 22.04 LTS AMI for the region
    AWS_AMI_ID=$(aws ec2 describe-images \
        --region "$AWS_REGION" \
        --owners 099720109477 \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$AWS_AMI_ID" ] || [ "$AWS_AMI_ID" = "None" ]; then
        log "ERROR" "Failed to find Ubuntu AMI for region $AWS_REGION"
        return 1
    fi
    
    log "INFO" "Using AMI: $AWS_AMI_ID"
    return 0
}

# ============================================================================
# Create or Get SSH Key Pair
# ============================================================================

setup_ssh_key() {
    log "INFO" "Setting up SSH key pair..."
    
    # Check if key pair already exists in AWS
    if aws ec2 describe-key-pairs \
        --region "$AWS_REGION" \
        --key-names "$AWS_KEY_NAME" &>/dev/null; then
        log "INFO" "Key pair '$AWS_KEY_NAME' already exists in AWS"
        
        # Check if local key file exists
        if [ -f "${HOME}/.ssh/${AWS_KEY_NAME}.pem" ]; then
            log "INFO" "Local key file found: ${HOME}/.ssh/${AWS_KEY_NAME}.pem"
            return 0
        else
            log "WARNING" "Key pair exists in AWS but local key file not found"
            local response
            response=$(prompt_user "Do you want to (c)reate new key pair or (s)pecify existing key file path?" "c")
            
            case "$response" in
                s|S|specify)
                    local key_path
                    key_path=$(prompt_user "Enter path to existing .pem file" "")
                    if [ -f "$key_path" ]; then
                        cp "$key_path" "${HOME}/.ssh/${AWS_KEY_NAME}.pem"
                        chmod 600 "${HOME}/.ssh/${AWS_KEY_NAME}.pem"
                        log "INFO" "Using existing key file"
                        return 0
                    else
                        log "ERROR" "Key file not found: $key_path"
                        return 1
                    fi
                    ;;
                c|C|create|*)
                    log "INFO" "Deleting existing key pair from AWS..."
                    aws ec2 delete-key-pair \
                        --region "$AWS_REGION" \
                        --key-name "$AWS_KEY_NAME" || {
                        log "ERROR" "Failed to delete existing key pair"
                        return 1
                    }
                    ;;
            esac
        fi
    fi
    
    # Create new key pair
    log "INFO" "Creating new SSH key pair: $AWS_KEY_NAME"
    
    mkdir -p "${HOME}/.ssh"
    
    aws ec2 create-key-pair \
        --region "$AWS_REGION" \
        --key-name "$AWS_KEY_NAME" \
        --query 'KeyMaterial' \
        --output text > "${HOME}/.ssh/${AWS_KEY_NAME}.pem" || {
        log "ERROR" "Failed to create key pair"
        return 1
    }
    
    chmod 600 "${HOME}/.ssh/${AWS_KEY_NAME}.pem"
    
    # Track resource for cleanup
    track_resource "keypair" "$AWS_KEY_NAME" "aws"
    
    log "INFO" "SSH key pair created: ${HOME}/.ssh/${AWS_KEY_NAME}.pem"
    return 0
}

# ============================================================================
# Create Security Group
# ============================================================================

create_security_group() {
    log "INFO" "Creating security group..."
    
    # Check if security group already exists
    AWS_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
        --region "$AWS_REGION" \
        --filters "Name=group-name,Values=$AWS_SECURITY_GROUP_NAME" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$AWS_SECURITY_GROUP_ID" ] && [ "$AWS_SECURITY_GROUP_ID" != "None" ]; then
        log "INFO" "Security group '$AWS_SECURITY_GROUP_NAME' already exists: $AWS_SECURITY_GROUP_ID"
        return 0
    fi
    
    # Create security group
    log "INFO" "Creating security group: $AWS_SECURITY_GROUP_NAME"
    
    AWS_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --region "$AWS_REGION" \
        --group-name "$AWS_SECURITY_GROUP_NAME" \
        --description "Security group for Graphiti MCP server" \
        --query 'GroupId' \
        --output text) || {
        log "ERROR" "Failed to create security group"
        return 1
    }
    
    log "INFO" "Security group created: $AWS_SECURITY_GROUP_ID"
    
    # Track resource for cleanup
    track_resource "security_group" "$AWS_SECURITY_GROUP_ID" "aws"
    
    # Add ingress rules for ports 22, 80, 443, 8000
    log "INFO" "Configuring security group rules..."
    
    # SSH (port 22)
    aws ec2 authorize-security-group-ingress \
        --region "$AWS_REGION" \
        --group-id "$AWS_SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 || log "WARNING" "Failed to add SSH rule (may already exist)"
    
    # HTTP (port 80)
    aws ec2 authorize-security-group-ingress \
        --region "$AWS_REGION" \
        --group-id "$AWS_SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 || log "WARNING" "Failed to add HTTP rule (may already exist)"
    
    # HTTPS (port 443)
    aws ec2 authorize-security-group-ingress \
        --region "$AWS_REGION" \
        --group-id "$AWS_SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 || log "WARNING" "Failed to add HTTPS rule (may already exist)"
    
    # MCP (port 8000)
    aws ec2 authorize-security-group-ingress \
        --region "$AWS_REGION" \
        --group-id "$AWS_SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 8000 \
        --cidr 0.0.0.0/0 || log "WARNING" "Failed to add MCP rule (may already exist)"
    
    log "INFO" "Security group configured successfully"
    return 0
}

# ============================================================================
# Create EC2 Instance
# ============================================================================

create_ec2_instance() {
    log "INFO" "Creating EC2 instance..."
    
    # Check if instance with same name already exists
    local existing_instance
    existing_instance=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=$AWS_INSTANCE_NAME" "Name=instance-state-name,Values=running,pending,stopped" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$existing_instance" ] && [ "$existing_instance" != "None" ]; then
        log "WARNING" "Instance with name '$AWS_INSTANCE_NAME' already exists: $existing_instance"
        local response
        response=$(prompt_user "Do you want to (u)se existing, (t)erminate and recreate, or (c)ancel?" "u")
        
        case "$response" in
            u|U|use)
                log "INFO" "Using existing instance"
                AWS_INSTANCE_ID="$existing_instance"
                
                # Start instance if stopped
                local state
                state=$(aws ec2 describe-instances \
                    --region "$AWS_REGION" \
                    --instance-ids "$AWS_INSTANCE_ID" \
                    --query 'Reservations[0].Instances[0].State.Name' \
                    --output text)
                
                if [ "$state" = "stopped" ]; then
                    log "INFO" "Starting stopped instance..."
                    aws ec2 start-instances \
                        --region "$AWS_REGION" \
                        --instance-ids "$AWS_INSTANCE_ID" || {
                        log "ERROR" "Failed to start instance"
                        return 1
                    }
                fi
                
                # Wait for instance to be running
                log "INFO" "Waiting for instance to be running..."
                aws ec2 wait instance-running \
                    --region "$AWS_REGION" \
                    --instance-ids "$AWS_INSTANCE_ID" || {
                    log "ERROR" "Instance failed to start"
                    return 1
                }
                
                # Get instance IP
                AWS_INSTANCE_IP=$(aws ec2 describe-instances \
                    --region "$AWS_REGION" \
                    --instance-ids "$AWS_INSTANCE_ID" \
                    --query 'Reservations[0].Instances[0].PublicIpAddress' \
                    --output text)
                
                log "INFO" "Instance IP: $AWS_INSTANCE_IP"
                return 0
                ;;
            t|T|terminate)
                log "INFO" "Terminating existing instance..."
                aws ec2 terminate-instances \
                    --region "$AWS_REGION" \
                    --instance-ids "$existing_instance" || {
                    log "ERROR" "Failed to terminate existing instance"
                    return 1
                }
                
                log "INFO" "Waiting for instance to terminate..."
                aws ec2 wait instance-terminated \
                    --region "$AWS_REGION" \
                    --instance-ids "$existing_instance" || {
                    log "WARNING" "Wait for termination timed out, continuing..."
                }
                ;;
            c|C|cancel|*)
                log "INFO" "Operation cancelled by user"
                exit 0
                ;;
        esac
    fi
    
    # Create instance
    log "INFO" "Launching EC2 instance..."
    log "INFO" "  - Instance type: $AWS_INSTANCE_TYPE"
    log "INFO" "  - AMI: $AWS_AMI_ID"
    log "INFO" "  - Region: $AWS_REGION"
    
    AWS_INSTANCE_ID=$(aws ec2 run-instances \
        --region "$AWS_REGION" \
        --image-id "$AWS_AMI_ID" \
        --instance-type "$AWS_INSTANCE_TYPE" \
        --key-name "$AWS_KEY_NAME" \
        --security-group-ids "$AWS_SECURITY_GROUP_ID" \
        --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=50,VolumeType=gp3}' \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$AWS_INSTANCE_NAME}]" \
        --query 'Instances[0].InstanceId' \
        --output text) || {
        log "ERROR" "Failed to create EC2 instance"
        return 1
    }
    
    log "INFO" "Instance created: $AWS_INSTANCE_ID"
    
    # Track resource for cleanup
    track_resource "instance" "$AWS_INSTANCE_ID" "aws"
    
    # Wait for instance to be running
    log "INFO" "Waiting for instance to be running..."
    aws ec2 wait instance-running \
        --region "$AWS_REGION" \
        --instance-ids "$AWS_INSTANCE_ID" || {
        log "ERROR" "Instance failed to start"
        return 1
    }
    
    log "INFO" "Instance is running"
    
    # Wait for status checks
    log "INFO" "Waiting for instance status checks..."
    aws ec2 wait instance-status-ok \
        --region "$AWS_REGION" \
        --instance-ids "$AWS_INSTANCE_ID" || {
        log "WARNING" "Status check wait timed out, continuing..."
    }
    
    # Get instance public IP
    AWS_INSTANCE_IP=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$AWS_INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    if [ -z "$AWS_INSTANCE_IP" ] || [ "$AWS_INSTANCE_IP" = "None" ]; then
        log "ERROR" "Failed to get instance public IP"
        return 1
    fi
    
    log "INFO" "Instance public IP: $AWS_INSTANCE_IP"
    
    return 0
}

# ============================================================================
# File Transfer to EC2 Instance
# ============================================================================

copy_files_to_ec2() {
    log "INFO" "Copying installation files to EC2 instance..."
    
    # Wait for SSH to be ready
    log "INFO" "Waiting for SSH to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if ssh -i "${HOME}/.ssh/${AWS_KEY_NAME}.pem" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 \
            "ubuntu@${AWS_INSTANCE_IP}" \
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
    ssh -i "${HOME}/.ssh/${AWS_KEY_NAME}.pem" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "ubuntu@${AWS_INSTANCE_IP}" \
        "mkdir -p /tmp/graphiti-installer" || {
        log "ERROR" "Failed to create remote directory"
        return 1
    }
    
    # Copy common scripts
    log "INFO" "Copying common scripts..."
    scp -i "${HOME}/.ssh/${AWS_KEY_NAME}.pem" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -r "${SCRIPT_DIR}/common" \
        "ubuntu@${AWS_INSTANCE_IP}:/tmp/graphiti-installer/" || {
        log "ERROR" "Failed to copy common scripts"
        return 1
    }
    
    # Copy docker configurations
    log "INFO" "Copying Docker configurations..."
    scp -i "${HOME}/.ssh/${AWS_KEY_NAME}.pem" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -r "${SCRIPT_DIR}/docker" \
        "ubuntu@${AWS_INSTANCE_IP}:/tmp/graphiti-installer/" || {
        log "ERROR" "Failed to copy Docker configurations"
        return 1
    }
    
    # Copy templates
    log "INFO" "Copying configuration templates..."
    scp -i "${HOME}/.ssh/${AWS_KEY_NAME}.pem" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -r "${SCRIPT_DIR}/templates" \
        "ubuntu@${AWS_INSTANCE_IP}:/tmp/graphiti-installer/" || {
        log "ERROR" "Failed to copy templates"
        return 1
    }
    
    # Copy local .env file
    log "INFO" "Copying local .env file with API keys..."
    scp -i "${HOME}/.ssh/${AWS_KEY_NAME}.pem" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "${SCRIPT_DIR}/.env" \
        "ubuntu@${AWS_INSTANCE_IP}:/tmp/graphiti-installer/.env" || {
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
    ssh -i "${HOME}/.ssh/${AWS_KEY_NAME}.pem" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "ubuntu@${AWS_INSTANCE_IP}" \
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
    ssh -i "${HOME}/.ssh/${AWS_KEY_NAME}.pem" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "ubuntu@${AWS_INSTANCE_IP}" \
        "chmod +x $remote_script" || {
        log "ERROR" "Failed to make remote script executable"
        return 1
    }
    
    # Execute installation
    log "INFO" "Running installation on remote instance..."
    log "INFO" "This may take several minutes..."
    
    ssh -i "${HOME}/.ssh/${AWS_KEY_NAME}.pem" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "ubuntu@${AWS_INSTANCE_IP}" \
        "sudo bash $remote_script" || {
        log "ERROR" "Remote installation failed"
        return 1
    }
    
    log "INFO" "Remote installation completed successfully"
    return 0
}

# ============================================================================
# AWS Resource Cleanup
# ============================================================================

cleanup_aws_resource() {
    local type="$1"
    local id="$2"
    
    log "INFO" "Cleaning up AWS $type: $id"
    
    case "$type" in
        instance)
            aws ec2 terminate-instances \
                --region "$AWS_REGION" \
                --instance-ids "$id" 2>/dev/null || log "WARNING" "Failed to terminate instance: $id"
            ;;
        security_group)
            aws ec2 delete-security-group \
                --region "$AWS_REGION" \
                --group-id "$id" 2>/dev/null || log "WARNING" "Failed to delete security group: $id"
            ;;
        keypair)
            aws ec2 delete-key-pair \
                --region "$AWS_REGION" \
                --key-name "$id" 2>/dev/null || log "WARNING" "Failed to delete key pair: $id"
            rm -f "${HOME}/.ssh/${id}.pem" 2>/dev/null || true
            ;;
        *)
            log "WARNING" "Unknown resource type: $type"
            ;;
    esac
}

# Override the cleanup function from utils.sh for AWS-specific cleanup
cleanup_aws_resource_override() {
    cleanup_aws_resource "$@"
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
    log "INFO" "  - Instance ID: $AWS_INSTANCE_ID"
    log "INFO" "  - IP Address: $AWS_INSTANCE_IP"
    log "INFO" "  - Region: $AWS_REGION"
    log "INFO" "  - Instance Type: $AWS_INSTANCE_TYPE"
    log "INFO" ""
    log "INFO" "MCP Endpoint URLs:"
    log "INFO" "  - HTTP: http://${AWS_INSTANCE_IP}:8000/mcp/"
    log "INFO" "  - Health Check: http://${AWS_INSTANCE_IP}:8000/health"
    log "INFO" ""
    
    # Check if domain is configured for HTTPS
    local domain
    domain=$(ssh -i "${HOME}/.ssh/${AWS_KEY_NAME}.pem" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "ubuntu@${AWS_INSTANCE_IP}" \
        "grep '^DOMAIN_NAME=' /opt/graphiti/.env 2>/dev/null | cut -d'=' -f2" 2>/dev/null || echo "")
    
    if [ -n "$domain" ]; then
        log "INFO" "  - HTTPS: https://${domain}/mcp/"
    fi
    
    log "INFO" ""
    log "INFO" "Next Steps:"
    log "INFO" "  1. Configure your MCP client with the endpoint URL"
    log "INFO" "  2. Test the connection: curl http://${AWS_INSTANCE_IP}:8000/health"
    log "INFO" "  3. View logs: ssh -i ${HOME}/.ssh/${AWS_KEY_NAME}.pem ubuntu@${AWS_INSTANCE_IP} 'docker logs graphiti-mcp'"
    log "INFO" ""
    log "INFO" "To SSH into the instance:"
    log "INFO" "  ssh -i ${HOME}/.ssh/${AWS_KEY_NAME}.pem ubuntu@${AWS_INSTANCE_IP}"
    log "INFO" ""
    log "INFO" "To terminate the instance:"
    log "INFO" "  aws ec2 terminate-instances --region $AWS_REGION --instance-ids $AWS_INSTANCE_ID"
    log "INFO" ""
    log "INFO" "To delete the security group:"
    log "INFO" "  aws ec2 delete-security-group --region $AWS_REGION --group-id $AWS_SECURITY_GROUP_ID"
    log "INFO" "========================================="
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    log "INFO" "Starting Graphiti Cloud Installer for AWS"
    log "INFO" "========================================="
    
    # Set up cleanup trap
    trap cleanup EXIT ERR
    
    # Step 1: Check prerequisites
    check_aws_prerequisites || {
        log "ERROR" "Prerequisites check failed"
        exit 1
    }
    
    # Step 2: Authenticate with AWS
    authenticate_aws || {
        log "ERROR" "AWS authentication failed"
        exit 1
    }
    
    # Step 2.5: Validate local .env file
    log "INFO" "Validating local .env file..."
    validate_local_env "${SCRIPT_DIR}/.env" || {
        log "ERROR" "Local .env validation failed"
        log "INFO" "Please create a .env file in the project root with at least one API key"
        exit 1
    }
    
    # Step 3: Configure AWS deployment
    configure_aws || {
        log "ERROR" "AWS configuration failed"
        exit 1
    }
    
    # Step 4: Get Ubuntu AMI
    get_ubuntu_ami || {
        log "ERROR" "Failed to get Ubuntu AMI"
        exit 1
    }
    
    # Step 5: Setup SSH key pair
    setup_ssh_key || {
        log "ERROR" "SSH key setup failed"
        exit 1
    }
    
    # Step 6: Create security group
    create_security_group || {
        log "ERROR" "Security group creation failed"
        exit 1
    }
    
    # Step 7: Create EC2 instance
    create_ec2_instance || {
        log "ERROR" "EC2 instance creation failed"
        exit 1
    }
    
    # Step 8: Copy installation files
    copy_files_to_ec2 || {
        log "ERROR" "File transfer failed"
        exit 1
    }
    
    # Step 9: Execute remote installation
    execute_remote_installation || {
        log "ERROR" "Remote installation failed"
        exit 1
    }
    
    # Step 10: Display results
    display_results
    
    log "INFO" "AWS installation completed successfully!"
    exit 0
}

# Run main function
main "$@"
