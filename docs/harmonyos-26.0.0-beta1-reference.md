# HarmonyOS 7 (API 26) Developer Beta 参考文档

> 来源：IT之家、华为开发者官网
> 更新时间：2026/08/02（已补充 26.0.0 Beta2）
> 注意：`harmonyos_knowledge_search` 尚未收录此版本内容，本文档为手动汇总

---

## 版本配套信息

### 26.0.0 Beta2（最新，2026/07/28 发布）

| 组件 | 版本 |
|------|------|
| API 版本 | **26.0.0 Beta2** |
| DevEco Studio | **26.0.0 Beta2 (26.0.0.621)** |
| SDK | HarmonyOS SDK 26.0.0 Beta2 (Ohos_sdk_public 26.0.0.32) |
| 发布时间 | **2026/07/28** |

### 26.0.0 Beta1（历史，2026/06/12 发布）

| 组件 | 版本 |
|------|------|
| API 版本 | 26.0.0 Beta1 |
| DevEco Studio | 26.0.0 Beta1 (26.0.0.461) |
| SDK | HarmonyOS SDK 26.0.0 Beta1 (Ohos_sdk_public 26.0.0.23) |
| 发布时间 | 2026/06/12 |

---

> 以下内容为 **Beta1 起已具备的特性**。Beta2 相对 Beta1 的新增与行为变更见文末「26.0.0 Beta2 新增与变更」章节。

## ArkUI — 沉浸光感与材质效果

### systemMaterial 属性
以下组件/元素新增配置项 `systemMaterial`，支持系统新材质效果：
- Toggle 组件
- Tips 组件悬浮气泡
- Toast
- 对话框
- 操作菜单
- 弹窗
- 自定义弹窗
- 半模态
- Popup

### Chip 组件材质
Chip 组件新增支持：
- `backgroundSystemMaterial` — 正常状态下的新材质背景
- `activatedBackgroundSystemMaterial` — 激活状态下的新材质背景

### 组件级沉浸光感
新增 ArkUI 组件级沉浸光感，提供一套高品质视觉与动效体系：
- 沉浸式系统新材质效果
- 空间动效
- 为应用组件带来通透、精致的视觉表现

### 弹窗背景模糊
提示弹窗背景支持新材质背景模糊效果。

### 全局组件复用
新增自定义组件全局复用能力：
- 可针对指定 `@Reusable`/`@ReusableV2` 复用组件配置复用池
- 用于提供全局复用的能力

### 标准悬浮窗
窗口管理新增标准悬浮窗：
- 悬浮在桌面/应用界面上的小型窗口
- 灵活的管理能力：判断设备是否支持、创建控制器以启动/更新/停止悬浮窗

---

## ArkWeb
- Chromium 内核从 **132 升级为 144** 版本

---

## Agent 能力
- 新增支持 **AgentCard**
- 提供 AgentCard 的配置、解析与持久化

---

## Graphics Accelerate Kit
- 新增**预启动特性**，提升游戏应用的启动体验

---

## Notification Kit
- 进一步增强通知管理能力和显示效果
- 支持以**半模态方式拉起应用的通知设置界面**

---

## Camera Kit
- 新增 C API，支持控制相机闪光灯
- 新增 ArkTS API，支持获取预览流图片数据

---

## Core File Kit
- 支持将沙箱目录共享为系统级可见

---

## Device Security Kit
- 增强星盾引擎能力
- 增强超级隐私管控能力

---

## 3D 与传感器
- 新增 ArkTS API，支持加载 **3D 高斯模型**
- 新增 ArkTS API、C API，支持获取外部相机和传感器数据进行计算

---

## ArkTS API
- 新增脚本信息的能力
- 新增用于管理 ModularObjectExtensionAbility 的 C API
  - 查询 ModularObjectExtensionAbility 信息
  - 连接与断开连接等能力

---

# 26.0.0 Beta2 新增与变更

> 更新来源：华为开发者官网版本说明（26.0.0 Beta2，2026/07/28）
> 本节仅列 Beta2 相对 Beta1 的**新增**与**行为变更**。

## ⚠️ 行为变更（涉及应用适配）

### 1. List 组件 onScrollVisibleContentChange 事件（API 12+，从 SDK 7.0.0.28 开始）
- **变更前**：列表从有数据切换为无数据时，`start`/`end` 参数复用旧值。
- **变更后**：该场景下 `start`/`end` 的 `index` 成员均为 **-1**，`itemGroupArea` 与 `itemIndexInGroup` 均为 `undefined`，符合空列表参数定义。
- **生效条件**：仅当 `targetSdkVersion ≥ 26.0.0` 时生效（已做版本隔离）。
- **适配**：事件回调中需判断 `start.index === -1 && end.index === -1` 作为"列表为空"分支。

### 2. ArkWeb Cookie 存储目录变更（API 9+，从 SDK 7.0.0.23 开始）
- **变更前**：Cookie 存储在应用缓存目录 `/data/storage/el2/base/cache/web/Cookies`，清空应用缓存会同时清除 Cookie（导致 Web 登录态丢失）。
- **变更后**：Cookie 存储在应用**数据目录**下，清空缓存不再清除 Cookie。
- **适配**：若应用期望"清空缓存时同时清除 Cookie"，需显式调用 `clearAllCookiesSync` / `clearAllCookies`。

---

## ArkUI（重点）

### 新增 V2 组件（基于状态管理 V2 实现）
- **ChipV2**、**ChipGroupV2**、**CounterV2**、**PopupV2**、**SwipeRefresherV2**、**TreeViewV2**
- ⚠️ 项目当前 V1 状态管理为主，接入这些组件需注意 V1/V2 不混用

### 新增容器与布局组件
- **LazyVWaterFlowLayout** — 懒加载瀑布流布局
- **LazyColumnLayout** — 懒加载垂直线性布局
- **LazyDynamicLayout** — 懒加载动态布局容器
- **DatePickerComponent** — 日期（年月日）与时间（时分秒）选择
- **SelectionContainer** — 跨节点文本选中、复制与菜单扩展

### 环境变量与状态
- **WithEnv** — 响应式环境变量容器
- **@CustomEnv** — 自定义环境变量装饰器
- **@ComponentActive / @ComponentInactive** — 组件非激活↔激活状态生命周期装饰器

### 材质与视觉
- `systemMaterial` 扩展：**Navigation**、**DatePickerDialog**、**SelectionMenu** 新增系统材质配置
- ChipGroup 新增 `backgroundSystemMaterial` / `activatedBackgroundSystemMaterial`
- 组件动态属性新增**悬浮状态样式**
- C API 新增沉浸式材质类型声明

### 手势与交互
- 新增**智慧手势**能力：使能、监听、选中态控制、动态决策行为
- 交互属性新增对智慧手势的响应
- 文本类组件新增**尾部缩进属性 `tailIndents`**（Text、属性字符串）

### 其他 ArkUI 增强
- OverlayManager 新增**按层级配置浮层**的能力
- 新增**调测标签**，帮助分辨同类节点，提升调试效率
- 窗口管理：支持设置主窗/子窗支持的窗口模式；闪控球新增**销毁事件监听**

---

## ArkTS
- `setMultithreadingDetectionEnabled` 新增多线程检测可配置参数（故障类型、采样频率、故障上报时间间隔）

---

## 其余 Kit 新增（精简）

| Kit | 新增能力 |
|-----|----------|
| Ability Kit | ModularObjectExtensionAbility 模块化对象（含 Taihe IPC）；pluginBundleManager 本地插件安装/卸载；自动填充请求信息定义 |
| Account Kit | 华为账号**亲密圈服务**（亲友添加与选择） |
| Agent Framework Kit | AgentAbilityExtension 智能体间 **A2A 协议通信** |
| **AOD Navigation Kit** 🆕 | 熄屏导航服务（轨迹、里程熄屏免解锁查看） |
| AppGallery Kit | 暂停下载任务；Car 设备支持（归因、隐私、图标、市场推荐等） |
| ArkData | 数据共享支持发布多值类型配置 |
| ArkGraphics 2D | 字体轮廓路径获取、字体回退能力 |
| **Confidential Space Kit** 🆕 | 机密空间：空间内运行数据应用、处理隐私数据 |
| Core File Kit | 新增**压缩解压缩模块** |
| Device Security Kit | 审计事件（开关机/音视频接口插拔/账户管理）；阻断类审计事件与超时阻断策略 |
| Enterprise Data Guard Kit | 进程管控时长管理（查询/设置策略） |
| Enterprise Space Kit | 切换工作空间；跨空间消息提醒配置 |
| Enterprise Threat Protection Kit | 威胁进程终止接口 |
| FAST Kit | 高性能排序、多项式零点求解、复数向量、高性能哈希表、系统优化 |
| Graphics Accelerate Kit | 游戏伴随服务（悬浮控件、状态感知、音频/画面采集） |
| **Linx Kit** 🆕 | 灵犀加速库：基于芯片底层软硬协同的 CPU 性能加速 |
| Map Kit | 折线文字、3D 地球背景、信号路线预测、离线地图未下载区域查询 |
| Media Kit | 广告插播、离线缓存下载、录屏暂停/恢复、指定窗口录屏、音频 PCM 处理 |
| Notification Kit | 锁屏通知开关字段；半模态拉起通知设置界面 |
| Online Authentication Kit | DID 去中心化身份（密钥生成、数字凭证管理、数据签名） |
| PDF Kit | 自定义渲染风格、二进制数据读取、坐标/矩形双向转换 |
| Pen Kit | 手写笔**跟手性加速**接口 |
| Performance Analysis Kit | 应用灰度采集、冻屏告警事件订阅、内存快照导出监听 |
| Remote Communication Kit | HTTP 版本选择、流式上传、QUIC 客户端、证书压缩、**国密 TLCP**、MPTCP |
| Scan Kit | 查询设备是否支持默认/自定义界面扫码 |
| Service Collaboration Kit | 碰一碰场景 API（触发连接、传递信息、断开连接） |
| **Service Support Kit** 🆕 | 设备硬件检测服务 |
| Spatial Recon Kit | 3DGS 高斯球编辑（选择/变换/上色/删除）；分块 3DGS 渲染 |
| UI Design Kit | 颜色选择与收藏（网格/光谱/滑块）；HdsSnackBar/HdsListItem 样式增强 |
| XEngine Kit | **控显分离**（折叠机上屏画面/下屏按键）；空域 AI 超分支持 Vulkan |

---

## 对项目（Bilibili 客户端）的潜在影响

1. **List 行为变更**：项目首页/搜索页若使用 `onScrollVisibleContentChange` 且未来升 targetSdk 到 26，需适配空列表 -1 场景（当前项目 targetSdk=6.1.1(24)，暂不生效）。
2. **ArkWeb Cookie**：若项目内使用 WebView 登录态存储，升级后清缓存不再丢 Cookie，行为更合理，无需改动。
3. **V2 组件**：ChipV2/SwipeRefresherV2 等未来可选，但需整体迁移状态管理（当前默认 V1）。
4. **系统材质**：弹窗/Toast/Navigation 支持 `systemMaterial`，可用于项目夜间模式适配。
