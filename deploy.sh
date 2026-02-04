#!/bin/bash
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

echo "=== Deploying Tibia 7.72 Server to $SERVER ==="

echo "Cleaning up old deployment..."
ssh $SERVER "rm -rf $DEST"

echo "Creating remote directory structure..."
ssh $SERVER "mkdir -p $DEST/{querymanager/data/sqlite/patches,login,game}"

echo "Copying game data tarball..."
scp tibia-game.tarball.tar.gz $SERVER:$DEST/

echo "Extracting game data on server..."
ssh $SERVER "cd $DEST/game && tar -xzf $DEST/tibia-game.tarball.tar.gz --strip-components=1"

echo "Copying binaries (overwriting old ones from tarball)..."
scp binaries/querymanager $SERVER:$DEST/querymanager/
scp binaries/login $SERVER:$DEST/login/
scp binaries/game $SERVER:$DEST/game/bin/

echo "Copying configs..."
scp docker/config/querymanager.cfg $SERVER:$DEST/querymanager/data/config.cfg
scp docker/config/login.cfg $SERVER:$DEST/login/config.cfg
scp docker/config/.tibia $SERVER:$DEST/game/.tibia

echo "Copying RSA key..."
scp game/tibia.pem $SERVER:$DEST/login/tibia.pem
scp game/tibia.pem $SERVER:$DEST/game/tibia.pem

echo "Copying SQLite schema files..."
scp tibia-querymanager/sqlite/*.sql $SERVER:$DEST/querymanager/data/sqlite/
scp tibia-querymanager/sqlite/patches/*.sql $SERVER:$DEST/querymanager/data/sqlite/patches/

echo "Creating user data directories..."
ssh $SERVER "for i in \$(seq -w 0 99); do mkdir -p $DEST/game/usr/\$i; done"

echo "Setting permissions..."
ssh $SERVER "chmod +x $DEST/querymanager/querymanager $DEST/login/login $DEST/game/bin/game"

echo "Cleaning up stale files..."
ssh $SERVER "rm -f $DEST/game/save/game.pid $DEST/tibia-game.tarball.tar.gz"

echo "=== Deployment complete! ==="
echo ""
echo "Directory structure:"
echo "  $DEST/querymanager/     - Query Manager (run from here)"
echo "  $DEST/login/            - Login Server (run from here)"  
echo "  $DEST/game/             - Game Server (run from here)"
echo ""
echo "To start (in order):"
echo "  cd $DEST/querymanager && ./querymanager"
echo "  cd $DEST/login && ./login"
echo "  cd $DEST/game && ./bin/game"
