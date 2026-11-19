# Wintch

**English** | [日本語](README.ja.md)

**Wintch** (Window + Switch) is a simple, lightweight **window-based switcher and launcher** designed for macOS 14.0 (Sonoma) and later.

While macOS's built-in `Command + Tab` switches between applications, Wintch lets you quickly switch to any specific window across Spaces (virtual desktops), including multiple windows of the same application.

---

## Key Features

* **Least Privilege & Opt-In (Privacy by Design)**
  The default **List Switcher** and **Search Launcher** do not use Screen Recording permission at all—they operate solely using the Accessibility API (`AXUIElement`) and window metadata (`CGWindowListCopyWindowInfo`). Only when you explicitly opt into the **Capture Preview** style in Settings does Wintch use `ScreenCaptureKit` to display in-memory thumbnail previews.
* **Window Switcher (Default: `Option + Tab`)**
  Displays standard windows across all Spaces in Most Recently Used (MRU) order. Hold the modifier key and press the trigger key (with `Shift` for reverse order) or arrow keys to move the selection, then release the modifier key to switch (press `Esc` to cancel).
* **Search Launcher & App Launching (Default: `Option + Space`)**
  Opens a toggleable search panel to filter by application name and window title using space-separated AND fuzzy matching with match highlights. When typing a query, installed applications not already shown in the window list appear below as launch candidates—allowing it to act as an app launcher even when zero windows are open.
* **Close Selected Window / Quit App (Switcher Modifier + `Q`)**
  Close unwanted windows directly from the switcher or launcher (if it is the last window of that app, Wintch gracefully quits the application).
* **Menu Bar Resident, Secure Input Support & Customization**
  Runs as a background menu bar app (`LSUIElement`) without a Dock icon, and continues to work even under Secure Input protection (e.g., password fields). Customize shortcuts (with bidirectional conflict prevention), switch display styles, and configure Launch at Login from Settings.
* **Zero External Dependencies & Standard Apple Frameworks Only**
  Built with Swift 6.0 / SwiftUI (using `NSPanel` solely for floating panel control) and an `@Observable` MVVM + Services architecture, with no third-party dependencies or private APIs (such as `CGS*`).

---

## Requirements

* **OS**: macOS 14.0 (Sonoma) or later
* **Developer Tools**: Swift 6.0 or later (Xcode or Apple Command Line Tools)
* **Required Permission**: macOS **Accessibility** permission
  * On first launch or when ungranted, an onboarding prompt guides you to grant access in **System Settings > Privacy & Security > Accessibility**.
* **Optional Permission**: macOS **Screen Recording** permission (only required if you select the **Capture Preview** style in the Window Switcher)

---

## Installation

### Install via Homebrew (Recommended)

```bash
brew install --cask sawarame/tap/wintch
```

To update or uninstall:

```bash
# Update to the latest version
brew upgrade --cask wintch

# Uninstall (add --zap to also remove preference files)
brew uninstall --cask wintch
```

### Manual Installation from GitHub Releases

1. Download the latest `Wintch-vX.Y.Z.dmg` (or `Wintch-vX.Y.Z.zip`) from the [Releases](https://github.com/sawarame/Wintch/releases) page.
2. Open `Wintch-vX.Y.Z.dmg`, drag and drop `Wintch.app` into the `Applications` folder, and launch it (if you downloaded `.zip`, extract it and move `Wintch.app` to `/Applications`).

*(Distributed builds (`.app` and `.dmg`) are signed with a Developer ID certificate and notarized by Apple, so Gatekeeper warnings will not appear on launch. Follow the prompt on first launch to grant Accessibility permission.)*

---

## Project Structure

```text
.
├── Package.swift                   # Swift Package definition (no external dependencies)
├── VERSION                         # App version definition (Semantic Versioning)
├── AGENTS.md                       # Project guide for AI agents and developers
├── README.md                       # Project overview, installation, and local development (English)
├── README.ja.md                    # Project overview, installation, and local development (Japanese)
├── .context/                       # Core documentation, canonical specifications, and constitution
│   ├── constitution.md             # Project constitution (design principles and constraints)
│   ├── spec.md                     # Canonical specification for all features
│   ├── tech_stack.md               # Tech stack and directory structure
│   ├── development.md              # Development, build, and release workflow
│   └── swift.md                    # Swift 6.0 coding conventions
├── .github/
│   └── workflows/
│       └── release.yml             # Automated testing, signing, notarization, ZIP/DMG release & Homebrew Tap update
├── Resources/
│   ├── Info.plist                  # Bundle configuration (LSUIElement / CFBundleIconFile, etc.)
│   └── Icons/
│       ├── AppIcon.svg             # App icon source artwork (1024x1024)
│       └── MenuBarIcon.svg         # Menu bar template icon (18x18)
├── Sources/
│   ├── Wintch/
│   │   └── WintchApp.swift         # App entry point & MenuBarExtra
│   └── WintchCore/
│       ├── App/                    # AppCoordinator (screen & service coordination)
│       ├── Domain/                 # Pure business logic (filtering, sorting, search, selection, profiles, etc.)
│       ├── Services/               # OS API isolation layer (AX / CGWindow / CGEventTap / Carbon / ScreenCaptureKit, etc.)
│       │   └── Protocols/          # Protocols for mock injection in tests
│       ├── ViewModels/             # @Observable ViewModels
│       └── Views/                  # SwiftUI views & SwitcherPanel (NSPanel)
├── Tests/
│   └── WintchCoreTests/            # Swift Testing unit tests
└── scripts/
    ├── build-app.sh                # Script to assemble .app bundle, inject version, generate icons, and sign
    └── build-dmg.sh                # Script to create and sign a DMG containing the .app bundle and /Applications symlink
```

See [constitution.md](.context/constitution.md) and [spec.md](.context/spec.md) for detailed design specifications and project principles.

---

## Local Development

### 1. Clone the Repository

```bash
git clone <repository-url>
cd Wintch
```

### 2. Run Tests

Unit tests for domain logic and ViewModels are written with Swift Testing.

```bash
swift test
```

> [!NOTE]
> If you encounter build errors related to `TestingMacros`, specify the Xcode Developer directory or clean the build cache before retrying:
>
> ```bash
> DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
> # or
> swift package clean && swift test
> ```

### 3. Build and Launch the `.app` Bundle

Scripts are provided to compile the binary with `swift build`, generate `.icns` from `AppIcon.svg`, bundle resources, and code-sign the app. Local development (Debug) builds are output as `Wintch_dev.app` to avoid conflicts with the distributed version.

```bash
# Debug build (generates .build/Wintch_dev.app)
./scripts/build-app.sh

# Launch the local development build
open .build/Wintch_dev.app

# Release build (generates .build/Wintch.app)
./scripts/build-app.sh release

# Build as a Universal Binary (Apple Silicon + Intel)
./scripts/build-app.sh release --universal

# Create a DMG disk image from the built .app bundle
./scripts/build-dmg.sh
```

*(Since running `swift run` directly does not construct an `.app` bundle or `Info.plist`, we recommend launching `.build/Wintch_dev.app` via `./scripts/build-app.sh` for verification.)*

### 4. Versioning and Automated Releases (GitHub Actions)

The app version is centrally managed in the [`VERSION`](VERSION) file at the repository root using Semantic Versioning (e.g., `0.1.0`, `0.2.0-beta.1`).

* Running `./scripts/build-app.sh` automatically injects the `VERSION` value and Git commit count into `Info.plist` (`CFBundleShortVersionString` / `CFBundleVersion`) inside the bundle.
* Updating `VERSION` and pushing to the `main` branch triggers [`.github/workflows/release.yml`](.github/workflows/release.yml), which runs tests, creates a `v<VERSION>` tag, builds a Universal Binary `.app`, signs, notarizes, and staples both `Wintch-v<VERSION>.zip` and `Wintch-v<VERSION>.dmg` (containing `Wintch.app` and an `/Applications` symlink), publishes them to GitHub Releases, and—for stable releases—automatically updates the Homebrew Tap (`sawarame/homebrew-tap`). (Manual `v*` tag pushes, GitHub Release publishing, and `workflow_dispatch` are also supported.)

### 5. Note on Accessibility Permissions When Rebuilding

`./scripts/build-app.sh` uses ad-hoc code signing (`codesign --force --deep --sign -`) for local development. Because macOS identifies permissions for ad-hoc signed apps by **each build's code signature hash (`cdhash`)**, rebuilding after code changes can silently invalidate the permission even though it still appears enabled in System Settings.

If the permission prompt appears after rebuilding, re-register the app as follows:

1. Quit the running `Wintch_dev` (or `Wintch`) instance
2. Open **System Settings > Privacy & Security > Accessibility**
3. Select **`Wintch_dev`** in the list and **remove it using the `−` button** (toggling it off and back on is not sufficient)
4. Click the **`＋` button** to re-add `.build/Wintch_dev.app`, then launch it again

---

## License

[MIT License](LICENSE)
