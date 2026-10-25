# Neorar

Archive manager for macOS 26+ (SwiftPM, SwiftUI). Build with `./build-app.sh` (needs Xcode's
`DEVELOPER_DIR`); UI strings are Portuguese keys translated in `Resources/Localizations/*.lproj`
(`scripts/translations.py` is the source for new keys).

## Showcase mode (site screenshots)

`NEORAR_SHOWCASE=1` (`Sources/Neorar/App/Showcase.swift`) is for the witchmymac.com screenshots.
Run a renamed copy, never the installed app: copy `build/Neorar.app`, delete `Contents/PlugIns`
(no Finder extension), set `CFBundleIdentifier` to `app.neorar.mac.showcase`, remove `NSServices`,
`CFBundleURLTypes`, `CFBundleDocumentTypes`, `UT*TypeDeclarations` and `SUFeedURL` from its
Info.plist, `codesign --force --deep --sign -`, then
`open -g -n --env CFFIXED_USER_HOME=<temp home> --env NEORAR_SHOWCASE=1 <copy> --args -AppleLanguages "(en)"`
with fictional archives in `<temp home>/Downloads` and `defaults write app.neorar.mac.showcase onboardingDone -bool true`.
In this mode there is no updater, no Services and no Finder-menu broadcast (which would reach the
installed extension). Extra variables, applied once the window is up:
- `NEORAR_SHOWCASE_SELECT=name1|name2` selects items of the current folder.
- `NEORAR_SHOWCASE_BROWSE=name` opens that archive in the window.
- `NEORAR_SHOWCASE_SHEET=compress|info` opens the Compress sheet (for the selection) or Info.
- `NEORAR_SHOWCASE_SETTINGS=general|extraction|compression|rar|about` opens Settings on that tab.
Afterwards: quit it, `defaults delete app.neorar.mac.showcase`, delete the temp home and
`lsregister -u` the copy.
