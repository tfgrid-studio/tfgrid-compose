#!/usr/bin/env bash
# Bump version script
# Usage: ./scripts/bump-version.sh 0.11.0

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <new-version>"
    echo "Example: $0 0.11.0"
    exit 1
fi

NEW_VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Update VERSION file
echo "$NEW_VERSION" > "$ROOT_DIR/VERSION"
echo "✅ Updated VERSION file to $NEW_VERSION"

# Update README badges
sed -i "s/version-[0-9.]*-blue/version-$NEW_VERSION-blue/g" "$ROOT_DIR/README.md"
sed -i "s/\*\*Version:\*\* [0-9.]*/\*\*Version:\*\* $NEW_VERSION/g" "$ROOT_DIR/README.md"
sed -i "s/v[0-9.]* - Production Ready/v$NEW_VERSION - Production Ready/g" "$ROOT_DIR/README.md"
echo "✅ Updated README.md badges to $NEW_VERSION"

echo ""
echo "🎉 Version bumped to $NEW_VERSION"
echo ""
echo "Next steps:"
echo "  1. Update CHANGELOG.md with changes for v$NEW_VERSION"
echo "  2. git add VERSION README.md CHANGELOG.md"
echo "  3. git commit -m \"chore: Bump version to $NEW_VERSION\""
echo "  4. git tag v$NEW_VERSION"
echo "  5. git push && git push --tags"
