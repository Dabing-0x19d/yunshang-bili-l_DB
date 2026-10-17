# 离线缓存页内嵌播放功能 — 实施计划

> 目标：在离线缓存页面直接播放已完成的缓存视频（不跳转 VideoPlayerPage）。
> 点击已完成条目 → 封面放大为 16:9（横屏）或竖屏比例 → 原位内嵌播放 → 其他列表项被放大封面挤开。

## 一、现状与关键代码位置

### 1.1 离线缓存页
- 文件：`entry/src/main/ets/pages/OfflineCachePage.ets`（约 397 行）
- 结构：`List { ForEach(items) { ListItem { Row { 封面Stack / 信息Column / 操作按钮 } } } }`
- ForEach key：`` `${bvid}_${cid}_${status}` ``（已稳定化，进度由 `CacheItemProgress` 子组件轮询刷新）
- 点击已完成条目 → `playItem(item)`（第 81 行附近）→ `router.pushUrl('pages/VideoPlayerPage')` 跳转
- 已有子组件：`CacheItemProgress`（文件顶部，@Component，内部 setInterval 轮询进度）

### 1.2 本地缓存文件
- `OfflineCacheService` 缓存目录：`filesDir/offline/{bvid}_{cid}/`
  - `video.m4s`（DASH 视频轨 / FLV 完整流）
  - `audio.m4s`（DASH 音频轨，仅分离流时存在）
- 条目模型：`entry/src/main/ets/model/OfflineCacheItem.ts`（interface `OfflineCacheItem`，`CacheStatus` enum，`videoPath`/`audioPath` 为本地绝对路径）
- Service 读取：`OfflineCacheService.getInstance().getCachedItem(bvid, cid)`

### 1.3 现有离线播放参考（重要！直接抄这部分逻辑）
- 文件：`entry/src/main/ets/pages/VideoPlayerPage.ets`
- 离线播放初始化（第 2931-2949 行）：
  - `media.createAVPlayer()`（import `media` from `@kit.MediaKit`）
  - 视频：`fs.openSync(videoPath, fs.OpenMode.READ_ONLY)` → `AVFileDescriptor { fd, offset: 0 }` → `av.fdSrc = vFd`（**用 fdSrc，兼容 API 24/26；不要用 createMediaSourceWithUrl/Fd**）
  - 音频（若有）：第二个 AVPlayer，同样 fdSrc
- 状态监听：`setupL()`（第 3014 行）监听 `av.on('stateChange')`；`setupAudioL()`（第 2987 行）监听音频播放器
- surface 绑定：`bindS()`（第 3217 行）`av.surfaceId = surfaceId`；`prepare()` → `play()`
- XComponent：`private xc: XComponentController = new XComponentController()`，`xc.getXComponentSurfaceId()`
- 释放：`av.release()`、`fs.closeSync(fd)`（第 2894-2901 行有离线 fd 关闭示例）

### 1.4 全局播放器冲突注意
- `entry/src/main/ets/services/PlayerService.ts`：全局播放器单例（视频最小化/悬浮窗用）
- `entry/src/main/ets/components/FloatingVideoButton.ets` 依赖它
- ⚠️ 列表页内嵌播放器是**独立的本地 AVPlayer 实例**，不要写入 PlayerService，避免与悬浮窗/全局播放状态冲突。切走/销毁时自行 release。

## 二、设计

### 2.1 交互
1. 点击已完成条目（status === COMPLETED）→ 该条目封面区展开
2. 封面从 68 高动画放大到 16:9（`width=屏宽-32, height=width*9/16`），或竖屏视频（`height=width*16/9` 按视频实际宽高比）
3. 展开区内渲染 `XComponent`（视频画面）+ 控制层（进度条、暂停/继续、关闭按钮）
4. 其他列表项被推下（List 高度布局自然挤开，`animateTo` 做过渡）
5. 点关闭/切到其他条目/离页 → 释放播放器、封面收起

### 2.2 组件拆分
新建 `entry/src/main/ets/components/OfflineInlinePlayer.ets`（内嵌播放器组件）：

```typescript
@Component
struct OfflineInlinePlayer {
  // 输入
  item: OfflineCacheItem        // 当前播放条目（用 @Prop 传 bvid/cid/videoPath/audioPath）
  // 输出：关闭回调
  onClose?: () => void

  // AVPlayer 双实例
  private av: media.AVPlayer | null = null
  private avAudio: media.AVPlayer | null = null
  private vFd: fs.File | null = null
  private aFd: fs.File | null = null
  private xc: XComponentController = new XComponentController()
  private surfaceId_: string = ''

  // 播放状态
  @State playing: boolean = false
  @State duration: number = 0        // 秒
  @State currentTime: number = 0     // 秒
  @State videoAspect: number = 16 / 9  // 视频实际宽高比（prepared 后读取）
}
```

要点：
- `aboutToAppear`：创建 AVPlayer → fdSrc → 等 XComponent surfaceId 就绪（`setTimeout` 轮询 `xc.getXComponentSurfaceId()`，参考 VideoPlayerPage resumeFromMinimized 的 300ms 重试模式）→ `bindS()` 绑定 surface → `prepare()` → `play()`，音频同步
- `aboutToDisappear`：`av.release()`、`avAudio.release()`、`fs.closeSync(fd)` 全部清理
- 进度：`av.on('timeUpdate')` 更新 `currentTime`；暂停/继续用 `av.pause()/play()` 双实例都调用
- 视频宽高比：prepared 后 `av.videoWidth / av.videoHeight`（若无则默认 16:9）
- 控制条：底部半透明渐变层 + Progress + 时间 + 暂停按钮 + 关闭按钮（关闭按钮回调 `onClose`）
- 关闭时**先 pause 双播放器再 release**，避免黑屏闪烁

### 2.3 页面改动（OfflineCachePage.ets）
- 新增状态：`@State playingBvid: string = ''`、`@State playingCid: number = 0`、`@State playerAspect: number = 16/9`（或直接存展开高度 `@State expandedHeight: number = 68`）
- `playItem(item)` 改为：
  - 若非 COMPLETED → return（保持现状）
  - `this.playingBvid = item.bvid; this.playingCid = item.cid;`（不跳转）
- 封面 Stack 改造（当前第 233-250 行附近）：
  - 若 `item.bvid === playingBvid && item.cid === playingCid`：高度 = 展开高度（16:9 或竖屏），内部 `OfflineInlinePlayer` + 动画
  - 否则：维持 120×68 封面
  - 外层用 `.animateTo({ duration: 300 }, ...)` 包裹高度变化，实现"挤开"过渡
- 行内操作按钮区：展开播放时隐藏暂停/继续按钮（或保留），点关闭后收起
- `aboutToDisappear`：清空 playingBvid/playingCid（组件自释放）

### 2.4 竖屏 19:6 / 16:9 说明
- 用户原话：「16比9或者竖屏的19比6」
- 实现：读取视频实际宽高比 `av.videoWidth/videoHeight`（prepared 后），
  - 宽 > 高 → 横屏：高度 = `width * 9 / 16`
  - 高 > 宽 → 竖屏：高度 = `width * 16 / 9`（竖屏全高播放）
- 展开高度由 `@State playerAspect` 驱动，prepared 后更新触发重排

## 三、实施步骤（按顺序）

### Step 1：新建 OfflineInlinePlayer.ets
1. import：`media` from `@kit.MediaKit`，`fileIo as fs` from `@kit.CoreFileKit`，`OfflineCacheItem` from model，`logInfo/logError` from Logger
2. 参照 VideoPlayerPage 第 2931-2949 行的离线 fdSrc 初始化写 `initPlayer()`
3. 参照第 3014 行 `setupL()` 写状态监听（stateChange：initialized→prepare，prepared→play，completed→pause+seek0；timeUpdate 更新进度；error 打日志）
4. 写 `bindSurface()`（轮询 surfaceId 就绪后 `av.surfaceId = id`；音频无需 surface）
5. build：`Stack { XComponent({ type: 'surface', controller: this.xc }) / 控制层 }`，控制层 = 渐变底 + Progress + 时间 + 播放/暂停按钮 + 关闭按钮
6. 释放逻辑 `releaseAll()`：pause → release → close fd

### Step 2：OfflineCachePage 接入
1. import `OfflineInlinePlayer`
2. 加 `@State playingBvid/playingCid/playerAspect`
3. 改 `playItem`：COMPLETED 时设置展开状态，不跳转
4. 改封面 Stack：命中展开 → `Column { OfflineInlinePlayer({ item, onClose: () => 收起 }) }` 高度动画；未命中 → 原封面
5. 封面 Image 尺寸：展开时占满；收起时 120×68
6. 收起逻辑：`this.playingBvid = ''; this.playingCid = 0;`（组件 aboutToDisappear 自动释放）

### Step 3：验证
1. `mcp__deveco-mcp__check_ets_files` 检查 OfflineInlinePlayer.ets 和 OfflineCachePage.ets（无 error）
2. 手动构建（用户环境：local.properties 指向 API 26 SDK，DevEco 构建）
3. 测试：完成缓存 → 点击条目 → 原位播放有画面有声音 → 进度走 → 暂停/继续 → 关闭收起 → 其他项恢复

## 四、坑与注意（必读）

1. **ArkTS 硬约束**：禁 `any`/`unknown`/`var`/解构/无类型对象字面量/`obj['key']`；必须显式返回类型；2 空格缩进；单引号
2. **fdSrc 必须用 fd**：`createMediaSourceWithUrl/Fd` 在 API 24/26 不通用，抄现有 `AVFileDescriptor { fd, offset: 0 }` 写法
3. **XComponent surfaceId 时机**：build 完成后 surface 才就绪，需 setTimeout 轮询（300ms 重试，参考 resumeFromMinimized 第 872-877 行）
4. **双播放器同步**：视频和音频都要 play/pause/seek，音频不绑 surface
5. **不要动 PlayerService**：内嵌播放器独立实例，避免与悬浮窗全局播放冲突；若视频已在播放（PlayerService 有活跃播放器），列表页展开前可先不动它（或提示）
6. **List 挤开动画**：用 `animateTo` 包裹高度/条件渲染变化；`if` 切换组件时注意动画帧（可用固定高度 + 条件子组件）
7. **封面 Image vs XComponent**：展开时用 XComponent 替代 Image 渲染；`playingBvid` 命中即切换，其他项保持 Image 不闪烁
8. **切条目**：点 A 展开播放中再点 B → 先收起 A（释放）再展开 B；在 `playItem` 里先清空再设置
9. **离页释放**：`aboutToDisappear` 清空状态；组件 `aboutToDisappear` 内 `releaseAll()`，fd 必须 closeSync
10. **竖屏比例**：prepared 后读 videoWidth/Height；解析失败默认 16:9
11. **已完成判断**：`item.status === CacheStatus.COMPLETED && item.videoPath` 才可播放（沿用 playItem 现有守卫）
12. **验证前先同步**：`mcp__deveco-mcp__project_sync`（若 LSP 未初始化）；构建用 DevEco（MCP 构建工具的 SDK 目录与用户 local.properties 不一致，会报 compileSdkVersion 格式错，**不是代码问题，勿改 build-profile.json5**）

## 五、验收标准
- [ ] 点击已完成缓存条目，封面原位放大为 16:9（横屏视频）/ 竖屏比例，不再跳转页面
- [ ] 内嵌播放有画面、有声音（DASH 双流）
- [ ] 进度条实时走动，可暂停/继续
- [ ] 其他列表项被展开封面自然挤开，收起后恢复
- [ ] 关闭播放器/离页无崩溃、无 fd 泄漏
- [ ] 正在下载/已暂停条目不受影响（不展开）
