#!/bin/bash

# Shape Network Simple Health Check Script
# Tests RPC endpoints, SSL, and basic blockchain status
#
# Usage: ./healthcheck.sh [--domain DOMAIN] [--ip IP]
#
# Options:
#   --domain DOMAIN    Override domain name
#   --ip IP           Override IP address
#   --help           Show this help message

# set -e  # Removed to allow script to continue on test failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((TESTS_FAILED++))
}

log_header() {
    echo -e "${GREEN}$1${NC}"
}

# Increment test counter
test_start() {
    ((TESTS_TOTAL++))
}

# Get domain from configuration or arguments
get_domain() {
    if [ ! -z "$DOMAIN" ]; then
        echo "$DOMAIN"
        return
    fi

    # Try to get from configuration file
    if [ -f ".shape-config" ]; then
        local config_domain=$(grep "DNS_FQDN=" .shape-config | cut -d'"' -f2)
        if [ ! -z "$config_domain" ]; then
            echo "$config_domain"
            return
        fi
    fi

    # Default fallback
    echo "mainnet-shape-snow.eastus2.cloudapp.azure.com"
}

# Get IP address from configuration or arguments
get_ip_address() {
    if [ ! -z "$IP_ADDRESS" ]; then
        echo "$IP_ADDRESS"
        return
    fi

    # Try to get from configuration file
    if [ -f ".shape-config" ]; then
        local config_ip=$(grep "STATIC_IP=" .shape-config | cut -d'"' -f2)
        if [ ! -z "$config_ip" ]; then
            echo "$config_ip"
            return
        fi
    fi

    # Default fallback
    echo "172.200.56.10"
}

# Simple SSL test
test_ssl() {
    local domain="$1"

    test_start
    log_info "Testing SSL for $domain"

    local response=$(curl -s -I --max-time 10 -k "https://$domain" 2>/dev/null)

    if [ $? -eq 0 ] && echo "$response" | grep -q "HTTP/2 200\|HTTP/1.1 200\|HTTP/2 301\|HTTP/1.1 301"; then
        log_success "SSL is working for $domain"
        return 0
    else
        log_error "SSL test failed for $domain (may still be provisioning)"
        return 1
    fi
}

# Test RPC endpoint
test_rpc_endpoint() {
    local url="$1"
    local name="$2"

    test_start
    log_info "Testing RPC endpoint: $name ($url)"

    local payload='{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
    local response=$(curl -s -X POST -H "Content-Type: application/json" --data "$payload" --max-time 10 "$url" 2>/dev/null)

    if [ $? -eq 0 ] && [ ! -z "$response" ]; then
        # Check if response contains expected JSON-RPC fields
        if echo "$response" | jq -e '.jsonrpc and .id' >/dev/null 2>&1; then
            log_success "RPC endpoint $name is responding"
            return 0
        else
            log_error "RPC endpoint $name returned invalid response"
            return 1
        fi
    else
        log_error "RPC endpoint $name is not responding"
        return 1
    fi
}

# Test blockchain sync status
test_sync_status() {
    local url="$1"
    local name="$2"

    test_start
    if [ -z "$name" ]; then
        log_info "Testing sync status"
    else
        log_info "Testing sync status: $name"
    fi

    local payload='{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
    local response=$(curl -s -X POST -H "Content-Type: application/json" --data "$payload" --max-time 10 "$url" 2>/dev/null)

    if [ $? -eq 0 ] && [ ! -z "$response" ]; then
        # Check if response has result field (can be true, false, or object)
        if echo "$response" | jq '.result' >/dev/null 2>&1; then
            local syncing=$(echo "$response" | jq -r '.result' 2>/dev/null)

            if [ "$syncing" = "false" ]; then
                if [ -z "$name" ]; then
                    log_success "Node is fully synced"
                else
                    log_success "Node is fully synced ($name)"
                fi
            else
                if [ -z "$name" ]; then
                    log_success "Node is syncing"
                else
                    log_success "Node is syncing ($name)"
                fi
            fi
            return 0
        else
            if [ -z "$name" ]; then
                log_error "Invalid response format for eth_syncing"
            else
                log_error "Invalid response format for eth_syncing ($name)"
            fi
            return 1
        fi
    else
        if [ -z "$name" ]; then
            log_error "Failed to get sync status"
        else
            log_error "Failed to get sync status ($name)"
        fi
        return 1
    fi
}

# Test current block number
test_current_block() {
    local url="$1"
    local name="$2"

    test_start
    if [ -z "$name" ]; then
        log_info "Testing current block"
    else
        log_info "Testing current block: $name"
    fi

    local payload='{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
    local response=$(curl -s -X POST -H "Content-Type: application/json" --data "$payload" --max-time 10 "$url" 2>/dev/null)

    if [ $? -eq 0 ] && echo "$response" | jq -e '.result' >/dev/null 2>&1; then
        local block_hex=$(echo "$response" | jq -r '.result' 2>/dev/null)
        local block_number=$((16#${block_hex#0x}))

        if [ -z "$name" ]; then
            log_success "Current block: $block_number (0x${block_hex#0x})"
        else
            log_success "Current block ($name): $block_number (0x${block_hex#0x})"
        fi
        return 0
    else
        if [ -z "$name" ]; then
            log_error "Failed to get current block"
        else
            log_error "Failed to get current block ($name)"
        fi
        return 1
    fi
}

# Test chain ID
test_chain_id() {
    local url="$1"
    local name="$2"

    test_start
    if [ -z "$name" ]; then
        log_info "Testing chain ID"
    else
        log_info "Testing chain ID: $name"
    fi

    local payload='{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
    local response=$(curl -s -X POST -H "Content-Type: application/json" --data "$payload" --max-time 10 "$url" 2>/dev/null)

    if [ $? -eq 0 ] && echo "$response" | jq -e '.result' >/dev/null 2>&1; then
        local chain_id_hex=$(echo "$response" | jq -r '.result' 2>/dev/null)
        local chain_id=$((16#${chain_id_hex#0x}))

        if [ "$chain_id" = "360" ]; then
            if [ -z "$name" ]; then
                log_success "Chain ID correct: $chain_id (Shape Network)"
            else
                log_success "Chain ID correct ($name): $chain_id (Shape Network)"
            fi
        else
            if [ -z "$name" ]; then
                log_success "Chain ID: $chain_id"
            else
                log_success "Chain ID ($name): $chain_id"
            fi
        fi
        return 0
    else
        if [ -z "$name" ]; then
            log_error "Failed to get chain ID"
        else
            log_error "Failed to get chain ID ($name)"
        fi
        return 1
    fi
}

# Test peer count
test_peer_count() {
    local url="$1"
    local name="$2"

    test_start
    if [ -z "$name" ]; then
        log_info "Testing peer count"
    else
        log_info "Testing peer count: $name"
    fi

    local payload='{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
    local response=$(curl -s -X POST -H "Content-Type: application/json" --data "$payload" --max-time 10 "$url" 2>/dev/null)

    if [ $? -eq 0 ] && echo "$response" | jq -e '.result' >/dev/null 2>&1; then
        local peer_count_hex=$(echo "$response" | jq -r '.result' 2>/dev/null)
        local peer_count=$((16#${peer_count_hex#0x}))

        if [ "$peer_count" -gt 0 ]; then
            if [ -z "$name" ]; then
                log_success "Peers connected: $peer_count"
            else
                log_success "Peers connected ($name): $peer_count"
            fi
        else
            if [ -z "$name" ]; then
                log_success "No peers connected: $peer_count"
            else
                log_success "No peers connected ($name): $peer_count"
            fi
        fi
        return 0
    else
        if [ -z "$name" ]; then
            log_error "Failed to get peer count"
        else
            log_error "Failed to get peer count ($name)"
        fi
        return 1
    fi
}

# Main execution
main() {
    # Parse simple arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --ip)
                IP_ADDRESS="$2"
                shift 2
                ;;
            --help)
                echo "Shape Network Simple Health Check Script"
                echo "Tests RPC endpoints, SSL, and basic blockchain status"
                echo ""
                echo "Usage: $0 [--domain DOMAIN] [--ip IP]"
                echo ""
                echo "Options:"
                echo "  --domain DOMAIN    Override domain name"
                echo "  --ip IP           Override IP address"
                echo "  --help           Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    local domain=$(get_domain)
    local ip_address=$(get_ip_address)

    log_header "🚀 Shape Network Health Check"
    log_info "Domain: $domain"
    log_info "Direct IP: $ip_address"
    echo ""

    # Test SSL
    log_header "🔒 SSL Test"
    test_ssl "$domain"
    echo ""

    # Test RPC endpoints
    log_header "📡 RPC Endpoint Tests"
    test_rpc_endpoint "https://$domain/rpc" "Domain RPC"
    test_rpc_endpoint "http://$ip_address:8545" "Direct IP RPC"

    # Test auth RPC if available (LoadBalancer service)
    if kubectl get svc -l component=op-geth -o jsonpath='{.items[0].spec.type}' 2>/dev/null | grep -q "LoadBalancer" 2>/dev/null; then
        test_rpc_endpoint "http://$ip_address:8551" "Auth RPC"
    fi
    echo ""

    # Test blockchain status
    log_header "🔷 Blockchain Status Tests"
    test_chain_id "https://$domain/rpc" ""
    test_sync_status "https://$domain/rpc" ""
    test_current_block "https://$domain/rpc" ""
    test_peer_count "https://$domain/rpc" ""
    echo ""

    # Summary
    log_header "📊 Test Summary"
    log_info "Total Tests: $TESTS_TOTAL"
    log_success "Passed: $TESTS_PASSED"
    if [ $TESTS_FAILED -gt 0 ]; then
        log_error "Failed: $TESTS_FAILED"
        echo ""
        log_info "Some tests failed. Check the output above for details."
        exit 1
    else
        echo ""
        log_success "🎉 All tests passed! Shape Network is healthy."
        exit 0
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
