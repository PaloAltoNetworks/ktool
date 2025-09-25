#!/bin/sh
(
  set -e

  error() {
    echo "[ERROR] $1" >&2
    exit 1
  }

  REPO="PaloAltoNetworks/ktool"
  ASSET_NAME="kubectl-ktool.sh"
  BINARY_NAME="kubectl-ktool"
  INSTALL_PATH="/usr/local/bin/$BINARY_NAME"

  echo "--> Getting latest release information..."
  RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest") || error "Failed to fetch release info"
  VERSION=$(echo "$RELEASE_JSON" | grep -m 1 '"tag_name":' | cut -d'"' -f4) || error "Failed to parse version tag"
  if [ -z "$VERSION" ]; then
    error "Could not find latest version tag"
  fi
  
  DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -m 1 'browser_download_url' | grep "$ASSET_NAME" | cut -d'"' -f4) || error "Failed to find download URL for $ASSET_NAME"  
  if [ -z "$DOWNLOAD_URL" ]; then
    error "Download URL for $ASSET_NAME is empty"
  fi

  echo "--> Downloading $BINARY_NAME ($VERSION)..."
  curl -fsSL -o "/tmp/$BINARY_NAME" "$DOWNLOAD_URL" || error "Download failed"

  echo "--> Making it executable..."
  chmod +x "/tmp/$BINARY_NAME" || error "Failed to make executable"

  echo "--> Moving to /usr/local/bin (may require sudo)..."
  sudo mv "/tmp/$BINARY_NAME" "$INSTALL_PATH" || error "Failed to move binary to $INSTALL_PATH"

  echo "\n[OK] Installed successfully!"
  echo "Run: kubectl ktool version"
)
