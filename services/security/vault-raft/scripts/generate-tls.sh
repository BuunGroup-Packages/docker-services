#!/bin/bash
# Generate TLS certificates for Vault
# This script creates a CA and server certificates for Vault nodes

set -e

# Check if running in auto mode (skip if certs already exist)
if [ "$1" = "--auto" ] && [ -f "/certs/vault-ca.pem" ]; then
    echo "Certificates already exist, skipping generation..."
    exit 0
fi

# Configuration
CERT_DIR="/certs"
if [ "$1" != "--auto" ]; then
    CERT_DIR="./certs"
fi
DAYS_VALID=3650  # 10 years
COUNTRY="US"
STATE="State"
CITY="City"
ORG="Organization"
OU="Vault"

# Create directories
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

echo "=== Generating TLS Certificates for Vault ==="
echo ""

# Generate CA private key
echo "1. Generating CA private key..."
openssl genrsa -out vault-ca-key.pem 4096

# Generate CA certificate
echo "2. Generating CA certificate..."
cat > ca-csr.conf <<EOF
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
OU = $OU
CN = Vault CA
EOF

openssl req -new -x509 -days $DAYS_VALID -key vault-ca-key.pem -out vault-ca.pem -config ca-csr.conf

# Generate server certificates for each node
for node in vault vault-2 vault-3; do
    echo ""
    echo "3. Generating certificate for $node..."
    
    # Generate private key
    openssl genrsa -out ${node}-key.pem 4096
    
    # Create certificate signing request config
    cat > ${node}-csr.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
OU = $OU
CN = ${node}

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${node}
DNS.2 = ${node}.vault_network
DNS.3 = localhost
DNS.4 = vault.local
IP.1 = 127.0.0.1
EOF

    # Add specific IPs based on node
    case $node in
        vault)
            echo "IP.2 = 172.20.0.2" >> ${node}-csr.conf
            ;;
        vault-2)
            echo "IP.2 = 172.20.0.3" >> ${node}-csr.conf
            ;;
        vault-3)
            echo "IP.2 = 172.20.0.4" >> ${node}-csr.conf
            ;;
    esac
    
    # Generate certificate signing request
    openssl req -new -key ${node}-key.pem -out ${node}-csr.pem -config ${node}-csr.conf
    
    # Create certificate extensions config
    cat > ${node}-extfile.conf <<EOF
subjectAltName = @alt_names
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth

[alt_names]
DNS.1 = ${node}
DNS.2 = ${node}.vault_network
DNS.3 = localhost
DNS.4 = vault.local
IP.1 = 127.0.0.1
EOF

    # Add specific IPs based on node
    case $node in
        vault)
            echo "IP.2 = 172.20.0.2" >> ${node}-extfile.conf
            ;;
        vault-2)
            echo "IP.2 = 172.20.0.3" >> ${node}-extfile.conf
            ;;
        vault-3)
            echo "IP.2 = 172.20.0.4" >> ${node}-extfile.conf
            ;;
    esac
    
    # Sign the certificate
    openssl x509 -req -in ${node}-csr.pem -CA vault-ca.pem -CAkey vault-ca-key.pem \
        -CAcreateserial -out ${node}.pem -days $DAYS_VALID \
        -extfile ${node}-extfile.conf
    
    # Create combined certificate chain
    cat ${node}.pem vault-ca.pem > ${node}-combined.pem
    
    # Clean up temporary files
    rm -f ${node}-csr.pem ${node}-csr.conf ${node}-extfile.conf
done

# Generate client certificate for CLI/API access
echo ""
echo "4. Generating client certificate..."
openssl genrsa -out vault-client-key.pem 4096

cat > client-csr.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
OU = $OU
CN = vault-client

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = clientAuth
EOF

openssl req -new -key vault-client-key.pem -out vault-client-csr.pem -config client-csr.conf

openssl x509 -req -in vault-client-csr.pem -CA vault-ca.pem -CAkey vault-ca-key.pem \
    -CAcreateserial -out vault-client.pem -days $DAYS_VALID

# Clean up
rm -f vault-client-csr.pem client-csr.conf ca-csr.conf

# Set permissions
find . -name "*-key.pem" -exec chmod 600 {} \;
find . -name "*.pem" ! -name "*-key.pem" -exec chmod 644 {} \;

# Create bundle for HAProxy
echo ""
echo "5. Creating HAProxy bundle..."
cat vault-ca.pem > haproxy-ca-bundle.pem

# Copy to host-certs if it exists (for local access)
if [ -d "/host-certs" ]; then
    echo ""
    echo "Copying certificates to host directory..."
    cp -r /certs/* /host-certs/
fi

# Display summary
echo ""
echo "=== Certificate Generation Complete ==="
echo ""
echo "Generated files in $CERT_DIR:"
echo "  CA Certificate:        vault-ca.pem"
echo "  CA Private Key:        vault-ca-key.pem"
echo ""
echo "  Server Certificates:"
echo "    vault:               vault.pem, vault-key.pem"
echo "    vault-2:             vault-2.pem, vault-2-key.pem"
echo "    vault-3:             vault-3.pem, vault-3-key.pem"
echo ""
echo "  Client Certificate:    vault-client.pem, vault-client-key.pem"
echo "  HAProxy CA Bundle:     haproxy-ca-bundle.pem"
echo ""
echo "To enable TLS in Vault:"
echo "1. Copy certificates to config directory:"
echo "   cp $CERT_DIR/vault*.pem ../config/"
echo ""
echo "2. Update config/vault.hcl:"
echo "   listener \"tcp\" {"
echo "     address = \"0.0.0.0:8200\""
echo "     tls_cert_file = \"/vault/config/vault.pem\""
echo "     tls_key_file = \"/vault/config/vault-key.pem\""
echo "     tls_client_ca_file = \"/vault/config/vault-ca.pem\""
echo "   }"
echo ""
echo "3. Update .env file:"
echo "   VAULT_TLS_DISABLE=0"
echo "   VAULT_CACERT=/vault/config/vault-ca.pem"
echo ""
echo "4. For client access:"
echo "   export VAULT_CACERT=$PWD/$CERT_DIR/vault-ca.pem"
echo "   export VAULT_CLIENT_CERT=$PWD/$CERT_DIR/vault-client.pem"
echo "   export VAULT_CLIENT_KEY=$PWD/$CERT_DIR/vault-client-key.pem"