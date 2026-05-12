#!/bin/bash
# PP GUI Linux installer — embedded inside the makeself .bin
# Installs to /opt/pp-gui, creates a launcher and .desktop entry.
set -e

INSTALL_DIR="/opt/pp-gui"
BIN_LINK="/usr/local/bin/pp-gui"
DESKTOP_FILE="/usr/share/applications/pp-gui.desktop"
ICON_DIR="/usr/share/icons/hicolor/512x512/apps"

echo "=== PP GUI Installer ==="
echo ""

# Detect root or sudo
if [ "$(id -u)" -ne 0 ]; then
  echo "This installer needs root privileges."
  echo "Please re-run with: sudo ./pp-gui-installer.bin"
  exit 1
fi

echo "[1/4] Installing application to $INSTALL_DIR ..."
# Remove previous installation to avoid file-vs-directory conflicts on upgrade
if [ -d "$INSTALL_DIR" ]; then
  rm -rf "$INSTALL_DIR"
fi
mkdir -p "$INSTALL_DIR"
# makeself executes the script from the extraction directory, so we can use current dir
cp -r . "$INSTALL_DIR/"
# remove the installer script itself from the final destination
rm -f "$INSTALL_DIR/install.sh"
chmod 755 "$INSTALL_DIR/pp_gui"

echo "[2/4] Creating launcher symlink at $BIN_LINK ..."
ln -sf "$INSTALL_DIR/pp_gui" "$BIN_LINK"

echo "[3/4] Installing icon ..."
mkdir -p "$ICON_DIR"
if [ -f "$INSTALL_DIR/data/flutter_assets/assets/app_icon_512.png" ]; then
  cp "$INSTALL_DIR/data/flutter_assets/assets/app_icon_512.png" \
     "$ICON_DIR/pp-gui.png"
fi

echo "[4/4] Creating .desktop entry ..."
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=PP GUI
GenericName=PP Protocol Client
Comment=Graphical client for the PP protocol
Exec=$INSTALL_DIR/pp_gui
Icon=pp-gui
Terminal=false
Categories=Network;
Keywords=vpn;proxy;pp;tunnel;
StartupNotify=true
EOF
chmod 644 "$DESKTOP_FILE"

# Update icon cache if possible (non-fatal)
gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
update-desktop-database 2>/dev/null || true

echo ""
echo "=== Installation complete! ==="
echo "You can now launch PP GUI from your application menu or run: pp-gui"
