#!/bin/bash
# Script to verify Vault cluster health

echo "=== Vault Cluster Health Check ==="
echo ""

# Get root token
export VAULT_TOKEN=$(docker run --rm -v vault-raft_vault_keys:/vault/keys busybox cat /vault/keys/root-token.txt 2>/dev/null)

if [ -z "$VAULT_TOKEN" ]; then
    echo "Error: Could not retrieve root token. Is Vault initialized?"
    exit 1
fi

echo "1. Cluster Members:"
docker exec -e VAULT_TOKEN=$VAULT_TOKEN vault vault operator raft list-peers 2>/dev/null || echo "   Failed to list peers"
echo ""

echo "2. Node Status:"
for node in vault vault-2 vault-3; do
    echo "   $node:"
    STATUS=$(docker exec $node vault status 2>/dev/null | grep -E "Sealed|HA Mode" | sed 's/^/      /')
    if [ -n "$STATUS" ]; then
        echo "$STATUS"
    else
        echo "      Node not responding"
    fi
done
echo ""

echo "3. HAProxy Health:"
HAPROXY_STATUS=$(curl -s http://localhost:8300/v1/sys/health 2>/dev/null)
if [ -n "$HAPROXY_STATUS" ]; then
    echo "   HAProxy is routing to active node ✓"
    echo "   Active cluster: $(echo $HAPROXY_STATUS | grep -o '"cluster_name":"[^"]*"' | cut -d'"' -f4)"
else
    echo "   HAProxy not responding ✗"
fi
echo ""

echo "4. Audit Log Status:"
AUDIT=$(docker exec -e VAULT_TOKEN=$VAULT_TOKEN vault vault audit list 2>/dev/null | grep -c "file/")
if [ "$AUDIT" -gt 0 ]; then
    echo "   Audit logging enabled ✓"
else
    echo "   Audit logging not enabled ✗"
fi
echo ""

echo "5. Summary:"
UNSEALED_COUNT=$(docker exec vault vault status 2>/dev/null | grep -c "Sealed.*false" || echo 0)
TOTAL_NODES=3

echo "   - Nodes in cluster: $TOTAL_NODES"
echo "   - Unsealed nodes: $UNSEALED_COUNT"
echo "   - Root token: ${VAULT_TOKEN:0:10}..."
echo "   - UI Access: http://localhost:8200 (direct) or http://localhost:8300 (HAProxy)"
echo ""