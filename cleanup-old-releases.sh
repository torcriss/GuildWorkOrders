#!/bin/bash

# Script to keep only the latest GitHub release and delete all others
# This ensures only one version is available on GitHub

echo "Fetching all releases..."

# Get all release tags except the latest one
OLD_RELEASES=$(gh release list --json tagName --jq '.[1:][].tagName')

if [ -z "$OLD_RELEASES" ]; then
    echo "No old releases to clean up. Only the latest release exists."
    exit 0
fi

echo "Found old releases to delete:"
echo "$OLD_RELEASES"

# Delete each old release
while IFS= read -r tag; do
    if [ -n "$tag" ]; then
        echo "Deleting release: $tag"
        gh release delete "$tag" --cleanup-tag --yes
        if [ $? -eq 0 ]; then
            echo "✓ Successfully deleted release: $tag"
        else
            echo "✗ Failed to delete release: $tag"
        fi
    fi
done <<< "$OLD_RELEASES"

echo "Cleanup complete. Only the latest release remains on GitHub."