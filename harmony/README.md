# 成长日记 - HarmonyOS 版

<p align="center">
  <img width="160" src="../assets/images/logo.svg">
</p>

基于现有 Flutter 版本功能，使用 **ArkTS + ArkUI** 开发的 HarmonyOS 原生应用版本。

---

## 功能特点

与 Flutter 版保持一致的完整功能：

- 📝 **文字记录**：添加标题和描述，记录宝宝的趣事和成长里程碑
- 📅 **时间轴展示**：按月龄/年龄分组展示所有记录，形成时间轴视图
- ✏️ **记录编辑**：支持编辑已有记录的标题、描述和日期
- 🗑️ **删除记录**：点击删除按钮删除记录（同步删除 WebDAV 媒体文件）
- 📷 **照片上传**：从相册选取照片，自动生成缩略图并上传至 WebDAV
- 🎬 **视频上传**：从相册选取视频并上传至 WebDAV
- 🖼️ **媒体浏览**：详情页展示照片网格，支持全屏预览；视频显示缩略图
- 👶 **多宝宝管理**：支持添加多个宝宝配置，快速切换，独立数据存储
- 📱 **配置分享**：生成含 XOR 加密的配置数据，与 Flutter 版 QR 码格式完全兼容；支持复制/粘贴方式导入
- ⬆️ **后台上传队列**：上传失败时自动加入队列，重新联网后可重试；主界面显示待上传数量
- ☁️ **WebDAV 存储**：与 Flutter 版共用同一套 WebDAV 数据存储，数据互通
- 🔄 **跨设备同步**：配置和日记条目存储在 WebDAV 服务器，多设备可共享
- 🎨 **粉色系界面**：与 Flutter 版风格保持一致的现代化简洁设计

---

## 技术栈

| 技术 | 说明 |
|------|------|
| **ArkTS** | HarmonyOS 官方编程语言（基于 TypeScript） |
| **ArkUI** | HarmonyOS 声明式 UI 框架 |
| **@ohos.net.http** | 网络请求（用于 WebDAV 通信） |
| **@ohos.data.preferences** | 本地偏好设置存储 |
| **@ohos.file.picker** | 相册选取（PhotoViewPicker） |
| **@ohos.file.fs** | 本地文件系统（缓存媒体文件） |
| **@ohos.multimedia.image** | 图片解码/缩放/编码（缩略图生成） |
| **@ohos.pasteboard** | 剪贴板（配置数据复制/粘贴） |
| **HarmonyOS SDK 5.0 (API 12)** | 目标平台 SDK |

---

## 项目结构

```
harmony/
├── AppScope/                          # 应用级资源
│   ├── app.json5                      # 应用配置
│   └── resources/base/
│       └── element/string.json        # 应用名称
├── entry/
│   ├── src/main/
│   │   ├── ets/
│   │   │   ├── entryability/
│   │   │   │   └── EntryAbility.ets   # 应用入口 Ability
│   │   │   ├── model/
│   │   │   │   ├── DiaryEntry.ets     # 日记条目模型 + 年龄计算
│   │   │   │   └── AppConfig.ets      # 应用配置模型
│   │   │   ├── service/
│   │   │   │   ├── PreferencesService.ets  # 本地存储服务
│   │   │   │   ├── WebDAVService.ets       # WebDAV 网络服务
│   │   │   │   ├── MediaService.ets        # 媒体选取/上传/缓存服务
│   │   │   │   ├── QRService.ets           # QR 数据加密/解密服务
│   │   │   │   └── UploadQueueService.ets  # 后台上传队列服务
│   │   │   └── pages/
│   │   │       ├── Index.ets          # 主页（时间轴 + 多宝宝切换）
│   │   │       ├── Setup.ets          # 初始设置页
│   │   │       ├── DiaryEditor.ets    # 日记编辑页（含照片/视频上传）
│   │   │       ├── DiaryDetail.ets    # 日记详情页（照片网格 + 全屏预览）
│   │   │       ├── Settings.ets       # 设置页（多宝宝管理 + QR 分享入口）
│   │   │       └── QRShare.ets        # 配置分享 / 导入页
│   │   ├── resources/
│   │   │   └── base/
│   │   │       ├── element/           # 字符串、颜色资源
│   │   │       └── profile/
│   │   │           └── main_pages.json  # 页面路由配置
│   │   └── module.json5               # 模块配置（权限等）
│   ├── build-profile.json5
│   ├── hvigorfile.ts
│   └── oh-package.json5
├── build-profile.json5                # 工程构建配置
├── hvigorfile.ts
└── oh-package.json5                   # 工程依赖配置
```

---

## 数据兼容性

HarmonyOS 版与 Flutter 版使用完全相同的 WebDAV 数据格式：

```
growth_diary/<baby-id>/
├── config.json           # 应用配置
├── entries/              # 日记条目 JSON 文件
│   ├── <entry-id>.json
│   └── ...
├── media/                # 原始媒体文件（Flutter 版上传）
└── thumbnails/           # 缩略图文件（Flutter 版生成）
```

两个版本可以共用同一台 WebDAV 服务器，**数据完全互通**。

---

## 开发环境搭建

### 前提条件

1. 安装 [DevEco Studio](https://developer.harmonyos.com/cn/develop/deveco-studio) **5.0.3** 或更高版本（DevEco Studio 5.0.3 起支持 HarmonyOS SDK 5.0 / API 12）
2. 安装 HarmonyOS SDK 5.0（API Level 12）
3. 准备一台运行 HarmonyOS 5.0+ 的设备或模拟器

### 打开项目

1. 启动 DevEco Studio
2. 选择 **File > Open...**
3. 导航到本仓库下的 `harmony/` 目录并打开
4. 等待 DevEco Studio 完成 Gradle/hvigor 同步

### 运行应用

1. 连接 HarmonyOS 设备（或启动模拟器）
2. 点击工具栏的 **Run** 按钮，或按 `Shift+F10`
3. 选择目标设备后，应用将自动构建并部署

### 构建 HAP 安装包

```bash
# 在 harmony/ 目录下执行
hvigorw assembleHap --mode module -p product=default -p buildMode=release
```

构建产物位于 `harmony/entry/build/default/outputs/default/`。

---

## 首次使用

1. 启动应用后显示 **初始设置** 界面
2. 填写宝宝信息：
   - 宝宝昵称（必填）
   - 宝宝生日（可选，用于计算年龄）
3. 配置 WebDAV 连接：
   - 服务器地址（必填，如 `https://nextcloud.example.com/remote.php/dav/files/user/`）
   - 用户名（必填）
   - 密码（必填）
4. 点击 **完成设置**
5. 开始添加成长记录！

---

## 与 Flutter 版的功能对比

| 功能 | Flutter 版 | HarmonyOS 版 |
|------|-----------|-------------|
| 文字记录 | ✅ | ✅ |
| 时间轴展示 | ✅ | ✅ |
| 编辑/删除记录 | ✅ | ✅ |
| WebDAV 同步 | ✅ | ✅ |
| 设置管理 | ✅ | ✅ |
| 照片上传 | ✅ | ✅ |
| 视频上传 | ✅ | ✅ |
| 照片浏览/全屏预览 | ✅ | ✅ |
| 视频播放 | ✅ | 🚧 视频列表已支持，内置播放器待集成 |
| 多宝宝管理 | ✅ | ✅ |
| QR 码分享 | ✅ | ✅ (复制/粘贴，数据格式兼容 Flutter) |
| 后台上传任务队列 | ✅ | ✅ |
| 视频缩略图自动生成 | ✅ | 🚧 依赖 Flutter 端生成，HarmonyOS 端展示 |

> **视频播放**：当前版本已显示视频列表及缩略图（Flutter 端生成），内置视频播放器（`XComponent + AVPlayer`）将在后续迭代中集成。
>
> **QR 码**：HarmonyOS 端使用复制/粘贴方式传递配置，数据格式与 Flutter 版 QR 码完全一致（相同 XOR 加密 + Base64），两端可互相导入。
