#!/bin/bash
# Command-line helpers for working on Cruise Bingo without opening Xcode.
#
#   ./dev.sh test                  Run all unit tests (engine + recognition)
#   ./dev.sh build                 Build the app for the iPhone simulator
#   ./dev.sh run                   Build, install and launch in the simulator
#   ./dev.sh screenshot [out.png]  Save a screenshot of the simulator
#   ./dev.sh photos                Add TestPhotos/* to the simulator's Photos (skips ones already there)
#   ./dev.sh ocr photo.jpg ...     Show what the app would read from photos of the bingo screen
#   ./dev.sh ocr-board card.jpg    Show the 5×5 numbers the app would read from a card photo
#   ./dev.sh demo-call photo.jpg   Launch the app straight into "Confirm call" for that photo,
#                                  then save a screenshot (debug builds only)
#   ./dev.sh demo-board card.jpg   Launch the app, scan that card photo into Board 1, screenshot
#   ./dev.sh demo-bulk a.jpg b.jpg  Launch the app, add a board for each card photo at once, screenshot
#
# Pick a different simulator with SIM_NAME, e.g.  SIM_NAME="iPhone 17" ./dev.sh run

set -euo pipefail
cd "$(dirname "$0")"

SIM_NAME="${SIM_NAME:-iPhone 16 Pro}"
DERIVED=".build/DerivedData"
APP_ID="com.example.AutoBingo"
APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/AutoBingo.app"

sim_id() {
    local id
    id=$(xcrun simctl list devices available | grep -m1 -E "^ +$SIM_NAME \(" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
    if [[ -z "$id" ]]; then
        echo "No simulator named '$SIM_NAME'. Available:" >&2
        xcrun simctl list devices available | grep -E "iPhone" >&2
        exit 1
    fi
    echo "$id"
}

build() {
    xcodebuild -project AutoBingo.xcodeproj -scheme AutoBingo \
        -destination "id=$(sim_id)" -derivedDataPath "$DERIVED" -quiet build
    echo "Build succeeded."
}

boot_and_install() {
    local id
    id=$(sim_id)
    xcrun simctl boot "$id" 2>/dev/null || true
    xcrun simctl bootstatus "$id" -b >/dev/null
    xcrun simctl terminate "$id" "$APP_ID" 2>/dev/null || true
    xcrun simctl install "$id" "$APP_PATH"
}

screenshot() {
    local out="${1:-screenshot.png}"
    xcrun simctl io "$(sim_id)" screenshot "$out" >/dev/null 2>&1
    echo "Saved $out"
}

# Adds each TestPhotos file to the simulator's photo library unless a photo with
# that original filename is already in it. `simctl addmedia` never checks for
# duplicates itself, so running it twice adds every photo twice.
add_test_photos() {
    local id db existing f missing=()
    id=$(sim_id)
    xcrun simctl boot "$id" 2>/dev/null || true
    xcrun simctl bootstatus "$id" -b >/dev/null
    db="$HOME/Library/Developer/CoreSimulator/Devices/$id/data/Media/PhotoData/Photos.sqlite"
    existing=""
    if [[ -f "$db" ]]; then
        existing=$(sqlite3 -readonly "$db" \
            "SELECT b.ZORIGINALFILENAME FROM ZASSET a
             JOIN ZADDITIONALASSETATTRIBUTES b ON b.ZASSET = a.Z_PK
             WHERE a.ZTRASHEDSTATE = 0" 2>/dev/null || true)
    fi
    shopt -s nullglob nocaseglob
    for f in TestPhotos/*.{jpg,jpeg,png,heic}; do
        if ! grep -qixF "$(basename "$f")" <<<"$existing"; then
            missing+=("$f")
        fi
    done
    shopt -u nullglob nocaseglob
    if [[ ${#missing[@]} -eq 0 ]]; then
        echo "All TestPhotos are already in the '$SIM_NAME' simulator's Photos."
        return
    fi
    xcrun simctl addmedia "$id" "${missing[@]}"
    echo "Added ${#missing[@]} photo(s) to the '$SIM_NAME' simulator."
}

absolute() { (cd "$(dirname "$1")" && echo "$PWD/$(basename "$1")"); }

case "${1:-}" in
    test)
        (cd BingoKit && swift test)
        ;;
    build)
        build
        ;;
    run)
        build
        boot_and_install
        xcrun simctl launch "$(sim_id)" "$APP_ID" >/dev/null
        echo "Running in the '$SIM_NAME' simulator. Use './dev.sh screenshot' to see it."
        ;;
    screenshot)
        screenshot "${2:-screenshot.png}"
        ;;
    photos)
        add_test_photos
        ;;
    ocr)
        shift
        [[ $# -gt 0 ]] || { echo "Usage: ./dev.sh ocr photo.jpg [more.jpg ...]"; exit 1; }
        files=()
        for f in "$@"; do files+=("$(absolute "$f")"); done
        (cd BingoKit && swift run -c release --quiet bingo-ocr "${files[@]}")
        ;;
    ocr-board)
        shift
        [[ $# -gt 0 ]] || { echo "Usage: ./dev.sh ocr-board card.jpg [more.jpg ...]"; exit 1; }
        files=()
        for f in "$@"; do files+=("$(absolute "$f")"); done
        (cd BingoKit && swift run -c release --quiet bingo-ocr --board "${files[@]}")
        ;;
    demo-board)
        [[ $# -ge 2 ]] || { echo "Usage: ./dev.sh demo-board card.jpg [out.png]"; exit 1; }
        photo=$(absolute "$2")
        build
        boot_and_install
        xcrun simctl launch "$(sim_id)" "$APP_ID" -demoBoardImage "$photo" >/dev/null
        sleep 6
        screenshot "${3:-demo-board.png}"
        ;;
    demo-bulk)
        shift
        [[ $# -gt 0 ]] || { echo "Usage: ./dev.sh demo-bulk card.jpg [more.jpg ...]"; exit 1; }
        paths=()
        for f in "$@"; do paths+=("$(absolute "$f")"); done
        joined=$(IFS='|'; echo "${paths[*]}")
        build
        boot_and_install
        xcrun simctl launch "$(sim_id)" "$APP_ID" -demoBulkBoardImages "$joined" >/dev/null
        sleep 8
        screenshot demo-bulk.png
        ;;
    demo-call)
        [[ $# -ge 2 ]] || { echo "Usage: ./dev.sh demo-call photo.jpg [out.png]"; exit 1; }
        photo=$(absolute "$2")
        build
        boot_and_install
        xcrun simctl launch "$(sim_id)" "$APP_ID" -demoCallImage "$photo" >/dev/null
        sleep 4
        screenshot "${3:-demo-call.png}"
        ;;
    *)
        sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
