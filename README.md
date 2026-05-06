# Advanced Weather Widget for KDE Plasma 6

A modern, highly customizable weather widget built specifically for KDE Plasma 6.

### Why this widget?
*   **Granular Precision:** Uses exact Latitude/Longitude coordinates for local data rather than generic city-level lookups.
*   **Modern UX:** A clean, native-feeling interface with smooth animations and intuitive layouts.
*   **Feature Rich:** From interactive radar maps and air quality to space weather and moon phases - everything is configurable.

## 📑 Table of Contents
- [📦 Installation](#-installation)
  - [⚠️ Prerequisites & Dependencies](#-prerequisites--dependencies)
  - [🛍 Install from KDE Store](#-install-from-kde-store-recommended)
  - [🛠 Manual Installation](#-manual-installation-development)
- [🖼️ Screenshots](#-screenshots)
- [✨ Detailed Features](#-detailed-features)
- [🌐 Translation](#-translation)
- [📚 External Resources](#external-resources)
- [🔑 Entering API Keys](#-entering-api-keys)
- [🐛 Bug Reports & Feedback](#-bug-reports--feedback)
- [❤️ Support](#-support-the-project)
- [📜 License](#-license)

---

# 📦 Installation

## ⚠️ Prerequisites & Dependencies
For the full functionality of this widget, please ensure you have the following Qt6 modules installed for your distribution:

### 📍 Location & Search
*Required for the Location map screen and GeoClue2 auto-detection.*

| Distribution | Package Name |
|---|---|
| **Fedora / RHEL** | `qt6-qtlocation` |
| **openSUSE** | `qt6-location` |
| **Arch Linux** | `qt6-location` |
| **Debian / Kubuntu / KDE Neon** | `qml6-module-qtlocation` `qml6-module-qtpositioning` |

### 📡 Radar Map
*Required for the interactive Radar tab (Chromium-based).*

| Distribution | Package Name |
|---|---|
| **Fedora / RHEL** | `qt6-qtwebengine` |
| **openSUSE** | `qt6-webengine` |
| **Arch Linux** | `qt6-webengine` |
| **Debian / Kubuntu / KDE Neon** | `qml6-module-qtwebengine` |

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

# 🖼️ Screenshots

<p align="center">
  <b>Panel Layout Styles</b><br>
  <img src="screenshots/panel/Single line.png" width="420" alt="Single line">
  <br>
  (<b>Single line:</b> A compact, one-row layout for a minimalist look.)
  <br><br>
  <img src="screenshots/panel/Simple mode.png" width="130" alt="Simple mode"> <br>  
    (<b>Simple mode:</b> Displays only the essential icon and current temperature.)
    <br><br>
  <img src="screenshots/panel/xfce style.png" width="130" alt="XFCE style"> <br>(<b>XFCE style:</b> A multiline display with an automatic scrollbox for detailed info.)
  <br><br>
  </p>

<p align="center">
  <b>Detailed Widget Layouts</b><br>
  <img src="screenshots/widget/advanced/advanced mode (cards).png" width="800" alt="Advanced Weather Widget (Advance mode)">
  <img src="screenshots/widget/advanced/advanced mode (list).png" width="800" alt="Advanced Weather Widget (List mode)">
  (<b>Advanced mode:</b> Choose between modern Cards or a clean List view.)
  <br><br>
  <img src="screenshots/widget/simple/simple mode (default).png" width="800" alt="Simple mode">
  <img src="screenshots/widget/simple/super simple.png" width="800" alt="Super Simple mode">
      (<b>Simple modes:</b> Focused views for those who want weather without the tabs.)
</p>

<p align="center">
  <b>Tabs</b><br>
  <img src="screenshots/widget/tabs/forecast.png" width="800" alt="Forecast tab">
  (Forecast tab)
  <br><br>
  <img src="screenshots/widget/tabs/radar.png" width="800" alt="Radar tab">
  (Radar tab)
</p>

# ✨ Detailed Features

### 📍 Location Management
- **Precision:** Automatic detection via GeoClue2/IP or manual search with dual geocoding (Open-Meteo + Nominatim).
- **Map Picker:** Integrated OpenStreetMap preview to pin your exact location.
- **Smart Data:** Automatic timezone, altitude detection, and localized city names.

### 🌦 Weather Providers & Adaptive Mode
- Choose from **10 different providers**.
- **Adaptive Failover:** Automatically cycles through providers if one goes offline, ensuring you never have a widget without data.

### 🔑 Entering API Keys
For providers that require an API key, you can enter it in the widget's settings:
1. Right-click on the widget in your panel or desktop.
2. Select **Configure Advanced Weather Widget**.
3. Navigate to the **General** settings.
4. Turn off **Adaptive** mode and choose your preferred provider.
5. Enter your API key in the corresponding field for your chosen provider.

| Provider | Key Required | Signup Link |
|---|---|---|
| **Open-Meteo / MET Norway** | No | - |
| **OpenWeatherMap** | **Yes** | [Sign Up](https://openweathermap.org/api) |
| **WeatherAPI** | **Yes** | [Sign Up](https://www.weatherapi.com/) |
| **Pirate Weather** | **Yes** | [Sign Up](https://pirateweather.net/) |
| **Tomorrow.io** | **Yes** | [Sign Up](https://www.tomorrow.io/weather-api/) |
| **Visual Crossing** | **Yes** | [Sign Up](https://www.visualcrossing.com/weather-data) |
| **StormGlass** | **Yes** | [Sign Up](https://stormglass.io/) |
| **Weatherbit** | **Yes** | [Sign Up](https://www.weatherbit.io/) |
| **QWeather** | **Yes** | [Sign Up](https://dev.qweather.com/) |

### 🌡 Data Points
- **Core:** Temp (Current/Apparent/Dew), Wind (Speed/Direction), Humidity, Pressure, Visibility.
- **Environment:** UV Index, Air Quality (CAQI), Pollen (Universal Index), Space Weather (Kp index, G-index, aurora probability).
- **Astronomy:** Configurable Sun Arc (Sunrise/Set) and Moon Path (Phases/Rise/Set).
- **Alerts:** Real-time push notifications from MeteoAlarm, NOAA NWS, and provider-specific sources.

### 🖥 Customization
- **Dual Temperature:** Option to display two different temperature metrics simultaneously (e.g., Actual + Apparent).
- **Panel Layouts:** Single line, Multiline (XFCE weather applet style with scrollbox), or Simple (compact icon + temp).
- **Widget Layouts:** Advanced (Details, Forecast and Radar tabs) and Simple (no tabs)
- **Themes:** 6 icon themes (Symbolic, Font, Flat, 3D, KDE) plus a custom per-item picker.
- **Visuals:** Fully interactive Radar Map (RainViewer), 16-day daily forecast, and hourly weather forecast.

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

You can check the current translation coverage in translation-status.md.

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
- **Chinese (Simplified)** - [Guokangz](https://github.com/Guokangz)
- **Czech** - [Zero-MF](https://github.com/Zero-MF)

---

## 🐛 Bug Reports & Feedback
If you encounter any issues or have suggestions, please open a [GitHub Issue](https://github.com/pnedyalkov91/advanced-weather-widget/issues). Please include your distribution, Plasma version, and the weather provider you were using.

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

---

## 📜 License

This project is licensed under the **GNU General Public License v2.0 or later**.
