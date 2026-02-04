#!/bin/bash
# sanity-check.sh - Test SSH connectivity and config.sh (read-only)
#
# Usage:
#   ./sanity-check.sh
#
# Quick way to verify your config.sh is correct and SSH works.

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "Error: config.sh not found!"
    echo "Copy config.example.sh to config.sh and edit with your server details."
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Sanity Check ===${NC}"
echo ""
echo "Config:"
echo "  SERVER:       $SERVER"
echo "  DEST:         $DEST"
echo "  SERVICE_NAME: $SERVICE_NAME"
echo ""

# SSH test
echo -n "Testing SSH connection... "
if timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 "$SERVER" "true" 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    echo ""
    echo "Could not connect. Check:"
    echo "  - SERVER setting in config.sh"
    echo "  - SSH keys are set up"
    echo "  - Server is reachable"
    exit 1
fi

# Get basic info
HOSTNAME=$(ssh "$SERVER" "hostname")
UPTIME=$(ssh "$SERVER" "uptime -p" 2>/dev/null || ssh "$SERVER" "uptime")

echo ""
echo "Remote server:"
echo "  Hostname: $HOSTNAME"
echo "  Uptime:   $UPTIME"

# Check if DEST exists
echo ""
echo -n "Checking DEST path exists... "
if ssh "$SERVER" "test -d '$DEST'" 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}NOT FOUND${NC}"
    echo "  $DEST does not exist on remote server"
fi

echo ""
echo -e "${GREEN}Sanity check passed!${NC}"
