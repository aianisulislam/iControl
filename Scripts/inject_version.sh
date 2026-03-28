#!/bin/bash

# =============================================================
# inject_version.sh
# Injects the app version number into index.html at build time.
# Replaces every occurrence of APP_VERSION in the built copy
# of index.html — source file is never modified.
# =============================================================

# Read the marketing version (e.g. "1.2.0") from the built Info.plist
# $TARGET_BUILD_DIR/$INFOPLIST_PATH is the path Xcode sets automatically
# PlistBuddy is a macOS built-in tool for reading .plist files
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$TARGET_BUILD_DIR/$INFOPLIST_PATH")

# Read the build number (e.g. "12") from the same Info.plist
# This is the internal counter, incremented with each build
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$TARGET_BUILD_DIR/$INFOPLIST_PATH")

# Capture the current date and time for the build log
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# Bail out early if version couldn't be read — avoids replacing
# APP_VERSION with an empty string in the HTML
if [ -z "$VERSION" ]; then
    echo "iControl: ERROR — could not read version from Info.plist, aborting injection"
    exit 1
fi

# The built copy of index.html lives here — this is NOT your source file
# Xcode copies resources to this location during the build phase
# sed -i '' means "edit in place" (the '' is required on macOS)
# s/APP_VERSION/$VERSION/g means "replace ALL occurrences of APP_VERSION with $VERSION"
sed -i '' "s/APP_VERSION/$VERSION/g" \
    "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources/index.html"

# Log the result to Xcode's build output so you can verify it worked
echo "iControl: injected version $VERSION (build $BUILD) at $TIMESTAMP into index.html"