# 成长日记 - HarmonyOS 版

<p align="center">
  <img width="160" src="../assets/images/logo.svg">
</p>

基于现有 Flutter 版本功能，使用 **ArkTS + ArkUI** 开发的 HarmonyOS 原生应用版本。

---

## 功能特点

与 Flutter 版保持一致的核心功能：

- 📝 **文字记录**：添加标题和描述，记录宝宝的趣事和成长里程碑
- 📅 **时间轴展示**：按月龄/年龄分组展示所有记录，形成时间轴视图
- ✏️ **记录编辑**：支持编辑已有记录的标题、描述和日期
- 🗑️ **删除记录**：长按或点击删除按钮删除记录（同步删除 WebDAV 媒体文件）
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
│   │   │   │   └── WebDAVService.ets       # WebDAV 网络服务
│   │   │   └── pages/
│   │   │       ├── Index.ets          # 主页（时间轴）
│   │   │       ├── Setup.ets          # 初始设置页
│   │   │       ├── DiaryEditor.ets    # 日记编辑页
│   │   │       ├── DiaryDetail.ets    # 日记详情页
│   │   │       └── Settings.ets       # 设置页
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

## 与 Flutter 版的功能差异

| 功能 | Flutter 版 | HarmonyOS 版 |
|------|-----------|-------------|
| 文字记录 | ✅ | ✅ |
| 时间轴展示 | ✅ | ✅ |
| 编辑/删除记录 | ✅ | ✅ |
| WebDAV 同步 | ✅ | ✅ |
| 设置管理 | ✅ | ✅ |
| 照片上传 | ✅ | 🚧 计划中 |
| 视频上传 | ✅ | 🚧 计划中 |
| 视频播放 | ✅ | 🚧 计划中 |
| 多宝宝管理 | ✅ | 🚧 计划中 |
| QR 码分享 | ✅ | 🚧 计划中 |
| 后台上传任务 | ✅ | 🚧 计划中 |

> HarmonyOS 版当前实现了核心的文字日记功能和 WebDAV 数据同步。
> 媒体文件（照片/视频）可通过 Flutter 版录入，HarmonyOS 版可查看媒体数量信息。
