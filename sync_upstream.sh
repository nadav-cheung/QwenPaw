#!/bin/bash
# Sync fork with upstream QwenPaw repository

set -e

cd /Users/nadav/IdeaProjects/QwenPaw

# Fetch latest from upstream
echo "Fetching from upstream..."
git fetch upstream

# Checkout main branch
git checkout main

# Rebase main with upstream/main
echo "Rebasing with upstream/main..."
git rebase upstream/main

# Push to origin (your fork)
echo "Pushing to origin..."
git push origin main

echo "Sync completed successfully!"
