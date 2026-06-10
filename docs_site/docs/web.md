# Web Platform

Flutter web games have specific requirements around rendering and audio. This page covers what you need to set up.

## Performance: WASM and CanvasKit

Use the WASM compiler and the CanvasKit renderer for web builds. WASM improves execution speed for game logic and CanvasKit provides more consistent 2D rendering than the default HTML renderer.

### Building for Web with WASM
To build your game with WASM support:

```bash
flutter build web --wasm
```

:::tip
Run with `--wasm` during development too so you catch any WASM-specific issues early.
:::

```bash
flutter run -d chrome --wasm
```

---

## Cross-Origin Isolation (COOP & COEP)

For WASM to run with maximum performance and support multi-threading, your web server **must** provide the following HTTP response headers:

- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp`

### Why is this needed?
These headers enable **Cross-Origin Isolation**, which is required for browsers to allow the use of `SharedArrayBuffer`. 

Flutter's WASM support relies on `SharedArrayBuffer` to enable multi-threading (for tasks like garbage collection and background processing). Without these headers, the browser restricts the WASM environment to a single thread, which can lead to significant frame drops and stuttering in complex games.

### Workaround for GitHub Pages / Static Hosting
If you are hosting your game on a platform that does not allow you to set custom HTTP headers (like **GitHub Pages**), you can use a Service Worker workaround.

1.  Download [coi-serviceworker.min.js](https://github.com/gzuidhof/coi-serviceworker) and place it in your `web/` folder.
2.  Add it to your `index.html` before other scripts:

```html
<script src="coi-serviceworker.min.js"></script>
```

3. Deploy it with `--pwa-strategy=none` flag to prevent flutter service worker from interfering with coi-serviceworker.min.js.

This script will automatically reload the page and set the required isolation context via a service worker.

---

## Audio Setup (Web)

The underlying `flutter_soloud` engine used by Goo2D requires specific JavaScript files to be manually initialized on the Web. If you skip this, audio will not work and you will see obfuscated console errors.

### 1. Update `index.html`
Open `web/index.html` and add the following scripts inside the `<body>` tag, **before** the `flutter.js` script:

```html
<!-- Add these lines for Goo2D Audio support -->
<script src="assets/packages/flutter_soloud/web/libflutter_soloud_plugin.js" defer></script>
<script src="assets/packages/flutter_soloud/web/init_module.dart.js" defer></script>
```

### 2. Deployment
When deploying your game, ensure these assets are correctly included in your build output. If you are using standard Flutter build commands, they should be copied automatically to the `build/web/assets` directory.

For more details on audio usage, see the [Audio Cookbook](./cookbook/audio).
