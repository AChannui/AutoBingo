# Disney Cruise Bingo Assistant — Project Plan

**Status:** Planning / requirements gathering  
**Target platform:** iPhone  
**Planned language and UI:** Swift + SwiftUI  
**Initial approach:** On-device processing; no backend required for the first version

## 1. Project goal

Build an iPhone app that helps track bingo during Disney cruises. The user photographs:

1. A bingo screen showing a called number.
2. Their physical bingo boards during setup.

The app recognizes the board numbers and called numbers, marks matching cells across three active boards, and checks whether any board satisfies the current winning rule.

The app is intended to assist the player. The user should be able to review and correct recognition results rather than relying on uncertain OCR without confirmation.

## 2. Initial scope

### In scope for the first useful version

- Support **three active 5×5 bingo boards** at a time.
- Capture/import a photo of each board during setup.
- Recognize the 25 board cells and let the user review/correct the extracted values.
- Capture/import a photo of the bingo screen to recognize a called number.
- Confirm or correct a recognized call before applying it.
- Track called numbers for the current game and ignore duplicate calls.
- Mark matching cells on all three boards.
- Support the free center square as an optional game setting.
- Support preset and user-drawn winning patterns.
- Support patterns that can appear anywhere or only at specified locations.
- Support rules requiring one or multiple qualifying occurrences.
- Show board progress and clearly indicate when a board wins.
- Allow the user to reset/start another game and replace the three boards.

### Deferred / later features

- Persistent game history and review of previous games.
- Additional convenience features not yet specified.
- Any online service, account, synchronization, or backend.
- More advanced recognition and automation beyond what is needed for a reliable first version.

## 3. Expected user workflow

1. **Set up boards:** Photograph three physical bingo boards.
2. **Review setup:** Confirm the detected 5×5 numbers, including the center cell.
3. **Configure a game:** Select a winning pattern/rule and choose whether the center is free.
4. **Track calls:** Photograph the big screen for each call.
5. **Confirm recognition:** Review the detected letter/number and correct it if needed.
6. **Update boards:** Apply the call to all three boards and update their marked cells.
7. **Check wins:** Evaluate the selected winning rule and clearly identify any winning board.
8. **Next game:** Reset called numbers and either keep or replace the boards. History can be added later.

## 4. Boards and game state

The app needs three active board slots. It does **not** need to manage 12 boards in the initial design. The user receives or uses three boards for a game and may replace them when the next game begins.

Suggested concepts:

- `BingoBoard`
  - Stable board ID.
  - 5×5 grid of recognized numbers.
  - Center/free-square information as needed.
  - Current marked state should be derived from called numbers and game settings where practical.
- `BingoGame`
  - The three active boards.
  - Set/list of called numbers for the current game.
  - Selected winning rule/pattern.
  - Free-center setting.
  - Current game status.
- `BingoPattern` / winning-rule model
  - Shape or rule type.
  - Allowed locations/orientations.
  - Required number of qualifying occurrences.
  - Any/all condition for grouped rules.
  - Free-center behavior should be applied consistently at game/rule evaluation time.
- `BingoEngine`
  - Pure logic for marking cells and evaluating whether a board satisfies the active rule.

Store board cells in a consistent order, such as row-major order, so each cell always has a stable coordinate `(row, column)`.

Keep board definitions separate from called-number state. Replacing a board should not require rebuilding the entire app state or recognition system.

## 5. Called-number recognition

Use the iPhone camera or photo picker to get a screen photo. Recognize the called bingo letter and number, such as `G-54` (example only).

Requirements:

- Show the recognized call to the user before applying it.
- Allow correction if recognition is wrong or uncertain.
- Avoid applying duplicate calls twice.
- Keep a call history for the current game so the user can review what has been recognized.
- Make it possible to undo/correct a call if practical for the first version.

Potential technology:
- Apple Vision for text recognition.
- Core Image and/or other native image-processing tools if preprocessing is needed.

Recognition should be implemented separately from bingo-rule evaluation.

## 6. Board-photo recognition

The board setup flow should:

- Detect or help the user align/crop a 5×5 grid.
- Correct perspective when the photo is angled, if feasible.
- Recognize each cell's number.
- Handle the center/free square.
- Present the extracted grid for confirmation and manual correction.
- Validate obvious OCR mistakes where possible using expected bingo column ranges and valid card structure.

Potential technology:
- Apple Vision for OCR.
- Core Image for image preprocessing.
- OpenCV is an optional alternative if needed, but prefer a native iOS implementation initially unless testing shows it is necessary.

Do not assume OCR is always correct. The confirmation UI is a core reliability feature.

## 7. Winning-pattern requirements

Patterns should be flexible. Known presets are shortcuts, not the only patterns the app can support. A custom editor should let the user tap cells on a 5×5 grid to draw a required shape.

### Known patterns discussed

1. **Regular five-in-a-row**
   - Five consecutive marked cells in a horizontal, vertical, or diagonal line, subject to the selected game rule.
2. **Specified vertical column(s)**
   - One or more selected B/I/N/G/O columns.
   - Support winning when **any one** selected column is complete.
   - Also support winning only when **all** selected columns are complete.
3. **T shape**
   - A shape described as three across with a stem extending two squares from the center.
   - Support orientations/rotations and reflections.
   - Exact interpretation and geometry should be confirmed during implementation.
4. **3×2 rectangle**
   - Six cells arranged as three columns by two rows.
   - Support rotations/reflections and placements where allowed.
5. **2×2 square**
   - Four adjacent cells forming a square.
6. **Custom drawn pattern**
   - User taps cells in a 5×5 editor to define the required shape.

### Pattern placement and occurrence rules

These are separate settings and should not be conflated:

- **Allowed locations**
  - Anywhere the shape fits.
  - Only specified positions, such as corners.
  - A fixed, exact arrangement.
  - Potentially other restricted regions.
- **Orientation**
  - Fixed orientation.
  - Rotations/reflections allowed.
- **Required occurrences**
  - Any one valid placement is sufficient.
  - A chosen number of placements must be complete (for example, any two).
  - All specified/eligible placements must be complete.
- **Grouped conditions**
  - Support rules such as any one of a selected set of columns, or all selected columns.
  - More complex combinations can be considered later without complicating the first version.

### Example: corner-only 2×2

The same 2×2 shape could be configured in several ways:
- Any one of the four corner placements wins.
- All four corner placements must be complete.
- A chosen number of corner placements must be complete.
- Only specifically selected corner positions count.

The app must not assume which rule is intended; the user configures it for the current game.

### Pattern matching model

Represent a shape as selected coordinates in a 5×5 grid (or an equivalent 25-cell mask). Generate/check valid placements according to the location and orientation rules.

For each placement, check whether every required cell is marked. Then apply the occurrence rule (any one, a specified count, or all). Column rules may use a dedicated rule type because they express grouped line conditions rather than only a single shape.

Define how overlapping placements count before implementing rules that require multiple occurrences. A simple initial approach is to count each distinct valid placement independently, then refine if actual cruise rules require non-overlapping placements.

## 8. Free center square

The center square can optionally be free for a game.

- **Free center enabled:** Center cell starts marked.
- **Free center disabled:** Center cell behaves like an ordinary cell and is marked only when its number is called.

The setting should be configurable per game, not a permanent global setting. Winning evaluation must apply this consistently to presets, columns, and custom patterns. If a required pattern includes the center, its free/marked status follows the selected setting.

## 9. Suggested iOS technology

- **Swift** for implementation.
- **SwiftUI** for screens and interactive grids.
- **Vision** for text recognition.
- **Core Image** for native image preprocessing where useful.
- **AVFoundation** and/or SwiftUI-compatible camera/photo-picker flows for image input.
- Local state/storage for the initial version; no server needed.
- Consider persistence for the three boards and game state if useful, while keeping full game-history functionality deferred.

Exact frameworks and persistence strategy can be finalized when implementation begins and the supported iOS version is chosen.

## 10. Suggested code organization

Possible types/modules (names are provisional):

- `BingoBoard` — board ID, grid and board validation.
- `BingoGame` — active boards, calls, game configuration.
- `BingoPattern` — preset/custom pattern representation.
- `WinningRule` — pattern matching, column conditions and occurrence requirements.
- `BingoEngine` — pure logic to update/evaluate board state.
- `NumberRecognizer` — reads called numbers from screen photos.
- `BoardRecognizer` — reads a 5×5 card from photos.
- `BoardSetupView` — capture, review and correction of board values.
- `GameView` — active game and three board displays.
- `CallConfirmationView` — recognized call and correction controls.
- `PatternEditorView` — custom 5×5 pattern drawing and rule configuration.
- `GameSetupView` — board selection/replacement, pattern and free-space settings.

Keep OCR/camera code separate from the bingo engine so the rule logic can be unit-tested without photos or a camera.

## 11. Testing plan

Before relying on the app during a real game, test the following independently:

### Bingo engine tests
- Called number marks the correct cell on each board.
- Duplicate calls do not change state incorrectly.
- Free center enabled/disabled.
- Horizontal, vertical, and diagonal lines.
- Each preset shape in every supported orientation.
- Shapes at board edges and corners.
- Fixed-position versus anywhere placement.
- Any-one, specified-count, and all-occurrences rules.
- Selected columns: any selected column versus all selected columns.
- No false win when even one required square is unmarked.

### Recognition tests
- Multiple photos of the same screen under different lighting/angles.
- Board photos with perspective and glare.
- OCR errors and user correction.
- Repeated screen photos and duplicate calls.
- Board validation and manual correction.

### Usability tests
- Setting up three boards is quick.
- Correcting a wrong OCR result is easy.
- Active board progress and a win are clear at a glance.
- Starting another game resets the right state without accidentally carrying over old calls.

## 12. Open decisions for later

These are not blockers for planning, but should be decided before or during implementation:

- Minimum iOS version.
- Whether called-number recognition should require confirmation every time or allow a faster mode later.
- Exact geometry of the T pattern (especially the meaning of “two down from the center”).
- Whether rotations/reflections are enabled by default for each preset.
- How the app should treat overlapping placements when multiple occurrences are required.
- Whether saved custom patterns are included in the first release or added later.
- Whether board/game state should persist across app restarts in the initial release.
- Whether a call can be undone and how.
- Additional features the user plans to discuss later.

## 13. Recommended build order

1. Write and unit-test the pure bingo engine using manually entered boards and calls.
2. Build a SwiftUI board display and active-game screen.
3. Add board setup with manual number entry/correction.
4. Add called-number photo recognition and confirmation.
5. Add board-photo OCR and grid correction.
6. Add the custom pattern editor and configurable placement/occurrence rules.
7. Test the full workflow using real sample photos.
8. Add game history and other deferred features later.

## Guiding principle

**Build a reliable, configurable bingo engine first; treat image recognition as an input mechanism that can be reviewed and corrected.** This keeps the most important logic testable and avoids making the app's correctness depend entirely on OCR.
