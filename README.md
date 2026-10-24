<div align="center">
  <img src="docs/logo.png" alt="Bili" width="140" style="border-radius: 28px;">

# Bili (云上太学)

**深度适配华为 HDS (Huawei Design System) 沉浸质感的 HarmonyOS / ArkTS 第三方 bilibili 客户端**

`HarmonyOS NEXT` `ArkTS` `UIDesignKit / HDS` `bilibili` `第三方客户端`

---

</div>

> 📌 **项目溯源**：本项目 Fork 自开源项目 [chunwcc/yunshang-bili](https://github.com/chunwcc/yunshang-bili)。在原项目优秀的哔哩哔哩业务接口与流媒体播放器架构基础上，本项目专注于针对 HarmonyOS NEXT 平台特性的深度现代化重构，**全面接入并落地华为官方 HDS (UIDesignKit) 沉浸式质感设计规范**，打造符合鸿蒙高阶美学的系统级视觉与交互体验。
>
> ⚠️ **本项目为非官方的第三方开源学习项目，与 bilibili 官方无任何关联，也未获得其授权。项目图标与名称均为独立设计，不包含商业素材。**

---

## ✨ 核心亮点：深度适配华为 HDS 设计系统 (UIDesignKit)

本项目深入践行 HarmonyOS NEXT 的 **HDS (Huawei Design System)** 设计规范与官方 `@kit.UIDesignKit` 能力，对整套客户端的视觉容器、导航层级、材质光效与交互流转进行了体系化重塑：

### 1. 沉浸式导航与标题栏体系 (`HdsNavDestination` / `HdsNavigation`)
- **系统级标题栏规范**：个人空间页 (`UpSpacePage`)、私信消息页 (`WhisperPage`)、关于页 (`AboutPage`)、收藏夹 (`FavoritesPage`) 等页面全量接入 `HdsNavDestination` / `HdsNavigation` 架构。
- **动态磨砂渐变动效**：标题栏启用 `ScrollEffectType.GRADIENT_BLUR` / `IMMERSIVE_GRADIENT_BLUR` 动态模糊；内容滑动时，标题栏从透底平滑过渡至精致级 (`EXQUISITE`) 沉浸磨砂，营造纵深立体空间感。
- **像素级避让与原生后退**：深度适配 `avoidLayoutSafeArea: true` 与顶部避让间距（`statusBarHeight + 56`），彻底杜绝系统状态栏与标题栏遮挡页面内容；同时完整保留原生返回按钮（`hideBackButton(false)`），完美响应标题栏点击与侧滑手势返回。

### 2. 沉浸光感材质与浮动交互 (`HdsTabs` / `barFloatingStyle`)
- **浮动光感底栏**：主页底栏全面拥抱 `HdsTabs` 的 `barFloatingStyle` 浮动条规范，挂载 `hdsMaterial.MaterialType.IMMERSIVE` 沉浸材质与 `MaterialLevel.ADAPTIVE` 自适应光感层级，光影随壁纸与深浅模式智能呼吸流动。
- **分段胶囊控制 (`SegmentButton`)**：
  - 个人空间、视频播放页等分段控制器采用沉浸光感玻璃槽包裹，移除固定高度限制，内部实现绝对垂直居中对齐；
  - 选中胶囊背景动态响应全局自定义主题色，字体颜色锁定高对比度白字（`#FFFFFF`），达成背景随主题变、文字清晰高可读性的完美平衡。
- **浮动迷你栏按钮 (`HdsMiniBarButton`)**：在搜索栏编辑触发、消息输入栏、智能抓手回到顶部等高频交互热区中，全面应用具备光影边缘反射的微型材质按钮。

### 3. 全局二级模态规范化 (`HdsNavigation` 模态重构)
- **拒绝割裂弹窗**：重构个人中心 (`ProfilePage`) 与个性化配置中心 (`PersonalizationPage`)，所有二级弹窗（深色模式切换、全局壁纸定制、主题色彩拾取器、横竖屏旋转策略等）统一收口至 `HdsNavigation` 模态卡片规范，交互动效与手势退出体验完全符合鸿蒙原生直觉。

### 4. 纸面编辑风与双模色彩系统
- **深浅双色全景覆盖**：配合 `ThemeController` 与 `ThemePersist` 架构，所有卡片背景、描边粗细（`hairline`）、磨砂遮罩透明度及文字对比度均经过明暗双模式精密调校。
- **圆角与留白系统**：统一重构个人信息卡片、动态卡片、视频网格的圆角规范（如卡片统一为 15vp），营造雅致通透的纸面现代排版风格。

---

## 一、重要声明（请先阅读）

### 1. 本仓库不附带任何真实凭据

代码中的 B 站客户端签名相关常量**已被置为占位符**：

| 文件 | 常量 |
|---|---|
| `entry/src/main/ets/utils/SignUtils.ets` | `AppSign.APP_KEYS` |
| `entry/src/main/ets/api/RecommendApiOptimized.ets` | `APP_KEY` / `APP_SEC` |

**签名算法本身完整保留**，但仓库不附带任何真实凭据值。若你需要调用相关接口，请自行准备合规的凭据。

### 2. 关于「仅供学习」

本仓库发布的是**学习用途的客户端实现**，请勿用于：
- 批量抓取、下载或二次分发受版权保护的内容
- 绕开付费墙、大会员权限等商业化限制
- 任何违反 bilibili 用户协议或适用法律的用途

使用者需自行承担其行为的一切后果。本项目的作者不对任何第三方的使用方式负责。

### 3. 默认登录方式已调整为 Web 扫码

为让开源版本**开箱即用、无需额外凭据即可登录**，`QrCodeLoginPage` 的 `isTvMode` 默认值设为 `false`，走公开接口 `passport.bilibili.com/x/passport-login/web/qrcode`。

---

## 二、功能概览

- 首页推荐流、热门、分区频道
- 视频播放（DASH / FLV，支持续播、倍速、画质切换、近 1:1 折叠屏横竖屏自适应）
- 弹幕渲染（滚动 / 顶部 / 底部 / 逆向，支持屏蔽规则与样式设置）
- 番剧影视（PGC）选集与分集进度上报
- 评论、回复、点赞、投币、收藏
- 动态、直播、私信、消息中心
- 个人空间（投稿、动态列表、粉丝/关注列表）
- 搜索、历史记录、离线缓存、观看历史

详见 [docs/功能清单.md](docs/功能清单.md)。

---

## 三、构建

### 环境要求

- DevEco Studio（建议 5.0+）
- HarmonyOS SDK：`compileSdkVersion 26.0.0`，`compatibleSdkVersion 6.1.0(23)`
- Node.js 与 hvigor（随 DevEco Studio 安装）

### 步骤

1. 用 DevEco Studio 打开本目录，等待依赖同步完成
2. **配置签名**：`File → Project Structure → Signing Configs`，使用你自己的证书
   （仓库内的 `build-profile.json5` 未包含签名配置，构建者需自行配置）
3. 连接设备或启动模拟器
4. `Build → Build Hap(s)/APP(s) → Build APP(s)`，或直接运行

命令行构建：

```bash
# 请替换为你本机的 SDK / Node 路径
export JAVA_HOME="<DevEco Studio 安装目录>/jbr"
export DEVECO_SDK_HOME="<HarmonyOS SDK 目录>"
node hvigorw.js --mode module -p module=entry@default -p product=default \
  -p requiredDeviceType=phone assembleHap --analyze=normal --no-daemon
```

---

## 四、目录结构

```
AppScope/                 应用级配置与图标
entry/src/main/ets/
  ├── api/                B 站各业务接口封装
  ├── components/         可复用 UI 组件（HdsNavigation、HdsTabs、Segment 封装）
  ├── model/              数据模型
  ├── pages/              页面实现
  ├── services/           弹幕渲染、DASH 转播、离线缓存等服务
  └── utils/              签名、主题持久化、日志与工具
docs/                     设计与排查文档
```

---

## 五、开源衍生与第三方代码声明

### 1. 衍生与重构声明

本项目基于开源项目 [chunwcc/yunshang-bili](https://github.com/chunwcc/yunshang-bili) 改造与重构开发。在继承原项目优秀的网络通信与播放器内核的基础上，重点进行了**全站 HDS (UIDesignKit) 沉浸质感规范重塑**、深色模式深度适配、模态层级统一与用户空间体验升级。

### 2. 第三方代码与参考

本项目包含以下**源自第三方**的组件，均已在文件头注明来源，各自的许可条款优先于本项目的 MIT：

| 文件 | 来源 | 许可 |
|---|---|---|
| `entry/src/main/ets/components/infra/HdsMiniBarButton.ets` | `ceshi/HdsButton_Component-main`（SummerKaze） | Apache-2.0 |
| `entry/src/main/ets/components/HdsTitleBarSegment.ets` | `DeadlinerNEXT/DeadlinerNEXT` | 参见其上游仓库 |

> `DeadlinerNEXT` 上游仓库在整理本文档时已无法访问（404）。
> 若你是该组件的作者或知晓其许可条款，请通过 Issue 联系，我们将按你的要求补充声明或移除该组件。

开发过程中部分接口设计与参数处理参考了 [PiliPlus](https://github.com/qinshah/PiliPlus)（Dart 实现，本项目为 ArkTS 重写，未复制源码）。

---

## 六、许可

本项目自身代码使用 **MIT License**，详见 [LICENSE](LICENSE)。
