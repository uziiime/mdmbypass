#!/bin/bash

BREW_PREFIX="$HOME/homebrew"
BREW_BIN="$BREW_PREFIX/bin/brew"

if [ -x "$BREW_BIN" ]; then
    export PATH="$BREW_PREFIX/bin:$PATH"
fi

# Also recognize normal Homebrew locations
if [ -x "/opt/homebrew/bin/brew" ]; then
    export PATH="/opt/homebrew/bin:$PATH"
    BREW_BIN="/opt/homebrew/bin/brew"
elif [ -x "/usr/local/bin/brew" ]; then
    export PATH="/usr/local/bin:$PATH"
    BREW_BIN="/usr/local/bin/brew"
fi

if ! command -v brew &>/dev/null; then
    echo "where is homebrew"

    NONINTERACTIVE=1 \
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null

    if [ -x "/opt/homebrew/bin/brew" ]; then
        export PATH="/opt/homebrew/bin:$PATH"
        BREW_BIN="/opt/homebrew/bin/brew"
    elif [ -x "/usr/local/bin/brew" ]; then
        export PATH="/usr/local/bin:$PATH"
        BREW_BIN="/usr/local/bin/brew"
    fi
fi

for tool in 7z dmg2img; do
    if ! command -v "$tool" &>/dev/null; then
        echo "not found specific file thing ($tool)"
        brew install "$tool" || {
            echo "failed to install $tool"
            exit 1
        }
    fi
done

echo "choose:"
echo "1) dmg > pkg > app"
echo "2) pkg > app"

read -r -p "answer: " TYPE

if [[ "$TYPE" != "1" && "$TYPE" != "2" ]]; then
    echo "stupid"
    exit 1
fi

if [[ "$TYPE" == "1" ]]; then
    FILE_PATH=$(osascript -e 'POSIX path of (choose file with prompt "select dmg to extract:")')
else
    FILE_PATH=$(osascript -e 'POSIX path of (choose file with prompt "select pkg to extract:")')
fi

if [ -z "$FILE_PATH" ]; then
    echo "no file selected"
    exit 1
fi

OUTDIR=$(osascript -e 'POSIX path of (choose folder with prompt "where do i save the files at:")')

if [ -z "$OUTDIR" ]; then
    echo "no output folder selected"
    exit 1
fi

BASE=$(basename "$FILE_PATH" | sed 's/\.[^.]*$//')

WORKDIR="$OUTDIR/${BASE}_extracted"

DMG_EXTRACT="$WORKDIR/dmg_extracted"
PKG_EXPAND="$WORKDIR/pkg_expanded"
APP_EXTRACT="$WORKDIR/app_extracted"

rm -rf "$WORKDIR"

mkdir -p "$WORKDIR"
mkdir -p "$DMG_EXTRACT"
mkdir -p "$APP_EXTRACT"

# ------------------------------------------------------------
# DMG extraction
# ------------------------------------------------------------

if [[ "$TYPE" == "1" ]]; then

    echo "trying to extract dmg..."

    # --------------------------------------------------------
    # Method 1: 7z directly on DMG
    # --------------------------------------------------------

    echo "trying 7z..."

    7z x "$FILE_PATH" -o"$DMG_EXTRACT" || echo "7z failed"

    # --------------------------------------------------------
    # Look for APP directly after 7z
    # --------------------------------------------------------

    APP_PATH=$(find "$DMG_EXTRACT" -type d -name "*.app" -print -quit 2>/dev/null)

    if [ -n "$APP_PATH" ]; then
        echo "app found: $APP_PATH"
    fi

    # --------------------------------------------------------
    # Look for PKG after 7z
    # --------------------------------------------------------

    PKG_PATH=$(find "$DMG_EXTRACT" -type f -name "*.pkg" -print -quit 2>/dev/null)

    # --------------------------------------------------------
    # Method 2: hdiutil
    # --------------------------------------------------------

    if [ -z "$APP_PATH" ] && [ -z "$PKG_PATH" ]; then

        echo "7z did not find an app or pkg"
        echo "trying hdiutil..."

        MOUNT_POINT="$WORKDIR/mounted_dmg"
        mkdir -p "$MOUNT_POINT"

        if hdiutil attach "$FILE_PATH" \
            -readonly \
            -nobrowse \
            -noautoopen \
            -mountpoint "$MOUNT_POINT"; then

            echo "hdiutil mounted dmg"

            cp -R "$MOUNT_POINT"/. "$DMG_EXTRACT"/

            hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || \
                echo "hdiutil detach failed"

            APP_PATH=$(find "$DMG_EXTRACT" -type d -name "*.app" -print -quit 2>/dev/null)

            PKG_PATH=$(find "$DMG_EXTRACT" -type f -name "*.pkg" -print -quit 2>/dev/null)

        else

            echo "hdiutil failed"

        fi
    fi

    # --------------------------------------------------------
    # Method 3: dmg2img LAST
    # --------------------------------------------------------

    if [ -z "$APP_PATH" ] && [ -z "$PKG_PATH" ]; then

        echo "hdiutil did not find an app or pkg"
        echo "trying dmg2img..."

        IMG_PATH="$WORKDIR/${BASE}.img"
        IMG_EXTRACT="$WORKDIR/img_extracted"

        mkdir -p "$IMG_EXTRACT"

        if dmg2img "$FILE_PATH" "$IMG_PATH"; then

            echo "dmg2img succeeded"

            echo "7z on img..."

            7z x "$IMG_PATH" -o"$IMG_EXTRACT" || \
                echo "7z on img failed"

            APP_PATH=$(find "$IMG_EXTRACT" -type d -name "*.app" -print -quit 2>/dev/null)

            PKG_PATH=$(find "$IMG_EXTRACT" -type f -name "*.pkg" -print -quit 2>/dev/null)

        else

            echo "dmg2img failed"

        fi
    fi

    # --------------------------------------------------------
    # Check final DMG result
    # --------------------------------------------------------

    if [ -n "$APP_PATH" ]; then

        echo "app found: $APP_PATH"

        echo "copying app..."

        cp -R "$APP_PATH" "$APP_EXTRACT/"

        if [ $? -eq 0 ]; then
            echo "app copied successfully"
        else
            echo "app copy failed"
        fi

    elif [ -n "$PKG_PATH" ]; then

        echo "pkg found: $PKG_PATH"

    else

        echo "where the fuck is the pkg or app"
        echo "Are these the world's most crispy fries?"
        echo

    fi

else

    PKG_PATH="$FILE_PATH"

fi

# ------------------------------------------------------------
# PKG extraction
# ------------------------------------------------------------

if [ -f "$PKG_PATH" ]; then

    echo "open pkg"

    rm -rf "$PKG_EXPAND"

    mkdir -p "$PKG_EXPAND"

    if pkgutil --expand "$PKG_PATH" "$PKG_EXPAND"; then
        echo "pkg expanded"
    else
        echo "pkgutil failed"
        exit 1
    fi

    echo "yay"

    # --------------------------------------------------------
    # Find Payload
    # --------------------------------------------------------

    PAYLOAD_PATH=$(find "$PKG_EXPAND" -type f -name "Payload" -print -quit 2>/dev/null)

    if [ -z "$PAYLOAD_PATH" ]; then

        echo "payload not found"

    else

        echo "payload: $PAYLOAD_PATH"
        echo "open payload"

        (
            cd "$APP_EXTRACT" || exit 1

            if cat "$PAYLOAD_PATH" | gunzip -dc | cpio -idmv; then
                echo "payload extracted"
            else
                echo "payload failed"
                exit 1
            fi
        )

    fi

fi

# ------------------------------------------------------------
# Final message
# ------------------------------------------------------------

echo "ok its done"
echo

echo "dmg extracted to        $DMG_EXTRACT"
echo "pkg expanded to         $PKG_EXPAND"
echo "app files extracted to  $APP_EXTRACT"
