<p align="center">
  <img width="200" src="./assets/images/logo.svg">
</p>

<h1 align="center">成长日记 (Growth Diary)</h1>

<p align="center">一个用于记录孩子从出生到现在的成长日记应用，基于 Flutter 开发的跨平台 App。</p>

## 功能特点

- 📸 **多媒体支持**: 支持上传照片和视频记录宝宝的成长瞬间
- 🎬 **视频播放增强**: 支持多视频播放、左右滑动切换、自动播放下一个视频
- 📝 **文字记录**: 可以添加文字描述，记录宝宝的趣事和成长里程碑
- ✏️ **记录编辑**: 支持编辑已有记录的描述和日期，编辑后保持在详情页
- 📅 **时间轴展示**: 按照宝宝年龄（月龄/岁数）组织记录，形成时间轴视图
- ☁️ **WebDAV 存储**: 使用 WebDAV 作为数据存储，支持自建服务器或第三方服务
- 🔄 **跨设备同步**: 配置信息存储在 WebDAV 中，可在多设备间同步
- 🎨 **简洁可爱**: 现代化的粉色系界面，简洁友好

## 年龄标记系统

- 出生 (0月龄)
- 1月龄, 2月龄, ... 11月龄
- 1岁, 1岁1月, 1岁2月, ...

## 技术栈

- **Flutter**: 跨平台 UI 框架
- **WebDAV**: 数据存储和同步
- **Dart**: 编程语言

## 安装和使用

### 前提条件

1. 安装 Flutter SDK (3.0.0 或更高版本)
2. 准备一个 WebDAV 服务器（可以使用 Nextcloud、ownCloud 或其他 WebDAV 服务）

### 构建应用

```bash
# 获取依赖
flutter pub get

# 运行应用（开发模式）
flutter run

# 构建 Android APK
flutter build apk

# 构建 iOS
flutter build ios
```

### 首次使用

1. 启动应用后会显示初始设置界面
2. 输入宝宝信息：
   - 宝宝昵称
   - 宝宝生日
3. 配置 WebDAV 连接：
   - WebDAV 服务器 URL
   - 用户名
   - 密码
4. 点击"完成设置"保存配置
5. 开始添加成长记录！

## 功能说明

### 主页（时间轴）

- 显示所有成长记录，按时间倒序排列
- 每条记录显示：
  - 年龄标记（月龄/岁数）
  - 日期
  - 描述摘要
  - 照片/视频数量
- 点击记录可查看详情
- 下拉刷新同步最新数据

### 记录详情

- 查看完整的记录内容
- **视频播放**：
  - 支持多视频播放
  - 左右滑动切换视频
  - 播放完成后自动播放下一个视频
  - 支持全屏播放控制
- **记录编辑**：
  - 编辑描述内容
  - 修改记录日期
  - 编辑后保持在详情页，立即看到更新效果
- 删除记录功能

### 新建记录

- 选择日期（自动计算宝宝年龄）
- 输入描述（可选）
- 添加照片（支持多选）
- 添加视频
- 自动上传到 WebDAV 服务器

### 设置

- 查看宝宝信息和 WebDAV 配置
- 重新配置应用

## 数据存储结构

在 WebDAV 服务器上，数据按以下结构组织：

```
growth_diary/<baby-id>/
├── config.json                    # 应用配置
├── entries/                       # 日记条目
│   ├── <entry-id-1>.json
│   ├── <entry-id-2>.json
│   └── ...
├── media/                         # 原始媒体文件
│   ├── <timestamp>_photo1.jpg
│   ├── <timestamp>_video1.mp4
│   └── ...
└── thumbnails/                    # 缩略图文件
    ├── <timestamp>_photo1_thumb.jpg
    ├── <timestamp>_video1_thumb.jpg
    └── ...
```

### 条目文件结构

每个 `entries/<entry-id>.json` 文件包含以下字段：

```json
{
  "id": "唯一标识符",
  "date": "2024-01-15T10:30:00.000Z",
  "title": "标题",
  "description": "详细描述",
  "imagePaths": ["media/20240115_103000_photo1.jpg"],
  "videoPaths": ["media/20240115_103000_video1.mp4"],
  "imageThumbnails": ["thumbnails/20240115_103000_photo1_thumb.jpg"],
  "videoThumbnails": ["thumbnails/20240115_103000_video1_thumb.jpg"],
  "ageInMonths": 6
}
```

## 隐私说明

- 所有数据存储在您自己的 WebDAV 服务器上
- 应用不会收集或上传任何个人信息到第三方服务器
