(
  set -e

  error() {
    echo "[ERROR] $1" >&2
    exit 1
  }

  REPO="PaloAltoNetworks/ktool"
  BINARY="kubectl-ktool"
  INSTALL_PATH="/usr/local/bin/$BINARY"

  echo "--> Getting latest version..."
  VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep -oP '"tag_name": "\K[^"]+') || error "Failed to fetch latest version"

  if [[ -z "$VERSION" ]]; then
    error "Latest version tag is empty"
  fi

  echo "--> Downloading $BINARY ($VERSION)..."
  curl -fsSL -o "/tmp/$BINARY" "https://github.com/$REPO/releases/download/$VERSION/$BINARY" || error "Download failed"

  echo "--> Making it executable..."
  chmod +x "/tmp/$BINARY" || error "Failed to make executable"

  echo "--> Moving to /usr/local/bin (may require sudo)..."
  sudo mv "/tmp/$BINARY" "$INSTALL_PATH" || error "Failed to move binary to $INSTALL_PATH"

  echo -e "\n[OK] Installed successfully!"
  echo "Run: kubectl ktool version"
)
