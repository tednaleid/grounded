# grounded — Justfile
# -------------------
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

# regenerate the AppIcon PNGs from bolt.car.circle via scripts/generate-icon.swift
icon:
    swift scripts/generate-icon.swift

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

inspect_base := "http://localhost:9877"

# hit GET /state and pretty-print the response
inspect-state:
    curl -sS {{inspect_base}}/state | jq .

# hit POST /force-poll and pretty-print the response
inspect-poll:
    curl -sS -X POST {{inspect_base}}/force-poll | jq .

# inject a synthetic state transition (Phase 2)
#   just inspect-simulate error
inspect-simulate state:
    curl -sS -X POST {{inspect_base}}/simulate \
        -H 'Content-Type: application/json' \
        -d '{"state":"{{state}}"}' | jq .

# inject N consecutive transient failures (Phase 2)
#   just inspect-simulate-failure 3
inspect-simulate-failure count:
    curl -sS -X POST {{inspect_base}}/simulate-failure \
        -H 'Content-Type: application/json' \
        -d '{"category":"networkFailure","count":{{count}}}' | jq .

# return the recent state transition history ring buffer (Phase 2)
inspect-history:
    curl -sS {{inspect_base}}/history | jq .

# clear the stored ChargePoint credentials (Phase 2)
inspect-clear-creds:
    curl -sS -X POST {{inspect_base}}/clear-credentials

# classify a fixture JSON file against the Core classifier (Phase 2)
#   just inspect-classify Tests/Fixtures/chargepoint/status_offline.json
inspect-classify fixture:
    curl -sS -X POST {{inspect_base}}/classify \
        -H 'Content-Type: application/json' \
        --data-binary @{{fixture}} | jq .

# deliver a test macOS notification (Phase 2)
#   just inspect-notify "title" "body"
inspect-notify title body:
    curl -sS -X POST {{inspect_base}}/notify-test \
        -H 'Content-Type: application/json' \
        -d '{"title":"{{title}}","body":"{{body}}"}'

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

# run SwiftLint in strict mode (warnings become errors)
lint:
    swiftlint lint --strict

# auto-fix fixable SwiftLint issues
fmt:
    swiftlint lint --fix

# everything CI runs; becomes the green-gate
check: check-core-purity lint test build
    @echo "just check: OK"

# launch the built app in the foreground
run: build
    {{symroot}}/Debug/Grounded.app/Contents/MacOS/Grounded

# launch the built app detached (so the debug inspect server is reachable)
dev: build
    @pkill -x Grounded 2>/dev/null || true
    @{{symroot}}/Debug/Grounded.app/Contents/MacOS/Grounded &
    @sleep 1
    @echo "Grounded launched in background. Use 'just stop' to quit."

# quit the running app gracefully
stop:
    @osascript -e 'tell application "Grounded" to quit' 2>/dev/null || echo "Grounded is not running"

# install the git pre-commit hook that runs `just check` before every commit
install-hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    hook=".git/hooks/pre-commit"
    cat > "$hook" << 'HOOK'
    #!/bin/sh
    just check
    HOOK
    chmod +x "$hook"
    echo "Installed pre-commit hook: $hook"

# bump CFBundleShortVersionString, commit, tag with release notes, push.
# Usage: just bump 0.1.0  (bare version, tag prefix is empty)
bump version:
    #!/usr/bin/env bash
    set -euo pipefail
    test -n "{{version}}" || { echo "Usage: just bump 0.1.0"; exit 1; }

    current=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
    echo "Bumping $current -> {{version}}"

    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString {{version}}" Resources/Info.plist
    git add Resources/Info.plist
    git commit -m "Bump version to {{version}}"

    prev_tag=$(git describe --tags --abbrev=0 HEAD~1 2>/dev/null || echo "")
    if [ -n "$prev_tag" ]; then
        commit_log=$(git log "${prev_tag}..HEAD" --oneline --no-merges)
    else
        commit_log=$(git log --oneline --no-merges -20)
    fi

    notes_file=$(mktemp)
    trap 'rm -f "$notes_file"' EXIT

    if command -v claude &>/dev/null; then
        prompt="Generate concise release notes for version {{version}}.
    Commits since ${prev_tag:-the beginning}:

    ${commit_log}

    Guidelines:
    - Group related commits into a single bullet point
    - Focus on user-facing changes, not implementation details
    - Skip version bumps, CI changes, and purely internal refactors
    - Keep each bullet to one line, use past tense
    - Output only a bullet list (- item), nothing else"

        if claude -p "$prompt" > "$notes_file" 2>/dev/null; then
            echo "Release notes (generated by Claude):"
        else
            echo "$commit_log" | sed 's/^[0-9a-f]* /- /' > "$notes_file"
            echo "Release notes (from commit log):"
        fi
    else
        echo "$commit_log" | sed 's/^[0-9a-f]* /- /' > "$notes_file"
        echo "Release notes (from commit log):"
    fi
    cat "$notes_file"

    git tag -a "{{version}}" -F "$notes_file"
    git push && git push --tags
    echo "{{version}} released!"

# re-trigger the release workflow for an existing tag while preserving
# the annotated tag message. Usage: just retag 0.1.0
retag version:
    #!/usr/bin/env bash
    set -euo pipefail
    tag="{{version}}"
    notes=$(git tag -l --format='%(contents)' "$tag" 2>/dev/null || echo "$tag")
    notes_file=$(mktemp)
    trap 'rm -f "$notes_file"' EXIT
    echo "$notes" > "$notes_file"
    gh release delete "$tag" --yes || true
    git push origin ":refs/tags/$tag" || true
    git tag -d "$tag" || true
    git tag -a "$tag" -F "$notes_file"
    git push && git push --tags

# clean all build artifacts
clean:
    rm -rf {{symroot}} grounded.xcodeproj DerivedData
