# AGENTS.md — Platform

Platform abstraction layer for cross-platform type aliases.

## Files

| File               | Purpose                                                |
|--------------------|--------------------------------------------------------|
| `IRPLFImage.swift` | Platform-specific image type alias (`UIImage` on iOS)  |
| `IRPLFView.swift`  | Platform-specific view type alias (`UIView` on iOS)    |

## Agent Notes

- These files provide `typealias` definitions to abstract platform differences.
- Currently iOS-only, but structured to support macOS in the future.
- Compile flags `IRPLATFORM_TARGET_OS_IPHONE_OR_TV` and `IRPLATFORM_TARGET_OS_MAC_OR_IPHONE` control platform selection.
