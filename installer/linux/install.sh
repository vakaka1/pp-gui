#!/bin/bash
# PP GUI Linux installer — embedded inside the makeself .bin
# Installs to /opt/pp-gui, creates a launcher and .desktop entry.
set -e

INSTALL_DIR="/opt/pp-gui"
BIN_LINK="/usr/local/bin/pp-gui"
DESKTOP_FILE="/usr/share/applications/pp-gui.desktop"
ICON_DIR="/usr/share/icons/hicolor/512x512/apps"

umask 022

echo "=== PP GUI Installer ==="
echo ""

# Detect root or sudo
if [ "$(id -u)" -ne 0 ]; then
  echo "This installer needs root privileges."
  echo "Please re-run with: sudo ./pp-gui-installer.bin"
  exit 1
fi

echo "[1/5] Installing application to $INSTALL_DIR ..."
# Remove previous installation to avoid file-vs-directory conflicts on upgrade
if [ -d "$INSTALL_DIR" ]; then
  rm -rf "$INSTALL_DIR"
fi
install -d -m 755 "$INSTALL_DIR"
# makeself executes the script from the extraction directory, so we can use current dir
cp -R --no-preserve=mode,ownership . "$INSTALL_DIR/"
# remove the installer script itself from the final destination
rm -f "$INSTALL_DIR/install.sh"

echo "[2/5] Fixing installed permissions ..."
find "$INSTALL_DIR" -type d -exec chmod 755 {} \;
find "$INSTALL_DIR" -type f -exec chmod 644 {} \;
chmod 755 "$INSTALL_DIR/pp_gui"
find "$INSTALL_DIR" -name '*.so' -exec chmod 755 {} \;

echo "[3/5] Checking installation ..."
if [ ! -x "$INSTALL_DIR/pp_gui" ]; then
  echo "ERROR: $INSTALL_DIR/pp_gui was not installed or is not executable." >&2
  exit 1
fi
if [ "$(stat -c '%a' "$INSTALL_DIR")" != "755" ]; then
  echo "ERROR: $INSTALL_DIR has wrong permissions after install:" >&2
  stat -c '%A %a %U:%G %n' "$INSTALL_DIR" >&2
  exit 1
fi

echo "[4/5] Creating launcher symlink at $BIN_LINK ..."
ln -sf "$INSTALL_DIR/pp_gui" "$BIN_LINK"

echo "[5/5] Installing desktop files ..."
mkdir -p "$ICON_DIR"
if [ -f "$INSTALL_DIR/data/flutter_assets/assets/app_icon_512.png" ]; then
  cp "$INSTALL_DIR/data/flutter_assets/assets/app_icon_512.png" \
     "$ICON_DIR/pp-gui.png"
fi

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
