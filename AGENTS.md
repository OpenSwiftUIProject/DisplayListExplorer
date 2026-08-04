# Repository instructions

## Local web preview

- Do not validate this app by opening `index.html` with a `file://` URL. ES modules and the SwiftWasm bundle require an HTTP server, and a file URL will leave the editor stuck loading.
- After every implementation change, build the real browser artifacts and start a preview server for the user to inspect. Do not substitute a mock or stub for the SwiftWasm module.
- Use the installed Swift 6.2.3 toolchain that matches the repository's WebAssembly SDK:

  ```sh
  TOOLCHAINS=org.swift.623202512101a swift package \
    --swift-sdk 6.2-SNAPSHOT-2026-01-12-a-wasm32-unknown-wasip1 \
    js -c release
  npm ci
  npm run preview
  ```

- Keep the preview server running after verification so the user can open it. Report the complete HTTP URL, including the `/DisplayListExplorer/` base path.
- If the default preview port is occupied, reuse the existing server when it serves this worktree; otherwise choose another port and report it explicitly.
