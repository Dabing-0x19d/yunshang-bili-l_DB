# ProfilePage（我的页面）参考文档

> 生成日期：2025-07-18  
> 文件位置：`entry/src/main/ets/pages/ProfilePage.ets`  
> 用途：误删后快速恢复功能的参考文档

---

## 一、页面布局结构（build）

```
Stack                       ← 全屏透明背景，透出壁纸
├─ Scroll
│  └─ Column (padding: 16)
│     ├─ 头像卡片
│     ├─ [if isLandscape] ──────────────────────┐
│     │  ├─ Row(三功能按钮)                      │
│     │  │  ├─ 深色模式(图标+文字)               │
│     │  │  ├─ 个性化(图标+文字)                 │
│     │  │  └─ 历史记录(图标+文字)               │
│     │  └─ Grid(3列)                           │
│     │     ├─ 搜索发现 [Toggle]                 │
│     │     ├─ 上次看到这里 [Toggle]             │
│     │     ├─ 卡片样式 >                        │
│     │     ├─ 我的收藏 >                        │
│     │     └─ 关于我们 >                        │
│     └─ [else 竖屏] ─────────────────────────  │
│        ├─ Row(三功能按钮)                      │
│        │  ├─ 深色模式(图标+文字)               │
│        │  ├─ 个性化(图标+文字)                 │
│        │  └─ 历史记录(图标+文字)               │
│        └─ 逐个 SettingItem                    │
│           ├─ 搜索发现 [Toggle]                 │
│           ├─ 上次看到这里 [Toggle]             │
│           ├─ 卡片样式 >                        │
│           ├─ 我的收藏 >                        │
│           └─ 关于我们 >                        │
├─ bindSheet: 卡片样式底部弹窗 (CardStyleSheetContent)
└─ bindSheet: 个性化底部弹窗 (PersonalizationSheetContent)
```

---

## 二、选项功能清单（7 项）

### 2.1 头像卡片（内置，无单独 Builder）

| 属性 | 值 |
|---|---|
| 位置 | `build()` 内第一项 |
| 点击事件 | 已登录 → `showLogoutConfirm()`；未登录 → `goToLogin()` |
| 头像 | 已登录有URL → `Image`；否则 `Circle` |
| 用户名称 | `userDisplayName` 状态变量 |
| 提示文字 | 已登录：`点击退出登录`；未登录：`点击登录，获取个性化推荐` |
| 样式 | `getCardItemBg()` 背景，圆角 24，阴影 `16,#1A000000` |

**恢复要点：**
```typescript
Column() {
  if (this.isLoggedIn && this.userAvatarUrl) {
    Image(this.userAvatarUrl).width(72).height(72).borderRadius(36).objectFit(ImageFit.Cover).margin({ bottom: 12 })
  } else {
    Circle({ width: 72, height: 72 })
      .fill(this.isLoggedIn ? this.customThemeColor : (this.isDarkMode ? '#333333' : '#E0E0E0'))
      .margin({ bottom: 12 })
  }
  Text(this.userDisplayName).fontSize(20).fontWeight(FontWeight.Medium)
    .fontColor($r('app.color.color_primary_text'))
  if (this.isLoggedIn) {
    Text('点击退出登录').fontSize(14).fontColor(this.customThemeColor).margin({ top: 8 }).fontWeight(FontWeight.Medium)
  } else {
    Text('点击登录，获取个性化推荐').fontSize(14).fontColor(this.customThemeColor).margin({ top: 8 }).fontWeight(FontWeight.Medium)
  }
}
.width('100%').padding(20)
.backgroundColor(this.getCardItemBg())
.borderRadius(24).margin({ top: 20, bottom: 16 })
.shadow({ radius: 16, color: '#1A000000', offsetY: 4 })
.onClick(() => {
  if (this.isLoggedIn) { this.showLogoutConfirm(); }
  else { this.goToLogin(); }
})
.clickEffect({ level: 0, scale: 0.9 })
```

---

### 2.2 深色模式（三功能按钮，横竖屏各一份）

| 属性 | 值 |
|---|---|
| Builder | 内联（横竖屏 copy-paste 重复） |
| 图标 | `$r('app.media.ic_settings_darkmode')`（深色）/ `$r('app.media.sun_min')`（浅色） |
| 点击 | `this.onDarkModeChange(!this.isDarkMode)` |
| 布局 | 140px 高 Column，图标 32×32 + 文字，居中 |
| 背景 | `getCardItemBg()`，圆角 20 |

**`onDarkModeChange()` 方法：**
```typescript
private async onDarkModeChange(isOn: boolean): Promise<void> {
  this.isDarkMode = isOn;
  AppStorage.set('isDarkMode', isOn);
  // 同步系统级色彩模式（HDS组件适配）
  getContext(this).getApplicationContext().setColorMode(
    isOn ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
         : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
  );
  await StatusBarUtils.updateStatusBarColor(getContext(this), isOn);
  await this.saveSettings();
  vibrator.vibrate(50);  // 震动反馈
  promptAction.showToast({ message: isOn ? '已切换深色模式' : '已切换浅色模式', duration: 1500 });
}
```

---

### 2.3 个性化（三功能按钮，横竖屏各一份）

| 属性 | 值 |
|---|---|
| Builder | 内联 |
| 图标 | `$r('app.media.ic_settings_personalize')` |
| 点击 | `this.goToPersonalization()` → `this.isPersonalizationSheetShow = true` |
| 弹出方式 | `bindSheet` 底部弹窗，`FIT_CONTENT` 高度 |
| 弹窗内容 | `PersonalizationPage` 组件（独立文件） |

**涉及文件：** `entry/src/main/ets/pages/PersonalizationPage.ets`

---

### 2.4 历史记录（三功能按钮，横竖屏各一份）

| 属性 | 值 |
|---|---|
| Builder | 内联 |
| 图标 | `$r('app.media.ic_settings_history')` |
| 点击 | `this.goToWatchHistory()` → `router.pushUrl({ url: 'pages/WatchHistoryPage' })` |

**跳转文件：** `entry/src/main/ets/pages/WatchHistoryPage.ets`

---

### 2.5 搜索发现 / 上次看到这里（Toggle 开关）

| 属性 | 搜索发现 | 上次看到这里 |
|---|---|---|
| Builder | 横屏：`SimpleSettingItem(…, true, …)` / 竖屏：`SettingItemWithToggle` | 同左 |
| 图标 | `$r('app.media.ic_public_search_filled')` | `$r('app.media.arrow_clockwise')` |
| StorageKey | `showSearchDiscovery` | `showRefreshSeparator` |
| 默认值 | `true` | `true` |
| 设置方式 | `AppStorage.set('showSearchDiscovery', value)` | `AppStorage.set('showRefreshSeparator', value)` |

**`SettingItemWithToggle` 恢复代码：**
```typescript
@Builder
SettingItemWithToggle(icon: ResourceStr, title: string, isOn: boolean, onChange: (isOn: boolean) => void) {
  Row() {
    Image(icon).width(24).height(24)
      .fillColor(this.isDarkMode ? '#E5E5E5' : '#333333')
      .margin({ right: 14 })
    Text(title).fontSize(16).fontColor(this.isDarkMode ? '#E5E5E5' : '#333333')
      .fontWeight(FontWeight.Medium)
    Blank()
    Toggle({ type: ToggleType.Switch, isOn: isOn })
      .selectedColor(this.customThemeColor)
      .switchPointColor(Color.White)
      .onChange((value: boolean) => { onChange(value); })
  }
  .width('100%').height(56)
  .backgroundColor(this.getCardItemBg())
  .borderRadius(20).padding({ left: 18, right: 18 }).margin({ bottom: 16 })
  .shadow({ radius: 8, color: '#0D000000', offsetY: 2 })
  .clickEffect({ level: 0, scale: 0.95 })
}
```

---

### 2.6 卡片样式（导航入口）

| 属性 | 值 |
|---|---|
| Builder | 横屏：`SimpleSettingItem(…, false, …)` / 竖屏：`SettingItem` |
| 图标 | `$r('app.media.transparency_lock')` |
| 点击 | `this.isCardStyleSheetShow = true` |
| 弹出方式 | `bindSheet` 底部弹窗，`FIT_CONTENT` 高度 |
| 弹窗内容 | `CardStyleSheet` 组件（独立文件） |

**涉及文件：** `entry/src/main/ets/pages/CardStyleSheet.ets`

**`SettingItem` 恢复代码：**
```typescript
@Builder
SettingItem(icon: ResourceStr, title: string, onClick: () => void) {
  Row() {
    Image(icon).width(24).height(24)
      .fillColor(this.isDarkMode ? '#E5E5E5' : '#333333')
      .margin({ right: 14 })
    Text(title).fontSize(16).fontColor(this.isDarkMode ? '#E5E5E5' : '#333333')
      .fontWeight(FontWeight.Medium)
    Blank()
    Text('›').fontSize(28)
      .fontColor($r('app.color.color_primary_text'))
      .fontWeight(FontWeight.Bold)
  }
  .width('100%').height(56)
  .backgroundColor(this.getCardItemBg())
  .borderRadius(20).padding({ left: 18, right: 18 }).margin({ bottom: 16 })
  .shadow({ radius: 8, color: '#0D000000', offsetY: 2 })
  .clickEffect({ level: 0, scale: 0.95 })
  .onClick(() => { onClick(); })
}
```

---

### 2.7 我的收藏（导航入口）

| 属性 | 值 |
|---|---|
| Builder | 横屏：`SimpleSettingItem(…, false, …)` / 竖屏：`SettingItem` |
| 图标 | `$r('app.media.ic_settings_favorites')` |
| 点击 | `this.goToFavorites()` → `router.pushUrl({ url: 'pages/FavoritesPage' })` |

**跳转文件：** `entry/src/main/ets/pages/FavoritesPage.ets`

---

### 2.8 关于我们（导航入口）

| 属性 | 值 |
|---|---|
| Builder | 横屏：`SimpleSettingItem(…, false, …)` / 竖屏：`SettingItem` |
| 图标 | `$r('app.media.ic_settings_about')` |
| 点击 | `this.goToAbout()` → `router.pushUrl({ url: 'pages/AboutPage' })` |

**跳转文件：** `entry/src/main/ets/pages/AboutPage.ets`（已删除 B站推荐助手内容，仅保留标题栏）

---

## 三、Builder 组件汇总

| Builder | 用途 | 参数 |
|---|---|---|
| `SettingItemWithValue(icon, title, value, onClick)` | 左侧图标+标题，右侧文本+› | 用于展示值 |
| `SettingItemWithToggle(icon, title, isOn, onChange)` | 左侧图标+标题，右侧 Switch 开关 | 搜索发现、上次看到这里（竖屏） |
| `SettingItem(icon, title, onClick)` | 左侧图标+标题，右侧 › 箭头 | 卡片样式、我的收藏、关于我们（竖屏） |
| `SimpleSettingItem(icon, title, isToggle?, isOn?, onChange?, onClick?)` | 通用，isToggle 控制显 Switch 还是 › | 仅横屏 Grid 中使用 |
| `PersonalizationSheetContent()` | 个性化弹窗 | — |
| `CardStyleSheetContent()` | 卡片样式弹窗 | — |

---

## 四、StorageLink 状态变量

| AppStorage Key | 类型 | 默认值 | 用途 |
|---|---|---|---|
| `isDarkMode` | `boolean` | `false` | 深色/浅色模式 |
| `wallpaper` | `string` | `'default'` | 壁纸主题 |
| `customWallpaper` | `string` | `''` | 自定义壁纸路径 |
| `wallpaperBlur` | `number` | `0` | 壁纸模糊度 |
| `wallpaperDarkness` | `number` | `50` | 壁纸暗度 |
| `customThemeColor` | `string` | `'#007DFF'` | 主题色 |
| `biliCookie` | `string` | `''` | B站登录 Cookie |
| ~~`atomgitToken`~~ | ~~`string`~~ | ~~`''`~~ | ~~已删除~~ |
| ~~`atomgitUser`~~ | ~~`string`~~ | ~~`''`~~ | ~~已删除~~ |
| `hideStatusBar` | `boolean` | `false` | 隐藏状态栏 |
| `showSearchDiscovery` | `boolean` | `true` | 搜索发现开关 |
| `showRefreshSeparator` | `boolean` | `true` | 上次看到这里开关 |
| `cardTransparentStyle` | `boolean` | `false` | 卡片透明模式 |
| `cardBorderFollowTheme` | `boolean` | `false` | 卡片边框跟随主题 |
| `cardBgOpacity` | `number` | `30` | 卡片背景透明度 |
| `refreshHomeFlag` | `number` | `0` | 刷新首页标记（@StorageProp） |

---

## 五、关键方法

### 导航/跳转
```typescript
goToLogin()            → QrCodeLoginPage
goToPersonalization()  → show PersonalizationSheet
goToAbout()            → AboutPage
goToFavorites()        → FavoritesPage
goToWatchHistory()     → WatchHistoryPage
goToHistory()          → 同上（别名）
```

### 生命周期/设置
```typescript
aboutToAppear()        → loadSettings() + getStatusBarHeight() + listenOrientationChange() + onLoginStateChanged()
loadSettings()         → 从 preferences 加载全部设置
saveSettings()         → 保存到 preferences
onLoginStateChanged()  → 监听 refreshHomeFlag 变化，更新登录状态
onDarkModeChange()     → 切换深色模式 + 保存 + 震动 + Toast
showLogoutConfirm()    → 弹 Dialog 确认后 doLogout()
doLogout()             → 清除 biliCookie + 刷新首页
```

---

## 六、涉及的其他文件清单

| 文件 | 用途 |
|---|---|
| `pages/QrCodeLoginPage.ets` | B站扫码登录 |
| `pages/WatchHistoryPage.ets` | 观看历史 |
| `pages/FavoritesPage.ets` | 我的收藏 |
| `pages/AboutPage.ets` | 关于我们（已精简） |
| `pages/PersonalizationPage.ets` | 个性设置弹窗 |
| `pages/CardStyleSheet.ets` | 卡片样式弹窗 |
| `utils/StatusBarUtils.ts` | 状态栏颜色管理 |
| `api/BilibiliApi.ts` | 用户信息 API（`getUserInfo`） |

---

## 七、误删恢复要点

1. **ProfilePage.ets 核心结构**：`export struct ProfilePage` 含约 30 个 `@StorageLink` + 约 10 个 Builder + `build()` 内横竖屏两套 UI。
2. **三功能按钮行（深色/个性化/历史记录）** 在横竖屏中代码完全重复，各 3 个 Column，高 140px，layoutWeight 均分。
3. **横屏 Grid 用** `columnsTemplate('1fr 1fr 1fr')` 排 5 个 GridItem。
4. **竖屏依次调用** `SettingItemWithToggle` + `SettingItem`。
5. **两个 bindSheet** 分别绑定 `isPersonalizationSheetShow` 和 `isCardStyleSheetShow`。
6. **`main_pages.json`** 需注册所有 router 跳转的目标页面。
