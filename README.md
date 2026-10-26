# OpenCodeRemote — opencode HarmonyOS 遥控客户端

一个 [opencode（AI 编码代理）](https://opencode.ai) 的 HarmonyOS 移动端遥控应用。
把运行在你电脑上的 opencode 服务"装进口袋"：手机上扫码配对后，随时浏览会话、
发送指令 / 提问、查看 AI 产出的 Markdown 渲染结果，并对 Agent 的敏感操作做**权限审批**。

> bundle name：`com.opencode.remote` ｜ 模块：`entry` ｜ 语言：ArkTS（ArkUI 声明式 UI）

## 功能特性

- **扫码配对**：解析桌面端 opencode `Pairing → Copy link` 的配对二维码 /
  链接 / 纯配对码（一次性，5 分钟有效），兑换 token 后以 Basic Auth 连接服务端。
- **多服务器管理**：保存多台 opencode 服务器（隧道地址、HTTPS、token），一键切换。
- **会话列表**：按更新时间展示历史会话，支持重命名（`PATCH /api/session/{id}`）、
  新建会话，定时轮询自动刷新。
- **会话详情 / 对话**：查看完整消息流，Markdown 渲染回复；发送 prompt、
  追加图片附件（data URL 内联上传）、停止生成。
- **权限审批**：Agent 触发危险操作时弹出权限请求卡片，手机端直接
  允许 / 拒绝（`POST /api/session/{id}/permission/{requestID}/reply`）。
- **模型切换**：拉取可用模型列表并切换当前会话模型；支持 Agent / Command 信息查看。
- **设置面板**：服务器、模型、连接状态等配置持久化存储在设备端。

## 项目结构

```text
harmonyOS/
├── AppScope/                     # 应用级配置（app.json5、资源）
├── entry/                        # 主模块（entry）
│   ├── build-profile.json5       # 模块级构建配置
│   └── src/main/
│       ├── module.json5          # 模块配置 + 权限声明（INTERNET / CAMERA）
│       └── ets/
│           ├── entryability/     # UIAbility 入口
│           ├── api/              # OpenCodeClient（REST 封装）、Parsers
│           ├── common/           # 常量、配对解析（Pairing）、工具类
│           ├── components/       # UI 组件（消息气泡、Markdown、权限卡片、
│           │                     #   连接面板、附件/模型/设置面板……）
│           ├── model/            # 数据模型（Session / Message / Model / Agent…）
│           ├── pages/            # 页面：首页、扫码、会话列表、会话详情、设置
│           └── store/            # 本地持久化（ConfigStore / ServerStore）
├── hvigor/                       # hvigor 构建系统配置
├── build-profile.json5           # 工程级构建配置（签名、products、modules）
├── hvigorfile.ts                 # 工程级构建脚本
└── oh-package.json5              # 依赖管理
```

## 环境要求

- **DevEco Studio**（建议 6.x 及以上）
- HarmonyOS SDK：兼容 `6.0.2(22)`，目标 `6.1.1(24)`
- 真机 / 模拟器：phone、tablet、2in1
- 一台运行 opencode 的电脑（服务端，通过隧道/局域网可达）

## 构建与安装

在工程根目录执行（Windows 示例，SDK 路径按本机情况调整）：

```powershell
$env:DEVECO_SDK_HOME = "D:\Software\Huawei\DevEco Studio\sdk"
& "D:\Software\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" `
    assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

产物在 `entry/build/default/outputs/default/entry-default-signed.hap`，
用 `hdc` 安装到设备：

```bash
hdc install -r entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.opencode.remote
```

也可以直接在 DevEco Studio 中打开工程，点击 Run。

## 使用说明

1. 在电脑上启动 opencode，打开 **Pairing** 面板，把二维码 / 配对链接准备好。
2. 在手机 App 中点击连接 → 扫码（或粘贴链接 / 仅粘贴配对码）。
3. 配对码一次性、5 分钟内有效；兑换成功后 token 以 Basic Auth
   （用户名 `opencode`）自动保存在服务器配置中。
4. 选择服务器即可开始浏览会话、发消息、审批权限、切换模型。

## 权限说明

| 权限 | 用途 |
| --- | --- |
| `ohos.permission.INTERNET` | 连接 opencode 服务端 |
| `ohos.permission.CAMERA` | 扫描桌面端配对二维码 |
