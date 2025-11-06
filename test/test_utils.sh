#!/bin/bash

# Test script for common/utils.sh
# This script tests the utility functions

set -euo pipefail

# Source the utils file
source common/utils.sh

echo "=========================================="
echo "Testing Graphiti Cloud Installer Utils"
echo "=========================================="
echo ""

# Test 1: Logging functions
echo "Test 1: Logging functions"
log "INFO" "This is an info message"
log "WARNING" "This is a warning message"
log "ERROR" "This is an error message (test only)"
echo "✓ Logging test passed"
echo ""

# Test 2: Command checking
echo "Test 2: Command checking"
if check_command "bash"; then
    echo "✓ check_command found 'bash'"
else
    echo "✗ check_command failed to find 'bash'"
    exit 1
fi

if ! check_command "nonexistent_command_xyz"; then
    echo "✓ check_command correctly reported missing command"
else
    echo "✗ check_command incorrectly found nonexistent command"
    exit 1
fi
echo ""

# Test 3: API key validation
echo "Test 3: API key validation"

# Test OpenAI key
if validate_api_key "openai" "sk-1234567890abcdefghijklmnopqrstuvwxyz"; then
    echo "✓ OpenAI key validation passed"
else
    echo "✗ OpenAI key validation failed"
    exit 1
fi

# Test invalid OpenAI key
if ! validate_api_key "openai" "invalid-key"; then
    echo "✓ Invalid OpenAI key correctly rejected"
else
    echo "✗ Invalid OpenAI key incorrectly accepted"
    exit 1
fi

# Test Anthropic key
if validate_api_key "anthropic" "sk-ant-1234567890abcdefghijklmnopqrstuvwxyz"; then
    echo "✓ Anthropic key validation passed"
else
    echo "✗ Anthropic key validation failed"
    exit 1
fi

# Test Groq key
if validate_api_key "groq" "gsk_1234567890abcdefghijklmnopqrstuvwxyz"; then
    echo "✓ Groq key validation passed"
else
    echo "✗ Groq key validation failed"
    exit 1
fi

# Test Google key
if validate_api_key "google" "AIzaSyAbCdEfGhIjKlMnOpQrStUvWxYz1234567"; then
    echo "✓ Google key validation passed"
else
    echo "✗ Google key validation failed"
    exit 1
fi

# Test empty key
if ! validate_api_key "openai" ""; then
    echo "✓ Empty key correctly rejected"
else
    echo "✗ Empty key incorrectly accepted"
    exit 1
fi
echo ""

# Test 4: Resource tracking
echo "Test 4: Resource tracking"
track_resource "instance" "i-1234567890" "aws"
track_resource "firewall" "fw-test-123" "gcp"
if [ ${#CREATED_RESOURCES[@]} -eq 2 ]; then
    echo "✓ Resource tracking works (${#CREATED_RESOURCES[@]} resources tracked)"
else
    echo "✗ Resource tracking failed"
    exit 1
fi
echo ""

# Test 5: Log file creation
echo "Test 5: Log file creation"
if [ -f "$LOG_FILE" ]; then
    echo "✓ Log file created at: $LOG_FILE"
    echo "  Log file size: $(wc -l < "$LOG_FILE") lines"
else
    echo "✗ Log file not created"
    exit 1
fi
echo ""

echo "=========================================="
echo "All tests passed! ✓"
echo "=========================================="
echo ""
echo "Log file location: $LOG_FILE"
