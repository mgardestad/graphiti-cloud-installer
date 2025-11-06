#!/bin/bash

# Graphiti Installation Validation Script
# Post-installation validation to verify all services are running correctly
# This script checks Docker containers, database connectivity, and MCP endpoints

set -euo pipefail

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Installation directory
readonly INSTALL_DIR="${INSTALL_DIR:-/opt/graphiti}"
readonly DOCKER_DIR="${INSTALL_DIR}/docker"

# Validation results
VALIDATION_PASSED=true

# ============================================================================
# Container Validation Functions
# ============================================================================

# check_container_running() - Check if a Docker container is running
# Arguments:
#   $1 - Container name pattern
# Returns:
#   0 if running, 1 otherwise
check_container_running() {
    local container_name="$1"
    
    log "INFO" "Checking if container '$container_name' is running..."
    
    if docker ps | grep -q "$container_name"; then
        log "INFO" "✓ Container '$container_name' is running"
        return 0
    else
        log "ERROR" "✗ Container '$container_name' is NOT running"
        
        # Show container status if it exists
        if docker ps -a | grep -q "$container_name"; then
            log "INFO" "Container status:"
            docker ps -a | grep "$container_name" || true
            
            log "INFO" "Container logs (last 20 lines):"
            docker logs --tail 20 "$container_name" 2>&1 || true
        else
            log "ERROR" "Container '$container_name' does not exist"
        fi
        
        VALIDATION_PASSED=false
        return 1
    fi
}

# validate_containers() - Validate all required containers are running
validate_containers() {
    log "INFO" "=== Validating Docker Containers ==="
    
    # Check graphiti-mcp container
    check_container_running "graphiti-mcp"
    
    # Check database container based on type
    local db_type
    db_type=$(grep "^DATABASE_TYPE=" "${INSTALL_DIR}/.env" 2>/dev/null | cut -d'=' -f2 || echo "falkordb")
    
    if [ "$db_type" = "neo4j" ]; then
        check_container_running "neo4j"
    else
        check_container_running "falkordb"
    fi
    
    # Check nginx container
    check_container_running "nginx-proxy"
    
    log "INFO" ""
}

# ============================================================================
# Database Connectivity Validation Functions
# ============================================================================

# validate_falkordb_connectivity() - Test FalkorDB connection
validate_falkordb_connectivity() {
    log "INFO" "Testing FalkorDB connectivity..."
    
    # Check if FalkorDB web interface is accessible
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f -s http://localhost:3000 > /dev/null 2>&1; then
            log "INFO" "✓ FalkorDB web interface is accessible on port 3000"
            return 0
        fi
        
        log "WARNING" "Attempt $attempt/$max_attempts: FalkorDB not ready yet, waiting..."
        sleep 2
        ((attempt++))
    done
    
    log "ERROR" "✗ FalkorDB web interface is not accessible"
    VALIDATION_PASSED=false
    return 1
}

# validate_neo4j_connectivity() - Test Neo4j connection
validate_neo4j_connectivity() {
    log "INFO" "Testing Neo4j connectivity..."
    
    # Check if Neo4j HTTP interface is accessible
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f -s http://localhost:7474 > /dev/null 2>&1; then
            log "INFO" "✓ Neo4j HTTP interface is accessible on port 7474"
            return 0
        fi
        
        log "WARNING" "Attempt $attempt/$max_attempts: Neo4j not ready yet, waiting..."
        sleep 2
        ((attempt++))
    done
    
    log "ERROR" "✗ Neo4j HTTP interface is not accessible"
    VALIDATION_PASSED=false
    return 1
}

# validate_database() - Validate database connectivity
validate_database() {
    log "INFO" "=== Validating Database Connectivity ==="
    
    # Determine database type
    local db_type
    db_type=$(grep "^DATABASE_TYPE=" "${INSTALL_DIR}/.env" 2>/dev/null | cut -d'=' -f2 || echo "falkordb")
    
    if [ "$db_type" = "neo4j" ]; then
        validate_neo4j_connectivity
    else
        validate_falkordb_connectivity
    fi
    
    log "INFO" ""
}

# ============================================================================
# Endpoint Validation Functions
# ============================================================================

# test_endpoint() - Test HTTP endpoint accessibility
# Arguments:
#   $1 - Endpoint URL
#   $2 - Expected HTTP status code (default: 200)
# Returns:
#   0 if accessible, 1 otherwise
test_endpoint() {
    local url="$1"
    local expected_status="${2:-200}"
    
    log "INFO" "Testing endpoint: $url"
    
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local status_code
        status_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        
        if [ "$status_code" = "$expected_status" ]; then
            log "INFO" "✓ Endpoint accessible (HTTP $status_code): $url"
            return 0
        fi
        
        log "WARNING" "Attempt $attempt/$max_attempts: Got HTTP $status_code, expected $expected_status"
        sleep 2
        ((attempt++))
    done
    
    log "ERROR" "✗ Endpoint not accessible: $url"
    VALIDATION_PASSED=false
    return 1
}

# validate_health_endpoint() - Test health endpoint
validate_health_endpoint() {
    log "INFO" "=== Validating Health Endpoint ==="
    
    test_endpoint "http://localhost:8000/health" "200"
    
    log "INFO" ""
}

# validate_mcp_endpoint() - Test MCP endpoint
validate_mcp_endpoint() {
    log "INFO" "=== Validating MCP Endpoint ==="
    
    # Test MCP endpoint (may return 404 or 405 for GET, but should be accessible)
    local url="http://localhost:8000/mcp/"
    log "INFO" "Testing MCP endpoint: $url"
    
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local status_code
        status_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        
        # MCP endpoint may return 404, 405, or 200 depending on implementation
        if [ "$status_code" != "000" ] && [ "$status_code" != "502" ] && [ "$status_code" != "503" ]; then
            log "INFO" "✓ MCP endpoint is accessible (HTTP $status_code): $url"
            log "INFO" ""
            return 0
        fi
        
        log "WARNING" "Attempt $attempt/$max_attempts: Got HTTP $status_code, waiting for service..."
        sleep 2
        ((attempt++))
    done
    
    log "ERROR" "✗ MCP endpoint not accessible: $url"
    VALIDATION_PASSED=false
    log "INFO" ""
    return 1
}

# ============================================================================
# MCP Request Testing Functions
# ============================================================================

# test_mcp_request() - Perform a simple MCP request test
test_mcp_request() {
    log "INFO" "=== Testing MCP Request ==="
    
    local mcp_url="http://localhost:8000/mcp/"
    
    log "INFO" "Sending test request to MCP endpoint..."
    
    # Create a simple test request (get status or list tools)
    local response
    response=$(curl -s -X POST "$mcp_url" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":1}' 2>&1 || echo "ERROR")
    
    if [ "$response" = "ERROR" ]; then
        log "ERROR" "✗ Failed to send MCP request"
        VALIDATION_PASSED=false
        return 1
    fi
    
    # Check if response contains expected JSON-RPC structure
    if echo "$response" | grep -q '"jsonrpc"'; then
        log "INFO" "✓ MCP endpoint responded with valid JSON-RPC"
        log "INFO" "Response preview: $(echo "$response" | head -c 200)..."
        return 0
    else
        log "WARNING" "MCP endpoint responded but format is unexpected"
        log "INFO" "Response: $response"
        # Don't fail validation for this, as the endpoint might have different behavior
        return 0
    fi
    
    log "INFO" ""
}

# ============================================================================
# Network Validation Functions
# ============================================================================

# validate_network() - Validate Docker network configuration
validate_network() {
    log "INFO" "=== Validating Docker Network ==="
    
    # Check if graphiti-network exists
    if docker network ls | grep -q "graphiti-network"; then
        log "INFO" "✓ Docker network 'graphiti-network' exists"
        
        # List containers on the network
        log "INFO" "Containers on graphiti-network:"
        docker network inspect graphiti-network --format '{{range .Containers}}  - {{.Name}}{{"\n"}}{{end}}' || true
    else
        log "ERROR" "✗ Docker network 'graphiti-network' not found"
        VALIDATION_PASSED=false
    fi
    
    log "INFO" ""
}

# ============================================================================
# Volume Validation Functions
# ============================================================================

# validate_volumes() - Validate Docker volumes for data persistence
validate_volumes() {
    log "INFO" "=== Validating Docker Volumes ==="
    
    local db_type
    db_type=$(grep "^DATABASE_TYPE=" "${INSTALL_DIR}/.env" 2>/dev/null | cut -d'=' -f2 || echo "falkordb")
    
    if [ "$db_type" = "neo4j" ]; then
        # Check Neo4j volumes
        for volume in neo4j-data neo4j-logs neo4j-import neo4j-plugins; do
            if docker volume ls | grep -q "$volume"; then
                log "INFO" "✓ Volume '$volume' exists"
            else
                log "WARNING" "Volume '$volume' not found"
            fi
        done
    else
        # Check FalkorDB volume
        if docker volume ls | grep -q "falkordb-data"; then
            log "INFO" "✓ Volume 'falkordb-data' exists"
        else
            log "WARNING" "Volume 'falkordb-data' not found"
        fi
    fi
    
    log "INFO" ""
}

# ============================================================================
# Main Validation Function
# ============================================================================

# run_validation() - Execute full validation workflow
run_validation() {
    log "INFO" "=========================================="
    log "INFO" "Starting Graphiti Installation Validation"
    log "INFO" "=========================================="
    log "INFO" ""
    
    # Check if installation directory exists
    if [ ! -d "$INSTALL_DIR" ]; then
        log "ERROR" "Installation directory not found: $INSTALL_DIR"
        log "ERROR" "Graphiti may not be installed"
        exit 1
    fi
    
    # Run validation checks
    validate_containers
    validate_network
    validate_volumes
    validate_database
    validate_health_endpoint
    validate_mcp_endpoint
    test_mcp_request
    
    # Print summary
    log "INFO" "=========================================="
    if [ "$VALIDATION_PASSED" = true ]; then
        log "INFO" "✓ All validation checks passed!"
        log "INFO" "=========================================="
        log "INFO" ""
        
        # Display connection information
        display_connection_info
        
        exit 0
    else
        log "ERROR" "✗ Some validation checks failed"
        log "ERROR" "=========================================="
        log "ERROR" ""
        log "ERROR" "Please check the errors above and review logs:"
        log "ERROR" "  - Installation log: $LOG_FILE"
        log "ERROR" "  - Docker logs: docker logs graphiti-mcp"
        log "ERROR" ""
        exit 1
    fi
}

# display_connection_info() - Display connection information
display_connection_info() {
    local db_type
    db_type=$(grep "^DATABASE_TYPE=" "${INSTALL_DIR}/.env" 2>/dev/null | cut -d'=' -f2 || echo "falkordb")
    
    local domain
    domain=$(grep "^DOMAIN_NAME=" "${INSTALL_DIR}/.env" 2>/dev/null | cut -d'=' -f2 || echo "")
    
    echo ""
    echo "=========================================="
    echo "Graphiti MCP Server Connection Info"
    echo "=========================================="
    echo ""
    
    if [ -n "$domain" ]; then
        echo "MCP Endpoint: https://$domain/mcp/"
        echo "Health Check: https://$domain/health"
    else
        echo "MCP Endpoint: http://localhost:8000/mcp/"
        echo "Health Check: http://localhost:8000/health"
    fi
    
    echo ""
    echo "Database: $db_type"
    
    if [ "$db_type" = "neo4j" ]; then
        echo "Neo4j Browser: http://localhost:7474"
        echo "Neo4j Bolt: bolt://localhost:7687"
    else
        echo "FalkorDB UI: http://localhost:3000"
        echo "FalkorDB Redis: redis://localhost:6379"
    fi
    
    echo ""
    echo "=========================================="
    echo ""
}

# ============================================================================
# Script Entry Point
# ============================================================================

# If script is executed directly (not sourced), run validation
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    run_validation
fi
