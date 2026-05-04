# Advanced Weather Widget for KDE Plasma 6

![image](screenshots/image.png)

A modern, highly customizable weather widget built specifically for KDE Plasma 6.

### Why this widget?
*   **Granular Precision:** Uses exact Latitude/Longitude coordinates for local data rather than generic city-level lookups.
*   **Modern UX:** A clean, native-feeling interface with smooth animations and intuitive layouts.
*   **Feature Rich:** From interactive radar maps and air quality to space weather and moon phases - everything is configurable.

---

# 📦 Installation

## ⚠️ Prerequisites & Dependencies
To prevent the "Empty Location Menu" or "Blank Radar" issues, please ensure you have the following Qt6 modules installed for your distribution:

### 📍 Location & Search
*Required for the Location settings menu and auto-detection.*

| Distribution | Package Name |
|---|---|
| **Fedora / RHEL** | `qt6-qtlocation` |
| **openSUSE** | `qt6-location` |
| **Arch Linux** | `qt6-location` |
| **Debian / Ubuntu / Neon** | `qml6-module-qtlocation` `qml6-module-qtpositioning` |

### 📡 Radar Map
*Required for the interactive Radar tab (Chromium-based).*

| Distribution | Package Name |
|---|---|
| **Fedora / RHEL** | `qt6-qtwebengine` |
| **openSUSE** | `qt6-webengine` |
| **Arch Linux** | `qt6-webengine` |
| **Debian / Ubuntu / Neon** | `qml6-module-qtwebengine` |

> **Note:** After installing these, restart your session or run `systemctl --user restart plasma-plasmashell`.

## 🛍 Install from KDE Store (Recommended)
1. Right-click your Panel or Desktop.
2. Select **Add Widgets...** -> **Get New Widgets** -> **Download New Plasma Widgets**.
3. Search for **Advanced Weather Widget**.
4. Click **Install**.

##  Manual Installation (Development)
If you prefer to install from source:
```bash
git clone https://github.com/pnedyalkov91/advanced-weather-widget.git && cd advanced-weather-widget
kpackagetool6 --type Plasma/Applet --install .
rm -rf ~/.cache/plasmashell/qmlcache
systemctl --user restart plasma-plasmashell
```

---

# ✨ Detailed Features

### 📍 Location Management
- **Precision:** Automatic detection via GeoClue2/IP or manual search with dual geocoding (Open-Meteo + Nominatim).
- **Map Picker:** Integrated OpenStreetMap preview to pin your exact location.
- **Smart Data:** Automatic timezone, altitude detection, and localized city names.

### 🌦 Weather Providers & Adaptive Mode
- Choose from **10 different providers** including Open-Meteo, MET Norway, OpenWeatherMap, WeatherAPI, Pirate Weather, Tomorrow.io, Visual Crossing, StormGlass, Weatherbit, and QWeather.
- **Adaptive Failover:** Automatically cycles through providers if one goes offline, ensuring you never have a dead widget.

### 🌡 Data Points
- **Core:** Temp (Current/Apparent/Dew), Wind (Speed/Direction), Humidity, Pressure, Visibility.
- **Environment:** UV Index, Air Quality (CAQI), Pollen (Universal Index), Space Weather (Kp index, G-index, aurora probability).
- **Astronomy:** Configurable Sun Arc (Sunrise/Set) and Moon Path (Phases/Rise/Set).
- **Alerts:** Real-time push notifications from MeteoAlarm, NOAA NWS, and provider-specific sources.

### 🖥 Customization
- **Panel Layouts:** Single line, Multiline (scrolling), or Simple (compact icon + temp).
- **Themes:** 6 icon themes (Symbolic, Font, Flat, 3D, KDE) plus a custom per-item picker.
- **Visuals:** Fully interactive Radar Map (RainViewer), 16-day Daily Forecast, and scrolling Hourly Forecast.

---

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
- **Spanish** - [NecaX](https://github.com/NecaX)
- **Chinese (Traditional)** - [Yo-oo](https://github.com/Yo-oo)

## External resources

- This project uses weather icons and font resources from: https://github.com/erikflowers/weather-icons
  Licensed under SIL OFL 1.1 (http://scripts.sil.org/OFL)

- This project uses code from the SunCalc library: https://github.com/mourner/suncalc
  Copyright (c) Vladimir Agafonkin
  Licensed under the BSD license

- The Radar tab uses the **RainViewer API** for weather radar data: https://www.rainviewer.com/

- The Radar tab uses **Leaflet.js** for interactive map rendering: https://leafletjs.com/
  Copyright (c) 2010–2024 Vladimir Agafonkin
  Licensed under BSD 2-Clause License

- Map tiles provided by **OpenStreetMap**: https://www.openstreetmap.org/copyright
  © OpenStreetMap contributors, licensed under ODbL

## ❤️ Support the project

Advanced Weather Widget is developed in my free time.

If you enjoy using it, you can support the project:

- Liberapay: https://liberapay.com/pnedyalkov
- PayPal: https://paypal.me/pnedyalkov91
- Revolut: https://revolut.me/petarnedyalkov91
