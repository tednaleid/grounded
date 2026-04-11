# grounded — starter Justfile (will be enhanced by /just-bootstrap)
# ------------------------------------------------------------------
# Every dev-facing command goes through `just`. Never call xcodebuild
# or swift test directly.

set shell := ["bash", "-cu"]

project := "grounded.xcodeproj"
scheme  := "grounded"
symroot := "/tmp/grounded-build"
destination := "platform=macOS"

# default: show recipes
default:
    @just --list

# regenerate the Xcode project from project.yml
generate:
    xcodegen generate

# build the app in Debug
build: generate
    xcodebuild build \
        -project {{project}} \
        -scheme {{scheme}} \
        -destination '{{destination}}' \
        -configuration Debug \
        SYMROOT={{symroot}}

# run all tests (optionally filter by test name: `just test ChargerState`)
test filter="": generate
    #!/usr/bin/env bash
    set -euo pipefail
    args=(
        -project "{{project}}"
        -scheme grounded
        -destination '{{destination}}'
        SYMROOT="{{symroot}}"
    )
    if [[ -n "{{filter}}" ]]; then
        args+=(-only-testing:"{{filter}}")
    fi
    xcodebuild test "${args[@]}"

# run only the core tests (pure Foundation, no framework deps)
test-core filter="": generate
    #!/usr/bin/env bash
    set -euo pipefail
    target="GroundedCoreTests"
    if [[ -n "{{filter}}" ]]; then
        target="${target}/{{filter}}"
    fi
    xcodebuild test \
        -project "{{project}}" \
        -scheme GroundedCoreTests \
        -destination '{{destination}}' \
        -only-testing:"${target}" \
        SYMROOT="{{symroot}}"

# run only the adapter tests
test-adapters filter="": generate
    #!/usr/bin/env bash
    set -euo pipefail
    target="GroundedAdapterTests"
    if [[ -n "{{filter}}" ]]; then
        target="${target}/{{filter}}"
    fi
    xcodebuild test \
        -project "{{project}}" \
        -scheme GroundedAdapterTests \
        -destination '{{destination}}' \
        -only-testing:"${target}" \
        SYMROOT="{{symroot}}"

# run only the integration tests
test-integration filter="": generate
    #!/usr/bin/env bash
    set -euo pipefail
    target="GroundedIntegrationTests"
    if [[ -n "{{filter}}" ]]; then
        target="${target}/{{filter}}"
    fi
    xcodebuild test \
        -project "{{project}}" \
        -scheme GroundedIntegrationTests \
        -destination '{{destination}}' \
        -only-testing:"${target}" \
        SYMROOT="{{symroot}}"

# enforce Core purity: no UI/system framework imports under Sources/Core
check-core-purity:
    #!/usr/bin/env bash
    set -euo pipefail
    forbidden='^import[[:space:]]+(AppKit|UIKit|WebKit|Security|UserNotifications|URLSession)'
    if find Sources/Core -name '*.swift' -print0 2>/dev/null \
        | xargs -0 -I{} grep -En "$forbidden" {} 2>&1 \
        | grep -q .; then
        echo "ERROR: forbidden imports found in Sources/Core/" >&2
        exit 1
    fi
    echo "Sources/Core purity: OK"

# everything CI runs; becomes the green-gate
check: check-core-purity test build
    @echo "just check: OK"

# clean all build artifacts
clean:
    rm -rf {{symroot}} grounded.xcodeproj
