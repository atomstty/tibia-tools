#!/bin/bash
# deploy-binary.sh - Deploy game binary and/or .tibia config to bonusera server
#
# Usage:
#   ./deploy-binary.sh                # Deploy what exists in deployment/ + fast restart
#   ./deploy-binary.sh --no-restart   # Deploy without restart
#   ./deploy-binary.sh --dry-run      # Preview what would be deployed

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

# Derived paths (from config)
REMOTE_BINARY="$DEST/game/bin/game"
REMOTE_CONFIG="$DEST/game/.tibia"
LOCAL_DIR="deployment"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
DRY_RUN=false
NO_RESTART=false

for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        --no-restart)
            NO_RESTART=true
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--no-restart]"
            echo ""
            echo "Deploy game binary and/or .tibia config from deployment/ directory"
            echo ""
            echo "Options:"
            echo "  --dry-run      Preview what would be deployed"
            echo "  --no-restart   Deploy without restarting the server"
            echo "  -h, --help     Show this help message"
            echo ""
            echo "Files to deploy (place in deployment/ directory):"
            echo "  game    - game binary"
            echo "  .tibia  - game configuration"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $arg${NC}"
            exit 1
            ;;
    esac
done

# Check what files exist
HAS_BINARY=false
HAS_CONFIG=false

if [[ -f "$LOCAL_DIR/game" ]]; then
    HAS_BINARY=true
fi

if [[ -f "$LOCAL_DIR/.tibia" ]]; then
    HAS_CONFIG=true
fi

# Exit if nothing to deploy
if [[ "$HAS_BINARY" == false && "$HAS_CONFIG" == false ]]; then
    echo -e "${RED}No files found in $LOCAL_DIR/${NC}"
    echo "Place files to deploy:"
    echo "  $LOCAL_DIR/game    - game binary"
    echo "  $LOCAL_DIR/.tibia  - game configuration"
    exit 1
fi

# Show what will be deployed
echo -e "${BLUE}=== Deploy Binary/Config ===${NC}"
echo ""

if [[ "$HAS_BINARY" == true ]]; then
    LOCAL_SIZE=$(stat -c%s "$LOCAL_DIR/game" 2>/dev/null || stat -f%z "$LOCAL_DIR/game")
    echo -e "${GREEN}[BINARY]${NC} $LOCAL_DIR/game ($(numfmt --to=iec $LOCAL_SIZE 2>/dev/null || echo "$LOCAL_SIZE bytes"))"
    echo "         -> $SERVER:$REMOTE_BINARY"
fi

if [[ "$HAS_CONFIG" == true ]]; then
    echo -e "${GREEN}[CONFIG]${NC} $LOCAL_DIR/.tibia"
    echo "         -> $SERVER:$REMOTE_CONFIG"
fi

echo ""

if [[ "$NO_RESTART" == true ]]; then
    echo -e "${YELLOW}[RESTART]${NC} Skipped (--no-restart)"
else
    echo -e "${GREEN}[RESTART]${NC} SIGQUIT (fast restart) + wait ${RESTART_WAIT}s"
fi

echo ""

# Dry run - exit here
if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}=== DRY RUN - No changes made ===${NC}"
    exit 0
fi

# Confirm
read -p "Proceed with deployment? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Deploy binary
if [[ "$HAS_BINARY" == true ]]; then
    echo ""
    echo -e "${BLUE}Deploying binary...${NC}"
    
    # Backup
    echo "  Creating backup: ${REMOTE_BINARY}.backup-${TIMESTAMP}"
    ssh "$SERVER" "cp $REMOTE_BINARY ${REMOTE_BINARY}.backup-${TIMESTAMP}"
    
    # Upload as .new
    echo "  Uploading: $LOCAL_DIR/game -> ${REMOTE_BINARY}.new"
    scp "$LOCAL_DIR/game" "$SERVER:${REMOTE_BINARY}.new"
    
    # Atomic replace + chmod
    echo "  Replacing binary (atomic mv)"
    ssh "$SERVER" "mv ${REMOTE_BINARY}.new $REMOTE_BINARY && chmod +x $REMOTE_BINARY"
    
    echo -e "${GREEN}  Binary deployed!${NC}"
fi

# Deploy config
if [[ "$HAS_CONFIG" == true ]]; then
    echo ""
    echo -e "${BLUE}Deploying config...${NC}"
    
    # Backup
    echo "  Creating backup: ${REMOTE_CONFIG}.backup-${TIMESTAMP}"
    ssh "$SERVER" "cp $REMOTE_CONFIG ${REMOTE_CONFIG}.backup-${TIMESTAMP}"
    
    # Upload as .new
    echo "  Uploading: $LOCAL_DIR/.tibia -> ${REMOTE_CONFIG}.new"
    scp "$LOCAL_DIR/.tibia" "$SERVER:${REMOTE_CONFIG}.new"
    
    # Atomic replace
    echo "  Replacing config (atomic mv)"
    ssh "$SERVER" "mv ${REMOTE_CONFIG}.new $REMOTE_CONFIG"
    
    echo -e "${GREEN}  Config deployed!${NC}"
fi

# Restart
if [[ "$NO_RESTART" == false ]]; then
    echo ""
    echo -e "${BLUE}Restarting server (SIGQUIT)...${NC}"
    ssh "$SERVER" "systemctl kill --signal=SIGQUIT $SERVICE_NAME"
    
    echo "  Waiting ${RESTART_WAIT}s for auto-restart..."
    sleep "$RESTART_WAIT"
    
    echo ""
    echo -e "${BLUE}Server status:${NC}"
    ssh "$SERVER" "systemctl status $SERVICE_NAME --no-pager" || true
fi

echo ""
echo -e "${GREEN}=== Deployment complete ===${NC}"
