import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ConfigStore } from '../store/ConfigStore';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'OpenCodeRemote', '%{public}s', 'Ability onCreate');
    // 初始化本地配置存储（连接参数持久化）
    ConfigStore.init(this.context);
  }

  onDestroy(): void {
    hilog.info(0x0000, 'OpenCodeRemote', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, 'OpenCodeRemote', '%{public}s', 'Ability onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'OpenCodeRemote', 'Failed to load content. code: %{public}d', err.code);
        return;
      }
      hilog.info(0x0000, 'OpenCodeRemote', 'Succeeded in loading content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, 'OpenCodeRemote', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0x0000, 'OpenCodeRemote', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(0x0000, 'OpenCodeRemote', '%{public}s', 'Ability onBackground');
  }
}
