import { common } from '@kit.AbilityKit';
import { logInfo, logWarn, logError } from '../utils/Logger';
import { window, curves, mediaquery } from '@kit.ArkUI';
import { getRecommendVideos, blacklistUploader } from '../api/BilibiliApi';
import { RecommendItem } from '../model/RecommendItem';
import { preferences } from '@kit.ArkData';
import { vibrator } from '@kit.SensorServiceKit';
import { WatchHistoryHelper } from '../model/WatchHistoryHelper';
import { sendDislikeFeedback, sendDislikeUpFeedback } from '../api/FeedbackService';
import { UserBehaviorService } from '../services/UserBehaviorService';  // ⭐ 用于本地屏蔽过滤

// ⭐ 已看视频缓存接口（带时间戳，支持7天有效期）
interface WatchedVideoCache {
  id: string;
  timestamp: number;  // 看到的时间
}

class VideoDataSource implements IDataSource {
  private items: RecommendItem[] = [];
  private listeners: DataChangeListener[] = [];

  public totalCount(): number {
    return this.items.length;
  }

  public getData(index: number): RecommendItem {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener);
    if (pos >= 0) this.listeners.splice(pos, 1);
  }

  notifyDataReload(): void {
    this.listeners.forEach(listener => listener.onDataReloaded());
  }

  notifyDataAdd(index: number): void {
    this.listeners.forEach(listener => listener.onDataAdd(index));
  }

  public addItems(newItems: RecommendItem[]): void {
    const startIdx = this.items.length;
    this.items.push(...newItems);
    this.notifyDataAdd(startIdx);
  }

  public reloadItems(allItems: RecommendItem[]): void {
    this.items = allItems;
    this.notifyDataReload();
  }

  public getRawItems(): RecommendItem[] {
    return this.items;
  }

  public setRawItems(items: RecommendItem[]): void {
    this.items = items;
  }
}

@Component
export struct HomePage {
  // ★ 由父组件传入，供 Scroll 组件和 HdsNavigation.bindToScrollable 使用
  externalScroller?: Scroller = undefined;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('navIndicatorHeight') navIndicatorHeight: number = 0;
  @StorageLink('refreshHomeFlag') @Watch('onRefreshFlagChange') refreshFlag: number = 0;
  @StorageLink('scrollToTopFlag') @Watch('onScrollToTop') scrollToTopFlag: number = 0;
  @StorageLink('hideStatusBar') hideStatusBar: boolean = false;
  @StorageLink('pageShowCounter') @Watch('onPageShowReset') pageShowCounter: number = 0;
  @StorageLink('homeScrollOffset') homeScrollOffset: number = 0;
  @StorageLink('customThemeColor') customThemeColor: string = '#007DFF';
  @StorageLink('showRefreshSeparator') showRefreshSeparator: boolean = true;
  @StorageLink('cardTransparentStyle') cardTransparentStyle: boolean = false;
  @StorageLink('cardBorderFollowTheme') cardBorderFollowTheme: boolean = false;
  @StorageLink('cardBorderOpacity') cardBorderOpacity: number = 40;
  @StorageLink('cardBorderFollowPlayCount') cardBorderFollowPlayCount: boolean = false;
  @StorageLink('cardBgOpacity') cardBgOpacity: number = 30;
  @StorageLink('cardBorderWidth') cardBorderWidth: number = 1.5;
  @StorageLink('cardCustomColor') cardCustomColor: string = '';

  @State dataSource: VideoDataSource = new VideoDataSource();
  @State statusBarHeight: number = 0;
  @State scrollOffset: number = 0;
  @State isLoading: boolean = true;
  @State isLoadingMore: boolean = false;
  @State isRefreshing: boolean = false;
  @State pageNum: number = 1;
  @State refreshIdx: number = 1;  // 刷新索引，每次刷新递增
  @State columnCount: number = 2;
  @State isLandscape: boolean = false;
  @State topPadding: number = 0;
  @State bottomPadding: number = 0;
  @State sidePadding: number = 12;
  @State manualLoading: boolean = false;

  // ⭐ 底部弹窗相关状态
  @State isMenuSheetVisible: boolean = false;
  @State selectedMenuItem: RecommendItem | null = null;

  // ⭐ 已看视频 ID 集合（用于去重）- 使用Map存储时间戳，支持7天有效期
  private watchedVideoIds: Map<string, number> = new Map();  // id -> timestamp
  // 最大保留的已看视频数量（防止内存过大）
  private readonly MAX_WATCHED_CACHE: number = 500;
  // 7天有效期（毫秒）
  private readonly WATCHED_EXPIRE_TIME: number = 7 * 24 * 60 * 60 * 1000;
  // 防抖保存时间（3秒）
  private readonly SAVE_DEBOUNCE_TIME: number = 3000;
  // 防抖保存定时器
  private pendingSaveTimer: number = -1;
  // ⭐ 滑过的视频ID（持久化存储的key）
  private readonly SEEN_VIDEOS_KEY: string = 'seen_video_ids_v2';  // v2版本，带时间戳

  // ⭐ "上次看到这里"重新实现：刷新时保留旧视频
  private readonly REFRESH_SEPARATOR_ID: string = '__refresh_separator__';
  private oldItems: RecommendItem[] = [];

  /**
   * ⭐ 从本地存储加载观看历史和滑过的视频用于去重
   * 这是解决"昨天看过的视频今天又出现"的关键！
   * 同时会清理过期的缓存条目，避免存储膨胀
   */
  private async loadWatchHistoryForDedup(): Promise<void> {
    try {
      const now = Date.now();
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;

      // 1. 加载持久化存储的已看视频ID（带时间戳）
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      
      const cachedStr = await pref.get(this.SEEN_VIDEOS_KEY, '') as string;

      if (cachedStr) {
        try {
          const cached: WatchedVideoCache[] = JSON.parse(cachedStr) as WatchedVideoCache[];
          let expiredCount = 0;

          for (const item of cached) {
            // 检查是否在7天有效期内
            if (now - item.timestamp < this.WATCHED_EXPIRE_TIME) {
              this.watchedVideoIds.set(item.id, item.timestamp);
            } else {
              expiredCount++;
            }
          }

          logInfo(`[去重] 从缓存加载 ${cached.length} 条，过期 ${expiredCount} 条，有效 ${this.watchedVideoIds.size} 条`);
          
          // ⭐ 如果有过期条目，主动清理存储，避免下次还要处理
          if (expiredCount > 0) {
            const validItems: WatchedVideoCache[] = [];
            this.watchedVideoIds.forEach((timestamp, id) => {
              validItems.push({ id, timestamp });
            });
            await pref.put(this.SEEN_VIDEOS_KEY, JSON.stringify(validItems));
            await pref.flush();
            logInfo(`[去重] 已清理 ${expiredCount} 条过期缓存`);
          }
        } catch (e) {
          logWarn(`[去重] 解析缓存失败: ${e}`);
        }
      }

      // 2. 加载观看历史（点进去看的）- 只加载最近100条
      await WatchHistoryHelper.getInstance().init(context);
      const history = await WatchHistoryHelper.getInstance().queryAllHistory(100);

      if (history && history.length > 0) {
        for (const item of history) {
          if (item.bvid && !this.watchedVideoIds.has(item.bvid)) {
            this.watchedVideoIds.set(item.bvid, now);  // 使用当前时间作为时间戳
          }
        }
        logInfo(`[去重] 从观看历史加载 ${history.length} 条`);
      }

      logInfo(`[去重] 总计 ${this.watchedVideoIds.size} 条去重记录（7天有效）`);
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : String(err);
      logError(`[去重] 加载历史失败: ${errorMsg}`);
    }
  }

  /**
   * ⭐ 保存已看视频ID到持久化存储（带时间戳）
   */
  private async saveSeenVideos(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'my_app_settings');

      // 转换为带时间戳的数组
      const now = Date.now();
      const cacheData: WatchedVideoCache[] = [];
      this.watchedVideoIds.forEach((timestamp, id) => {
        cacheData.push({ id, timestamp });
      });

      // 只保存最近的500条
      const toSave = cacheData.slice(-this.MAX_WATCHED_CACHE);
      await pref.put(this.SEEN_VIDEOS_KEY, JSON.stringify(toSave));
      await pref.flush();

      logInfo(`[去重] 已保存 ${toSave.length} 条已看视频记录`);
    } catch (err) {
      logError(`[去重] 保存失败: ${err}`);
    }
  }

  /**
   * ⭐ 防抖保存：延迟3秒后保存，避免频繁写磁盘
   * 用于自动记录浏览时调用
   */
  private scheduleSaveSeenVideos(): void {
    if (this.pendingSaveTimer !== -1) {
      clearTimeout(this.pendingSaveTimer);
    }
    this.pendingSaveTimer = setTimeout(async () => {
      await this.saveSeenVideos();
      this.pendingSaveTimer = -1;
    }, this.SAVE_DEBOUNCE_TIME);
  }

  /**
   * ⭐ 自动记录浏览过的视频（调用此方法）
   * 在 FlowItem.onAppear 和 onCardClick 中调用
   */
  private autoRecordWatched(item: RecommendItem): void {
    // 如果已记录过，不重复记录（避免频繁触发）
    if (this.watchedVideoIds.has(item.id)) {
      return;
    }
    // 记录到缓存
    this.watchedVideoIds.set(item.id, Date.now());
    // 防抖保存
    this.scheduleSaveSeenVideos();
  }

  private pageSize: number = 20;
  private hasMore: boolean = true;
  private lastScrollY: number = 0;
  private readonly SCROLL_THRESHOLD: number = 10;
  private maxRetryPages: number = 20;
  private longPullTimer: number = -1;
  private longPullTriggered: boolean = false;
  private windowSizeChangeListener: ((size: window.Size) => void) | null = null;
  private mainWindowRef: window.Window | null = null;
  private isPageActive: boolean = false;
  @State refreshBuilderText: string = '下拉刷新';
  @State showSearchIcon: boolean = false;

  // 媒体查询监听器
  private landscapeListener: mediaquery.MediaQueryListener | null = null;

  @State cardsVisible: boolean[] = [];
  @State isBulkLoading: boolean = false;
  private cardDelays: number[] = [];
  private cardTranslateYs: number[] = [];

  async aboutToAppear() {
    this.isPageActive = true;
    await this.getStatusBarHeight();
    await this.waitForStableOrientation();
    await this.initOrientationAndColumn();
    // ⭐ 加载观看历史用于去重
    await this.loadWatchHistoryForDedup();
    await this.refreshData();
    await this.watchWindowSizeChange();
    this.updatePaddings();
    AppStorage.set('bottomBarHidden', false);
    // 注册媒体查询监听横竖屏变化（官方推荐）
    this.registerOrientationListener();
  }

  async aboutToDisappear() {
    this.isPageActive = false;
    // 清除防抖保存定时器
    if (this.pendingSaveTimer !== -1) {
      clearTimeout(this.pendingSaveTimer);
      this.pendingSaveTimer = -1;
    }
    // 保存当前列数设置
    await this.saveCurrentColumnCount();
    // ⭐ 不再保存滑过的视频ID - 依赖B站服务端去重
    // await this.saveSeenVideos();
    if (this.mainWindowRef && this.windowSizeChangeListener) {
      this.mainWindowRef.off('windowSizeChange', this.windowSizeChangeListener);
      this.windowSizeChangeListener = null;
    }
    // 移除媒体查询监听
    if (this.landscapeListener) {
      this.landscapeListener.off('change');
      this.landscapeListener = null;
    }
  }

  // 注册媒体查询监听
  private registerOrientationListener() {
    const mediaQuery = this.getUIContext().getMediaQuery();
    this.landscapeListener = mediaQuery.matchMediaSync('(orientation: landscape)');
    this.landscapeListener.on('change', async (result: mediaquery.MediaQueryResult) => {
      if (!this.isPageActive) return;
      const newIsLandscape = result.matches;
      if (this.isLandscape !== newIsLandscape) {
        logInfo(`[HomePage] 方向变化: ${newIsLandscape ? '横屏' : '竖屏'}`);
        this.isLandscape = newIsLandscape;
        // 加载新方向对应的列数（用户自定义值）
        await this.loadColumnCountForOrientation();
        this.updatePaddings();
        // 可选：刷新滚动偏移量保持
        AppStorage.setOrCreate('homeScrollOffset', this.scrollOffset);
      }
    });
  }

  private async waitForStableOrientation(): Promise<void> {
    await new Promise<void>(resolve => setTimeout(resolve, 150));
  }

  onPageShowReset() {
    this.isRefreshing = false;
    this.showSearchIcon = false;
    this.refreshBuilderText = '下拉刷新';
    this.longPullTriggered = false;
    if (this.longPullTimer !== -1) {
      clearTimeout(this.longPullTimer);
      this.longPullTimer = -1;
    }
    this.recheckOrientationAndColumn();
  }

  private async recheckOrientationAndColumn() {
    await this.waitForStableOrientation();
    await this.initOrientationAndColumn();
    this.updatePaddings();
  }

  @Watch('onHideStatusBarChange')
  @StorageLink('hideStatusBar') watchHideStatusBarLink: boolean = false;

  private async onHideStatusBarChange() {
    await this.getStatusBarHeight();
    this.updatePaddings();
  }

  private onScrollToTop() {
    if (this.externalScroller) {
      this.externalScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 300 } });
    }
  }

  private async initOrientationAndColumn() {
    let mainWindow = AppStorage.get<window.Window>('mainWindow');
    if (!mainWindow) {
      try {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        mainWindow = await window.getLastWindow(context);
      } catch (err) {
        logError('获取窗口失败', err);
      }
    }
    if (mainWindow) {
      try {
        const props = mainWindow.getWindowProperties();
        const width = props.windowRect.width;
        const height = props.windowRect.height;
        const newIsLandscape = width > height;
        if (this.isLandscape !== newIsLandscape) {
          this.isLandscape = newIsLandscape;
          logInfo(`initOrientationAndColumn: 方向更新为 ${this.isLandscape ? '横屏' : '竖屏'}`);
        }
      } catch (err) {
        logError('获取窗口属性失败', err);
        this.isLandscape = false;
      }
    } else {
      this.isLandscape = false;
    }
    await this.loadColumnCountForOrientation();
    logInfo(`initOrientationAndColumn: 方向=${this.isLandscape ? '横屏' : '竖屏'}, 列数=${this.columnCount}`);
  }

  private async watchWindowSizeChange() {
    const mainWindow = AppStorage.get<window.Window>('mainWindow');
    if (mainWindow && !this.windowSizeChangeListener) {
      this.mainWindowRef = mainWindow;
      this.windowSizeChangeListener = async (size: window.Size) => {
        // 仅更新内边距（处理分屏等情况）
        this.updatePaddings();
      };
      mainWindow.on('windowSizeChange', this.windowSizeChangeListener);
      logInfo('watchWindowSizeChange: 已注册窗口尺寸变化监听器');
    }
  }

  private updatePaddings() {
    const suspendedBarHeight = 56;
    if (this.isLandscape) {
      // 横屏：顶部边距12
      this.topPadding = 12;
      this.bottomPadding = 176 + this.navIndicatorHeight;
    } else {
      // 竖屏：使用首页的高度
      this.topPadding = suspendedBarHeight;
      this.bottomPadding = 190 + this.navIndicatorHeight;
    }
  }

  private async loadColumnCountForOrientation() {
    const key = this.isLandscape ? 'homeColumnCountLandscape' : 'homeColumnCountPortrait';
    const defaultValue = this.isLandscape ? 3 : 2;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      const saved = await pref.get(key, defaultValue) as number;
      logInfo(`loadColumnCountForOrientation: key=${key}, 保存值=${saved}`);
      this.columnCount = saved;
    } catch (err) {
      logError('加载列数失败', err);
      this.columnCount = defaultValue;
    }
  }

  private async saveCurrentColumnCount() {
    if (!this.isPageActive) return;
    const key = this.isLandscape ? 'homeColumnCountLandscape' : 'homeColumnCountPortrait';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      await pref.put(key, this.columnCount);
      await pref.flush();
      logInfo(`saveCurrentColumnCount: 保存 ${key}=${this.columnCount}`);
    } catch (err) {
      logError('保存列数失败', err);
    }
  }

  onRefreshFlagChange() {
    this.refreshData();
  }

  private onRefresh() {
    this.refreshData().finally(() => {
      this.isRefreshing = false;
    });
  }

  private async manualRefresh() {
    if (this.manualLoading) return;
    this.manualLoading = true;
    await this.refreshData();
    this.manualLoading = false;
    this.getUIContext().getPromptAction().showToast({ message: '已刷新推荐内容', duration: 1000 });
  }

  // ⭐ 过滤已看过的视频
  private filterWatched(items: RecommendItem[]): RecommendItem[] {
    const now = Date.now();
    return items.filter(item => {
      const timestamp = this.watchedVideoIds.get(item.id);
      if (!timestamp) return true;  // 没看过
      // 检查是否在有效期内
      if (now - timestamp >= this.WATCHED_EXPIRE_TIME) {
        // 过期了，删除缓存条目并允许显示
        this.watchedVideoIds.delete(item.id);
        return true;
      }
      return false;  // 在有效期内，过滤掉
    });
  }

  // ⭐ 记录已看过的视频（带时间戳）
  private recordWatched(items: RecommendItem[]): void {
    const now = Date.now();
    for (const item of items) {
      this.watchedVideoIds.set(item.id, now);
    }
    // 防止 Map 过大，保留最近的
    if (this.watchedVideoIds.size > this.MAX_WATCHED_CACHE) {
      // 按时间戳排序，保留最近的
      const entries = Array.from(this.watchedVideoIds.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, this.MAX_WATCHED_CACHE);
      this.watchedVideoIds = new Map(entries);
    }
  }

  private mergeUnique(existing: RecommendItem[], newItems: RecommendItem[]): RecommendItem[] {
    const map = new Map<string, RecommendItem>();
    for (const item of existing) map.set(item.id, item);
    for (const item of newItems) {
      if (!map.has(item.id)) map.set(item.id, item);
    }
    return Array.from(map.values());
  }

  async refreshData() {
    // ⭐ 第一步：错落缩小现有卡片（随机延迟，与新卡片入场动画风格一致）
    const oldCount = this.dataSource.totalCount();
    if (oldCount > 0) {
      this.isBulkLoading = false;
      for (let i = 0; i < oldCount; i++) {
        const delay = Math.floor(Math.random() * 300); // 0~300ms 随机
        setTimeout(() => {
          const newVisible = [...this.cardsVisible];
          if (i < newVisible.length) {
            newVisible[i] = false;
            this.cardsVisible = newVisible;
          }
        }, delay);
      }
    }

    // ⭐ 保存当前视频列表，刷新后放在新视频下方
    this.oldItems = this.dataSource.getRawItems();

    this.isLoading = true;
    this.pageNum = 1;
    this.hasMore = true;
    this.refreshIdx++;  // 递增刷新索引

    // ⭐ 循环请求，直到获取足够的未观看视频
    let filteredItems: RecommendItem[] = [];
    let attempts = 0;
    const maxAttempts = 5;  // 最多尝试5次
    const minRequired = Math.floor(this.pageSize * 0.5);  // 至少需要一半的数量

    while (filteredItems.length < minRequired && attempts < maxAttempts) {
      let newItems = await getRecommendVideos(this.refreshIdx + attempts, this.pageSize);

      // ⭐ 调用服务层过滤（屏蔽UP主、已看视频）
      logInfo(`[调试] refreshData: 调用 filterRecommendList 前，原始数量: ${newItems.length}`);
      newItems = UserBehaviorService.filterRecommendList(newItems);
      logInfo(`[调试] refreshData: 调用 filterRecommendList 后，过滤数量: ${newItems.length}`);
      
      // 过滤已看过的视频
      const newFiltered = this.filterWatched(newItems);
      filteredItems = filteredItems.concat(newFiltered);

      logInfo(`[去重] 第${attempts + 1}次请求: 原始${newItems.length}条 → 过滤后${newFiltered.length}条 → 累计${filteredItems.length}条`);

      attempts++;

      // 如果已经获取足够的视频，退出循环
      if (filteredItems.length >= this.pageSize) {
        break;
      }
    }

    // 更新刷新索引
    this.refreshIdx += attempts;

    // 去重（防止重复）
    let uniqueItems = this.mergeUnique([], filteredItems);

    // ⭐ 组合：新视频 + (可选分隔卡片 + 旧视频)
    const combinedItems: RecommendItem[] = [...uniqueItems];
    if (this.showRefreshSeparator && this.oldItems.length > 0) {
      // 创建分隔卡片
      const separatorItem = new RecommendItem();
      separatorItem.id = this.REFRESH_SEPARATOR_ID;
      combinedItems.push(separatorItem);
      // 追加旧视频（去重）
      const newIds = new Set(uniqueItems.map(item => item.id));
      for (const old of this.oldItems) {
        if (!newIds.has(old.id)) {
          combinedItems.push(old);
        }
      }
    }

    if (combinedItems.length > 0) {
      // ⭐ 记录已看过的视频
      // ⭐ 不再自动标记所有视频为已看，改为滑动/点击时自动记录
      // this.recordWatched(uniqueItems);

      this.dataSource.reloadItems(combinedItems);
      this.pageNum = 2;
      logInfo(`刷新成功，获取到 ${uniqueItems.length} 条新视频，合并后共 ${combinedItems.length} 条`);

      const count = this.dataSource.totalCount();
      this.cardsVisible = new Array(count).fill(false);
      this.cardDelays = [];
      this.cardTranslateYs = [];
      for (let i = 0; i < count; i++) {
        this.cardDelays.push(Math.floor(Math.random() * 600));
        this.cardTranslateYs.push(Math.floor(Math.random() * 40) + 15);
      }
      this.isBulkLoading = true;
      setTimeout(() => {
        const maxDelay = this.cardDelays.length > 0 ? Math.max(...this.cardDelays) : 0;
        for (let i = 0; i < count; i++) {
          setTimeout(() => {
            const newVisible = [...this.cardsVisible];
            newVisible[i] = true;
            this.cardsVisible = newVisible;
          }, this.cardDelays[i]);
        }
        setTimeout(() => {
          this.isBulkLoading = false;
        }, maxDelay + 1600);
      }, 120);

      // ⭐ 刷新时不设置 hasMore = false，让加载更多时再判断
      // 只有返回 0 条数据才说明没有更多了
    } else {
      this.hasMore = false;
    }
    this.isLoading = false;
  }


  async loadMore() {
    if (this.isLoadingMore || !this.hasMore) return;
    this.isLoadingMore = true;

    let addedCount = 0;
    let attempt = 0;
    const maxAttempt = this.maxRetryPages;

    while (attempt < maxAttempt && addedCount === 0) {
      // ⭐ 使用 refreshIdx 而不是 pageNum，确保索引一致
      this.refreshIdx++;
      // ⭐ 调用服务层过滤（屏蔽UP主、已看视频）
      let items = await getRecommendVideos(this.refreshIdx, this.pageSize);
      logInfo(`[调试] loadMore: 调用 filterRecommendList 前，原始数量: ${items.length}`);
      items = UserBehaviorService.filterRecommendList(items);
      logInfo(`[调试] loadMore: 调用 filterRecommendList 后，过滤数量: ${items.length}`);
      if (items.length === 0) break;
      // ⭐ 过滤已看过的视频
      const filteredItems = this.filterWatched(items);
      const beforeCount = this.dataSource.totalCount();
      const merged = this.mergeUnique(this.dataSource.getRawItems(), filteredItems);
      const newCount = merged.length - beforeCount;
      if (newCount > 0) {
        this.dataSource.setRawItems(merged);
        this.dataSource.notifyDataAdd(beforeCount);
        const newTotal = merged.length;
        const currentVisible = this.cardsVisible.length;
        if (newTotal > currentVisible) {
          const addCount = newTotal - currentVisible;
          const extendedVisible = [...this.cardsVisible, ...new Array<boolean>(addCount).fill(false)];
          this.cardsVisible = extendedVisible;
          for (let i = 0; i < addCount; i++) {
            const globalIdx = currentVisible + i;
            this.cardDelays[globalIdx] = Math.floor(Math.random() * 180) + i * 55;
            this.cardTranslateYs[globalIdx] = Math.floor(Math.random() * 55) + 35;
          }
          setTimeout(() => {
            for (let i = 0; i < addCount; i++) {
              const globalIdx = currentVisible + i;
              setTimeout(() => {
                const newVisible = [...this.cardsVisible];
                newVisible[globalIdx] = true;
                this.cardsVisible = newVisible;
              }, this.cardDelays[globalIdx]);
            }
          }, 100);
        }
        addedCount = newCount;
        logInfo(`加载更多成功，获取到 ${newCount} 条新内容，refreshIdx=${this.refreshIdx}`);
        break;
      } else {
        attempt++;
      }
    }

    if (addedCount === 0) {
      this.hasMore = false;
    }
    this.isLoadingMore = false;
  }

  async getStatusBarHeight() {
    if (this.hideStatusBar) {
      this.statusBarHeight = 0;
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const windowClass: window.Window = await window.getLastWindow(context);
      const avoidArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.statusBarHeight = this.getUIContext().px2vp(avoidArea.topRect.height);
    } catch (error) {
      this.statusBarHeight = 40;
    }
  }

  private opacityToHexAlpha(opacity: number): string {
    const val = Math.round(opacity / 100 * 255);
    const hex = val.toString(16);
    return hex.length === 1 ? '0' + hex : hex;
  }

  formatCount(count: number): string {
    if (count >= 100000000) return (count / 100000000).toFixed(1) + '亿';
    if (count >= 10000) return (count / 10000).toFixed(1) + '万';
    return count.toString();
  }

  getPlayCountColor(count: number): string {
    if (count >= 10000000) return '#FF0000';
    if (count >= 3000000) return '#C2185B';
    if (count >= 1000000) return '#FF8C00';
    if (count >= 100000) return '#FFB800';
    if (count >= 50000) return '#4A90D9';
    return '#999999';
  }

  private onCardClick(item: RecommendItem) {
    // 自动记录点击播放的视频（用于去重）
    this.autoRecordWatched(item);
    
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/VideoPlayerPage',
      params: {
        bvid: item.id,
        cid: item.cid,
        title: item.title,
        ownerName: item.ownerName,
        coverUrl: item.coverUrl
      }
    }).catch((err: Error) => logError(`跳转播放页失败: ${err.message}`));
  }

  /**
   * ⭐ 显示视频菜单（底部弹窗）
   */
  private showVideoMenu(item: RecommendItem): void {
    this.selectedMenuItem = item;
    this.isMenuSheetVisible = true;
  }

  /**
   * ⭐ 处理不感兴趣
   */
  private async handleDislike(item: RecommendItem): Promise<void> {
    try {
      // 1. 发送反馈到B站
      const result = await sendDislikeFeedback(item.id, 1);

      // 2. 加入本地去重集合（带时间戳）
      this.watchedVideoIds.set(item.id, Date.now());
      await this.saveSeenVideos();  // 保存到持久化存储

      // 3. 从列表中移除
      this.removeVideoFromList(item.id);

      this.getUIContext().getPromptAction().showToast({ message: '已减少此类推荐', duration: 1500 });
      logInfo(`[不感兴趣] ${item.id} - ${item.title}`);
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '操作失败', duration: 1500 });
    }
  }

  /**
   * ⭐ 屏蔽UP主
   */
  private async handleBlockUploader(item: RecommendItem): Promise<void> {
    try {
      // 1. 发送反馈到B站
      const result = await sendDislikeUpFeedback(item.ownerMid);

      // 2. ⭐ 添加到本地屏蔽列表（持久化存储）
      UserBehaviorService.addBlockedUploader(item.ownerMid);

      // 3. 从列表中移除该UP主的所有视频
      this.removeVideosByUploader(item.ownerMid);

      this.getUIContext().getPromptAction().showToast({ message: `已屏蔽 ${item.ownerName}`, duration: 1500 });
      logInfo(`[屏蔽UP主] ${item.ownerMid} - ${item.ownerName}`);
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '操作失败', duration: 1500 });
    }
  }

  /**
   * ⭐ 拉黑UP主（API拉黑）
   */
  private async handleBlacklistUploader(item: RecommendItem): Promise<void> {
    try {
      const result = await blacklistUploader(Number(item.ownerMid));
      if (result) {
        // 拉黑成功，也加入本地屏蔽列表
        UserBehaviorService.addBlockedUploader(item.ownerMid);
        this.removeVideosByUploader(item.ownerMid);
        this.getUIContext().getPromptAction().showToast({ message: `已拉黑 ${item.ownerName}`, duration: 1500 });
        logInfo(`[拉黑UP主] ${item.ownerMid} - ${item.ownerName}`);
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '拉黑失败，请检查登录状态', duration: 2000 });
      }
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '操作失败', duration: 1500 });
    }
  }

  /**
   * ⭐ 标记为看过类似视频
   */
  private async handleSeenBefore(item: RecommendItem): Promise<void> {
    // 加入本地去重集合
    this.watchedVideoIds.set(item.id, Date.now());
    await this.saveSeenVideos();  // 保存到持久化存储

    // 从列表中移除
    this.removeVideoFromList(item.id);

    this.getUIContext().getPromptAction().showToast({ message: '已标记为看过', duration: 1500 });
  }

  /**
   * ⭐ 从列表中移除单个视频
   */
  private removeVideoFromList(bvid: string) {
    const items = this.dataSource.getRawItems();
    const newItems = items.filter(item => item.id !== bvid);
    this.dataSource.reloadItems(newItems);

    // 更新可见状态数组
    this.cardsVisible = new Array(newItems.length).fill(true);
  }

  /**
   * ⭐ 移除某UP主的所有视频
   */
  private removeVideosByUploader(mid: string) {
    const items = this.dataSource.getRawItems();
    const newItems = items.filter(item => item.ownerMid !== mid);
    this.dataSource.reloadItems(newItems);

    // 更新可见状态数组
    this.cardsVisible = new Array(newItems.length).fill(true);
  }

  private handlePinch(scale: number) {
    let changed = false;
    if (this.isLandscape) {
      if (scale > 1.05 && this.columnCount < 4) {
        this.columnCount++;
        changed = true;
      } else if (scale < 0.95 && this.columnCount > 3) {
        this.columnCount--;
        changed = true;
      }
    } else {
      if (scale > 1.05 && this.columnCount < 3) {
        this.columnCount = 3;
        changed = true;
      } else if (scale < 0.95 && this.columnCount > 2) {
        this.columnCount = 2;
        changed = true;
      }
    }
    if (changed) {
      this.saveCurrentColumnCount();
      this.getUIContext().getPromptAction().showToast({ message: `${this.columnCount}列`, duration: 800 });
    }
  }

  /**
   * ⭐ 底部菜单弹窗内容
   */
  @Builder
  menuSheetContent() {
    Column() {
      Column() {
        // 顶部拖动条
        Row() {
          Row()
            .width(36)
            .height(4)
            .backgroundColor(this.isDarkMode ? '#666666' : '#CCCCCC')
            .borderRadius(2)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 12, bottom: 16 })

        // 菜单选项
        Column({ space: 12 }) {
          // 不感兴趣
          this.MenuItemButton('不感兴趣', () => {
            this.isMenuSheetVisible = false;
            if (this.selectedMenuItem) {
              this.handleDislike(this.selectedMenuItem);
            }
          })

          // 屏蔽UP主
          this.MenuItemButton('屏蔽UP主', () => {
            this.isMenuSheetVisible = false;
            if (this.selectedMenuItem) {
              this.handleBlockUploader(this.selectedMenuItem);
            }
          })

          // 拉黑UP主
          this.MenuItemButton('拉黑UP主', () => {
            this.isMenuSheetVisible = false;
            if (this.selectedMenuItem) {
              this.handleBlacklistUploader(this.selectedMenuItem);
            }
          })

          // 看过类似
          this.MenuItemButton('看过类似', () => {
            this.isMenuSheetVisible = false;
            if (this.selectedMenuItem) {
              this.handleSeenBefore(this.selectedMenuItem);
            }
          })

          // 取消
          this.MenuItemButton('取消', () => {
            this.isMenuSheetVisible = false;
          }, true)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 30 })
      }
      .width(this.isLandscape ? '100%' : '85%')
      .backgroundColor(this.isDarkMode ? '#1A1A1A' : '#FFFFFF')
      .borderRadius(20)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * ⭐ 菜单项按钮
   */
  @Builder
  MenuItemButton(text: string, onClick: () => void, isCancelButton: boolean = false) {
    Text(text)
      .fontSize(15)
      .fontColor(isCancelButton ? '#FFFFFF' : (this.isDarkMode ? '#FFFFFF' : '#000000'))
      .width('100%')
      .height(50)
      .textAlign(TextAlign.Center)
      .backgroundColor(isCancelButton ? this.customThemeColor : (this.isDarkMode ? '#2A2A2A' : '#F5F5F5'))
      .borderRadius(20)
      .onClick(() => onClick())
  }

  @Builder
  customRefreshComponent() {
    Stack() {
      Column() {
        if (this.showSearchIcon) {
          Image($r('app.media.ic_public_search_filled'))
            .width(32)
            .height(32)
            .objectFit(ImageFit.Contain)
            .fillColor(this.customThemeColor)
        } else {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(this.customThemeColor)
        }
        Text(this.refreshBuilderText)
          .fontSize(12)
          .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Center)
    }
    .alignContent(Alignment.Center)
    .width('100%')
    .height(60)
  }

  @Builder
  VideoCard(item: RecommendItem) {
    // 正常视频卡片
    Column() {
      Image(item.coverUrl)
        .width('100%')
        .aspectRatio(16 / 9)
        .objectFit(ImageFit.Cover)
        .borderRadius(12)
        .backgroundColor('#E0E0E0')
        .draggable(false)
        .sharedTransition(`videoCover_${item.id}`, {
          duration: 350,
          curve: Curve.EaseOut
        })
      Column() {
        Text(item.title)
          .fontSize(14).fontColor(this.isDarkMode ? Color.White : Color.Black)
          .width('100%').margin({ bottom: 6 })
        Row() {
          Text(item.ownerName)
            .fontSize(12)
            .fontColor($r('app.color.color_primary_text'))
            .padding({ left: 6, right: 6, top: 4, bottom: 4 })
            .backgroundColor('rgba(186, 136, 65, 1)')
            .borderRadius(7)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
          Blank()
          Row() {
            Text(this.formatCount(item.playCount) + '播放')
              .fontSize(12)
              .fontColor(this.getPlayCountColor(item.playCount))
            Image($r('app.media.play_fill'))
              .width(20)
              .height(20)
              .objectFit(ImageFit.Contain)
              .margin({ left: 4 })
              .fillColor(this.getPlayCountColor(item.playCount))
          }
          .alignItems(VerticalAlign.Center)
          .height(20)
          .flexShrink(0)
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('100%')
      .padding(8)
      .backgroundColor('transparent')
    }
    .width('100%')
    .backgroundColor(this.cardCustomColor && this.cardCustomColor !== '#007DFF'
      ? (this.cardTransparentStyle
        ? '#' + this.opacityToHexAlpha(this.cardBgOpacity) + this.cardCustomColor.slice(1)
        : this.cardCustomColor)
      : (this.cardTransparentStyle
        ? (this.isDarkMode
          ? `rgba(0,0,0,${this.cardBgOpacity / 100})`
          : `rgba(255,255,255,${this.cardBgOpacity / 100})`)
        : (this.isDarkMode ? '#2C2C2C' : '#FFFFFF')))
    .border({ width: this.cardTransparentStyle ? this.cardBorderWidth : 0,
      color: this.cardTransparentStyle
        ? (this.cardBorderFollowPlayCount
          ? ('#' + this.opacityToHexAlpha(this.cardBorderOpacity) + this.getPlayCountColor(item.playCount).slice(1))
          : (this.cardBorderFollowTheme
            ? ('#' + this.opacityToHexAlpha(this.cardBorderOpacity) + this.customThemeColor.slice(1))
            : (this.isDarkMode ? 'rgba(255,255,255,0.12)' : 'rgba(255,255,255,0.25)')))
        : Color.Transparent })
    .borderRadius(12).clip(true)
    .shadow({ radius: 4, color: '#10000000', offsetY: 2 })
    .clickEffect({ level: 0, scale: 0.9 })
    .onClick(() => this.onCardClick(item))
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.showVideoMenu(item);
        })
    )
    .width('100%')
  }

  /**
   * ⭐ "上次看到这里" 分隔卡片
   */
  @Builder
  RefreshSeparatorCard() {
    Column() {
      Column() {
        Image($r('app.media.arrow_clockwise'))
          .width(40).height(40)
          .fillColor(this.customThemeColor)
          .margin({ bottom: 6 })
        Text('上次看到这里')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.customThemeColor)
        Text('点击刷新，加载最新内容')
          .fontSize(12)
          .fontColor(this.customThemeColor)
          .opacity(0.7)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height(100)
      .backgroundColor(this.isDarkMode ? '#2A2A2A' : '#F0F8FF')
      .borderRadius(16)
      .borderWidth(1)
      .borderColor(this.customThemeColor)
      .opacity(0.8)
      .padding({ left: 16, right: 16 })
      .clickEffect({ level: 0, scale: 0.95 })
      .onClick(() => {
        if (!this.manualLoading) {
          // 震动反馈
          try {
            vibrator.startVibration({ type: 'time', duration: 20 }, { id: 0, usage: 'physicalFeedback' });
          } catch (_e) { }
          // 回到顶部
          if (this.externalScroller) {
            this.externalScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 300 } });
          }
          this.manualRefresh();
        }
      })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  build() {
    Stack() {
      Refresh({ refreshing: $$this.isRefreshing, builder: this.customRefreshComponent() }) {
        Scroll(this.externalScroller!) {
          Column() {
            if (this.isLoading && this.dataSource.totalCount() === 0) {
              Row() { LoadingProgress().width(40).height(40).color(this.customThemeColor) }
              .width('100%').height(200).justifyContent(FlexAlign.Center)
            } else {
              // 直接使用 WaterFlow，无需条件重建，columnCount 变化时会自动响应
              WaterFlow() {
                LazyForEach(this.dataSource, (item: RecommendItem, index: number) => {
                  FlowItem() {
                    if (item.id === this.REFRESH_SEPARATOR_ID) {
                      this.RefreshSeparatorCard()
                    } else {
                      this.VideoCard(item)
                    }
                  }
                  .onAppear(() => {
                    // 自动记录浏览过的视频（用于去重）
                    this.autoRecordWatched(item);
                  })
                  .opacity(this.cardsVisible.length > index ? (this.cardsVisible[index] ? 1 : 0) : 1)
                  .scale({
                    x: this.cardsVisible.length > index ? (this.cardsVisible[index] ? 1 : 0.8) : 1,
                    y: this.cardsVisible.length > index ? (this.cardsVisible[index] ? 1 : 0.8) : 1
                  })
                  .translate({
                    y: this.cardsVisible.length > index
                      ? (this.cardsVisible[index] ? 0 : (this.cardTranslateYs[index] || 60))
                      : 0
                  })
                  .animation({
                    duration: 1400,
                    curve: this.isBulkLoading
                      ? curves.springCurve(0.15, 1, 80, 8)
                      : curves.springCurve(0.15, 1, 80, 12)
                  })
                }, (item: RecommendItem, index: number) => `${item.id}_${index}`)
              }
              .columnsTemplate('1fr '.repeat(this.columnCount).trim())
              .columnsGap(12).rowsGap(16)
              .padding({ left: this.sidePadding, right: this.sidePadding, top: this.topPadding, bottom: this.bottomPadding })
              .backgroundColor('transparent')
              .cachedCount(60)
              .clip(false)
              .gesture(PinchGesture().onActionUpdate((event: GestureEvent) => this.handlePinch(event.scale)))
            }
            if (this.isLoadingMore) {
              Row() { LoadingProgress().width(24).height(24).color(this.customThemeColor); Text('努力获取新内容...').fontSize(12).fontColor('#999999').margin({ left: 8 }) }
              .width('100%').height(40).justifyContent(FlexAlign.Center).backgroundColor('transparent')
            } else if (!this.hasMore && this.dataSource.totalCount() > 0) {
              Text('没有更多推荐了，试试“换一批”')
                .fontSize(12).fontColor('#999999').width('100%').height(40).textAlign(TextAlign.Center)
            }
          }.width('100%').clip(false)
        }
        .scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring).backgroundColor('transparent')
        .onWillScroll((_, yOffset: number) => {
          this.scrollOffset = yOffset;
          const absoluteOffset = this.externalScroller!.currentOffset().yOffset;
          const delta = absoluteOffset - this.lastScrollY;

          if (delta > this.SCROLL_THRESHOLD) {
            this.lastScrollY = absoluteOffset;
            this.homeScrollOffset = absoluteOffset;
            AppStorage.set('homeScrollOffset', absoluteOffset);
            AppStorage.set('bottomBarHidden', true);
          } else if (delta < -this.SCROLL_THRESHOLD) {
            AppStorage.set('bottomBarHidden', false);
          }

          this.lastScrollY = absoluteOffset;
          this.homeScrollOffset = absoluteOffset;
          AppStorage.set('homeScrollOffset', absoluteOffset);
        })
        .onReachEnd(() => {
          if (!this.isLoadingMore && !this.isLoading && !this.isRefreshing && this.hasMore) this.loadMore();
        })
      }
      .onStateChange((refreshStatus: RefreshStatus) => {
        if (refreshStatus === RefreshStatus.OverDrag) {
          if (this.longPullTimer !== -1) clearTimeout(this.longPullTimer);
          this.longPullTimer = setTimeout(() => {
            this.showSearchIcon = true;
            this.refreshBuilderText = '释放打开搜索';
            this.longPullTriggered = true;
            // 触发震动反馈
            try {
              vibrator.startVibration({ type: 'time', duration: 25 }, { id: 0, usage: 'physicalFeedback' });
            } catch (err) { }
          }, 800);
        } else if (refreshStatus === RefreshStatus.Drag) {
          if (this.longPullTimer !== -1) clearTimeout(this.longPullTimer);
          // 如果之前已触发长按，现在取消则震动反馈
          if (this.longPullTriggered) {
            try {
              vibrator.startVibration({ type: 'time', duration: 15 }, { id: 0, usage: 'physicalFeedback' });
            } catch (err) { }
          }
          this.showSearchIcon = false;
          this.refreshBuilderText = '下拉刷新';
          this.longPullTriggered = false;
        } else if (refreshStatus === RefreshStatus.Refresh) {
          if (this.longPullTimer !== -1) clearTimeout(this.longPullTimer);
        } else {
          if (this.longPullTimer !== -1) clearTimeout(this.longPullTimer);
          this.showSearchIcon = false;
          this.refreshBuilderText = '下拉刷新';
          this.longPullTriggered = false;
        }
      })
      .onRefreshing(() => {
        if (this.longPullTriggered) {
          this.isRefreshing = false;
          this.showSearchIcon = false;
          this.refreshBuilderText = '下拉刷新';
          this.longPullTriggered = false;
          setTimeout(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/SearchPage' }).catch((err: Error) => {
              logError(`下拉跳转搜索页失败: ${err.message}`);
            });
          }, 100);
          return;
        }
        this.onRefresh();
      })
      .width('100%')
      .height('100%')
      .backgroundColor('transparent')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('transparent')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.isMenuSheetVisible, this.menuSheetContent(), {
      height: SheetSize.FIT_CONTENT,
      backgroundColor: Color.Transparent,
      dragBar: false,
      showClose: false,
      onDisappear: () => {
        this.isMenuSheetVisible = false;
      }
    })
  }
}