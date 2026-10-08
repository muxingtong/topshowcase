import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { resourceManager } from '@kit.LocalizationKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;
const TAG = 'testTag';

export default class ShowcaseAbility extends UIAbility {
  private mainWindow: window.Window | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    // 沉浸式：内容铺满整屏（延伸到状态栏 / 导航栏之下）
    try {
      const win = windowStage.getMainWindowSync();
      this.mainWindow = win;
      win.setWindowLayoutFullScreen(true);
      this.applySystemBars(win);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'immersive setup failed: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
    });
  }

  // 系统深浅色切换时同步状态栏图标颜色
  onConfigurationUpdate(newConfig: Configuration): void {
    if (this.mainWindow !== null) {
      this.applySystemBars(this.mainWindow);
    }
  }

  private applySystemBars(win: window.Window): void {
    let dark: boolean = false;
    try {
      const cfg = this.context.resourceManager.getConfigurationSync();
      dark = cfg.colorMode === resourceManager.ColorMode.DARK;
    } catch (err) {
      dark = false;
    }
    const content: string = dark ? '#FFFFFF' : '#000000';
    const props: window.SystemBarProperties = {
      statusBarContentColor: content,
      navigationBarContentColor: content
    };
    try {
      win.setWindowSystemBarProperties(props);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}
