#!/bin/bash
# Sync docs/ folder to public website repository
# Usage: ./sync-website.sh

echo "🔄 Syncing website files to public repository..."
git subtree push --prefix docs public-web main
echo "✅ Website synced successfully to https://github.com/andi-coding/spotwatt.github.io"
