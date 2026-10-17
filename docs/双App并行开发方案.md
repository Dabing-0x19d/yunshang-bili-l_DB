# 双 App 并行开发方案（现有 B 站播放器 + 新多源媒体客户端）

> 2026-09-19 定稿。目标：**一款保持现在的（B 站客户端，继续迭代），一款新做（Emby/Jellyfin/WebDAV/SMB/IPTV 等多源媒体客户端，要上架）**，
> 且公共能力只维护一份。

## 一、结论

**两个独立工程 + 公共能力按阶段收敛成 HAR。** 不要把两个 App 塞进同一个工程的多 product 里。

## 二、三条路对比

| 方案 | 做法 | 优点 | 致命问题 |
|---|---|---|---|
| **A（推荐）两工程 + HAR** | 旧工程不动；新工程独立；公共件抽成 HAR 双向复用 | 发布节奏、签名、版本、崩溃面完全隔离；公共件仍是一份 | 需要做 HAR 抽取（有工作量） |
| B 单工程双 product + 双 target | 官方「多目标产物构建」，`products[]` 各配 `bundleName/icon/签名/vendor`，模块内按 `target` 定制源码集 | 官方支持；一次改动两边生效 | 官方语境是**同一 App 的多变体**（免费/付费、社区/专业/旗舰）。两个 App 是**整体性差异**，用 target 分源码集等于在每个文件里假装共享，IDE 索引与回归风险都变得很难看；一处公共件改动会让另一款回归，而你只有一个人的回归能力 |
| C 直接复制一份工程分叉 | 拷贝 83k 行改 | 5 分钟就能开始 | 3 个月后两份分叉，改一处要改两遍。**你工程里已经吃过这苦头**（同款外观 Builder 出现过 8 份副本，见长期记忆红线 9） |

> 官方文档出处：华为《能力说明 · 定制多目标构建产物》——"一个工程可以定义多个 product，每个 product 对应一个定制化应用包"，
> 定制维度含 HAP 包名、deviceType、**source 源码集**、resource、buildOption、distributionFilter。它是为"同产品多变体"设计的。

## 三、推荐路径：两阶段（先快后净）

**阶段 1（现在 → 新 App 第一个可用版）：拷贝起步。**
新工程从旧工程点名拷文件，不建 HAR。理由：新 App 的接口边界还不知道长什么样，此时做抽象就是过度设计，还会拖慢进度。

**阶段 2（新 App 播放/UI 稳定后）：收敛 HAR。**
把两边都在用、且已经稳定的模块抽成 HAR，逐块替换。**一次只抽一块，抽完立刻跑两边真机回归。**

### 目录布局

```
D:\HWXM\
├── MyApplication3\        ← 现有 B 站客户端（继续迭代，本方案不改它一行）
├── media-app\             ← 新 App（独立工程，独立 bundleName，要上架）
│   ├── AppScope\          ← 应用名 / 图标 / 版本
│   └── docs\拷贝清单.md    ← ⭐ 防漂移台账（见第六节）
└── libs\                  ← 阶段 2 才建：HAR 集合（独立 git 仓库）
    ├── harmony-commons\   ← Logger / ImageUrl / ThemeColor / GenericDataSource / 格式化
    ├── harmony-ui-kit\    ← HDS 封装 / 卡片 / 悬浮按钮 / 主题
    ├── harmony-player-core\ ← AVPlayer 内核 + 控制层 + 手势 + 小窗 + 全屏
    └── harmony-danmaku-core\ ← 弹幕引擎（新 App 若做弹幕/歌词才需要）
```

## 四、操作清单（按顺序，每步都有验收点）

| 步 | 动作 | 验收点 |
|---|---|---|
| **0** | 定身份：新 App 的 `bundleName`、应用名、上架主体（个人 / 企业，决定 APP 备案路径） | 写出三行决定，写进新工程 README |
| **1** | 在 `D:\HWXM\` 新建空工程 `media-app`（Empty Ability） | `assembleHap` 出包并能装到手机 |
| **2** | 拷**零风险纯工具**：`Logger` / `ImageUrl` / `ImageCache` / `ThemeColor` / `GenericDataSource` / `NumberFormat` / `TimeFormat` / `VibrateUtils` / `StatusBarUtils` | 编译通过；建 `docs\拷贝清单.md` 登记每个文件的来源与日期 |
| **3** | 拷 **UI 基建**：`HdsMiniBarButton` / `MaterialLevel` / `HdsTitleBarSegment` / `FullImagePreview` / `ImmersiveLightWrapper` | 主页能出一个悬浮回顶按钮、能开全屏图预览 |
| **4** | 拷 **播放内核**并把 B 站耦合剪干净：`VideoPlayerPage` 的播放/手势/全屏/小窗部分 + `VideoControls`。剪掉：弹幕按钮、三连、选集、UP 信息、画质切换（B 站 playurl 逻辑） | 能播一个本地 mp4 + 一个 HTTP mp4，能全屏旋转、能拖进度 |
| **5** | 走 P0 业务：`MediaSource` 抽象 + Emby/Jellyfin 适配器 + 本地文件夹 + WebDAV + 多源管理 | 能从你自己的 Emby 服务器浏览库、进详情、播放、进度回传 |
| **6** | **收敛期**：抽 HAR（顺序：commons → ui-kit → player-core → danmaku-core），两个工程都改为 `file:` 依赖 | 每次抽一块，两个 App 各跑一次真机回归 |

## 五、身份隔离清单（两款 App 必须完全分开）

| 项 | 现有 B 站款 | 新媒体款 |
|---|---|---|
| bundleName | 已定（**已上架则不可改**） | 全新，且上架后不可改 ⇒ 第 0 步就定死 |
| 签名 | 本机 debug 证书即可（建议**不做上架**：第三方平台客户端有版权/商标风险） | 需**发布证书 + 上架 profile**，与调试签名分开配 |
| 版本号 | 独立 | 独立 |
| 应用名 / 图标 / AppScope | 独立 | 独立 |
| 备案 / 软著 | 自用可不做 | 上架必须做 |

## 六、防漂移纪律（阶段 1 的关键，别省）

拷贝起步最大的风险是"两份副本悄悄跑偏"——你的工程里 `resizeImageUrl` 曾散落 8 份、`dynTextSegmentsBuilder` 有 2 份，就是同一个坑。所以：

1. 每拷一个文件，**当天**记进 `media-app/docs/拷贝清单.md`：源路径、目标路径、日期、为什么拷。
2. 在清单顶部写死一句：「**本清单里的文件在新 App 第一个可用版发布前，必须完成 HAR 收敛。**」
3. 阶段 1 期间，**旧工程里这些文件如果改了修 bug，必须同步到新工程**（清单就是同步检查表）；不同步就等于埋雷。
4. 阶段 2 收敛完成后，删除清单、改为 `file:` 依赖，两边物理上只剩一份。

## 七、已知坑（提前写在墙上）

1. **HAR 的 `file:` 依赖是"拷贝"不是"软链"**：ohpm 会把 HAR 内容同步进 `oh_modules`。改了 HAR 源码但没重新同步 ⇒ 新 App 里"改了没生效"，能白折腾半天。收敛期每次改完 HAR 都要重新 install/sync。
2. **`useNormalizedOHMUrl: true`（你工程 strictMode 里开着）会影响跨模块 import 解析**：抽 HAR 是跨模块引用，必须和这个开关一起验证。旧工程改动前先确认这条。
3. **`build-profile.json5` 继续不提交**（长期记忆红线 14：IDE 每次会改口令值）；新工程照做。
4. **别用 ZCode 之类的 AI IDE 打开这两个工程**（红线 14：该工具曾把本仓库完整 git 历史静默外传）。新工程也别放 C 盘、桌面。
5. 新工程的目标 SDK 必须用 **Release 版 SDK**（红线 12），否则上架直接触发「使用了 beta 版本 API」拒审。
6. 阶段 1 期间**旧工程一行不改**。旧工程今天的 DASH 修复已经稳定，不要为了"顺手统一"去动它。

## 八、时间预期（AI 协同口径）

| 里程碑 | 内容 | 日历时间 |
|---|---|---|
| M0 | 第 0~2 步：建工程 + 身份 + 纯工具 | 1~2 天 |
| M1 | 第 3~4 步：UI 基建 + 播放内核移植，能播本地/HTTP 视频 | 2~3 天 |
| M2 | 第 5 步：Emby/Jellyfin + 本地 + WebDAV 跑通（= 之前 P0） | 3~5 天 |
| M3 | 收敛期第 6 步：HAR 抽取，两边各回归一次 | 1~2 天 |
| 之后 | P1/P2/P3（多源扩展、硬骨头、可选功能） | 见另一份估时 |

**M0~M3 合计约 1~1.5 周**，之后你就有了"两款并行、公共件一份"的干净结构。
