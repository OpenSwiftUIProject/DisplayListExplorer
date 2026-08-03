# DisplayList Explorer

DisplayList Explorer converts a SwiftUI `DisplayList.description` S-expression into its compact `minimalDescription` form, links source elements to their encodings, and explains every token.

The parser and converter are written in Swift. [JavaScriptKit](https://github.com/swiftwasm/JavaScriptKit) compiles the browser executable to WebAssembly, CodeMirror provides the source editor and range decorations, Vite packages the static assets, and GitHub Actions deploys the result to GitHub Pages.

## Features

- Converts content, effects, nested flattened lists, effect children, and state variants.
- Reproduces the single-line formatting emitted by `SExpPrinter`.
- Links source and `minimalDescription` ranges with bidirectional hover highlighting.
- Provides dedicated `minimalDesc`, encoding info, and occurrence statistics tabs.
- Highlights every matching source range when a statistics row is hovered or focused.
- Runs entirely in the browser; pasted descriptions are not uploaded.
- Tests the conversion engine natively with SwiftPM before every deployment.

The mapping follows OpenSwiftUI's [`DisplayListPrinter.swift`](https://github.com/OpenSwiftUIProject/OpenSwiftUI/blob/main/Sources/OpenSwiftUICore/Render/DisplayList/DisplayListPrinter.swift), audited for SwiftUI 6.5.4. The interaction model is inspired by [SwiftFiddle/swiftregex](https://github.com/SwiftFiddle/swiftregex).
The CodeMirror decoration and statistics interaction patterns are adapted from [SwiftFiddle/swift-ast-explorer](https://github.com/SwiftFiddle/swift-ast-explorer); see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

### Known ambiguity

`DisplayList.description` prints identity effects, empty property effects, and platform effects with the same empty `(effect …)` form, while `minimalDescription` encodes them differently. Because the source text has already discarded that distinction, the converter renders an empty effect as identity and calls out the ambiguity in the interface.

## Local development

Prerequisites:

- Swift 6.2.3 with its matching WebAssembly SDK
- A matching `wasm32-unknown-wasip1` Swift SDK
- Node.js 24 or newer

Build the Swift package for WebAssembly, install the web dependencies, and start Vite:

```sh
swift package --swift-sdk "$SWIFT_SDK_ID" js
npm ci
npm run dev
```

Run the native converter tests with:

```sh
swift test
```

## GitHub Pages

The Pages workflow is manual while the repository is private. When the repository is ready to become public, set its Pages source to **GitHub Actions** and run **Deploy to GitHub Pages** from the Actions tab. The workflow tests the converter, builds the SwiftWasm package, bundles the site with the repository's Pages base path, and deploys the `dist` artifact.

## License

DisplayList Explorer is available under the MIT License. Third-party attributions are listed in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
