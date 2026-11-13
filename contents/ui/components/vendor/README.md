# Open-Meteo file reader

Vendored for the radar map (librewxr-map.html), which reads the wind of the
whole planet from Open-Meteo's open-data files
(https://openmeteo.s3.amazonaws.com/data_spatial/).

- `index.browser.js`: `@openmeteo/file-reader` 0.0.20, `dist/esm/index.browser.js`
- `om_file_format.web.js`, `om_file_format.web.wasm`: `@openmeteo/file-format-wasm` 0.0.20, `dist/`

License: GPL-2.0-only (https://github.com/open-meteo/typescript-omfiles).

Served from unpkg, the WebAssembly arrives truncated in QtWebEngine, hence
this local copy.

# Coasts and borders

`coast-borders.bin`: the coasts and land borders the radar map draws over
its color layers (temperature...). Natural Earth 1:10m, public domain
(https://www.naturalearthdata.com/), simplified to about 500 m and packed by
`scripts/make_coast_lines.py`.
