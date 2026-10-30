#!/bin/bash
# Archives Chess Dashboard, signs it for the App Store and uploads it to TestFlight, all with the
# App Store Connect API key named in .env at the repo root (ASC_KEY_ID, ASC_ISSUER_ID,
# ASC_KEY_PATH). Signing uses the distribution certificate named in ExportOptions.plist and the
# "Chess Dashboard App Store" profile. The certificate lives in its own keychain, unlocked here
# with CHESSDASH_KEYCHAIN_PASSWORD from .env, so signing never stops on a password prompt. Each
# build is numbered by the date and time, so every upload is new.
#
#   ios/testflight.sh              # archive, export, upload
#   ios/testflight.sh --no-upload  # archive and export only (build/ios-export/ChessDashboard.ipa)
#
# ENV_FILE=/path/to/.env overrides where the values are read from (e.g. a git worktree).
set -euo pipefail
cd "$(dirname "$0")"
upload=1
for arg in "$@"; do
  case "$arg" in
    --no-upload) upload=0 ;;
    *) echo "usage: $0 [--no-upload]" >&2; exit 2 ;;
  esac
done
env_file=${ENV_FILE:-../.env}
env_value() { sed -n "s/^$1=//p" "$env_file" | tr -d '\r'; }
key_id=$(env_value ASC_KEY_ID)
issuer=$(env_value ASC_ISSUER_ID)
key_path=$(env_value ASC_KEY_PATH)
key_path=${key_path/#\~/$HOME}
archive=../build/ChessDashboard.xcarchive
export_dir=../build/ios-export
keychain=$HOME/Library/Keychains/tvhome-signing.keychain-db

# unlock-keychain has no stdin or file input: without -p it prompts on the terminal, so the
# password stays on its command line (briefly visible to local `ps`).
security unlock-keychain -p "$(env_value CHESSDASH_KEYCHAIN_PASSWORD)" "$keychain"
if ! security list-keychains -d user | grep -q tvhome-signing; then
  # Each line is an indented, quoted path; keep paths with spaces whole.
  keychains=()
  while IFS= read -r kc; do
    keychains+=("$kc")
  done < <(security list-keychains -d user | sed -n 's/^[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p')
  security list-keychains -d user -s "${keychains[@]}" "$keychain"
fi

xcodegen generate -q
xcodebuild archive -project ChessDashboard.xcodeproj -scheme ChessDashboard -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" -allowProvisioningUpdates \
  -authenticationKeyPath "$key_path" -authenticationKeyID "$key_id" -authenticationKeyIssuerID "$issuer" \
  CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" -quiet
rm -rf "$export_dir"
# Apple's openrsync runs `rsync` from PATH, and Homebrew's rejects its options.
PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive -archivePath "$archive" \
  -exportPath "$export_dir" -exportOptionsPlist ExportOptions.plist -quiet
ipa="$export_dir/ChessDashboard.ipa"
if [ "$upload" = 0 ]; then
  echo "Exported $(cd "$(dirname "$ipa")" && pwd)/$(basename "$ipa") (not uploaded)"
  exit 0
fi
# altool finds the key by its ID in ~/.appstoreconnect/private_keys.
xcrun altool --upload-app -t ios -f "$ipa" --apiKey "$key_id" --apiIssuer "$issuer"
