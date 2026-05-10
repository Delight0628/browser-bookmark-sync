---
name: browser-bookmark-sync
description: Windows scheduled task based cross-browser bookmark synchronization for Chrome, Edge and Doubao browser. Uses PowerShell scripts with direct JSON file operations to periodically sync bookmarks via Windows Task Scheduler. No admin rights needed for sync operations.
version: 1.0.0
author: Roo Agent Skills
---

# 跨浏览器书签同步方案 - Windows 定时任务版

基于 Windows 定时任务和直接文件操作的跨浏览器书签同步方案，适用于 Windows 11 系统。

## 方案原理

所有 Chromium 系浏览器（Chrome、Edge、豆包浏览器）使用**相同的 JSON 格式**存储书签：
- 文件名为 `Bookmarks`（无扩展名）
- 位于用户数据目录：`%LOCALAPPDATA%\{Browser}\User Data\Default\`
- 格式为 Chromium 标准 JSON，结构一致

**研究结论**：Chrome 无官方 CLI 接口用于书签导入/导出，最佳方案是直接读写 Bookmarks JSON 文件。

## 快速开始

```powershell
# 1. 执行同步（自动检测修改并合并）
.\scripts\automated-sync.ps1 -Action Sync

# 2. 查看状态
.\scripts\automated-sync.ps1 -Action Status

# 3. 导出所有浏览器书签
.\scripts\automated-sync.ps1 -Action Export

# 4. 配置定时任务（每日凌晨3点同步）
.\scripts\setup-scheduled-task.ps1 -Frequency Daily -Hour 3

# 5. 自定义间隔（每6小时同步）
.\scripts\setup-scheduled-task.ps1 -Frequency Custom -CustomIntervalHours 6
```

## 核心组件

| 组件 | 文件 | 用途 |
|------|------|------|
| 自动化同步脚本 | [`scripts/automated-sync.ps1`](scripts/automated-sync.ps1) | 书签导出/导入/合并/同步核心逻辑 |
| 定时任务配置 | [`scripts/setup-scheduled-task.ps1`](scripts/setup-scheduled-task.ps1) | 创建/管理 Windows 计划任务 |
| API 研究文档 | [`references/chrome-bookmark-api-research.md`](references/chrome-bookmark-api-research.md) | Chrome 书签自动化接口研究报告 |

## 工作原理

```
┌─────────────────────────────────────────────────────────────┐
│              Windows 任务计划程序                              │
│           (每日/每周/每月/自定义间隔触发)                       │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│           automated-sync.ps1                                 │
│  1. 导出所有浏览器书签到临时目录                               │
│  2. 检测哪些浏览器书签已修改（哈希对比）                       │
│  3. 合并修改过的书签到中央存储                                │
│  4. 备份浏览器原始书签                                        │
│  5. 将合并后的书签写回各浏览器                                │
└──────────────────────────┬──────────────────────────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌─────────┐  ┌─────────┐  ┌─────────┐
        │  Chrome  │  │  Edge   │  │  豆包   │
        │ Bookmarks│  │Bookmarks│  │Bookmarks│
        └─────────┘  └─────────┘  └─────────┘
```

1. **导出**：定时触发后，首先导出所有浏览器当前书签到临时目录
2. **检测**：通过文件哈希对比，检测哪些浏览器书签已修改
3. **合并**：以中央存储为基准，合并各浏览器修改过的书签（冲突解决策略：时间戳优先）
4. **写回**：将合并后的书签写回各浏览器（浏览器需处于关闭状态）

## 支持浏览器

| 浏览器 | 书签文件路径 |
|--------|-------------|
| Google Chrome | `%LOCALAPPDATA%\Google\Chrome\User Data\Default\Bookmarks` |
| Microsoft Edge | `%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Bookmarks` |
| 豆包浏览器 | `%LOCALAPPDATA%\Doubao\User Data\Default\Bookmarks` |

## 定时任务配置

### 支持的频率

| 频率 | 参数 | 说明 |
|------|------|------|
| 每日 | `-Frequency Daily` | 每天指定时间执行 |
| 每周 | `-Frequency Weekly` | 每周指定星期执行 |
| 每月 | `-Frequency Monthly` | 每月指定日期执行 |
| 自定义 | `-Frequency Custom` | 按小时间隔执行 |

### 示例命令

```powershell
# 每日凌晨 3 点同步
.\scripts\setup-scheduled-task.ps1 -Frequency Daily -Hour 3

# 每周日凌晨 2 点同步
.\scripts\setup-scheduled-task.ps1 -Frequency Weekly -Hour 2

# 每 6 小时同步一次
.\scripts\setup-scheduled-task.ps1 -Frequency Custom -CustomIntervalHours 6

# 查看现有任务
.\scripts\setup-scheduled-task.ps1 -ListTasks

# 移除定时任务
.\scripts\setup-scheduled-task.ps1 -RemoveTask
```

## 冲突解决

| 冲突场景 | 解决策略 |
|---------|---------|
| 同一书签被不同浏览器修改 | 以最后修改的时间戳为准 |
| 一个浏览器添加，另一个删除 | 保留添加操作 |
| 不同浏览器添加不同书签 | 合并所有书签 |
| 浏览器正在运行 | 跳过该浏览器，记录警告日志 |

## 注意事项

1. **浏览器状态**：同步时浏览器应处于关闭状态，否则跳过该浏览器
2. **定时任务权限**：创建定时任务需要管理员权限
3. **磁盘空间**：确保 `D:\BrowserBookmarks\` 目录有足够空间存储备份
4. **合并策略**：默认使用时间戳优先策略，可通过参数调整

## 目录结构

```
browser-bookmark-sync/
├── SKILL.md                          # 本文件（技能入口）
├── scripts/
│   ├── automated-sync.ps1            # 核心同步脚本
│   └── setup-scheduled-task.ps1      # 定时任务配置脚本
└── references/
    └── chrome-bookmark-api-research.md # API 研究报告
```

## 许可证

本技能采用 MIT 许可证开源。
