#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# macOS 26 SDK also supports machines with CLT but without the SwiftUI macro plugin.
sdk_path="${HABAR_TEST_SDK:-$(xcrun --show-sdk-path)}"
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    sdk_path="${HABAR_TEST_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
fi
output_dir="$(mktemp -d /tmp/HABarTests.XXXXXX)"
trap 'rm -rf "$output_dir"' EXIT
xcrun swiftc -sdk "$sdk_path" -O -parse-as-library -swift-version 5 \
    -default-isolation MainActor -module-name HABarStoreTests \
    HABar/ViewModels/HomeAssistantStore.swift HABar/Models/HomeAssistantModels.swift \
    HABar/Services/*.swift Tests/FixtureURLProtocol.swift Tests/HomeAssistantStoreTests.swift \
    -o "$output_dir/HABarStoreTests"
"$output_dir/HABarStoreTests"
xcrun swiftc -sdk "$sdk_path" -O -parse-as-library -swift-version 5 \
    -default-isolation MainActor -module-name HABarWindowTests \
    HABar/Views/*.swift HABar/ViewModels/HomeAssistantStore.swift \
    HABar/Models/HomeAssistantModels.swift HABar/Services/*.swift \
    Tests/FixtureURLProtocol.swift Tests/WindowLifecycleTests.swift \
    -o "$output_dir/HABarWindowTests"
"$output_dir/HABarWindowTests"
