# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a SwiftUI iOS application called "dama" targeting iOS 26.0+ using Swift 5.0. The project follows standard iOS app architecture with:

- **Main app entry point**: `dama/damaApp.swift` - Contains the @main App struct
- **Main view**: `dama/ContentView.swift` - Primary SwiftUI view with basic "Hello, world!" content
- **Bundle identifier**: `com.linkai.dama`
- **Development team**: GAH499CG22

### Project Requirement
项目使用中文注释以及和用户交互

主页命名为打码页，实现离线打码功能， 采用业内先进流行的技术方案：
1. 用户上传一或多张图片
2. **主要工具按钮** (三个功能):
- **自动打码**: 默认激活状态，OCR检测敏感信息区域
- **取消打码**: 清除当前图片所有马赛克区域
- **手动打码**: 切换手动打码模式，手动框选实现像素化打码



## Project Structure

```
dama/
├── dama/                     # Main app source code
│   ├── damaApp.swift        # App entry point (@main)
│   ├── ContentView.swift    # Main SwiftUI view
│   └── Assets.xcassets/     # App icons and assets
├── damaTests/               # Unit3 tests
├── damaUITests/             # UI tests
└── dama.xcodeproj/          # Xcode project configuration
```

## Development Commands

### Building
```bash
# Build the project
xcodebuild -scheme dama -configuration Debug build

# Build for Release
xcodebuild -scheme dama -configuration Release build
```

### Testing
```bash
# Run unit tests
xcodebuild test -scheme dama -destination 'platform=iOS Simulator,name=iPhone 17'

# Run only unit tests (exclude UI tests)
xcodebuild test -scheme dama -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:damaTests

# Run only UI tests
xcodebuild test -scheme dama -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:damaUITests
```

### Available Targets
- **dama**: Main application target
- **damaTests**: Unit test target
- **damaUITests**: UI test target

### Build Configurations
- **Debug**: Development builds with debug symbols
- **Release**: Production builds with optimizations

## Swift Configuration

- **Swift Version**: 5.0
- **iOS Deployment Target**: 26.0
- **Supported Devices**: iPhone and iPad (TARGETED_DEVICE_FAMILY = "1,2")
- **SwiftUI Features**: Uses SwiftUI previews, approachable concurrency
- **Code Signing**: Automatic signing configured