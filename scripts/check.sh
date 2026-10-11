#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swift build
swiftc -D CORE_STANDALONE_CHECKS -parse-as-library Sources/MediaInfoCore/*.swift Tests/MediaInfoCoreTests/StandaloneChecks.swift -o .build/core-checks
.build/core-checks
scripts/make-fixtures.sh
swiftc -parse-as-library Sources/MediaInfoCore/*.swift scripts/camera-metadata-check.swift -o .build/camera-metadata-check
.build/camera-metadata-check
swiftc -parse-as-library Sources/MediaInfoQuickLook/PlaybackModel.swift scripts/playback-check.swift -o .build/playback-check
.build/playback-check
swiftc -parse-as-library Sources/MediaInfoCore/*.swift scripts/integration-check.swift -o .build/integration-check
.build/integration-check
swiftc -parse-as-library Sources/MediaInfoCore/*.swift Sources/MediaInfoQuickLook/AppModel.swift Sources/MediaInfoQuickLook/FinderSelection.swift scripts/app-model-check.swift -o .build/app-model-check
.build/app-model-check
swiftc -parse-as-library Sources/MediaInfoQuickLook/GlobalHotKey.swift scripts/hotkey-conflict-check.swift -o .build/hotkey-conflict-check
.build/hotkey-conflict-check
plutil -lint Resources/Info.plist Resources/MediaInfoQuickLook.entitlements MediaInfoQuickLook.xcodeproj/project.pbxproj
