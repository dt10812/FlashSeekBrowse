# 🌐 FlashSeekBrowse

**FlashSeekBrowse** is a fast, lightweight macOS browser written in Swift using `WKWebView`.  
It features privacy protections, persistent tabs, a custom UI, and Sparkle-powered auto-updates.

![Icon](Icon-256.png)

---

## ✨ Features

- 🧭 Smart address bar with search engine selection
- 🗂 Tabbed browsing with persistent state
- 🛡 Fingerprinting protection (Canvas, WebGL, WebRTC)
- 🌙 Dark mode and custom theming
- 🧩 Settings, bookmarks, history, and download manager
- 🛠 DevTools support (via WebKit’s built-in features)
- ⚡ Optimized performance with preloaded WebViews

---

## 🛠 Build Instructions

### 1. Requirements

- macOS 12+ (Monterey or later)
- Xcode 14+
- SwiftUI + WebKit

### 2. Clone the repo

```bash
git clone https://github.com/dt10812/FlashSeekBrowse.git
cd flashseekbrowse
```

### 3. Open in Xcode
### 4. Build & Run
1. Select a macOS target
2. Press ⌘ + R to run
## 🔐 Code Signing & Notarization (for public distribution)
If you plan to distribute this browser outside the Mac App Store:
### 1. Sign the app

```bash
codesign --deep --force --verify \
  --options runtime \
  --timestamp \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  FlashSeekBrowse.app # Or any name you choose for the browser.
```

Replace "Your Name (TEAMID)" with your real name and Team ID in your Apple Account.

### 2. Create a .dmg

```bash
hdiutil create -volname "FlashSeekBrowse" \
  -srcfolder FlashSeekBrowse.app \
  -ov -format UDZO FlashSeekBrowse.dmg
```

3. Notarize (once credentials are stored)

```bash
xcrun notarytool submit FlashSeekBrowse.dmg \
  --keychain-profile "notary-profile" \
  --wait
```
4. Staple

```bash
xcrun stapler staple FlashSeekBrowse.dmg
```

## 🧪 Development Tips
- Each tab uses WKWebView stored in memory to avoid reloads

- Debug WebView with ⌥ + ⌘ + I (enable in Safari → Developer)

- JavaScript messages are bridged via WKScriptMessageHandler

- Custom permissions, canvas blocking, and user-agent spoofing supported
## 📄 License
The License is in the LICENSE file.


## ✉️ Contact / Contributions
If you'd like to contribute, fix bugs, or request features:

- Open an issue

- Or email: ducthinh100812@gmail.com



