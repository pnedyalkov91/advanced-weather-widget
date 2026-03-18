# Advanced Weather Widget for KDE Plasma 6

A modern, highly customizable weather widget built specifically for KDE Plasma 6.

It delivers accurate forecasts, multiple weather provider support, adaptive failover logic, and extensive appearance customization — all while integrating naturally into the Plasma desktop.

---

## ✨ Key Features

### 📍 Location Management
- Automatic location detection (GeoClue2)
- Convenient manual city search
- Reverse geocoding using Nominatim (timezone & elevation detection)
- Support for non-Latin names (e.g. Cyrillic)

### 🌦 Multiple Weather Providers

Choose between:
- Open-Meteo
- met.no
- WeatherAPI (API key required)
- OpenWeather (API key required)

### 🔄 Adaptive Mode

- Automatically switches providers if one fails
- Improves reliability and availability
- Seamless fallback handling

### 🎨 Appearance Customization

Individually configurable appearance for:
- Panel mode
- Full widget mode
- Tooltip view

Additional options:
- Adjustable transparency
- Native Plasma blur support
- Flexible forecast layout
- Scrollbox mode

### ⚙ Advanced Personalization

- Unit configuration
- Provider selection
- Auto / manual location mode
- Clean first-run experience
- Extensive customization settings

---

## 🖼 Screenshots

### Panel Mode (Single line)
![Panel Mode Single Line](screenshots/panel_single_line.png)

### Panel Mode (Multiple lines)
![Panel Mode Multiple Lines](screenshots/panel_multi_lines.png)

### Widget from panel
![Widget From Panel](screenshots/widget_from_panel.png)

### Full Widget Mode
![Widget Mode Desktop](screenshots/widget.png)

### Tooltip View
![Tooltip](screenshots/tooltip.png)

### Settings – Location
![Settings Location](screenshots/location.png)

### Settings – General (Providers)
![Settings Providers](screenshots/providers.png)

### Settings – General (Appearance)
![Settings Appearance](screenshots/appearance.png)


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
- Kate/Kwrite  
- VS Code

4. Translate all strings by filling the `msgstr ""` fields.

Example:

```po
msgid "Configure icon…"
msgstr "Configurar ícone…"
```

5. When the translation is ready:

- open a **GitHub Issue** and attach the `.po` file (you may need to compress it as `.zip` because GitHub blocks `.po` attachments).
- open a **Pull Request** with the `.po` and `.mo` files  

### Translators

Thank you to everyone who contributed translations to this project ❤️

- **German** - [HolySoap](https://github.com/HolySoap)
- **Brazilian Portuguese** - [PauloAlbqrq](https://github.com/PauloAlbqrq)
- **Bulgarian** - Petar Nedyalkov (Author)
- **Dutch** - Heimen Stoffels (<vistausss@fastmail.com>)
- **Russian** - [Dmaliog](https://github.com/dmaliog)
- **French** - [LAZER-TY](https://github.com/LAZER-TY)

## 🎨 Icons & Fonts

This project uses weather icons and font resources from:
https://github.com/erikflowers/weather-icons 
Licensed under SIL OFL 1.1 (http://scripts.sil.org/OFL)

## ❤️ Support the project

Advanced Weather Widget is developed in my free time.

If you enjoy using it, you can supporting the project:

- Liberapay: https://liberapay.com/pnedyalkov
- PayPal: https://paypal.me/pnedyalkov91
- Revolut: https://revolut.me/petarnedyalkov91
