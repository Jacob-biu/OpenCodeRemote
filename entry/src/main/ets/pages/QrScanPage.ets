import { webview } from '@kit.ArkWeb';
import { abilityAccessCtrl, common, PermissionRequestResult } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../common/Constants';
import { ServerConfig } from '../model/Config';
import { PairingParser, PairingLink } from '../common/Pairing';
import { ConfigStore } from '../store/ConfigStore';
import { OpenCodeClient, PairResult } from '../api/OpenCodeClient';

/** 暴露给 Web 侧的 JS 桥（window.qrBridge.onResult / onError） */
class QrBridge {
  scanCallback: (text: string) => void = () => {};
  errorCallback: (msg: string) => void = () => {};

  onResult(text: string): void {
    this.scanCallback(text);
  }

  onError(msg: string): void {
    this.errorCallback(msg);
  }
}

/**
 * 相机内扫码页（HarmonyOS 6.1 相机 API）：
 * - ArkTS：XComponent 实时取景 + 连续自动拍照，识别全程无需点击
 * - ArkWeb：只跑 jsQR 解码，解码器移出屏幕不遮挡取景
 * 识别到二维码后自动解析配对并进入会话列表。
 */
@Entry
@Component
struct QrScanPage {
  @State hint: string = '正在启动相机…';
  @State camReady: boolean = false;
  @State sourceVisible: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private xController: XComponentController = new XComponentController();
  private bridge: QrBridge = new QrBridge();
  private surfaceId: string = '';
  private session: camera.VideoSession | undefined = undefined;
  private photoOutput: camera.PhotoOutput | undefined = undefined;
  private detected: boolean = false;
  private busy: boolean = false;
  private previewRatio: number = 0.75;
  private frames: number = 0;
  private failCount: number = 0;

  aboutToAppear(): void {
    this.bridge.scanCallback = (text: string) => {
      this.handleScanResult(text);
    };
    this.bridge.errorCallback = (msg: string) => {
      this.hint = msg;
    };
    this.requestCameraPermission();
  }

  onPageHide(): void {
    this.stopCamera();
  }

  aboutToDisappear(): void {
    this.stopCamera();
  }

  /** 识别到二维码 → 在本页内完成配对闭环（不依赖跨页回传） */
  private handleScanResult(text: string): void {
    if (this.detected) {
      return;
    }
    this.detected = true;
    hilog.info(0x0000, 'OpenCodeRemote', 'scan decoded: %{public}s', text.substring(0, 120));

    const link: PairingLink = PairingParser.parse(text, '');
    if (!link.ok) {
      this.hint = '无法识别配对内容，请确认是 desktop 的 Pairing 二维码';
      this.detected = false;
      this.nextCapture();
      return;
    }
    this.hint = '配对中… ' + link.host;
    OpenCodeClient.pair(link.host, link.port, link.useHttps, link.code).then((res: PairResult) => {
      if (res.error.length > 0) {
        hilog.error(0x0000, 'OpenCodeRemote', 'pair failed: %{public}s', res.error);
        this.hint = '配对失败：' + res.error + '（将自动重试）';
        this.detected = false;
        setTimeout(() => {
          this.nextCapture();
        }, 1500);
        return;
      }
      const cfg: ServerConfig = new ServerConfig();
      cfg.host = link.host;
      cfg.port = link.port;
      cfg.username = Constants.DEFAULT_USERNAME;
      cfg.password = res.token;
      cfg.useHttps = link.useHttps;
      ConfigStore.save(cfg);
      this.hint = '配对成功，正在进入…';
      this.stopCamera();
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/SessionListPage' });
    });
  }

  /** 动态申请相机权限 */
  private requestCameraPermission(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    atManager.requestPermissionsFromUser(context, ['ohos.permission.CAMERA'])
      .then((res: PermissionRequestResult) => {
        if (res.authResults.length > 0 && res.authResults[0] === 0) {
          this.hint = '相机权限已授予';
        } else {
          this.hint = '未授予相机权限，可用下方「从图中选择」';
        }
      })
      .catch((err: BusinessError) => {
        this.hint = '相机权限申请失败：' + err.message;
      });
  }

  /** 初始化相机：预览 + 连续自动拍照 */
  private async initCamera(): Promise<void> {
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const manager: camera.CameraManager = camera.getCameraManager(context);
      const devices: camera.CameraDevice[] = manager.getCameraDevices(
        camera.CameraPosition.CAMERA_POSITION_BACK,
        [camera.CameraType.CAMERA_TYPE_DEFAULT],
        camera.ConnectionType.CAMERA_CONNECTION_BUILT_IN);
      if (devices.length === 0) {
        this.hint = '未找到后置摄像头';
        return;
      }
      const input: camera.CameraInput = manager.createCameraInput(devices[0]);
      this.hint = '正在打开相机…';
      try {
        await input.open();
      } catch (e) {
        const openErr = e as BusinessError;
        this.hint = '打开相机失败：' + (openErr && openErr.message ? openErr.message : '未知错误');
        return;
      }
      const capability: camera.CameraOutputCapability =
        manager.getSupportedOutputCapability(devices[0], camera.SceneMode.NORMAL_VIDEO);
      if (capability.previewProfiles.length === 0) {
        this.hint = '该相机不支持预览';
        return;
      }
      const previewOutput: camera.PreviewOutput =
        manager.createPreviewOutput(capability.previewProfiles[0], this.surfaceId);
      this.previewRatio = capability.previewProfiles[0].size.width / capability.previewProfiles[0].size.height;
      let photoOutput: camera.PhotoOutput;
      if (capability.photoProfiles.length > 0) {
        photoOutput = manager.createPhotoOutput(capability.photoProfiles[0]);
      } else {
        photoOutput = manager.createPhotoOutput();
      }
      this.photoOutput = photoOutput;
      const session: camera.VideoSession =
        manager.createSession<camera.VideoSession>(camera.SceneMode.NORMAL_VIDEO);
      this.session = session;
      this.hint = '正在配置相机…';
      session.beginConfig();
      session.addInput(input);
      session.addOutput(previewOutput);
      session.addOutput(photoOutput);
      await session.commitConfig();
      this.hint = '正在启动相机…';
      await session.start();
      this.enableAutoFocus(session);

      photoOutput.on('photoAvailable', (err: BusinessError, photo: camera.Photo) => {
        if (err) {
          return;
        }
        this.onPhotoReady(photo);
      });
      photoOutput.on('captureReady', (err: BusinessError) => {
        if (!err) {
          this.nextCapture();
        }
      });
      photoOutput.on('error', (err: BusinessError) => {
        this.hint = '相机错误：' + err.message;
      });

      this.camReady = true;
      this.hint = '对准桌面端 opencode 的配对二维码，识别后自动配对';
      setTimeout(() => {
        this.nextCapture();
      }, 800);
    } catch (e) {
      const err = e as BusinessError;
      this.hint = '相机启动失败：' + (err && err.message ? err.message : '未知错误');
    }
  }

  /** 开启连续自动对焦 */
  private enableAutoFocus(session: camera.VideoSession): void {
    try {
      if (session.isFocusModeSupported(camera.FocusMode.FOCUS_MODE_CONTINUOUS_AUTO)) {
        session.setFocusMode(camera.FocusMode.FOCUS_MODE_CONTINUOUS_AUTO);
      }
    } catch (e) {
      // 对焦能力不可用时保持默认行为
    }
  }

  private stopCamera(): void {
    const session: camera.VideoSession | undefined = this.session;
    this.session = undefined;
    this.photoOutput = undefined;
    if (session !== undefined) {
      session.stop().catch(() => {
      });
    }
  }

  /** 连续自动拍照：识别全程无需用户点击 */
  private nextCapture(): void {
    if (this.detected || this.busy) {
      return;
    }
    const po: camera.PhotoOutput | undefined = this.photoOutput;
    if (po === undefined) {
      return;
    }
    this.busy = true;
    setTimeout(() => {
      if (this.detected) {
        this.busy = false;
        return;
      }
      po.capture().then(() => {
        this.busy = false;
      }).catch((e: BusinessError) => {
        this.busy = false;
        this.failCount += 1;
        if (this.failCount <= 20) {
          setTimeout(() => {
            this.nextCapture();
          }, 400);
        } else {
          this.hint = '连续拍照失败：' + (e && e.message ? e.message : '未知错误');
        }
      });
    }, 120);
  }

  /** 一帧照片 → JPEG 字节 → base64 → 交给 Web 的 jsQR 解码 */
  private onPhotoReady(photo: camera.Photo): void {
    if (this.detected) {
      return;
    }
    photo.main.getComponent(image.ComponentType.JPEG).then((comp: image.Component) => {
      this.frames += 1;
      const helper: util.Base64Helper = new util.Base64Helper();
      const b64: string = helper.encodeToStringSync(new Uint8Array(comp.byteBuffer));
      this.controller.runJavaScript('qrDecodeBase64(' + JSON.stringify(b64) + ')');
    }).catch(() => {
    });
    this.nextCapture();
  }

  // ---------------- 从图片中取二维码 ----------------

  /** 图库选择 */
  private onPickGallery(): void {
    this.sourceVisible = false;
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      picker.select().then((res: photoAccessHelper.PhotoSelectResult) => {
        if (res.photoUris.length > 0) {
          this.hint = '正在识别…';
          this.decodeUri(res.photoUris[0]);
        }
      }).catch(() => {
        this.hint = '已取消选择';
      });
    } catch {
      this.hint = '无法打开图库';
    }
  }

  /** 相机拍摄 */
  private onPickCamera(): void {
    this.sourceVisible = false;
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    const savePath: string = context.filesDir + '/qr_scan.jpg';
    const profile: cameraPicker.PickerProfile = {
      cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
      saveUri: 'file://' + savePath
    };
    cameraPicker.pick(context, [cameraPicker.PickerMediaType.PHOTO], profile)
      .then((res: cameraPicker.PickerResult) => {
        if (res.resultCode !== 0) {
          this.hint = '已取消拍摄';
          return;
        }
        this.hint = '正在识别…';
        this.decodeUri('file://' + savePath);
      })
      .catch(() => {
        this.hint = '已取消拍摄';
      });
  }

  /** 文件选择 */
  private onPickFile(): void {
    this.sourceVisible = false;
    try {
      const options: picker.DocumentSelectOptions = { maxSelectNumber: 1 };
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      docPicker.select(options).then((uris: string[]) => {
        if (uris.length > 0) {
          this.hint = '正在识别…';
          this.decodeUri(uris[0]);
        }
      }).catch(() => {
        this.hint = '已取消选择';
      });
    } catch {
      this.hint = '无法打开文件选择器';
    }
  }

  /** 读取图片字节并送去解码 */
  private decodeUri(uri: string): void {
    try {
      const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat: fileIo.Stat = fileIo.statSync(file.fd);
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file.fd);
      const helper: util.Base64Helper = new util.Base64Helper();
      const b64: string = helper.encodeToStringSync(new Uint8Array(buffer));
      this.controller.runJavaScript('qrDecodeBase64(' + JSON.stringify(b64) + ')');
    } catch (e) {
      this.hint = '读取图片失败，请改用「文件选择」';
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ===== 取景区 =====
      Column({ space: 0 }) {
        Row({ space: 10 }) {
          Image($r('app.media.icon_back'))
            .width(22)
            .height(22)
            .fillColor(Color.White)
            .borderRadius(11)
            .stateStyles({
              pressed: {
                .opacity(0.5)
                .scale({ x: 0.9, y: 0.9 })
              },
              normal: {
                .opacity(1)
                .scale({ x: 1, y: 1 })
              }
            })
            .onClick(() => {
              this.getUIContext().getRouter().back();
            })
          Text('扫描配对码')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
          Blank()
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 14, bottom: 12 })
        .backgroundColor(Color.Black)

        Stack({ alignContent: Alignment.Center }) {
          XComponent({ id: 'qr_camera', type: XComponentType.SURFACE, controller: this.xController })
            .aspectRatio(this.previewRatio)
            .width('100%')
            .onLoad(() => {
              this.surfaceId = this.xController.getXComponentSurfaceId();
              this.initCamera();
            })

          // 取景框（只描边，不遮挡画面）
          Column() {
            Blank()
            Row() {
              Blank()
              Column() {
                Blank()
              }
              .width('74%')
              .height(230)
              .border({ width: 2, color: '#0A6CFF' })
              .borderRadius(16)
              Blank()
            }
            .width('100%')
            .height(230)
            Blank()
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Block)

          // jsQR 解码器：移出屏幕（保持 JS 上下文运行，不遮挡取景）
          Web({ src: $rawfile('qr/scan.html'), controller: this.controller })
            .width(200)
            .height(120)
            .translate({ x: -2000 })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .onPermissionRequest((event: OnPermissionRequestEvent) => {
              event.request.grant(['camera']);
            })
            .onControllerAttached(() => {
              this.controller.registerJavaScriptProxy(this.bridge, 'qrBridge', ['onResult', 'onError']);
            })
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(Color.Black)

        // 底部操作条
        Row({ space: 10 }) {
          Button('从图中选择二维码')
            .height(38)
            .fontSize(13)
            .backgroundColor('rgba(255,255,255,0.14)')
            .fontColor(Color.White)
            .onClick(() => {
              this.sourceVisible = true;
            })
            .bindSheet($$this.sourceVisible, this.SourceSheetBuilder(), {
              // 内容为标题 + 3 行来源（约 734px，每行约 198px），按内容收紧：
              // 20% 会裁掉第三行「文件选择」，28% 留少量余量
              height: '28%',
              dragBar: true,
              showClose: true,
              backgroundColor: $r('app.color.card_bg')
            })
          Text(this.hint)
            .fontSize(12)
            .fontColor('#9AA5B4')
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 14 })
        .backgroundColor(Color.Black)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)

    .width('100%')
    .height('100%')
  }

  }
  @Builder
  private SourceRow(title: string, desc: string, icon: string, kind: number) {
    Row({ space: 12 }) {
      Image($r(`app.media.${icon}`))
        .width(26)
        .height(26)
        .fillColor($r('app.color.text_primary'))
      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        Text(desc)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Image($r('app.media.icon_chevron'))
        .width(18)
        .height(18)
        .fillColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .stateStyles({
      pressed: {
        .opacity(0.6)
      },
      normal: {
        .opacity(1)
      }
    })
    .onClick(() => {
      if (kind === 0) {
        this.onPickGallery();
      } else if (kind === 1) {
        this.onPickCamera();
      } else {
        this.onPickFile();
      }
    })
  }

  @Builder
  private SourceSheetBuilder() {
    Column({ space: 6 }) {
      Text('选择二维码来源')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ top: 6, bottom: 4 })
      this.SourceRow('图库选择', '从相册中挑选二维码图片', 'icon_image', 0)
      this.SourceRow('相机拍摄', '拍摄一张二维码图片', 'icon_camera', 1)
      this.SourceRow('文件选择', '从文件中选择二维码图片', 'icon_file', 2)
      Blank()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, bottom: 12 })
    .backgroundColor($r('app.color.card_bg'))
  }
}
