#!/bin/bash
# config.sh - Server configuration for deployment scripts
#
# USAGE:
#   1. Copy this file to config.sh:
#      cp config.example.sh config.sh
#
#   2. Edit config.sh with your actual server details
#
#   3. Never commit config.sh to version control!
#

# Server connection (SSH user@host or SSH config alias)
# Examples:
#   SERVER="root@192.168.1.100"
#   SERVER="deploy@myserver.example.com"
#   SERVER="myserver"  # if using ~/.ssh/config alias
SERVER="root@your-server-ip"

# Remote installation directory (absolute path on the server)
DEST="/opt/tibia"

# Systemd service name for the game server
SERVICE_NAME="tibia-game"

# Restart wait time in seconds (how long to wait after restart signal)
RESTART_WAIT=15
