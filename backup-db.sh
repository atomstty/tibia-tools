#!/bin/bash
#
# backup-db.sh - Backup the Tibia SQLite database from remote server
#
# Usage:
#   ./backup-db.sh                    # Backup to backups/ with timestamp
#   ./backup-db.sh -o mybackup.db     # Backup to specific file
#   ./backup-db.sh --list             # List existing backups
#   ./backup-db.sh --help             # Show help
#
set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "Error: config.sh not found!"
    echo "Copy config.example.sh to config.sh and edit with your server details."
    exit 1
fi

# Derived paths
REMOTE_DB="$DEST/querymanager/data/tibia.db"
BACKUP_DIR="$SCRIPT_DIR/backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default output file
OUTPUT_FILE=""
LIST_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --list|-l)
            LIST_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Backup the Tibia SQLite database from remote server"
            echo ""
            echo "Options:"
            echo "  -o, --output FILE    Save backup to specific file"
            echo "  -l, --list           List existing backups"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Default backup location: $BACKUP_DIR/"
            echo "Remote database: \$DEST/querymanager/data/tibia.db"
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

# List mode
if $LIST_MODE; then
    echo ""
    echo "=========================================="
    echo " Existing Backups"
    echo "=========================================="
    echo ""
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_info "No backups directory found"
        exit 0
    fi
    
    backups=($(ls -1t "$BACKUP_DIR"/*.db 2>/dev/null || true))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log_info "No backups found in $BACKUP_DIR/"
        exit 0
    fi
    
    echo "Found ${#backups[@]} backup(s):"
    echo ""
    
    for backup in "${backups[@]}"; do
        size=$(du -h "$backup" | cut -f1)
        name=$(basename "$backup")
        mtime=$(stat -c "%y" "$backup" 2>/dev/null | cut -d'.' -f1 || stat -f "%Sm" "$backup" 2>/dev/null)
        echo "  $name  ($size)  $mtime"
    done
    
    echo ""
    exit 0
fi

# Create backup directory if needed
mkdir -p "$BACKUP_DIR"

# Generate output filename if not specified
if [[ -z "$OUTPUT_FILE" ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    OUTPUT_FILE="$BACKUP_DIR/tibia_${TIMESTAMP}.db"
fi

echo ""
echo "=========================================="
echo " Tibia Database Backup"
echo "=========================================="
echo ""

log_info "Server: $SERVER"
log_info "Remote DB: $REMOTE_DB"
log_info "Local destination: $OUTPUT_FILE"
echo ""

# Check if remote database exists
log_info "Checking remote database..."
if ! ssh "$SERVER" "test -f '$REMOTE_DB'"; then
    log_error "Database not found at $REMOTE_DB"
    exit 1
fi
log_success "Database exists"

# Get remote database size
REMOTE_SIZE=$(ssh "$SERVER" "du -h '$REMOTE_DB' | cut -f1")
log_info "Remote database size: $REMOTE_SIZE"

# Perform backup using SQLite's backup mechanism for consistency
log_info "Creating backup..."

# Use sqlite3 .backup command on remote for a consistent backup
ssh "$SERVER" "sqlite3 '$REMOTE_DB' '.backup /tmp/tibia_backup.db'" || {
    log_warning "sqlite3 not available, falling back to direct copy"
    ssh "$SERVER" "cp '$REMOTE_DB' /tmp/tibia_backup.db"
}

# Copy to local
scp "$SERVER:/tmp/tibia_backup.db" "$OUTPUT_FILE"

# Cleanup remote temp file
ssh "$SERVER" "rm -f /tmp/tibia_backup.db"

# Verify backup
if [[ -f "$OUTPUT_FILE" ]]; then
    LOCAL_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
    log_success "Backup created: $OUTPUT_FILE ($LOCAL_SIZE)"
    
    # Basic integrity check
    if command -v sqlite3 &> /dev/null; then
        log_info "Verifying backup integrity..."
        if sqlite3 "$OUTPUT_FILE" "PRAGMA integrity_check;" | grep -q "ok"; then
            log_success "Integrity check passed"
        else
            log_warning "Integrity check returned warnings"
        fi
        
        # Show some stats
        ACCOUNTS=$(sqlite3 "$OUTPUT_FILE" "SELECT COUNT(*) FROM Accounts;" 2>/dev/null || echo "?")
        CHARACTERS=$(sqlite3 "$OUTPUT_FILE" "SELECT COUNT(*) FROM Characters;" 2>/dev/null || echo "?")
        log_info "Accounts: $ACCOUNTS, Characters: $CHARACTERS"
    fi
else
    log_error "Backup failed!"
    exit 1
fi

echo ""
echo "=========================================="
echo -e " ${GREEN}BACKUP COMPLETE${NC}"
echo "=========================================="
echo ""
