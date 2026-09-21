#This code is edited and made by AI.
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

# ============================================================
# 10 SECOND INACTIVITY WATCHDOG
# ============================================================

run_with_timeout() {

    local LOGFILE
    local PID
    local LAST_SIZE
    local CURRENT_SIZE
    local ELAPSED
    local ANSWER

    LOGFILE="$(mktemp)"

    "$@" >"$LOGFILE" 2>&1 &
    PID=$!

    LAST_SIZE=0
    ELAPSED=0

    while kill -0 "$PID" 2>/dev/null; do

        sleep 1

        if [ -f "$LOGFILE" ]; then
            CURRENT_SIZE=$(wc -c < "$LOGFILE" | tr -d ' ')
        else
            CURRENT_SIZE=0
        fi

        if [ "$CURRENT_SIZE" -gt "$LAST_SIZE" ]; then
            ELAPSED=0
            LAST_SIZE="$CURRENT_SIZE"
        else
            ELAPSED=$((ELAPSED + 1))
        fi

        if [ "$ELAPSED" -ge 10 ]; then

            echo
            echo "=========================================="
            echo "No activity for 10 seconds."
            echo "=========================================="
            echo
            echo "The current operation is still running."
            echo
            read -r -p "Continue waiting? [y/N]: " ANSWER

            if [[ "$ANSWER" =~ ^[Yy]$ ]]; then

                echo
                echo "Continuing..."
                echo

                ELAPSED=0

            else

                echo
                echo "Stopping current operation..."

                kill "$PID" 2>/dev/null
                sleep 1

                if kill -0 "$PID" 2>/dev/null; then
                    kill -9 "$PID" 2>/dev/null
                fi

                wait "$PID" 2>/dev/null

                cat "$LOGFILE"

                rm -f "$LOGFILE"

                return 124
            fi
        fi
    done

    wait "$PID"
    local STATUS=$?

    cat "$LOGFILE"

    rm -f "$LOGFILE"

    return "$STATUS"
}

# ============================================================
# CHOOSE TYPE
# ============================================================

echo "choose:"
echo "1) dmg > pkg > app"
echo "2) pkg > app"

read -r -p "answer: " TYPE

if [[ "$TYPE" != "1" && "$TYPE" != "2" ]]; then
    echo "stupid"
    exit 1
fi

# ============================================================
# SELECT FILE
# ============================================================

if [[ "$TYPE" == "1" ]]; then
    FILE_PATH=$(osascript -e 'POSIX path of (choose file with prompt "select dmg to extract:")')
else
    FILE_PATH=$(osascript -e 'POSIX path of (choose file with prompt "select pkg to extract:")')
fi

if [ -z "$FILE_PATH" ]; then
    echo "no file selected"
    exit 1
fi

# ============================================================
# SELECT OUTPUT DIRECTORY
# ============================================================

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

# ============================================================
# DMG
# ============================================================

if [[ "$TYPE" == "1" ]]; then

    echo "trying to extract dmg..."

    # --------------------------------------------------------
    # 7z
    # --------------------------------------------------------

    echo "trying 7z..."

    run_with_timeout 7z x "$FILE_PATH" "-o$DMG_EXTRACT"

    SEVEN_STATUS=$?

    if [ "$SEVEN_STATUS" -eq 0 ]; then
        echo "7z finished successfully"
    elif [ "$SEVEN_STATUS" -eq 124 ]; then
        echo "7z stopped by user"
    else
        echo "7z failed"
    fi

    # --------------------------------------------------------
    # Search for APP
    # --------------------------------------------------------

    APP_PATH=$(find "$DMG_EXTRACT" \
        -type d \
        -name "*.app" \
        -print \
        -quit \
        2>/dev/null)

    # --------------------------------------------------------
    # Search for PKG
    # --------------------------------------------------------

    PKG_PATH=$(find "$DMG_EXTRACT" \
        -type f \
        -name "*.pkg" \
        -print \
        -quit \
        2>/dev/null)

    # --------------------------------------------------------
    # hdiutil
    # --------------------------------------------------------

    if [ -z "$APP_PATH" ] && [ -z "$PKG_PATH" ]; then

        echo
        echo "7z did not find an app or pkg"
        echo "trying hdiutil..."

        MOUNT_POINT="$WORKDIR/mounted_dmg"

        mkdir -p "$MOUNT_POINT"

        if run_with_timeout hdiutil attach \
            "$FILE_PATH" \
            -readonly \
            -nobrowse \
            -noautoopen \
            -mountpoint "$MOUNT_POINT"; then

            echo "hdiutil mounted dmg"

            echo "copying dmg contents..."

            run_with_timeout cp -R \
                "$MOUNT_POINT"/. \
                "$DMG_EXTRACT"/

            CP_STATUS=$?

            if [ "$CP_STATUS" -eq 0 ]; then
                echo "dmg contents copied"
            else
                echo "copy failed"
            fi

            hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || \
                echo "hdiutil detach failed"

            APP_PATH=$(find "$DMG_EXTRACT" \
                -type d \
                -name "*.app" \
                -print \
                -quit \
                2>/dev/null)

            PKG_PATH=$(find "$DMG_EXTRACT" \
                -type f \
                -name "*.pkg" \
                -print \
                -quit \
                2>/dev/null)

        else

            echo "hdiutil failed"

        fi
    fi

    # --------------------------------------------------------
    # dmg2img — LAST DMG METHOD
    # --------------------------------------------------------

    if [ -z "$APP_PATH" ] && [ -z "$PKG_PATH" ]; then

        echo
        echo "hdiutil did not find an app or pkg"
        echo "trying dmg2img..."

        IMG_PATH="$WORKDIR/${BASE}.img"
        IMG_EXTRACT="$WORKDIR/img_extracted"

        mkdir -p "$IMG_EXTRACT"

        echo "converting dmg to img..."

        if run_with_timeout dmg2img \
            "$FILE_PATH" \
            "$IMG_PATH"; then

            echo "dmg2img succeeded"

            echo
            echo "7z on img..."

            run_with_timeout 7z x \
                "$IMG_PATH" \
                "-o$IMG_EXTRACT"

            IMG_STATUS=$?

            if [ "$IMG_STATUS" -eq 0 ]; then
                echo "7z on img finished successfully"
            elif [ "$IMG_STATUS" -eq 124 ]; then
                echo "7z on img stopped by user"
            else
                echo "7z on img failed"
            fi

            APP_PATH=$(find "$IMG_EXTRACT" \
                -type d \
                -name "*.app" \
                -print \
                -quit \
                2>/dev/null)

            PKG_PATH=$(find "$IMG_EXTRACT" \
                -type f \
                -name "*.pkg" \
                -print \
                -quit \
                2>/dev/null)

        else

            echo "dmg2img failed"

        fi
    fi

    # --------------------------------------------------------
    # Final DMG result
    # --------------------------------------------------------

    if [ -n "$APP_PATH" ]; then

        echo
        echo "app found: $APP_PATH"
        echo "copying app..."

        run_with_timeout cp -R \
            "$APP_PATH" \
            "$APP_EXTRACT/"

        if [ $? -eq 0 ]; then
            echo "app copied successfully"
        else
            echo "app copy failed"
        fi

    elif [ -n "$PKG_PATH" ]; then

        echo
        echo "pkg found: $PKG_PATH"

    else

        echo
        echo "where the fuck is the pkg or app"
        echo "Are these the world's most crispy fries?"
        echo

    fi

else

    # ========================================================
    # PKG MODE
    # ========================================================

    PKG_PATH="$FILE_PATH"

fi

# ============================================================
# PKG EXTRACTION
# ============================================================

if [ -f "$PKG_PATH" ]; then

    echo
    echo "open pkg"

    rm -rf "$PKG_EXPAND"
    mkdir -p "$PKG_EXPAND"

    if run_with_timeout pkgutil \
        --expand \
        "$PKG_PATH" \
        "$PKG_EXPAND"; then

        echo "pkg expanded"

    else

        echo "pkgutil failed"
        exit 1

    fi

    echo "yay"

    # --------------------------------------------------------
    # Find Payload
    # --------------------------------------------------------

    PAYLOAD_PATH=$(find "$PKG_EXPAND" \
        -type f \
        -name "Payload" \
        -print \
        -quit \
        2>/dev/null)

    if [ -z "$PAYLOAD_PATH" ]; then

        echo "payload not found"

    else

        echo "payload: $PAYLOAD_PATH"
        echo "open payload"

        (
            cd "$APP_EXTRACT" || exit 1

            if run_with_timeout bash -c \
                'cat "$1" | gunzip -dc | cpio -idmv' \
                _ \
                "$PAYLOAD_PATH"; then

                echo "payload extracted"

            else

                echo "payload failed"
                exit 1

            fi
        )

    fi

fi

# ============================================================
# FIX APP PERMISSIONS / QUARANTINE
# ============================================================

FINAL_APP=$(find "$APP_EXTRACT" \
    -type d \
    -name "*.app" \
    -print \
    -quit \
    2>/dev/null)

if [ -n "$FINAL_APP" ]; then

    echo
    echo "fixing app permissions..."

    MACOS_DIR="$FINAL_APP/Contents/MacOS"

    if [ -d "$MACOS_DIR" ]; then

        EXECUTABLE=$(find "$MACOS_DIR" \
            -type f \
            -perm -111 \
            -print \
            -quit \
            2>/dev/null)

        if [ -n "$EXECUTABLE" ]; then

            echo "making executable:"
            echo "$EXECUTABLE"

            chmod +x "$EXECUTABLE"

            echo "removing quarantine..."

            xattr -dr com.apple.quarantine "$FINAL_APP" 2>/dev/null || \
                echo "could not remove quarantine attribute"

            echo "app permissions fixed"

        else

            echo "no executable found in Contents/MacOS"

        fi

    else

        echo "Contents/MacOS not found"

    fi

fi

# ============================================================
# FINAL
# ============================================================

echo
echo "ok its done"
echo

echo "dmg extracted to        $DMG_EXTRACT"
echo "pkg expanded to         $PKG_EXPAND"
echo "app files extracted to  $APP_EXTRACT"
