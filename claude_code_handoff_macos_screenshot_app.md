# Project Handoff: Native macOS Screenshot Utility

## 1. Project Context & Goal
You are an expert macOS developer (Swift, SwiftUI, AppKit). We are building a native macOS screenshot utility, similar to CleanShot X or Shottr. 
The goal of this phase is to build a functional MVP that I can use as my daily driver. It must focus on high performance, beautiful aesthetic outputs (background padding + shadow), and seamless system integration.

## 2. Tech Stack & Frameworks
- **Language**: Swift 6 (Strict Concurrency enabled).
- **UI Framework**: SwiftUI (primary) + AppKit (where necessary for window management, global hotkeys, and menu bar).
- **Screen Capture**: `ScreenCaptureKit` (for modern, performant screen/window recording and capturing).
- **Graphics/Rendering**: `CoreGraphics`, `SwiftUI Canvas` (for annotations and image composition).
- **System Integration**: `NSPasteboard` (clipboard), `NSStatusItem` (menu bar app).

## 3. Architecture & Guidelines
- **App Lifecycle**: The app should run as an Agent/Accessory app (Menu Bar only). It should not show in the Dock (`LSUIElement = YES` in Info.plist).
- **State Management**: Use modern `@Observable` macros. Keep state clean and separated from UI views.
- **Permissions**: The app will need Screen Recording permissions. Provide clear fallback UI/alerts if permissions are missing.
- **Modularity**: Separate the core capture logic (`CaptureService`), image processing/rendering logic (`RenderService`), and UI (`EditorView`, `SelectionView`).

## 4. MVP Scope & Features (Implementation Order)

Please implement the following features step-by-step. Ask for my confirmation before moving to the next major step.

### Step 1: Foundation & Menu Bar
- Create the basic App structure.
- Configure `Info.plist` to hide the Dock icon (`LSUIElement`).
- Create an `NSStatusItem` (Menu bar icon) with a basic menu: "Capture Area", "Capture Full Screen", "Settings", "Quit".

### Step 2: Permissions & Global Hotkeys
- Implement a check for Screen Recording permissions. If not granted, prompt the user to open System Settings.
- Implement global hotkeys (e.g., `Cmd + Shift + 1` for area, `Cmd + Shift + 2` for full screen). *Hint: You can use `NSEvent.addGlobalMonitorForEvents` or a lightweight wrapper.*

### Step 3: Screen Capture Mechanism (ScreenCaptureKit)
- Implement `CaptureService` using `ScreenCaptureKit`.
- Provide a method to capture the entire screen.
- Provide an interactive transparent overlay (`NSWindow` covering the active screen) that allows the user to click-and-drag to select a specific `CGRect`.
- Once the user releases the mouse, capture that specific `CGRect`.

### Step 4: The Editor Canvas (Aesthetics)
- After capture, open a borderless, floating `NSWindow` (transparent background) containing a SwiftUI View (`EditorView`).
- **Aesthetic Processing**: The captured image should be placed on a larger canvas with:
  - Configurable padding (e.g., 40-60pt).
  - A beautiful background (solid color or gradient).
  - A nice, soft drop shadow applied to the screenshot itself (`shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)`).
- Provide basic zoom/pan capabilities for the canvas.

### Step 5: Basic Annotations
- Implement a simple toolbar in the `EditorView`.
- Add an "Arrow" tool: user can drag on the canvas to draw a vector arrow pointing at something on the screenshot.

### Step 6: Export & Cleanup
- Add two buttons: "Copy" and "Save".
- **Copy**: Render the composed SwiftUI Canvas (screenshot + background + shadow + annotations) into an `NSImage` and write it to `NSPasteboard`.
- **Save**: Render the composition and save it to the Desktop/Downloads as a `.png`.
- Close the `EditorView` and return to the background state upon successful export.

## 5. Instructions for Claude Code
1. Start by scaffolding the project structure and modifying the `Info.plist`.
2. When writing code involving AppKit+SwiftUI bridging (like transparent windows or `NSHostingController`), ensure memory leaks are avoided and windows are properly deallocated when closed.
3. Write clean, well-documented code.
4. Let's start with **Step 1 & Step 2**. Please write the code for the Menu Bar app and the permissions/hotkeys logic first.