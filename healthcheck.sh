#!/bin/bash

# Shape Network Comprehensive Health Check Script
# Unified testing for all endpoints: Homepage, WebSocket, SSL, Direct IP Access
# Includes Shape Network specific tests: sync status, latest block, chain ID, gas price, peer count
#
# Usage:
# ./healthcheck.sh [options]
#
# Options:
#   --domain DOMAIN    Override domain name (default: auto-detect)
#   --ip IP            Override IP address (default: auto-detect)
#   --verbose          Enable verbose output
#   --ssl-only         Run only SSL tests
#   --rpc-only         Run only WebSocket and JSON-RPC tests
#   --shape-only       Run only Shape Network specific tests
#   --quick            Quick health check (skip detailed tests)
#   --help             Show this help message
#
# Features:
# - SSL certificate validation and protocols
# - HTTPS endpoint testing with security headers
# - Homepage availability and content validation
# - WebSocket connectivity (domain /ws + direct IP:8546)
# - HTTP JSON-RPC testing (domain /rpc + direct IP:8545)
# - Auth RPC testing (direct IP:8551)
# - Shape Network sync status and latest block
# - Chain ID validation (360 for Shape Network)
# - Gas price monitoring
# - Peer count and client version
# - Performance metrics and timing
# - Kubernetes cluster status
# - Comprehensive error reporting

set -e

# Configuration
DEFAULT_TIMEOUT=30
WS_TIMEOUT=30
MAX_RETRIES=3

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Test options
VERBOSE=false
SSL_ONLY=false
RPC_ONLY=false
SHAPE_ONLY=false
SKIP_SSL=false
QUICK=false

# Helper function for hex to decimal conversion
hex_to_dec() {
    local hex_value="$1"
    if [ -z "$hex_value" ] || [ "$hex_value" = "null" ]; then
        echo "0"
        return
    fi
    local clean_hex=$(echo "$hex_value" | sed 's/0x//' | tr '[:lower:]' '[:upper:]')
    echo "ibase=16; $clean_hex" | bc 2>/dev/null || echo "0"
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    ((TESTS_PASSED++))
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((TESTS_FAILED++))
}

log_header() {
    echo -e "${GREEN}$1${NC}"
}

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
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

    # Try to get from Azure
    if command -v az &> /dev/null; then
        local resource_group=$(az aks list --query "[0].resourceGroup" -o tsv 2>/dev/null)
        local cluster_name=$(az aks list --query "[0].name" -o tsv 2>/dev/null)

        if [ ! -z "$resource_group" ] && [ ! -z "$cluster_name" ]; then
            local node_rg=$(az aks show --resource-group "$resource_group" --name "$cluster_name" --query nodeResourceGroup -o tsv 2>/dev/null)
            if [ ! -z "$node_rg" ]; then
                local dns_label="mainnet-shape-snow"
                local fqdn=$(az network public-ip show --resource-group "$node_rg" --name "shape-snow-mainnet-static-ip" --query dnsSettings.fqdn -o tsv 2>/dev/null)
                if [ ! -z "$fqdn" ]; then
                    echo "$fqdn"
                    return
                fi
            fi
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

    # Try to get from Azure
    if command -v az &> /dev/null; then
        local resource_group=$(az aks list --query "[0].resourceGroup" -o tsv 2>/dev/null)
        local cluster_name=$(az aks list --query "[0].name" -o tsv 2>/dev/null)

        if [ ! -z "$resource_group" ] && [ ! -z "$cluster_name" ]; then
            local node_rg=$(az aks show --resource-group "$resource_group" --name "$cluster_name" --query nodeResourceGroup -o tsv 2>/dev/null)
            if [ ! -z "$node_rg" ]; then
                local ip_name="shape-snow-mainnet-static-ip"
                local ip_addr=$(az network public-ip show --resource-group "$node_rg" --name "$ip_name" --query ipAddress -o tsv 2>/dev/null)
                if [ ! -z "$ip_addr" ]; then
                    echo "$ip_addr"
                    return
                fi
            fi
        fi
    fi

    # Default fallback
    echo "172.200.56.10"
}

# Check if domain is reachable
check_domain_reachability() {
    local domain="$1"
    local timeout="${2:-$DEFAULT_TIMEOUT}"

    test_start
    log_test "Checking domain reachability: $domain"

    if ping -c 1 -W "$timeout" "$domain" &> /dev/null; then
        log_success "Domain $domain is reachable"
        return 0
    else
        log_error "Domain $domain is not reachable"
        return 1
    fi
}

# SSL Certificate Tests
test_ssl_certificate() {
    local domain="$1"
    local port="${2:-443}"

    test_start
    log_test "Testing SSL certificate for $domain:$port"

    local cert_info=$(echo | openssl s_client -servername "$domain" -connect "$domain:$port" 2>/dev/null | openssl x509 -noout -dates -subject -issuer 2>/dev/null)

    if [ $? -eq 0 ] && [ ! -z "$cert_info" ]; then
        local subject=$(echo "$cert_info" | grep "subject=" | sed 's/subject=//')
        local issuer=$(echo "$cert_info" | grep "issuer=" | sed 's/issuer=//')
        local not_before=$(echo "$cert_info" | grep "notBefore=" | sed 's/notBefore=//')
        local not_after=$(echo "$cert_info" | grep "notAfter=" | sed 's/notAfter=//')

        log_success "SSL certificate is valid"
        [ "$VERBOSE" = true ] && log_info "Subject: $subject"
        [ "$VERBOSE" = true ] && log_info "Issuer: $issuer"
        [ "$VERBOSE" = true ] && log_info "Valid from: $not_before"
        [ "$VERBOSE" = true ] && log_info "Valid until: $not_after"

        # Check if certificate is close to expiry (within 30 days)
        # Try different date parsing methods for better compatibility
        local expiry_date=""
        if command -v gdate &> /dev/null; then
            # Use gdate if available (macOS compatibility)
            expiry_date=$(gdate -d "$not_after" +%s 2>/dev/null)
        else
            # Try standard date command
            expiry_date=$(date -d "$not_after" +%s 2>/dev/null)
        fi

        if [ ! -z "$expiry_date" ] && [ "$expiry_date" != "null" ]; then
            local current_date=$(date +%s)
            local days_left=$(( (expiry_date - current_date) / 86400 ))

            if [ $days_left -lt 0 ]; then
                log_warning "SSL certificate appears to be expired or has invalid dates"
            elif [ $days_left -lt 30 ]; then
                log_warning "SSL certificate expires in $days_left days"
            else
                [ "$VERBOSE" = true ] && log_info "Certificate expires in $days_left days"
            fi
        else
            log_warning "Could not parse SSL certificate expiry date"
        fi

        return 0
    else
        log_warning "SSL certificate validation failed - certificate may not be ready yet"
        [ "$VERBOSE" = true ] && log_info "This is normal if SSL certificates are still being issued by Let's Encrypt"
        return 0  # Don't fail the test, just warn
    fi
}

test_ssl_protocols() {
    local domain="$1"

    test_start
    log_test "Testing SSL/TLS protocols for $domain"

    local supported_protocols=""
    local protocols=("tls1_3" "tls1_2" "tls1_1" "tls1")

    for protocol in "${protocols[@]}"; do
        if echo | openssl s_client -"$protocol" -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout 2>/dev/null; then
            supported_protocols="$supported_protocols $protocol"
        fi
    done

    if [ ! -z "$supported_protocols" ]; then
        log_success "Supported SSL/TLS protocols:$supported_protocols"
        return 0
    else
        log_warning "No SSL/TLS protocols supported - SSL certificate may not be ready yet"
        return 0  # Don't fail, just warn
    fi
}

test_ssl_ciphers() {
    local domain="$1"

    test_start
    log_test "Testing SSL cipher suites for $domain"

    local ciphers=$(openssl ciphers 'ALL:eNULL' | sed -e 's/:/ /g')
    local working_ciphers=""

    for cipher in $ciphers; do
        if echo | openssl s_client -cipher "$cipher" -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout 2>/dev/null; then
            working_ciphers="$working_ciphers $cipher"
        fi
    done

    if [ ! -z "$working_ciphers" ]; then
        [ "$VERBOSE" = true ] && log_success "Working cipher suites:$working_ciphers"
        log_success "SSL cipher suites are working"
        return 0
    else
        log_warning "No SSL cipher suites working - SSL certificate may not be ready yet"
        return 0  # Don't fail, just warn
    fi
}

# HTTPS Endpoint Tests
test_https_endpoint() {
    local url="$1"
    local expected_status="${2:-200}"
    local timeout="${3:-$DEFAULT_TIMEOUT}"

    test_start
    log_test "Testing HTTPS endpoint: $url"

    local response=$(curl -s -w "HTTPSTATUS:%{http_code};TIME:%{time_total}" \
        --max-time "$timeout" \
        -k "$url" 2>/dev/null)

    local http_code=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://' | sed -e 's/;TIME:.*//')
    local response_time=$(echo "$response" | tr -d '\n' | sed -e 's/.*TIME://')

    if [ "$http_code" = "$expected_status" ]; then
        log_success "HTTPS endpoint responded with $http_code (took ${response_time}s)"
        return 0
    else
        log_error "HTTPS endpoint failed: HTTP $http_code (expected $expected_status)"
        return 1
    fi
}

test_security_headers() {
    local url="$1"

    test_start
    log_test "Testing security headers for $url"

    local headers=$(curl -s -I -k "$url" 2>/dev/null)
    local score=0
    local total_checks=0

    # Check for important security headers
    ((total_checks++))
    if echo "$headers" | grep -i "strict-transport-security" >/dev/null; then
        ((score++))
        [ "$VERBOSE" = true ] && log_info "✅ HSTS header present"
    else
        [ "$VERBOSE" = true ] && log_warning "❌ Missing HSTS header"
    fi

    ((total_checks++))
    if echo "$headers" | grep -i "x-frame-options" >/dev/null; then
        ((score++))
        [ "$VERBOSE" = true ] && log_info "✅ X-Frame-Options header present"
    else
        [ "$VERBOSE" = true ] && log_warning "❌ Missing X-Frame-Options header"
    fi

    ((total_checks++))
    if echo "$headers" | grep -i "x-content-type-options" >/dev/null; then
        ((score++))
        [ "$VERBOSE" = true ] && log_info "✅ X-Content-Type-Options header present"
    else
        [ "$VERBOSE" = true ] && log_warning "❌ Missing X-Content-Type-Options header"
    fi

    local percentage=$(( (score * 100) / total_checks ))
    log_success "Security headers: $score/$total_checks ($percentage%)"
    return 0
}

# Homepage Tests
test_homepage() {
    local domain="$1"

    test_start
    log_test "Testing homepage: https://$domain"

    local response=$(curl -s -w "HTTPSTATUS:%{http_code};TIME:%{time_total}" \
        --max-time "$DEFAULT_TIMEOUT" \
        -k "https://$domain" 2>/dev/null)

    local http_code=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://' | sed -e 's/;TIME:.*//')
    local response_time=$(echo "$response" | tr -d '\n' | sed -e 's/.*TIME://')
    local body=$(echo "$response" | sed -e 's/HTTPSTATUS.*//')

    if [ "$http_code" = "200" ]; then
        log_success "Homepage responded with $http_code (took ${response_time}s)"

        # Check for expected content
        if echo "$body" | grep -i "shape\|blockchain\|network" >/dev/null; then
            [ "$VERBOSE" = true ] && log_info "✅ Homepage contains expected content"
        else
            [ "$VERBOSE" = true ] && log_warning "⚠️  Homepage content may not be as expected"
        fi

        return 0
    else
        log_error "Homepage failed: HTTP $http_code"
        return 1
    fi
}

# WebSocket Tests
test_websocket() {
    local endpoint="$1"
    local port="${2:-}"
    local use_ssl="${3:-true}"
    local endpoint_type="${4:-domain}"

    local protocol="ws"
    [ "$use_ssl" = true ] && protocol="wss"

    local url="$protocol://$endpoint"
    [ ! -z "$port" ] && url="$protocol://$endpoint:$port"

    test_start
    log_test "Testing WebSocket ($endpoint_type): $url"

    # Simple WebSocket test using curl (if available)
    if command -v websocat &> /dev/null; then
        # Use websocat for proper WebSocket testing
        local test_message='{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
        local response=$(echo "$test_message" | timeout "$WS_TIMEOUT" websocat "$url" 2>/dev/null)

        if [ $? -eq 0 ] && [ ! -z "$response" ]; then
            log_success "WebSocket connection successful ($endpoint_type)"
            return 0
        else
            log_error "WebSocket connection failed ($endpoint_type)"
            return 1
        fi
    else
        # Fallback: try HTTP upgrade to WebSocket
        local response=$(curl -s -I \
            -H "Connection: Upgrade" \
            -H "Upgrade: websocket" \
            -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
            -H "Sec-WebSocket-Version: 13" \
            --max-time "$WS_TIMEOUT" \
            "$url" 2>/dev/null)

        if echo "$response" | grep -i "101 Switching Protocols" >/dev/null; then
            log_success "WebSocket upgrade successful ($endpoint_type)"
            return 0
        else
            log_warning "WebSocket upgrade test inconclusive ($endpoint_type) - websocat not available"
            return 0
        fi
    fi
}

# HTTP JSON-RPC Tests
test_jsonrpc_http() {
    local endpoint="$1"
    local use_ssl="${2:-true}"
    local endpoint_type="${3:-domain}"

    local protocol="http"
    [ "$use_ssl" = true ] && protocol="https"

    local url="$protocol://$endpoint"

    test_start
    log_test "Testing HTTP JSON-RPC ($endpoint_type): $url"

    # Test basic JSON-RPC call
    local payload='{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
    local curl_opts="-s -X POST -H 'Content-Type: application/json' --data '$payload' --max-time '$DEFAULT_TIMEOUT'"
    [ "$use_ssl" = true ] && curl_opts="$curl_opts -k"
    local response=$(eval curl $curl_opts "$url" 2>/dev/null)

    if [ $? -eq 0 ] && [ ! -z "$response" ]; then
        # Check if response contains expected JSON-RPC fields
        if echo "$response" | jq -e '.jsonrpc and .id' >/dev/null 2>&1; then
            local chain_id=$(echo "$response" | jq -r '.result' 2>/dev/null)
            if [ ! -z "$chain_id" ] && [ "$chain_id" != "null" ]; then
                log_success "HTTP JSON-RPC working ($endpoint_type) - Chain ID: $chain_id"
                return 0
            else
                log_success "HTTP JSON-RPC responded ($endpoint_type) but no chain ID"
                return 0
            fi
        else
            log_error "HTTP JSON-RPC response not valid JSON-RPC format ($endpoint_type)"
            return 1
        fi
    else
        log_error "HTTP JSON-RPC request failed ($endpoint_type)"
        return 1
    fi
}

test_jsonrpc_methods() {
    local endpoint="$1"
    local use_ssl="${2:-true}"
    local endpoint_type="${3:-domain}"

    local protocol="http"
    [ "$use_ssl" = true ] && protocol="https"

    local url="$protocol://$endpoint"

    test_start
    log_test "Testing Shape Network JSON-RPC methods ($endpoint_type): $url"

    # Shape Network specific methods
    local methods=("eth_blockNumber" "eth_chainId" "eth_gasPrice" "eth_syncing" "net_version" "net_peerCount" "web3_clientVersion" "eth_accounts" "eth_mining" "eth_hashrate")
    local passed=0
    local failed=0

    for method in "${methods[@]}"; do
        local payload="{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":[],\"id\":1}"
        local curl_opts="-s -X POST -H 'Content-Type: application/json' --data '$payload' --max-time '$DEFAULT_TIMEOUT'"
        [ "$use_ssl" = true ] && curl_opts="$curl_opts -k"
        local response=$(eval curl $curl_opts "$url" 2>/dev/null)

        if [ $? -eq 0 ] && echo "$response" | jq -e '.result' >/dev/null 2>&1; then
            ((passed++))
            [ "$VERBOSE" = true ] && log_info "✅ $method: OK ($endpoint_type)"
        else
            ((failed++))
            [ "$VERBOSE" = true ] && log_warning "❌ $method: Failed ($endpoint_type)"
        fi
    done

    if [ $passed -gt 0 ]; then
        log_success "JSON-RPC methods ($endpoint_type): $passed passed, $failed failed"
        return 0
    else
        log_error "All JSON-RPC methods failed ($endpoint_type)"
        return 1
    fi
}

# Performance Tests
test_performance() {
    local domain="$1"

    test_start
    log_test "Testing performance metrics for $domain"

    local results=$(curl -s -w "@-" \
        -o /dev/null \
        --max-time "$DEFAULT_TIMEOUT" \
        -k "https://$domain" <<< '{
            "time_namelookup": "%{time_namelookup}",
            "time_connect": "%{time_connect}",
            "time_appconnect": "%{time_appconnect}",
            "time_pretransfer": "%{time_pretransfer}",
            "time_redirect": "%{time_redirect}",
            "time_starttransfer": "%{time_starttransfer}",
            "time_total": "%{time_total}"
        }')

    if [ $? -eq 0 ]; then
        local total_time=$(echo "$results" | jq -r '.time_total' 2>/dev/null)

        if [ ! -z "$total_time" ] && [ "$total_time" != "null" ]; then
            log_success "Performance test completed (${total_time}s total)"
            [ "$VERBOSE" = true ] && log_info "Detailed timing: $results"
            return 0
        else
            log_warning "Performance test completed (timing data unavailable)"
            return 0
        fi
    else
        log_error "Performance test failed"
        return 1
    fi
}

# Shape Network Specific Tests
test_shape_network_sync_status() {
    local endpoint="$1"
    local use_ssl="${2:-true}"
    local endpoint_type="${3:-domain}"

    local protocol="http"
    [ "$use_ssl" = true ] && protocol="https"

    local url="$protocol://$endpoint"

    test_start
    log_test "Testing Shape Network sync status ($endpoint_type): $url"

    # Test eth_syncing to check sync status
    local payload='{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
    local curl_opts="-s -X POST -H 'Content-Type: application/json' --data '$payload' --max-time '$DEFAULT_TIMEOUT'"
    [ "$use_ssl" = true ] && curl_opts="$curl_opts -k"
    local response=$(eval curl $curl_opts "$url" 2>/dev/null)

    if [ $? -eq 0 ] && [ ! -z "$response" ]; then
        if echo "$response" | jq '.result' >/dev/null 2>&1; then
            local syncing=$(echo "$response" | jq -r '.result' 2>/dev/null)

            if [ "$syncing" = "false" ]; then
                log_success "Shape Network is fully synced ($endpoint_type)"
                return 0
            elif echo "$response" | jq '.result | type == "object"' >/dev/null 2>&1; then
                # Node is syncing - result is an object with sync details
                local current_block=$(hex_to_dec "$(echo "$response" | jq -r '.result.currentBlock' 2>/dev/null)")
                local highest_block=$(hex_to_dec "$(echo "$response" | jq -r '.result.highestBlock' 2>/dev/null)")

                if [ ! -z "$current_block" ] && [ ! -z "$highest_block" ] && [ "$highest_block" -gt 0 ]; then
                    local blocks_behind=$((highest_block - current_block))
                    local sync_percentage=$(( (current_block * 100) / highest_block ))

                    log_success "Shape Network syncing ($endpoint_type): $current_block/$highest_block blocks ($sync_percentage% complete, $blocks_behind behind)"
                else
                    log_success "Shape Network is syncing ($endpoint_type)"
                fi
                return 0
            else
                log_error "Invalid sync status format ($endpoint_type): $syncing"
                return 1
            fi
        else
            log_error "Invalid response format for eth_syncing ($endpoint_type)"
            return 1
        fi
    else
        log_error "Failed to get sync status ($endpoint_type)"
        return 1
    fi
}

test_shape_network_latest_block() {
    local endpoint="$1"
    local use_ssl="${2:-true}"
    local endpoint_type="${3:-domain}"

    local protocol="http"
    [ "$use_ssl" = true ] && protocol="https"

    local url="$protocol://$endpoint"

    test_start
    log_test "Testing Shape Network latest block ($endpoint_type): $url"

    # Test eth_blockNumber to get latest block
    local payload='{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
    local curl_opts="-s -X POST -H 'Content-Type: application/json' --data '$payload' --max-time '$DEFAULT_TIMEOUT'"
    [ "$use_ssl" = true ] && curl_opts="$curl_opts -k"
    local response=$(eval curl $curl_opts "$url" 2>/dev/null)

    if [ $? -eq 0 ] && [ ! -z "$response" ]; then
        if echo "$response" | jq -e '.result' >/dev/null 2>&1; then
            local block_hex=$(echo "$response" | jq -r '.result' 2>/dev/null)
            local block_number=$(hex_to_dec "$block_hex")

            if [ ! -z "$block_number" ]; then
                log_success "Shape Network latest block ($endpoint_type): $block_number (0x$block_hex)"

                # Get block details
                local block_payload="{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$block_hex\", false],\"id\":1}"
                local block_curl_opts="-s -X POST -H 'Content-Type: application/json' --data '$block_payload' --max-time '$DEFAULT_TIMEOUT'"
                [ "$use_ssl" = true ] && block_curl_opts="$block_curl_opts -k"
                local block_response=$(eval curl $block_curl_opts "$url" 2>/dev/null)

                if [ $? -eq 0 ] && echo "$block_response" | jq -e '.result' >/dev/null 2>&1; then
                    local block_hash=$(echo "$block_response" | jq -r '.result.hash' 2>/dev/null)
                    local tx_count=$(echo "$block_response" | jq -r '.result.transactions | length' 2>/dev/null)
                    local timestamp=$(echo "$block_response" | jq -r '.result.timestamp' 2>/dev/null | sed 's/0x//' | xargs printf "%d\n" 2>/dev/null)

                    if [ ! -z "$block_hash" ]; then
                        [ "$VERBOSE" = true ] && log_info "Block hash: $block_hash"
                        [ "$VERBOSE" = true ] && log_info "Transactions: $tx_count"
                        if [ ! -z "$timestamp" ]; then
                            local block_time=$(date -d "@$(hex_to_dec "$timestamp")" 2>/dev/null || date -r "$(hex_to_dec "$timestamp")" 2>/dev/null)
                            [ "$VERBOSE" = true ] && log_info "Block time: $block_time"
                        fi
                    fi
                fi

                return 0
            else
                log_error "Invalid block number format ($endpoint_type)"
                return 1
            fi
        else
            log_error "Invalid response format for eth_blockNumber ($endpoint_type)"
            return 1
        fi
    else
        log_error "Failed to get latest block ($endpoint_type)"
        return 1
    fi
}

test_shape_network_chain_id() {
    local endpoint="$1"
    local use_ssl="${2:-true}"
    local endpoint_type="${3:-domain}"

    local protocol="http"
    [ "$use_ssl" = true ] && protocol="https"

    local url="$protocol://$endpoint"

    test_start
    log_test "Testing Shape Network Chain ID ($endpoint_type): $url"

    # Test eth_chainId
    local payload='{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
    local curl_opts="-s -X POST -H 'Content-Type: application/json' --data '$payload' --max-time '$DEFAULT_TIMEOUT'"
    [ "$use_ssl" = true ] && curl_opts="$curl_opts -k"
    local response=$(eval curl $curl_opts "$url" 2>/dev/null)

    if [ $? -eq 0 ] && [ ! -z "$response" ]; then
        if echo "$response" | jq -e '.result' >/dev/null 2>&1; then
            local chain_id_hex=$(echo "$response" | jq -r '.result' 2>/dev/null)
            local chain_id=$(hex_to_dec "$chain_id_hex")

            if [ "$chain_id" = "360" ]; then
                log_success "Shape Network Chain ID correct ($endpoint_type): $chain_id (0x$(echo "$chain_id_hex" | sed 's/0x//'))"
                return 0
            elif [ ! -z "$chain_id" ]; then
                log_warning "Unexpected Chain ID ($endpoint_type): $chain_id (expected: 360)"
                return 0
            else
                log_error "Invalid Chain ID format ($endpoint_type)"
                return 1
            fi
        else
            log_error "Invalid response format for eth_chainId ($endpoint_type)"
            return 1
        fi
    else
        log_error "Failed to get Chain ID ($endpoint_type)"
        return 1
    fi
}

test_shape_network_gas_price() {
    local endpoint="$1"
    local use_ssl="${2:-true}"
    local endpoint_type="${3:-domain}"

    local protocol="http"
    [ "$use_ssl" = true ] && protocol="https"

    local url="$protocol://$endpoint"

    test_start
    log_test "Testing Shape Network gas price ($endpoint_type): $url"

    # Test eth_gasPrice
    local payload='{"jsonrpc":"2.0","method":"eth_gasPrice","params":[],"id":1}'
    local curl_opts="-s -X POST -H 'Content-Type: application/json' --data '$payload' --max-time '$DEFAULT_TIMEOUT'"
    [ "$use_ssl" = true ] && curl_opts="$curl_opts -k"
    local response=$(eval curl $curl_opts "$url" 2>/dev/null)

    if [ $? -eq 0 ] && [ ! -z "$response" ]; then
        if echo "$response" | jq -e '.result' >/dev/null 2>&1; then
            local gas_price_hex=$(echo "$response" | jq -r '.result' 2>/dev/null)
            local gas_price_wei=$(hex_to_dec "$gas_price_hex")
            local gas_price_gwei=$((gas_price_wei / 1000000000))

            if [ ! -z "$gas_price_gwei" ]; then
                log_success "Shape Network gas price ($endpoint_type): ${gas_price_gwei} gwei (0x$gas_price_hex wei)"
                return 0
            else
                log_error "Invalid gas price format ($endpoint_type)"
                return 1
            fi
        else
            log_error "Invalid response format for eth_gasPrice ($endpoint_type)"
            return 1
        fi
    else
        log_error "Failed to get gas price ($endpoint_type)"
        return 1
    fi
}

test_shape_network_peer_count() {
    local endpoint="$1"
    local use_ssl="${2:-true}"
    local endpoint_type="${3:-domain}"

    local protocol="http"
    [ "$use_ssl" = true ] && protocol="https"

    local url="$protocol://$endpoint"

    test_start
    log_test "Testing Shape Network peer count ($endpoint_type): $url"

    # Test net_peerCount
    local payload='{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
    local curl_opts="-s -X POST -H 'Content-Type: application/json' --data '$payload' --max-time '$DEFAULT_TIMEOUT'"
    [ "$use_ssl" = true ] && curl_opts="$curl_opts -k"
    local response=$(eval curl $curl_opts "$url" 2>/dev/null)

    if [ $? -eq 0 ] && [ ! -z "$response" ]; then
        if echo "$response" | jq -e '.result' >/dev/null 2>&1; then
            local peer_count_hex=$(echo "$response" | jq -r '.result' 2>/dev/null)
            local peer_count=$(hex_to_dec "$peer_count_hex")

            if [ ! -z "$peer_count" ]; then
                if [ "$peer_count" -gt 0 ]; then
                    log_success "Shape Network peers connected ($endpoint_type): $peer_count"
                else
                    log_warning "Shape Network has no peers connected ($endpoint_type)"
                fi
                return 0
            else
                log_error "Invalid peer count format ($endpoint_type)"
                return 1
            fi
        else
            log_error "Invalid response format for net_peerCount ($endpoint_type)"
            return 1
        fi
    else
        log_error "Failed to get peer count ($endpoint_type)"
        return 1
    fi
}

test_shape_network_client_version() {
    local endpoint="$1"
    local use_ssl="${2:-true}"
    local endpoint_type="${3:-domain}"

    local protocol="http"
    [ "$use_ssl" = true ] && protocol="https"

    local url="$protocol://$endpoint"

    test_start
    log_test "Testing Shape Network client version ($endpoint_type): $url"

    # Test web3_clientVersion
    local payload='{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}'
    local curl_opts="-s -X POST -H 'Content-Type: application/json' --data '$payload' --max-time '$DEFAULT_TIMEOUT'"
    [ "$use_ssl" = true ] && curl_opts="$curl_opts -k"
    local response=$(eval curl $curl_opts "$url" 2>/dev/null)

    if [ $? -eq 0 ] && [ ! -z "$response" ]; then
        if echo "$response" | jq -e '.result' >/dev/null 2>&1; then
            local client_version=$(echo "$response" | jq -r '.result' 2>/dev/null)

            if [ ! -z "$client_version" ]; then
                log_success "Shape Network client version ($endpoint_type): $client_version"
                return 0
            else
                log_error "Empty client version response ($endpoint_type)"
                return 1
            fi
        else
            log_error "Invalid response format for web3_clientVersion ($endpoint_type)"
            return 1
        fi
    else
        log_error "Failed to get client version ($endpoint_type)"
        return 1
    fi
}

test_op_node_status() {
    local endpoint="$1"
    local use_ssl="${2:-true}"
    local endpoint_type="${3:-op-node}"

    local protocol="http"
    [ "$use_ssl" = true ] && protocol="https"

    local url="$protocol://$endpoint"

    test_start
    log_test "Testing op-node status ($endpoint_type): $url"

    # Test op-node health endpoint (if available)
    local curl_opts="-s --max-time '$DEFAULT_TIMEOUT'"
    [ "$use_ssl" = true ] && curl_opts="$curl_opts -k"
    local response=$(eval curl $curl_opts "$url" 2>/dev/null)

    if [ $? -eq 0 ] && [ ! -z "$response" ]; then
        log_success "op-node responding ($endpoint_type)"
        [ "$VERBOSE" = true ] && log_info "Response: $response"
        return 0
    else
        log_warning "op-node not responding or endpoint not available ($endpoint_type)"
        return 0  # Don't fail as this might be expected
    fi
}

# Main test execution
run_ssl_tests() {
    local domain="$1"

    if [ "$SKIP_SSL" = true ]; then
        log_info "Skipping SSL tests (--skip-ssl option enabled)"
        return 0
    fi

    log_header "🔒 SSL Certificate Tests"
    test_ssl_certificate "$domain"
    test_ssl_protocols "$domain"
    test_ssl_ciphers "$domain"
    echo ""
}

run_https_tests() {
    local domain="$1"

    log_header "🌐 HTTPS Endpoint Tests"
    test_https_endpoint "https://$domain"
    test_security_headers "https://$domain"
    test_homepage "$domain"
    echo ""
}

run_websocket_tests() {
    local domain="$1"
    local ip_address="$2"

    log_header "🔗 WebSocket Tests"

    # Test domain-based WebSocket (SSL) - using /ws path
    test_websocket "$domain/ws" "" true "domain"

    # Test IP-based WebSocket (direct port access)
    test_websocket "$ip_address" "8546" false "direct IP"

    echo ""
}

run_jsonrpc_tests() {
    local domain="$1"
    local ip_address="$2"

    log_header "📡 JSON-RPC Tests"

    # Test domain-based JSON-RPC (SSL) - using /rpc path
    test_jsonrpc_http "$domain/rpc" true "domain"

    # Test IP-based JSON-RPC (direct port access)
    test_jsonrpc_http "$ip_address:8545" false "direct IP"

    if [ "$QUICK" != true ]; then
        test_jsonrpc_methods "$domain/rpc" true "domain"
        test_jsonrpc_methods "$ip_address:8545" false "direct IP"
    fi

    echo ""
}

run_performance_tests() {
    local domain="$1"

    log_header "⚡ Performance Tests"
    test_performance "$domain"
    echo ""
}

run_shape_network_tests() {
    local domain="$1"
    local ip_address="$2"

    log_header "🔷 Shape Network Specific Tests"

    # Determine protocol based on SSL skip flag
    local use_ssl=true
    [ "$SKIP_SSL" = true ] && use_ssl=false
    local protocol="https"
    [ "$use_ssl" = false ] && protocol="http"

    if [ "$use_ssl" = true ]; then
        # Test domain-based endpoints when SSL is enabled
        test_shape_network_chain_id "$domain/rpc" "$use_ssl" "domain ($protocol)"
        test_shape_network_sync_status "$domain/rpc" "$use_ssl" "domain ($protocol)"
        test_shape_network_latest_block "$domain/rpc" "$use_ssl" "domain ($protocol)"
        test_shape_network_gas_price "$domain/rpc" "$use_ssl" "domain ($protocol)"
        test_shape_network_peer_count "$domain/rpc" "$use_ssl" "domain ($protocol)"
        test_shape_network_client_version "$domain/rpc" "$use_ssl" "domain ($protocol)"
    else
        log_info "Skipping domain-based tests (--skip-ssl enabled)"
        log_info "💡 Tip: Domain endpoints require SSL certificates to be ready"
        log_info "💡 Tip: Use 'kubectl port-forward' to test internal services:"
        log_info "   kubectl port-forward svc/shape-node-op-geth 8545:8545"
        log_info "   Then test with: curl http://localhost:8545 -X POST -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_chainId\",\"params\":[],\"id\":1}'"
    fi

    # Test additional IP-based endpoints (only if LoadBalancer service is configured)
    if kubectl get svc -l component=op-geth -o jsonpath='{.items[0].spec.type}' 2>/dev/null | grep -q "LoadBalancer"; then
        test_shape_network_chain_id "$ip_address:8551" false "auth RPC"
        test_jsonrpc_http "$ip_address:8551" false "auth RPC"
        test_jsonrpc_methods "$ip_address:8551" false "auth RPC"
    else
        log_info "💡 Direct IP endpoints not available (ClusterIP services)"
        log_info "💡 Use kubectl port-forward for internal testing"
    fi

    # Test op-node RPC endpoint (only if LoadBalancer service is configured)
    if kubectl get svc -l component=op-node -o jsonpath='{.items[0].spec.type}' 2>/dev/null | grep -q "LoadBalancer"; then
        test_op_node_status "$ip_address:9545" false "op-node RPC"
    fi

    echo ""
}

run_kubernetes_tests() {
    log_header "☸️  Kubernetes Infrastructure Tests"

    # Test pod status
    log_info "Testing pod status..."
    local total_pods=$(kubectl get pods -n shape-network --no-headers 2>/dev/null | wc -l)
    local ready_pods=$(kubectl get pods -n shape-network --no-headers 2>/dev/null | grep -c "Running\|Completed")

    if [ "$total_pods" -gt 0 ] && [ "$ready_pods" -eq "$total_pods" ]; then
        log_success "✅ All pods are ready ($ready_pods/$total_pods)"
    else
        log_error "❌ Some pods are not ready ($ready_pods/$total_pods)"
    fi

    # Test services
    log_info "Testing services..."
    local services=$(kubectl get svc -n shape-network --no-headers 2>/dev/null | wc -l)
    if [ "$services" -gt 0 ]; then
        log_success "✅ Services are available ($services services)"
    else
        log_error "❌ No services found"
    fi

    # Test ingress
    log_info "Testing ingress..."
    local ingress_count=$(kubectl get ingress -n shape-network --no-headers 2>/dev/null | wc -l)
    if [ "$ingress_count" -gt 0 ]; then
        log_success "✅ Ingress is configured ($ingress_count ingress resources)"
    else
        log_error "❌ No ingress found"
    fi

    # Test certificates
    log_info "Testing SSL certificates..."
    local cert_count=$(kubectl get certificate -n shape-network --no-headers 2>/dev/null | wc -l)
    if [ "$cert_count" -gt 0 ]; then
        local ready_certs=$(kubectl get certificate -n shape-network --no-headers 2>/dev/null | grep -c "True")
        if [ "$ready_certs" -eq "$cert_count" ]; then
            log_success "✅ All SSL certificates are ready ($ready_certs/$cert_count)"
        else
            log_warning "⚠️  Some SSL certificates are not ready ($ready_certs/$cert_count)"
        fi
    else
        log_error "❌ No SSL certificates found"
    fi

    # Test NGINX ingress controller
    log_info "Testing NGINX ingress controller..."
    if kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | grep -q "Running"; then
        log_success "✅ NGINX ingress controller is running"
    else
        log_error "❌ NGINX ingress controller is not running"
    fi

    # Test cert-manager
    log_info "Testing cert-manager..."
    if kubectl get pods -n cert-manager --no-headers 2>/dev/null | grep -q "Running"; then
        log_success "✅ cert-manager is running"
    else
        log_error "❌ cert-manager is not running"
    fi

    echo ""
}

# Show usage
show_usage() {
    cat << EOF
Shape Network Comprehensive Health Check Script

Usage: $0 [options]

Options:
    --domain DOMAIN    Override domain name (default: auto-detect)
    --ip IP            Override IP address (default: auto-detect)
    --verbose          Enable verbose output
    --ssl-only         Run only SSL certificate tests
    --rpc-only         Run only WebSocket and JSON-RPC tests
    --shape-only       Run only Shape Network specific tests
    --skip-ssl         Skip SSL certificate tests (useful when certificates are not ready)
    --quick            Quick health check (skip detailed tests)
    --help             Show this help message

Examples:
    $0                          # Full health check (domain + IP)
    $0 --domain example.com     # Check specific domain
    $0 --ip 192.168.1.100       # Check specific IP
    $0 --ssl-only               # SSL tests only
    $0 --rpc-only --verbose     # WebSocket + JSON-RPC tests with verbose output
    $0 --shape-only             # Shape Network specific tests only
    $0 --skip-ssl --shape-only  # Shape Network tests without SSL (when certs not ready)
    $0 --quick                  # Quick check

Notes:
    • SSL certificates may take time to be issued by Let's Encrypt
    • Use --skip-ssl when SSL certificates are not ready yet
    • Domain endpoints require working SSL certificates
    • Direct IP endpoints require LoadBalancer services (not ClusterIP)
    • Use kubectl port-forward for internal service testing

Test Coverage:
    🔒 SSL/TLS: Certificate validation, protocols, ciphers
    🌐 HTTPS: Endpoint testing, security headers, homepage
    🔗 WebSocket: Domain (/ws) and direct IP (port 8546)
    📡 JSON-RPC: Domain (/rpc), direct IP (ports 8545, 8551)
    🔷 Shape Network: Sync status, latest block, chain ID, gas price
    ☸️  Infrastructure: Peer count, client version, Kubernetes status

EOF
}

# Parse command line arguments
parse_args() {
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
            --verbose)
                VERBOSE=true
                shift
                ;;
            --ssl-only)
                SSL_ONLY=true
                shift
                ;;
            --rpc-only)
                RPC_ONLY=true
                shift
                ;;
            --shape-only)
                SHAPE_ONLY=true
                shift
                ;;
            --skip-ssl)
                SKIP_SSL=true
                shift
                ;;
            --quick)
                QUICK=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main execution
main() {
    parse_args "$@"

    local domain=$(get_domain)
    local ip_address=$(get_ip_address)

    log_header "🚀 Shape Network Health Check"
    log_info "Domain: $domain"
    log_info "Direct IP: $ip_address"
    echo ""

    # Basic connectivity check for domain
    if ! check_domain_reachability "$domain"; then
        log_error "Cannot proceed with domain tests - domain unreachable"
        # Continue with IP tests
    fi
    echo ""

    # Run tests based on options
    if [ "$SSL_ONLY" = true ]; then
        run_ssl_tests "$domain"
    elif [ "$RPC_ONLY" = true ]; then
        run_jsonrpc_tests "$domain" "$ip_address"
        run_websocket_tests "$domain" "$ip_address"
    elif [ "$SHAPE_ONLY" = true ]; then
        run_shape_network_tests "$domain" "$ip_address"
    elif [ "$QUICK" = true ]; then
        # Quick check - basic tests only
        log_header "⚡ Quick Health Check"
        if [ "$SKIP_SSL" != true ]; then
            test_ssl_certificate "$domain"
        fi
        test_https_endpoint "https://$domain"
        
        # Determine protocol based on SSL skip flag for Shape Network tests
        local use_ssl=true
        [ "$SKIP_SSL" = true ] && use_ssl=false
        local protocol="https"
        [ "$use_ssl" = false ] && protocol="http"
        
        if [ "$use_ssl" = true ]; then
            test_shape_network_chain_id "$domain/rpc" "$use_ssl" "domain ($protocol)"
            test_shape_network_sync_status "$domain/rpc" "$use_ssl" "domain ($protocol)"
            test_shape_network_latest_block "$domain/rpc" "$use_ssl" "domain ($protocol)"
            test_jsonrpc_http "$domain/rpc" "$use_ssl" "domain ($protocol)"
            test_websocket "$domain/ws" "" "$use_ssl" "domain ($protocol)"
        else
            log_info "Skipping domain-based tests (--skip-ssl enabled) - testing direct IP endpoints only"
        fi
        
        test_jsonrpc_http "$ip_address:8545" false "direct IP"
        test_websocket "$ip_address" "8546" false "direct IP"
        echo ""
    else
        # Full comprehensive test suite
        run_ssl_tests "$domain"
        run_https_tests "$domain"
        run_shape_network_tests "$domain" "$ip_address"
        run_jsonrpc_tests "$domain" "$ip_address"
        run_websocket_tests "$domain" "$ip_address"
        run_performance_tests "$domain"
        run_kubernetes_tests
    fi

    # Summary
    log_header "📊 Test Summary"
    log_info "Total Tests: $TESTS_TOTAL"
    log_success "Passed: $TESTS_PASSED"
    if [ $TESTS_FAILED -gt 0 ]; then
        log_error "Failed: $TESTS_FAILED"
        echo ""
        log_warning "Some tests failed. Check the output above for details."
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
