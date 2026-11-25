# Cruise Bingo — Development Plan

Companion to `disney_cruise_bingo_project_plan.md` (the requirements). This file tracks
*how* we build it and the decisions we've made.

## Project layout

```
auto_bingo/
├── AutoBingo.xcodeproj        ← open this in Xcode
├── AutoBingo/                 ← the iPhone app (SwiftUI screens, saving state)
│   ├── AutoBingoApp.swift
│   ├── GameStore.swift
│   └── Views/…
├── dev.sh                     ← command-line helpers (test, build, run, screenshot, ocr)
└── BingoKit/                  ← Swift package
    ├── Sources/BingoKit/          ← pure bingo rules: Board, PatternShape, WinningRule, Engine, Game
    ├── Sources/BingoRecognition/  ← photo → text (Apple Vision) → ranked call guesses
    ├── Sources/bingo-ocr/         ← CLI: shows what the app reads from a photo
    └── Tests/                     ← unit tests, incl. real Vision OCR on generated images
```

The bingo rules live in `BingoKit` so they can be tested without a phone, camera or photos
(the plan's guiding principle). Later, OCR code will only *produce numbers* that flow
into the same engine.

## Decisions made (defaults — easy to change later)

| Open question | Decision for v1 |
|---|---|
| Minimum iOS | **iOS 17** (uses SwiftUI `@Observable`) |
| Confirm every call? | Yes — calls are typed/confirmed before applying |
| T-shape geometry | 3 across + 2-cell stem down from the middle (5 cells) |
| Rotations/reflections default | On for shapes; can switch to fixed |
| Overlapping placements | Each distinct placement counts separately |
| Saved custom patterns | Later (current game's custom pattern is kept) |
| Persist across restarts | Yes — current game saved as JSON on the device |
| Undo a call | Yes — undo last call, or swipe-delete any call in history |

## How winning rules work

Every rule becomes a list of **placements** (sets of cells), plus an **occurrence** requirement:

- *Five in a row* → 5 rows + 5 columns (+ 2 diagonals)
- *Columns* → one placement per selected B/I/N/G/O column
- *Shapes* (2×2, 3×2, T, blackout, custom) → every position/orientation allowed by the
  placement setting: **anywhere**, **only at selected corners**, or **exactly as drawn**
- Occurrence: **any one**, **at least N**, or **all** placements complete

A board wins when enough placements are fully marked. Marks are never stored — they
are worked out from the board numbers + called numbers + free-center setting, so undoing
a call or changing the rule mid-game is always correct.

## Phases

- [x] **Phase 1 — Engine + tests**: board model/validation, shapes, rules, marking, win checks
- [x] **Phase 2 — Playable app (manual entry)**: type boards in, type calls in, see marks/wins,
      configure rule + free center, call history/undo, new game, auto-save
- [x] **Phase 3 — Call photo recognition**: camera/photo → Apple Vision OCR → ranked guesses
      (letter+number beats bare number, bigger text beats smaller, OCR look-alikes fixed only when
      the column range agrees) → confirmation sheet → same call flow as typing
- [x] **Phase 4 — Board photo recognition**: photo → OCR each number with its position →
      fit the grid using the fact that each number's value tells its column → place all numbers,
      drop stray text → (if needed) retry after perspective-correcting the card → pre-fill the
      board editor, doubtful squares highlighted yellow, photo kept for side-by-side checking
- [ ] **Phase 5 — Real-world testing** with sample photos from a cruise; tune OCR
- [ ] **Later**: game history, saved custom patterns, faster "auto-apply" call mode

## Running it

Everything works from the command line (handy over SSH):

```
./dev.sh test                  # all unit tests
./dev.sh run                   # build + launch in the iPhone simulator
./dev.sh screenshot shot.png   # see what the simulator shows
./dev.sh ocr photo.jpg         # what called number would the app read from this screen photo?
./dev.sh ocr-board card.jpg    # what 5×5 numbers would the app read from this card photo?
./dev.sh demo-call photo.jpg   # open the app's "Confirm call" screen with that photo + screenshot
./dev.sh demo-board card.jpg   # scan that card into Board 1 in the app + screenshot
```

- **Tests (Terminal):** `./dev.sh test`
- **App:** open `AutoBingo.xcodeproj`, choose an iPhone simulator at the top, press ▶︎ (⌘R).
- **On your own iPhone:** select the AutoBingo target → *Signing & Capabilities* → pick your
  Apple ID team, change the bundle identifier to something unique, plug in the phone, ▶︎.
