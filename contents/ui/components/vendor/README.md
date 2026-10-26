# Open-Meteo file reader

Vendored for the radar map (librewxr-map.html), which reads the wind of the
whole planet from Open-Meteo's open-data files
(https://openmeteo.s3.amazonaws.com/data_spatial/).

- `index.browser.js`: `@openmeteo/file-reader` 0.0.20, `dist/esm/index.browser.js`
- `om_file_format.web.js`, `om_file_format.web.wasm`: `@openmeteo/file-format-wasm` 0.0.20, `dist/`

License: GPL-2.0-only (https://github.com/open-meteo/typescript-omfiles).

Served from unpkg, the WebAssembly arrives truncated in QtWebEngine, hence
this local copy.
