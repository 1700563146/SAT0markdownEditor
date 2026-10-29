# 预设主题配色方案

本文记录 2026-08-26 对应用预设主题配色的替换。新的浅色/深色主题配色
取自 Catppuccin、Rosé Pine、Nord、Tokyo Night、Dracula、Gruvbox 与
Solarized 等开源配色方案，并以 WCAG AA 可读性要求复核文字对比度。

## 深色主题

| 名称 | 来源 | 背景 | 表面 | 主文字 | 次要文字 |
| --- | --- | --- | --- | --- | --- |
| 摩卡夜色 | [Catppuccin Mocha](https://github.com/catppuccin/palette) | `#1E1E2E` | `#313244` | `#CDD6F4` | `#A6ADC8` |
| 松林暮色 | [Rosé Pine](https://github.com/rose-pine/palette) | `#191724` | `#26233A` | `#E0DEF4` | `#908CAA` |
| 极地冰蓝 | [Nord](https://github.com/nordtheme/nord) | `#2E3440` | `#3B4252` | `#E5E9F0` | `#81A1C1` |
| 东京夜蓝 | [Tokyo Night](https://github.com/folke/tokyonight.nvim) | `#1A1B26` | `#292E42` | `#C0CAF5` | `#A9B1D6` |
| 德古拉之夜 | [Dracula](https://github.com/dracula/dracula-theme) | `#282A36` | `#44475A` | `#F8F8F2` | `#BD93F9` |
| 复古炭灰 | [Gruvbox Dark](https://github.com/morhetz/gruvbox) | `#282828` | `#3C3836` | `#EBDBB2` | `#A89984` |

## 浅色主题

| 名称 | 来源 | 背景 | 表面 | 主文字 | 次要文字 |
| --- | --- | --- | --- | --- | --- |
| 拿铁奶油 | [Catppuccin Latte](https://github.com/catppuccin/palette) | `#EFF1F5` | `#E6E9EF` | `#4C4F69` | `#6C6F85` |
| 松林晨光 | [Rosé Pine Dawn](https://github.com/rose-pine/palette) | `#FAF4ED` | `#FFFAF3` | `#464261` | `#797593` |
| 东京晨蓝 | [Tokyo Night Day](https://github.com/folke/tokyonight.nvim) | `#E1E2E7` | `#FFFFFF` | `#3760BF` | `#68709A` |
| 复古暖纸 | [Gruvbox Light](https://github.com/morhetz/gruvbox) | `#FBF1C7` | `#F2E5BC` | `#3C3836` | `#7C6F64` |
| 日光暖黄 | [Solarized Light](https://github.com/altercation/solarized) | `#FDF6E3` | `#EEE8D5` | `#073642` | `#586E75` |

## 实现位置

- 预设主题定义：`lib/utils/constants.dart`
- 可读性测试：`test/utils/theme_scheme_test.dart`
- 主题设置入口：`lib/screens/settings/appearance_settings_screen.dart`
