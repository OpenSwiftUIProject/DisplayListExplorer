# DisplayListExplorer

**DisplayList Explorer** converts a SwiftUI `DisplayList.description` S-expression into its compact `minimalDescription` form, links source elements to their encodings, and explains every token.

The parser and converter are written in Swift. [JavaScriptKit](https://github.com/swiftwasm/JavaScriptKit) compiles the browser executable to WebAssembly, CodeMirror provides the source editor and range decorations, Vite packages the static assets, and GitHub Actions deploys the result to GitHub Pages.

## Features

- Converts content, effects, nested flattened lists, effect children, and state variants.
- Reconstructs a readable `DisplayList.description` from `minimalDescription`.
- Reproduces the single-line formatting emitted by `SExpPrinter`.
- Links source and `minimalDescription` ranges with bidirectional hover highlighting.
- Provides dedicated `minimalDesc`, encoding info, and occurrence statistics tabs.
- Previews DisplayList frames inside draggable iPhone presets or a custom-size Window frame, with
  zoom, fit, actual-size controls, a point ruler, resolved content, effects, and payload placeholders.
- Highlights every matching source range when a statistics row is hovered or focused.
- Copies compact, self-contained links that reopen a shared `minimalDescription`.
- Runs entirely in the browser; pasted descriptions are not uploaded.
- Tests the conversion engine natively with SwiftPM before every deployment.

### Reverse conversion

The direction control can use the current output as the next input. Because `minimalDescription`
intentionally omits rendering details, reconstructed descriptions mark an unknown scalar or
identifier with `?` and an unrecoverable payload or effect kind with `*`. Converting the
reconstructed description forward again preserves the original `minimalDescription`.

### Shared links

`Copy link` stores the canonical `minimalDescription`, rather than the much larger source
description, as versioned UTF-8 Base64URL in the URL fragment. Opening the link decodes that value
and starts in reverse-conversion mode. Fragments are not included in HTTP requests, so shared
DisplayList data is only decoded in the browser.

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

Opening `index.html` through a `file://` URL cannot run the ES Module and WebAssembly bundle.
To build with the GitHub Pages base path and launch the production preview in one step, run:

```sh
npm run preview
```

Then open <http://127.0.0.1:4173/DisplayListExplorer/>.

Run the native converter tests with:

```sh
swift test
```

## GitHub Pages

The Pages workflow deploys every push to `main` and can also be run manually from any branch through `workflow_dispatch`. It tests the converter, builds the SwiftWasm package, bundles the site with the repository's Pages base path, and deploys the `dist` artifact to <https://openswiftuiproject.github.io/DisplayListExplorer/>.

## Pull request previews

Pull requests opened from branches in this repository are deployed to an isolated Cloudflare Pages preview after CI succeeds. Each pull request receives a stable branch alias such as `https://pr-42.display-list-explorer.pages.dev`, while every update also creates an immutable deployment URL. GitHub attaches the resulting URL to the pull request as a deployment and maintains a single bot comment containing the stable URL and a commit-by-commit table of immutable snapshots.

The workflow expects a `CLOUDFLARE_API_TOKEN` repository secret with Cloudflare Pages edit access and a `CLOUDFLARE_ACCOUNT_ID` repository variable. Pull requests from forks still run the converter and site build, but skip deployment because repository secrets are not exposed to fork workflows.

## License

DisplayList Explorer is available under the MIT License. Third-party attributions are listed in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
