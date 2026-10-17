// CardStyleMode.ts - 卡片样式「深浅色独立」档案：深/浅模式各存一份，切换时自动装载
// 参考 WallpaperTheme 深浅色双档案思路（wallpaperLight/wallpaperDark）。

import { preferences } from '@kit.ArkData';

/** 进入模式档案的样式键（风格相关，功能开关不入档） */
export const CARD_STYLE_MODE_KEYS: string[] = [
  'cardTransparentStyle',
  'cardTransparentStyleVideo',
  'cardBorderOpacity',
  'cardBgOpacity',
  'cardBorderWidth',
  'cardBorderFollowTheme',
  'cardBorderFollowPlayCount',
  'cardCapsuleShow',
  'cardCapsuleFollowTheme',
  'cardCapsuleSize',
  'cardCapsuleRadius',
  'cardCapsuleColor',
  'cardPlayCountShow',
  'cardPlayCountIcon',
  'cardPlayCountSize',
  'cardPlayCountColorMode',
  'cardPlayCountColor',
  'cardCustomColor',
  'cardListBorderRadius',
  'cardListMargin',
  'playerFollowTheme',
  'cardBorderRadius',
  'cardMargin',
  'cardBgBlurAmount',
  'cardBgDarkness'
];

export function cardStyleModeArchiveKey(dark: boolean): string {
  return dark ? 'cardStyleModeDark' : 'cardStyleModeLight';
}

/** 把当前激活值整体写入当前模式的档案（AppStorage 为值来源） */
export async function persistCardStyleModeArchive(pref: preferences.Preferences, dark: boolean): Promise<void> {
  try {
    const obj: Record<string, number | string | boolean> = {};
    for (const k of CARD_STYLE_MODE_KEYS) {
      const v = AppStorage.get<number | string | boolean>(k);
      if (v !== undefined) {
        obj[k] = v;
      }
    }
    await pref.put(cardStyleModeArchiveKey(dark), JSON.stringify(obj));
    await pref.flush();
  } catch (e) {
    // 归档失败不影响主流程（下次修改会重写）
  }
}

/** 装载某模式的档案到激活键；无档案时保持当前值 */
export async function applyCardStyleModeArchive(pref: preferences.Preferences, dark: boolean): Promise<void> {
  try {
    const json = await pref.get(cardStyleModeArchiveKey(dark), '') as string;
    if (!json) return;
    const obj = JSON.parse(json) as Record<string, number | string | boolean>;
    for (const k of CARD_STYLE_MODE_KEYS) {
      const v = obj[k];
      if (v !== undefined && v !== null) {
        AppStorage.set(k, v);
      }
    }
  } catch (e) {
    // 档案损坏时静默跳过
  }
}
