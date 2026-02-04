#!/bin/bash
#
# deploy-patches.sh - Deploy incremental patches to Tibia 7.72 server
#
# Usage:
#   ./deploy-patches.sh              # Deploy patches + restart server
#   ./deploy-patches.sh --no-restart # Deploy patches only
#   ./deploy-patches.sh --dry-run    # Preview what would be deployed
#   ./deploy-patches.sh --help       # Show help
#
set -e

# Script directory (where patches/ folder is)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "Error: config.sh not found!"
    echo "Copy config.example.sh to config.sh and edit with your server details."
    exit 1
fi

# Derived paths (from config)
REMOTE_GAME_DIR="$DEST/game"
REMOTE_SAVE_DIR="$REMOTE_GAME_DIR/save"
REMOTE_DAT_DIR="$REMOTE_GAME_DIR/dat"
REMOTE_NPC_DIR="$REMOTE_GAME_DIR/npc"
REMOTE_PID_FILE="$REMOTE_SAVE_DIR/game.pid"
PATCHES_DIR="$SCRIPT_DIR/patches"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
DRY_RUN=false
NO_RESTART=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-restart)
            NO_RESTART=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Deploy incremental patches to Tibia 7.72 server"
            echo ""
            echo "Options:"
            echo "  --dry-run      Preview what would be deployed (no changes)"
            echo "  --no-restart   Deploy patches without restarting server"
            echo "  --help, -h     Show this help message"
            echo ""
            echo "Patches directory: $PATCHES_DIR"
            echo "  map/*.pat      Map patches (copied to save/ directory)"
            echo "  dat/*.rules    Dat file rules (appended with duplicate check)"
            echo "  npc/*.npc      NPC files (copied to npc/ directory)"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_dry() {
    echo -e "${YELLOW}[DRY-RUN]${NC} $1"
}

# Check if patches directory exists
if [[ ! -d "$PATCHES_DIR" ]]; then
    log_error "Patches directory not found: $PATCHES_DIR"
    exit 1
fi

echo ""
echo "=========================================="
echo " Tibia 7.72 Patch Deployment"
echo "=========================================="
echo ""

if $DRY_RUN; then
    log_warning "DRY-RUN MODE - No changes will be made"
    echo ""
fi

# Count patches
MAP_PATCHES=($(find "$PATCHES_DIR/map" -name "*.pat" 2>/dev/null || true))
DAT_RULES=($(find "$PATCHES_DIR/dat" -name "*.rules" 2>/dev/null || true))
NPC_FILES=($(find "$PATCHES_DIR/npc" -name "*.npc" 2>/dev/null || true))

log_info "Found ${#MAP_PATCHES[@]} map patch(es)"
log_info "Found ${#DAT_RULES[@]} dat rule file(s)"
log_info "Found ${#NPC_FILES[@]} NPC file(s)"
echo ""

# Deploy map patches
if [[ ${#MAP_PATCHES[@]} -gt 0 ]]; then
    log_info "Deploying map patches to $SERVER:$REMOTE_SAVE_DIR/"
    
    for patch in "${MAP_PATCHES[@]}"; do
        patch_name=$(basename "$patch")
        
        if $DRY_RUN; then
            log_dry "Would copy: $patch_name -> $REMOTE_SAVE_DIR/"
        else
            scp -q "$patch" "$SERVER:$REMOTE_SAVE_DIR/"
            log_success "Copied: $patch_name"
        fi
    done
    echo ""
else
    log_info "No map patches to deploy"
    echo ""
fi

# Deploy dat rules
if [[ ${#DAT_RULES[@]} -gt 0 ]]; then
    log_info "Deploying dat rules..."
    
    for rules_file in "${DAT_RULES[@]}"; do
        rules_name=$(basename "$rules_file")
        # Convert .rules to .dat (e.g., moveuse.rules -> moveuse.dat)
        dat_name="${rules_name%.rules}.dat"
        remote_dat="$REMOTE_DAT_DIR/$dat_name"
        
        log_info "Processing: $rules_name -> $dat_name"
        
        # Read rules from file (skip comments and empty lines)
        while IFS= read -r rule || [[ -n "$rule" ]]; do
            # Skip empty lines and comments
            [[ -z "$rule" || "$rule" =~ ^[[:space:]]*# ]] && continue
            
            # Extract a unique identifier from the rule (the comment at the end)
            # e.g., "Demona Entrance" from the rule
            rule_id=$(echo "$rule" | grep -oP '"\K[^"]+(?="[^"]*$)' || echo "$rule" | head -c 50)
            
            if $DRY_RUN; then
                log_dry "Would append rule: \"$rule_id\""
            else
                # Check if rule already exists (by searching for the identifier)
                if ssh "$SERVER" "grep -qF '$rule_id' '$remote_dat' 2>/dev/null"; then
                    log_warning "Rule already exists, skipping: \"$rule_id\""
                else
                    # Append the rule
                    ssh "$SERVER" "echo '$rule' >> '$remote_dat'"
                    log_success "Appended rule: \"$rule_id\""
                fi
            fi
        done < "$rules_file"
    done
    echo ""
else
    log_info "No dat rules to deploy"
    echo ""
fi

# Deploy NPC files
if [[ ${#NPC_FILES[@]} -gt 0 ]]; then
    log_info "Deploying NPC files to $SERVER:$REMOTE_NPC_DIR/"
    
    for npc_file in "${NPC_FILES[@]}"; do
        npc_name=$(basename "$npc_file")
        
        if $DRY_RUN; then
            log_dry "Would copy: $npc_name -> $REMOTE_NPC_DIR/"
        else
            scp -q "$npc_file" "$SERVER:$REMOTE_NPC_DIR/"
            log_success "Copied: $npc_name"
        fi
    done
    echo ""
else
    log_info "No NPC files to deploy"
    echo ""
fi

# Restart server
if $NO_RESTART; then
    log_info "Skipping server restart (--no-restart)"
elif $DRY_RUN; then
    log_dry "Would restart server via: ssh $SERVER 'kill -3 \$(cat $REMOTE_PID_FILE)'"
else
    log_info "Restarting server..."
    
    # Check if PID file exists
    if ssh "$SERVER" "test -f '$REMOTE_PID_FILE'"; then
        ssh "$SERVER" "kill -3 \$(cat '$REMOTE_PID_FILE')"
        log_success "Restart signal sent (SIGQUIT)"
    else
        log_warning "PID file not found at $REMOTE_PID_FILE"
        log_warning "Server may not be running. Start it manually."
    fi
fi

echo ""
echo "=========================================="
if $DRY_RUN; then
    echo -e " ${YELLOW}DRY-RUN COMPLETE${NC}"
else
    echo -e " ${GREEN}DEPLOYMENT COMPLETE${NC}"
fi
echo "=========================================="
echo ""
