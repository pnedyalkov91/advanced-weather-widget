# Advanced Weather Widget for KDE Plasma 6

![image](screenshots/image.png)

A modern, highly customizable weather widget built specifically for KDE Plasma 6.

It delivers accurate forecasts, multiple weather provider support, adaptive failover logic, and extensive appearance customization - all while integrating naturally into the Plasma desktop.

---

## ✨ Key Features

### 📍 Location Management
- Automatic location detection via GeoClue2 or IP address with confirmation dialog
- Manual city search with dual geocoding (Open-Meteo + Nominatim / OSM)
- Location search with map using OpenStreetMap and Nominatim geocoding API with autocomplete and map preview
- Reverse geocoding for localized city names and non-Latin scripts (e.g. Cyrillic)
- Automatic timezone and altitude detection
- Multi-location support with quick switching and per-location settings

### 🌦 Weather Providers

Choose between:
- **Open-Meteo** - free, no API key required (recommended)
- **MET Norway** - free Norwegian Meteorological Institute, no API key
- **OpenWeatherMap** (requires API key)
- **WeatherAPI.com** (requires API key)
- **Pirate Weather** (requires API key)
- **Tomorrow.io** (requires API key)
- **Visual Crossing** (requires API key)
- **StormGlass** (requires API key)
- **Weatherbit** (requires API key)
- **QWeather** (requires API key)

### 🔄 Adaptive Mode
- Automatic fallback chain: Open-Meteo  →  met.no  →  Pirate Weather  →  Visual Crossing  →  Tomorrow.io  →  StormGlass  →  Weatherbit  →  QWeather  →  OpenWeatherMap  →  WeatherAPI.com
- Seamless provider switching if one fails
- Provider-specific location availability verification

### 🌡 Weather Data
- **Temperature** - current, feels like (apparent), dew point, daily high / low
- **Wind** - speed with 16-point compass direction arrow
- **Humidity, Pressure, Visibility**
- **Precipitation** - current rate and daily total
- **Snow Cover** - current snow depth
- **UV Index** - 0–11+ scale (Low → Extreme)
- **Air Quality** - European CAQI with 6 bands (Good → Extremely Poor), per-pollutant breakdown (PM2.5, PM10, NO₂, O₃, SO₂, CO), plus AQHI score
- **Pollen** - Universal Pollen Index (0–12) with 4 bands, 6 types: Alder, Birch, Grass, Mugwort, Olive, Ragweed
- **Space Weather** - Kp index, geomagnetic storm scale (G0–G5), solar wind speed, Bz magnetic field, X-ray flux / solar flare class, aurora visibility probability (from NOAA SWPC)
- **Weather Alerts** - Supported providers: MeteoAlarm (38 European countries); NOAA NWS (USA only); MET Norway (Norway only). Also the widget can display alerts from the following providers: Pirate Weather, Visual Crossing and Weather API (Requires API key and alert support from the providers)
- **Sunrise / Sunset** - configurable modes (both, upcoming, sunrise only, sunset only)
- **Moon Phase** - phase name, icon, moonrise / moonset times; multiple display modes
- **25+ weather conditions** with day / night variants

### 🖥 Panel Modes
- **Single line** - horizontal row of selected items with configurable separator
- **Multiline** - large weather icon with scrolling item rows (1–8 visible lines, adjustable scroll speed)
- **Simple** - compact icon + temperature with layout options:
  - Horizontal, Vertical, or Compressed (badge overlay)
  - Compressed badge: position, spacing, background colour, opacity

All panel modes support:
- Drag-and-drop item reordering (17 available items)
- Per-item icon show / hide toggle
- 6 icon themes: Symbolic, Font (wi-font), Flat Color, 3D Oxygen, KDE system, Custom (per-item icon picker)
- Custom font (family, size, bold) or system font
- Item spacing and width controls
- System tray support (Compressed mode only)

### 💬 Tooltip
- Enable / disable toggle
- Prefix style: Icons or Text labels
- Configurable items with drag-and-drop ordering
- Location name: truncate or wrap
- Size: auto or manual (width / height)
- Icon theme and size selection

### 📊 Widget Popup
- Two tabs: **Details** and **Forecast** (configurable default)
- Header with location name, detect / change / refresh buttons

#### Details View
- **Cards** (2-column grid) or **List** layout
- Expandable cards with visualizations:
  - Sun arc for sunrise / sunset
  - Moon path for moon phase
  - CAQI pollutant breakdown bars for air quality
  - Per-type pollen bars with info tooltips
  - Space weather dashboard (Kp, Bz, solar wind, flare class, aurora %) (Provider: NOAA SWPC)
  - Multi-alert carousel for weather alerts (Providers: Eumetnet Meteoalarm, MET Norway, NOAA NWS or supporting weather provider)
- Configurable card height, per-item icons, accent colours

#### Forecast View
- **Daily forecast** - 3 to 7 days with condition icon, text, and colour-coded min / max temperatures
- **Hourly forecast** - click a day to expand inline scrolling hourly cards with temperature, wind, precipitation probability, and precipitation rate
- Optional **sunrise / sunset markers** between hourly cards

### ⚙ Units & Display
- **Presets**: Metric (°C, km/h, hPa, mm), Imperial (°F, mph, inHg, in), KDE locale (auto), Custom
- **Individual unit overrides** in custom mode: temperature, wind speed (km/h, mph, m/s, kn), pressure (hPa, mmHg, inHg)
- **Round values** - toggle between whole numbers and decimals
- **Show temperature unit** - toggle to display °C / °F or just °
- Popup minimum size: auto or manual (200–2000 px)

### 🎨 Icon Themes & Fonts
- 6 panel icon themes, 6 widget condition icon themes (with per-condition custom picker for 24 day / night weather slots)
- Tooltip and details view icon themes
- Bundled icon sets in 4 sizes: 16, 22, 24, 32 px
- Panel and widget fonts configurable independently (system or custom)

### 🌐 Internationalization
- 7 translations: Bulgarian, German, French, Dutch, Brazilian Portuguese, Russian, Turkish
- Full i18n support for all UI labels, weather conditions, air quality / pollen / space weather descriptions
- Locale-aware date / time formatting (12h / 24h, date format)
- Localized location search results

---

## 📦 Installation

### Install from KDE Store (Recommended)

Open:

System Settings → Add Widgets → Download New Widgets

Search for:

**Advanced Weather Widget**

Or visit:
https://store.kde.org/p/2349879

---

## 🛠 Manual Installation (Development)

```bash
kpackagetool6 --type Plasma/Applet --install .
rm -rf ~/.cache/plasmashell/qmlcache
systemctl --user restart plasma-plasmashell
```

## 🌐 Translation

Translations are welcome! If you would like to help translate the widget into your language, please follow the instructions below.

1. Download the translation template:

https://github.com/pnedyalkov91/advanced-weather-widget/blob/main/translate/template.pot

2. Rename the file using your locale code. You can find a list of locale codes here:

https://help.sap.com/docs/SAP_BUSINESSOBJECTS_BUSINESS_INTELLIGENCE_PLATFORM/09382741061c40a989fae01e61d54202/46758c5e6e041014910aba7db0e91070.html

For example:
```
pt_BR.po
de_DE.po
fr_FR.po
ru_RU.po
```

3. Open the `.po` file in a translation editor such as:

- Poedit
- Lokalize (KDE)
- Kate / Kwrite
- VS Code

4. Translate all strings by filling the `msgstr ""` fields.

Example:

```po
msgid "Configure icon…"
msgstr "Configurar ícone…"
```

5. When the translation is ready:

- open a **GitHub Issue** and attach the `.po` file (you may need to compress it as `.zip` because GitHub blocks `.po` attachments).

### Translators

Thank you to everyone who contributed translations to this project ❤️

- **German** - [HolySoap](https://github.com/HolySoap)
- **Brazilian Portuguese** - [PauloAlbqrq](https://github.com/PauloAlbqrq)
- **Bulgarian** - Petar Nedyalkov (Author)
- **Dutch** - Heimen Stoffels (<vistausss@fastmail.com>)
- **Russian** - [Dmaliog](https://github.com/dmaliog)
- **French** - [LAZER-TY](https://github.com/LAZER-TY)
- **Turkish** - [herzane52](https://github.com/herzane52)

## External resources

- This project uses weather icons and font resources from: https://github.com/erikflowers/weather-icons
  Licensed under SIL OFL 1.1 (http://scripts.sil.org/OFL)

- This project uses code from the SunCalc library: https://github.com/mourner/suncalc
  Copyright (c) Vladimir Agafonkin
  Licensed under the BSD license

## ❤️ Support the project

Advanced Weather Widget is developed in my free time.

If you enjoy using it, you can support the project:

- Liberapay: https://liberapay.com/pnedyalkov
- PayPal: https://paypal.me/pnedyalkov91
- Revolut: https://revolut.me/petarnedyalkov91
