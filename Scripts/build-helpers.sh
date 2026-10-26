#!/bin/zsh
set -euo pipefail

# The signed app bundles its agent and CLI; no installed binaries are downloaded.
repository_root=${SRCROOT:-${0:A:h:h}}
configuration=${CONFIGURATION:-Debug}
scratch="$repository_root/.build/Helpers-$configuration"
xcrun swift build --package-path "$repository_root/Packages/LedgeKit" --scratch-path "$scratch" -c ${configuration:l} --product LedgeAgent
xcrun swift build --package-path "$repository_root/Packages/LedgeKit" --scratch-path "$scratch" -c ${configuration:l} --product ledge
binary_path=$(xcrun swift build --package-path "$repository_root/Packages/LedgeKit" --scratch-path "$scratch" -c ${configuration:l} --show-bin-path)
destination="${TARGET_BUILD_DIR:?}/${CONTENTS_FOLDER_PATH:?}"
/bin/mkdir -p "$destination/MacOS" "$destination/Library/LaunchAgents"
/usr/bin/ditto "$binary_path/LedgeAgent" "$destination/MacOS/LedgeAgent"
# Default macOS volumes are case-insensitive: `ledge` would overwrite `Ledge`.
/usr/bin/ditto "$binary_path/ledge" "$destination/MacOS/ledge-cli"
/usr/bin/ditto "$repository_root/LedgeAgent/Resources/com.ledge.agent.plist" "$destination/Library/LaunchAgents/com.ledge.agent.plist"
/usr/bin/ditto "$repository_root/SDKs/python/ledge_sdk" "$destination/Resources/PluginSDK/python/ledge_sdk"
if [[ ${CODE_SIGNING_ALLOWED:-NO} == YES && -n ${EXPANDED_CODE_SIGN_IDENTITY:-} ]]; then
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --identifier com.ledge.agent --options runtime --timestamp "$destination/MacOS/LedgeAgent"
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --identifier com.ledge.cli --options runtime --timestamp "$destination/MacOS/ledge-cli"
fi
