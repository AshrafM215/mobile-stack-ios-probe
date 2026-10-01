# Mobile stack iOS feasibility probe

**NON-PRODUCTION / SYNTHETIC DATA ONLY.** This repository holds small synthetic spike applications used only to
check that three mobile stacks can be configured, resolved, built, linked and launched for the iOS Simulator on
standard GitHub-hosted macOS runners:

- `candidate-a-flutter` - Flutter, MapLibre Native through `maplibre_gl`, ARKit through a platform channel;
- `candidate-b-react-native` - React Native (New Architecture), MapLibre Native through
  `@maplibre/maplibre-react-native`, ARKit through a TurboModule;
- `candidate-c-native/ios` - Swift/SwiftUI with MapLibre Native iOS and ARKit.

All map content is invented synthetic geometry near 0N 0E. There are no real places, people, accounts, credentials,
signing identities or production endpoints. Workflow results are development evidence only; they are not a
benchmark, a product, or a statement about any real-world deployment.
