#!/usr/bin/env bash
# ABOUTME: Creates the tednaleid/homebrew-grounded tap repo on GitHub and
# ABOUTME: seeds it with an initial cask from the latest release. One-time setup.
set -euo pipefail

OWNER="tednaleid"
TAP_REPO="homebrew-grounded"
MAIN_REPO="grounded"       # repo + cask + bundle-id segment (lowercase)
APP_NAME="Grounded"        # macOS .app bundle display name (capitalized)

# -- Preflight checks --

if ! command -v gh &>/dev/null; then
    echo "Error: gh CLI is required. Install with: brew install gh"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    echo "Error: not authenticated with gh. Run: gh auth login"
    exit 1
fi

# -- Get latest release version and compute SHA-256 of the DMG --

echo "Fetching latest release info..."
VERSION=$(gh release view --repo "${OWNER}/${MAIN_REPO}" --json tagName -q .tagName)

DMG_URL="https://github.com/${OWNER}/${MAIN_REPO}/releases/download/${VERSION}/${MAIN_REPO}-${VERSION}.dmg"
echo "Downloading ${MAIN_REPO}-${VERSION}.dmg to compute SHA-256..."
SHA256=$(curl -sL "$DMG_URL" | shasum -a 256 | awk '{print $1}')
echo "  sha256: ${SHA256}"

# -- Create and clone the tap repo --

# `gh repo clone` + `gh repo create` as separate steps hits a GraphQL
# eventual-consistency race: REST-side create succeeds, but the GraphQL read
# `gh repo clone` uses can't yet resolve the new repo and errors out. Use
# `gh repo create --clone` which atomically creates and clones via the REST
# response URL. SSH remote per `gh config get git_protocol`.
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

if gh repo view "${OWNER}/${TAP_REPO}" &>/dev/null; then
    echo "Repo ${OWNER}/${TAP_REPO} already exists, cloning."
    git clone "git@github.com:${OWNER}/${TAP_REPO}.git" .
else
    echo "Creating ${OWNER}/${TAP_REPO}..."
    gh repo create "${OWNER}/${TAP_REPO}" --public \
        --description "Homebrew tap for ${APP_NAME}" \
        --clone
    cd "${TAP_REPO}"
fi

mkdir -p Casks

cat > "Casks/${MAIN_REPO}.rb" <<CASK
cask "${MAIN_REPO}" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/${OWNER}/${MAIN_REPO}/releases/download/#{version}/${MAIN_REPO}-#{version}.dmg"
  name "${APP_NAME}"
  desc "macOS menubar app that monitors a home ChargePoint charger"
  homepage "https://github.com/${OWNER}/${MAIN_REPO}"

  depends_on macos: ">= :sonoma"

  app "${APP_NAME}.app"

  zap trash: [
    "~/Library/Application Support/${MAIN_REPO}",
    "~/Library/Preferences/com.${OWNER}.${MAIN_REPO}.plist",
    "~/Library/Caches/com.${OWNER}.${MAIN_REPO}",
  ]
end
CASK

cat > README.md <<README
# homebrew-${MAIN_REPO}

Homebrew tap for [${APP_NAME}](https://github.com/${OWNER}/${MAIN_REPO}).

## Install

\`\`\`bash
brew install --cask ${OWNER}/${MAIN_REPO}/${MAIN_REPO}
\`\`\`

Or:

\`\`\`bash
brew tap ${OWNER}/${MAIN_REPO}
brew install --cask ${MAIN_REPO}
\`\`\`

## Update

\`\`\`bash
brew upgrade --cask ${MAIN_REPO}
\`\`\`
README

git add "Casks/${MAIN_REPO}.rb" README.md
git commit -m "Initial cask for ${APP_NAME} ${VERSION}"
git push

echo ""
echo "Tap repo created and populated at: https://github.com/${OWNER}/${TAP_REPO}"
echo ""
echo "-- Next step: create a fine-grained Personal Access Token --"
echo ""
echo "1. Go to: https://github.com/settings/personal-access-tokens/new"
echo "2. Token name: ${MAIN_REPO}-homebrew-tap"
echo "3. Repository access: Only select repositories -> ${OWNER}/${TAP_REPO}"
echo "4. Permissions: Contents -> Read and write"
echo "5. Generate the token and copy it"
echo ""
echo "Then set it as a secret on the ${MAIN_REPO} repo:"
echo ""
echo "  gh secret set HOMEBREW_TAP_TOKEN --repo ${OWNER}/${MAIN_REPO}"
echo ""
echo "(Paste the token when prompted.)"
echo ""
echo "For signed, notarized releases you'll also want to set these secrets:"
echo "  APPLE_CERTIFICATE           (base64-encoded .p12 developer ID certificate)"
echo "  APPLE_CERTIFICATE_PASSWORD  (password for the .p12 file)"
echo "  APPLE_ID                    (Apple ID email)"
echo "  APPLE_TEAM_ID               (10-character Apple Developer Team ID)"
echo "  APPLE_APP_SPECIFIC_PASSWORD (app-specific password for notarytool)"
echo ""
echo "Without these the release workflow still runs: it ad-hoc signs the app"
echo "so development works, but the cask won't be installable for other users."
