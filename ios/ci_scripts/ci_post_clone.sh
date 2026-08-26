#!/bin/sh
# ci_post_clone.sh — Xcode Cloud Custom Build Script (läuft nach dem Clone).
#
# Xcode Cloud erkennt den Ordner `ci_scripts/` neben dem .xcodeproj und führt
# dieses Script automatisch aus. Es schreibt die gitignorte
# `Config/Official.xcconfig`, die `Config/Shared.xcconfig` per
# `#include?` optional einbindet — damit ist JEDER Xcode-Cloud-Build ein
# offizieller Build (Compile-Condition OFFICIAL_BUILD gesetzt,
# siehe docs/BRANDING.md "Official vs. community builds").
#
# Lokal ausführbar (ohne CI-Env greift der relative Fallback-Pfad), um den
# offiziellen Build zu simulieren; danach Official.xcconfig wieder löschen.
set -e

# Xcode Cloud setzt CI_PRIMARY_REPOSITORY_PATH auf die Repo-Wurzel;
# Fallback: relativ zu diesem Script (ios/ci_scripts/ -> Repo-Wurzel).
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/../.." && pwd)}"
XCCONFIG="$REPO_ROOT/ios/Config/Official.xcconfig"

mkdir -p "$(dirname "$XCCONFIG")"
cat > "$XCCONFIG" <<'EOF'
SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) OFFICIAL_BUILD
EOF

echo "ci_post_clone: wrote $XCCONFIG (OFFICIAL_BUILD enabled)"
