# Native SwiftUI app instead of Tauri/WebView

We need a local macOS app plus a companion CLI to browse and export coding-agent sessions. Tauri (Rust + WebView) was considered for matching a web-style mockup quickly, but the product must feel like a normal local app and the author does not want a web-tech UI stack. We use a SwiftUI macOS app with a shared Swift library and an `asv` CLI target so all UI and parsing stay native and on-device.
