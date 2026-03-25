#!/usr/bin/env bash
set -e

VERSION="$1"
if [ -z "$VERSION" ]; then
  echo "usage: ./scripts/release.sh <version>"
  echo "example: ./scripts/release.sh 0.2.0"
  exit 1
fi

# Ensure clean working tree
if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree is not clean"
  git status --short
  exit 1
fi

# Ensure gh CLI is available
if ! command -v gh &>/dev/null; then
  echo "error: gh CLI is required (brew install gh)"
  exit 1
fi

echo "==> Building universal binary..."
swift build -c release --arch arm64
swift build -c release --arch x86_64
lipo -create \
  .build/arm64-apple-macosx/release/gazectl \
  .build/x86_64-apple-macosx/release/gazectl \
  -output bin/gazectl-bin
chmod +x bin/gazectl-bin

SIZE=$(ls -lh bin/gazectl-bin | awk '{print $5}')
echo "    binary: bin/gazectl-bin ($SIZE)"

echo "==> Updating version to $VERSION..."
npm version "$VERSION" --no-git-tag-version
sed -i '' "s/static let version = \".*\"/static let version = \"$VERSION\"/" Sources/CLI.swift

echo "==> Committing and tagging..."
git add package.json Sources/CLI.swift
git commit -m "v$VERSION"
git tag "v$VERSION"

echo "==> Pushing to GitHub..."
git push origin main --tags

echo "==> Creating GitHub release..."
gh release create "v$VERSION" bin/gazectl-bin \
  --title "v$VERSION" \
  --generate-notes

echo "==> Publishing to npm..."
npm publish

echo "==> Cleaning up..."
rm bin/gazectl-bin

echo ""
echo "Released v$VERSION"
echo "  npm: https://www.npmjs.com/package/gazectl"
echo "  github: https://github.com/jnsahaj/gazectl/releases/tag/v$VERSION"
