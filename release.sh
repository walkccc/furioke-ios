#!/usr/bin/env bash

set -e

# ============================================
# Zestimer Release Script
# ============================================

# Usage:
#   ./release.sh v1.2.3
#
# Or run without args:
#   ./release.sh
#
# Requirements:
# - git
# - GitHub CLI (gh)
# - Authenticated gh login
# ============================================

# Get version
if [ -z "$1" ]; then
  read -p "Enter version (e.g. v1.2.3): " VERSION
else
  VERSION=$1
fi

# Validate version
if [ -z "$VERSION" ]; then
  echo "❌ Version is required"
  exit 1
fi

echo ""
echo "🚀 Releasing $VERSION..."
echo ""

# Ensure clean working tree
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ You have uncommitted changes."
  echo "Commit or stash them first."
  exit 1
fi

# Ensure on main branch
CURRENT_BRANCH=$(git branch --show-current)

if [ "$CURRENT_BRANCH" != "main" ]; then
  echo "❌ You must be on main branch"
  echo "Current branch: $CURRENT_BRANCH"
  exit 1
fi

# Pull latest changes
echo "⬇️ Pulling latest changes..."
git pull origin main

# ============================================
# Recreate tag if already exists
# ============================================

# Delete local tag if exists
if git rev-parse "$VERSION" >/dev/null 2>&1; then
  echo "⚠️ Local tag $VERSION exists. Recreating..."
  git tag -d "$VERSION"
fi

# Delete remote tag if exists
if git ls-remote --tags origin | grep -q "refs/tags/$VERSION$"; then
  echo "⚠️ Remote tag $VERSION exists. Deleting..."
  git push origin ":refs/tags/$VERSION"
fi

# Create annotated tag
echo "🏷️ Creating tag..."
git tag -a "$VERSION" -m "App Store release $VERSION"

# Push main branch
echo "⬆️ Pushing main..."
git push origin main

# Push tag
echo "⬆️ Pushing tag..."
git push origin "$VERSION"

# ============================================
# Release notes
# ============================================

echo ""
echo "📝 Enter release notes"
echo "(Press Ctrl+D when done)"
echo ""

NOTES=$(cat)

# Default notes if empty
if [ -z "$NOTES" ]; then
  NOTES="- Bug fixes
- Performance improvements"
fi

# ============================================
# GitHub Release
# ============================================

echo ""
echo "📦 Creating GitHub release..."

# Delete existing GitHub release if exists
if gh release view "$VERSION" >/dev/null 2>&1; then
  echo "⚠️ GitHub release exists. Deleting..."
  gh release delete "$VERSION" --yes
fi

# Create release
gh release create "$VERSION" \
  --title "Zestimer $VERSION" \
  --notes "$NOTES"

echo ""
echo "✅ Done!"
echo "🎉 Released $VERSION successfully"
