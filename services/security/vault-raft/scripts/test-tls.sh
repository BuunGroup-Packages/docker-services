#!/bin/bash
# Comprehensive TLS testing script for Vault HA setup
# This script tests the complete TLS flow: Client -> HAProxy -> Vault nodes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VAULT_ADDR="https://localhost:8300"
CERT_DIR="./certs"
VAULT_CACERT="$CERT_DIR/vault-ca.pem"

echo -e "${BLUE}=== Vault TLS End-to-End Testing Script ===${NC}"
echo ""

# Function to print test results
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
    else
        echo -e "${RED}✗ $2${NC}"
        if [ -n "$3" ]; then
            echo -e "${YELLOW}  Error: $3${NC}"
        fi
    fi
}

# Function to test certificate validity
test_certificate() {
    local cert_file=$1
    local cert_name=$2
    
    echo -e "${BLUE}Testing certificate: $cert_name${NC}"
    
    if [ ! -f "$cert_file" ]; then
        print_result 1 "Certificate file exists" "File not found: $cert_file"
        return 1
    fi
    
    # Check certificate validity
    if openssl x509 -in "$cert_file" -noout -checkend 86400 > /dev/null 2>&1; then
        print_result 0 "Certificate is valid and not expiring soon"
    else
        print_result 1 "Certificate validity check" "Certificate is invalid or expiring"
        return 1
    fi
    
    # Show certificate details
    echo -e "${YELLOW}Certificate details:${NC}"
    openssl x509 -in "$cert_file" -noout -subject -issuer -dates -ext subjectAltName
    echo ""
    
    return 0
}

# Function to test network connectivity
test_connectivity() {
    local host=$1
    local port=$2
    local name=$3
    
    if timeout 5 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        print_result 0 "Network connectivity to $name ($host:$port)"
        return 0
    else
        print_result 1 "Network connectivity to $name ($host:$port)" "Connection refused or timeout"
        return 1
    fi
}

# Function to test TLS handshake
test_tls_handshake() {
    local host=$1
    local port=$2
    local name=$3
    local ca_cert=$4
    
    echo -e "${BLUE}Testing TLS handshake with $name${NC}"
    
    if [ -n "$ca_cert" ] && [ -f "$ca_cert" ]; then
        if echo | openssl s_client -connect "$host:$port" -CAfile "$ca_cert" -verify_return_error -quiet 2>/dev/null; then
            print_result 0 "TLS handshake with $name (CA verified)"
        else
            print_result 1 "TLS handshake with $name (CA verified)" "Handshake failed or certificate verification failed"
            return 1
        fi
    else
        if echo | openssl s_client -connect "$host:$port" -verify_return_error -quiet 2>/dev/null; then
            print_result 0 "TLS handshake with $name (no CA verification)"
        else
            print_result 1 "TLS handshake with $name (no CA verification)" "Handshake failed"
            return 1
        fi
    fi
    
    return 0
}

# Function to test Vault API over TLS
test_vault_api() {
    local vault_addr=$1
    local ca_cert=$2
    
    echo -e "${BLUE}Testing Vault API over TLS${NC}"
    
    local curl_opts="-s -f"
    if [ -n "$ca_cert" ] && [ -f "$ca_cert" ]; then
        curl_opts="$curl_opts --cacert $ca_cert"
    else
        curl_opts="$curl_opts -k"
    fi
    
    # Test health endpoint
    if response=$(curl $curl_opts "$vault_addr/v1/sys/health" 2>/dev/null); then
        print_result 0 "Vault health endpoint accessible via TLS"
        echo -e "${YELLOW}Health status: $(echo $response | jq -r '.sealed // "unknown"' 2>/dev/null || echo "response received")${NC}"
    else
        print_result 1 "Vault health endpoint accessible via TLS" "API request failed"
        return 1
    fi
    
    return 0
}

# Function to test HAProxy stats
test_haproxy_stats() {
    echo -e "${BLUE}Testing HAProxy stats endpoint${NC}"
    
    if curl -s -f "http://localhost:8404/stats" > /dev/null 2>&1; then
        print_result 0 "HAProxy stats endpoint accessible"
        echo -e "${YELLOW}HAProxy backend status:${NC}"
        curl -s "http://localhost:8404/stats;csv" | grep vault | cut -d',' -f1,2,18 | column -t -s','
    else
        print_result 1 "HAProxy stats endpoint accessible" "Stats endpoint not reachable"
        return 1
    fi
    
    return 0
}

# Main testing flow
echo -e "${BLUE}1. Checking certificate files${NC}"
echo ""

# Test CA certificate
test_certificate "$CERT_DIR/vault-ca.pem" "CA Certificate"

# Test server certificates
for node in vault vault-2 vault-3; do
    test_certificate "$CERT_DIR/${node}.pem" "$node Server Certificate"
done

# Test HAProxy certificate
test_certificate "$CERT_DIR/haproxy.pem" "HAProxy Certificate"

# Test client certificate
test_certificate "$CERT_DIR/vault-client.pem" "Client Certificate"

echo ""
echo -e "${BLUE}2. Testing network connectivity${NC}"
echo ""

# Test direct Vault node connectivity
test_connectivity "localhost" "8200" "Vault Node 1"
test_connectivity "localhost" "8210" "Vault Node 2"
test_connectivity "localhost" "8220" "Vault Node 3"

# Test HAProxy connectivity
test_connectivity "localhost" "8300" "HAProxy Frontend"
test_connectivity "localhost" "8404" "HAProxy Stats"

echo ""
echo -e "${BLUE}3. Testing TLS handshakes${NC}"
echo ""

# Test direct node TLS handshakes
test_tls_handshake "localhost" "8200" "Vault Node 1" "$VAULT_CACERT"
test_tls_handshake "localhost" "8210" "Vault Node 2" "$VAULT_CACERT"
test_tls_handshake "localhost" "8220" "Vault Node 3" "$VAULT_CACERT"

# Test HAProxy TLS handshake
test_tls_handshake "localhost" "8300" "HAProxy Frontend" "$VAULT_CACERT"

echo ""
echo -e "${BLUE}4. Testing Vault API over TLS${NC}"
echo ""

# Test API through HAProxy
export VAULT_CACERT="$VAULT_CACERT"
test_vault_api "$VAULT_ADDR" "$VAULT_CACERT"

# Test direct API access to nodes
test_vault_api "https://localhost:8200" "$VAULT_CACERT"
test_vault_api "https://localhost:8210" "$VAULT_CACERT"
test_vault_api "https://localhost:8220" "$VAULT_CACERT"

echo ""
echo -e "${BLUE}5. Testing HAProxy load balancing${NC}"
echo ""

test_haproxy_stats

echo ""
echo -e "${BLUE}6. Certificate chain validation${NC}"
echo ""

# Validate certificate chains
echo -e "${YELLOW}Validating certificate chains:${NC}"
for node in vault vault-2 vault-3 haproxy; do
    if openssl verify -CAfile "$CERT_DIR/vault-ca.pem" "$CERT_DIR/${node}.pem" > /dev/null 2>&1; then
        print_result 0 "$node certificate chain validation"
    else
        print_result 1 "$node certificate chain validation" "Chain validation failed"
    fi
done

echo ""
echo -e "${BLUE}7. Advanced TLS testing${NC}"
echo ""

# Test cipher suites
echo -e "${YELLOW}Testing cipher suites:${NC}"
if openssl s_client -connect localhost:8300 -cipher 'ECDHE+AESGCM' -quiet < /dev/null 2>/dev/null; then
    print_result 0 "Strong cipher suite support (ECDHE+AESGCM)"
else
    print_result 1 "Strong cipher suite support (ECDHE+AESGCM)" "Cipher not supported"
fi

# Test protocol versions
echo -e "${YELLOW}Testing TLS protocol versions:${NC}"
for version in tls1_2 tls1_3; do
    if echo | openssl s_client -connect localhost:8300 -$version -quiet 2>/dev/null; then
        print_result 0 "TLS protocol $version support"
    else
        print_result 1 "TLS protocol $version support" "Protocol not supported"
    fi
done

echo ""
echo -e "${BLUE}=== Test Summary ===${NC}"
echo ""

# Final recommendations
echo -e "${YELLOW}Recommendations for production:${NC}"
echo "1. Regularly rotate certificates (current validity: 10 years)"
echo "2. Monitor certificate expiration dates"
echo "3. Implement certificate management automation"
echo "4. Enable audit logging in Vault configuration"
echo "5. Regularly test TLS configuration with this script"
echo "6. Monitor HAProxy backend health via stats endpoint"

echo ""
echo -e "${GREEN}TLS testing completed!${NC}"
echo ""
echo -e "${YELLOW}To connect to Vault with TLS:${NC}"
echo "export VAULT_ADDR=\"$VAULT_ADDR\""
echo "export VAULT_CACERT=\"$(pwd)/$VAULT_CACERT\""
echo "vault status"