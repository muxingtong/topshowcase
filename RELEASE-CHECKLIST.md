# 展物 · 上架流程梳理

> 基于本仓库**当前实际状态**逐项核对得出，不是通用清单。
> 第 0 节是现在就能看到的阻塞项，第 1~6 节是可依次推进的流程。

---

## 更新记录（HarmonyOS 7 / API 26 升级）

- 工程级 `build-profile.json5`：`compatibleSdkVersion` / `targetSdkVersion` 已升级到 `26.0.0`。
- 工程级 `oh-package.json5` 与 `hvigor/hvigor-config.json5`：`modelVersion` 已升级到 `7.0.0`。
- 修复废弃 API：`GalleryViews.ets` 中 `List.onScroll` 已替换为 `onScrollFrameBegin`。
- 签名配置已清空为 `"signingConfig": ""`，当前使用未签名 debug 包在模拟器验证。
- 大版本迭代：版本号升级到 `2.0.0`（versionCode `2000000`）。
- 已移除 rawfile 测试种子图与 `READ_IMAGEVIDEO` 权限，回归正式空态。
- 已在两台 HarmonyOS 7 模拟器验证 UI：
  - 手机（Pura X View / 1320×2232 竖屏）：网格 3 列正常显示 12 件藏品。
  - 平板（MatePad Pro 13 / 2880×1920 横屏）：网格自动扩展到 7 列。

> 注：正式上架前请在 DevEco Studio 中生成发布签名并回填 `build-profile.json5`。

---

## 0. 当前状态体检

### 🔴 阻塞项（不改就过不了）

| # | 问题 | 现状 | 位置 |
|---|---|---|---|
| 1 | **签名已清空** | 当前 `signingConfig` 为空，仅用于模拟器调试；上架必须换成**发布证书 + 发布 Profile** | [build-profile.json5](build-profile.json5) |
| 2 | **vendor 是模板默认值** | `"vendor": "example"` | [app.json5](AppScope/app.json5) |

上架必须用**发布证书 + 发布 Profile**。未签名包或调试证书签出的包 AGC 会直接拒收。

### 🟡 需要确认（可能需要改）

| # | 项 | 现状 | 处理 |
|---|---|---|---|
| 3 | **deviceTypes 声明了三种设备** | `phone` / `tablet` / `2in1` | phone / tablet 已在 HarmonyOS 7 模拟器验证；`2in1` 尚未实测，不打算适配就裁掉 |
| 4 | versionCode | `2000000` | 大版本迭代已递增 |
| 5 | versionName | `"2.0.0"` | 用户可见版本号，已随大版本升级 |
| 6 | 应用名只有中文 | `app_name = 展物` | 只在国内上架可接受；有海外计划需补 `en_US` 等 `string.json` |

### 🟢 已就绪

| 项 | 状态 |
|---|---|
| 应用图标（分层） | `AppScope/resources/base/media/` 下 background + foreground，均 1024×1024 PNG |
| 上架直角图标 | `store-icon/app_icon_1024.png` / `app_icon_216.png` |
| 启动图标 | `startWindowIcon = $media:startIcon`（512×512） |
| 权限 | **未申请敏感权限**——导入导出全走系统选择器（`PhotoViewPicker` / `DocumentViewPicker`），用户主动选择 |
| 无障碍/深色模式 | 已有 `base` / `dark` 两套完整配色 |
| 横竖屏 | 已适配，并在手机竖屏 / 平板横屏验证 |
| API 版本 | 已升级到 HarmonyOS 7（API 26），模拟器验证通过 |
| 版本号 | 已升级到 `2.0.0`（versionCode `2000000`）|

---

## 1. AGC 侧准备

- [ ] 注册**华为开发者账号**（企业或个人）
- [ ] 完成**实名认证**（个人需身份证+人脸；企业需营业执照。未认证无法上架）
- [ ] 登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html)
- [ ] 创建应用：**包名必须填 `com.mu.showcase`**（与代码严格一致，创建后不可改）
- [ ] 填写应用分类（本项目属「工具 > 相册/图库」一类）
- [ ] 申请**发布证书**（.cer）
- [ ] 申请**发布 Profile**（.p7b），绑定上面那个证书

> 调试证书和发布证书是两套东西。DevEco 里 `Project Structure > Signing Configs` 可以自动申请，也可以手动在 AGC 生成后导入。

---

## 2. 改代码与配置

- [ ] `AppScope/app.json5`：`"vendor"` 从 `"example"` 改成真实开发者/公司名
- [ ] `build-profile.json5`：把 `signingConfigs` 换成发布证书
  - `storeFile` → 发布用 `.p12`
  - `certpath` → 发布证书 `.cer`
  - `profile` → 发布 Profile `.p7b`
  - `keyAlias` → 你创建密钥库时设的别名（不再是 `debugKey`）
  - `storePassword` / `keyPassword` → 正式密码
- [ ] `versionCode` 确认递增（首次上架保持当前值即可）
- [ ] 若不做平板/PC 适配，从 `deviceTypes` 裁掉 `tablet` / `2in1`

> **签名密码是 DevEco 加密存储的形式**（`00000020` 开头的十六进制串），不是明文，但也**与本地机器绑定**——换机器或多人协作时需要重新输入。当前仅用于本应用的调试签名，风险可控；换成发布证书后建议把 `signingConfigs` 抽到本地未跟踪的文件，避免证书路径与密码散播。

---

## 3. 构建 Release 包

- [ ] DevEco 里切到 `release` 构建模式（`buildModeSet` 里已配好 `release`）
- [ ] 编译通过，无 error
- [ ] 产物是 **`.app`**（App Pack，不是 `.hap`）——AGC 收的是 `.app`
- [ ] 上架包**不要**勾选调试相关选项

---

## 4. AGC 填写应用资料

### 4.1 素材

- [ ] 应用图标：`store-icon/app_icon_1024.png`（1024×1024 PNG，34.7 KB）
  - 或 `app_icon_216.png`（216×216，4.4 KB）
  - 两者都满足「正方形 / 直角 / PNG ≤3MB」
- [ ] 应用截图：**手机至少 3 张**，建议覆盖主要排布（网格 / 长廊 / 展台 / 详情页）
  - 平板、PC 若在 `deviceTypes` 里声明了，**各自也要截图**
- [ ] 应用介绍、一句话简介、更新说明

### 4.2 合规（这一段最容易被拒）

- [ ] **隐私政策**：必须有一个可公网访问的 URL
  - 本项目要写清楚：**图片只存本地沙箱，不上传任何服务器，不采集任何个人信息**
  - 但用了 `photoAccessHelper` / `FilePicker`，要说明"仅在你主动选择时读取所选文件"
- [ ] **权限使用说明**：本项目**没有申请任何权限**，如实声明即可
  - 这一点要主动写进说明，很多审核员会默认相册类应用申请了存储权限
- [ ] **内容分级**：按实际内容勾选
- [ ] **个人信息处理说明**：声明不收集个人信息

---

## 5. 上传与提审

- [ ] 上传 `.app` 包，等 AGC 校验通过（校验版本号、签名、权限）
- [ ] 填写测试说明（审核员需要知道怎么验证功能）
  - 建议写明：**打开 App → 点右下「＋」→ 从系统相册选几张图 → 用底部三颗胶囊切换排布（含长廊、展台）→ 点任意图片进详情**
  - App 本身不带预置素材，审核员首次打开会看到空状态——**这点必须提前说明**，否则容易被判"功能不完整"
- [ ] 提交审核

---

## 6. 审核与发布

- [ ] 跟进审核结果（通常会给具体驳回理由）
- [ ] 通过后选择**定时发布**或**立即发布**
- [ ] 发布后验证：从应用市场装一次，确认与开发包一致

---

## 二、本项目需要特别当心的三件事

### 1. 空状态是第一印象

审核员装完打开，看到的是「还没有藏品 / 点击右下角「＋」添加照片或视频」。**如果测试说明里没解释，很可能被判功能缺失。**

要么在提审说明里写清操作路径，要么考虑加一份可选的示例素材。

### 2. `deviceTypes` 声明了就要做到

声明 `tablet` / `2in1` 意味着审核员**可能用平板或 PC 测**。刚做的横屏适配（长廊转横向、详情页左右并排、网格列数自适应）需要真机验证过再提审。

三个自查点：
- 旋转时是否有明显闪烁或重排
- 横屏长廊的焦点是否落在屏幕正中的那一列
- 横屏详情页右侧栏（320vp）在 360vp 屏高下，内容会不会被裁掉

### 3. 签名配置的协作问题

`build-profile.json5` 里那串 `00000020BBB6E266...` 是 **DevEco 加密后的密码**，不是明文——所以不存在"密码泄露"的问题。

但它**与本地机器绑定**：换机器、换同事、或在 CI 上构建时，这些密文解不开，必须重新输入。而且 `certpath` / `profile` / `storeFile` 都是 `/storage/Users/currentUser/Documents/ohos/config/` 下的**绝对路径**。

换成发布证书后，建议把 `signingConfigs` 整段抽到本地未跟踪的文件里，仓库只留一份占位配置。否则这个项目在别人机器上根本构建不了。

---

## 三、建议的推进顺序

严格按这个顺序，避免返工：

```
1. AGC 注册 + 实名认证          ← 最耗时，先启动
2. AGC 创建应用（包名 com.mu.showcase）
3. 申请发布证书 + Profile
4. 改 vendor + 换发布签名
5. 真机验证 tablet / 2in1 适配    ← 决定要不要保留 deviceTypes
6. 构建 release .app
7. 准备截图 + 隐私政策 URL        ← 可并行
8. 上传 + 填资料 + 提审
```

**第 1 步最慢，建议立刻启动**，其余步骤可以在等待认证期间并行准备。

---

## 附：相关文件索引

| 用途 | 路径 |
|---|---|
| 应用配置（包名/版本/vendor/图标） | `AppScope/app.json5` |
| 模块配置（设备类型/Ability/启动图标） | `showcase/src/main/module.json5` |
| 签名与构建模式 | `build-profile.json5` |
| 应用名 | `AppScope/resources/base/element/string.json` |
| 分层图标素材 | `AppScope/resources/base/media/` |
| 上架直角图标 | `store-icon/` |
| 图标合成脚本 | `tools/make_store_icon.py` |
| UI 设计规范 | `UI-DESIGN.md` |
