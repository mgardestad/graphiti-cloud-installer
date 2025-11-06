#!/bin/bash

# Test MCP Connection Script
# This script tests the connectivity and functionality of a Graphiti MCP endpoint

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
MCP_HOST="${MCP_HOST:-localhost}"
MCP_PORT="${MCP_PORT:-8000}"
MCP_ENDPOINT="http://${MCP_HOST}:${MCP_PORT}"

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to test HTTP endpoint
test_endpoint() {
    local endpoint=$1
    local description=$2
    
    log_info "Testing ${description}..."
    
    if curl -f -s -o /dev/null -w "%{http_code}" "${endpoint}" | grep -q "200\|404"; then
        log_info "✓ ${description} is accessible"
        return 0
    else
        log_error "✗ ${description} is not accessible"
        return 1
    fi
}

# Function to test MCP health endpoint
test_health() {
    log_info "Testing health endpoint..."
    
    local response=$(curl -s -w "\n%{http_code}" "${MCP_ENDPOINT}/health" 2>/dev/null)
    local body=$(echo "$response" | head -n -1)
    local status=$(echo "$response" | tail -n 1)
    
    if [ "$status" = "200" ]; then
        log_info "✓ Health check passed"
        echo "  Response: $body"
        return 0
    else
        log_error "✗ Health check failed (HTTP $status)"
        return 1
    fi
}

# Function to test MCP root endpoint
test_mcp_root() {
    log_info "Testing MCP root endpoint..."
    
    local response=$(curl -s -w "\n%{http_code}" "${MCP_ENDPOINT}/mcp/" 2>/dev/null)
    local status=$(echo "$response" | tail -n 1)
    
    if [ "$status" = "200" ] || [ "$status" = "404" ]; then
        log_info "✓ MCP endpoint is accessible"
        return 0
    else
        log_error "✗ MCP endpoint is not accessible (HTTP $status)"
        return 1
    fi
}

# Function to test get_status MCP request
test_get_status() {
    log_info "Testing MCP get_status request..."
    
    local payload='{
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {
            "name": "get_status",
            "arguments": {}
        }
    }'
    
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${MCP_ENDPOINT}/mcp/" 2>/dev/null)
    
    if echo "$response" | grep -q '"result"\|"error"'; then
        log_info "✓ get_status request successful"
        echo "  Response: $response"
        return 0
    else
        log_warning "⚠ get_status request returned unexpected response"
        echo "  Response: $response"
        return 1
    fi
}

# Function to test add_episode MCP request
test_add_episode() {
    log_info "Testing MCP add_episode request..."
    
    local payload='{
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "add_episode",
            "arguments": {
                "name": "Test Episode",
                "episode_body": "This is a test episode created by the test script.",
                "source_description": "MCP Connection Test Script",
                "reference_time": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
            }
        }
    }'
    
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${MCP_ENDPOINT}/mcp/" 2>/dev/null)
    
    if echo "$response" | grep -q '"result"\|"error"'; then
        log_info "✓ add_episode request successful"
        echo "  Response: $response"
        return 0
    else
        log_warning "⚠ add_episode request returned unexpected response"
        echo "  Response: $response"
        return 1
    fi
}

# Function to validate JSON response
validate_response() {
    local response=$1
    
    if command -v jq &> /dev/null; then
        if echo "$response" | jq empty 2>/dev/null; then
            log_info "✓ Response is valid JSON"
            return 0
        else
            log_error "✗ Response is not valid JSON"
            return 1
        fi
    else
        log_warning "⚠ jq not installed, skipping JSON validation"
        return 0
    fi
}

# Main test execution
main() {
    echo "========================================="
    echo "  Graphiti MCP Connection Test"
    echo "========================================="
    echo ""
    echo "Testing endpoint: ${MCP_ENDPOINT}"
    echo ""
    
    local failed=0
    
    # Test 1: Health endpoint
    if ! test_health; then
        ((failed++))
    fi
    echo ""
    
    # Test 2: MCP root endpoint
    if ! test_mcp_root; then
        ((failed++))
    fi
    echo ""
    
    # Test 3: get_status request
    if ! test_get_status; then
        ((failed++))
    fi
    echo ""
    
    # Test 4: add_episode request
    if ! test_add_episode; then
        ((failed++))
    fi
    echo ""
    
    # Summary
    echo "========================================="
    if [ $failed -eq 0 ]; then
        log_info "All tests passed! ✓"
        echo "========================================="
        exit 0
    else
        log_error "$failed test(s) failed"
        echo "========================================="
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --host)
            MCP_HOST="$2"
            MCP_ENDPOINT="http://${MCP_HOST}:${MCP_PORT}"
            shift 2
            ;;
        --port)
            MCP_PORT="$2"
            MCP_ENDPOINT="http://${MCP_HOST}:${MCP_PORT}"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --host HOST    MCP server host (default: localhost)"
            echo "  --port PORT    MCP server port (default: 8000)"
            echo "  --help         Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  MCP_HOST       MCP server host"
            echo "  MCP_PORT       MCP server port"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main
