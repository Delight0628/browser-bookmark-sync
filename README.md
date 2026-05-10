# Browser Bookmark Sync - Windows 定时任务版

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Windows%2011-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-7.0+-blue)

基于 Windows 定时任务和直接文件操作的跨浏览器书签同步方案，支持 Chrome、Edge 和豆包浏览器。

## 概述

本方案通过 PowerShell 脚本直接读写 Chromium 系浏览器的 `Bookmarks` JSON 文件，配合 Windows 任务计划程序实现定期自动同步。

**研究结论**：Chrome 无官方 CLI 接口用于书签导入/导出，直接文件操作是最可靠的自动化方案。

## 功能特性

- ✅ 支持 Chrome、Edge、豆包浏览器
- ✅ 自动检测书签变更（哈希对比）
- ✅ 智能合并策略（时间戳优先）
- ✅ 自动备份原始书签
- ✅ Windows 定时任务自动化
- ✅ 无需管理员权限（同步操作）
- ✅ 详细日志记录

## 安装

无需安装，直接下载脚本即可使用。

```powershell
# 克隆或下载本项目
git clone <repository-url>
cd browser-bookmark-sync
```

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
```

## 定时任务配置

| 频率 | 命令 |
|------|------|
| 每日 | `.\scripts\setup-scheduled-task.ps1 -Frequency Daily -Hour 3` |
| 每周 | `.\scripts\setup-scheduled-task.ps1 -Frequency Weekly -Hour 2` |
| 每月 | `.\scripts\setup-scheduled-task.ps1 -Frequency Monthly -Hour 3` |
| 自定义间隔 | `.\scripts\setup-scheduled-task.ps1 -Frequency Custom -CustomIntervalHours 6` |

## 支持浏览器

| 浏览器 | 书签文件路径 |
|--------|-------------|
| Google Chrome | `%LOCALAPPDATA%\Google\Chrome\User Data\Default\Bookmarks` |
| Microsoft Edge | `%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Bookmarks` |
| 豆包浏览器 | `%LOCALAPPDATA%\Doubao\User Data\Default\Bookmarks` |

## 工作原理

```
Windows 任务计划程序
       │
       ▼
automated-sync.ps1
  ├── 导出所有浏览器书签
  ├── 检测变更（哈希对比）
  ├── 合并书签数据
  ├── 备份原始文件
  └── 写回各浏览器
```

## 冲突解决

| 冲突场景 | 解决策略 |
|---------|---------|
| 同一书签被不同浏览器修改 | 以最后修改的时间戳为准 |
| 一个浏览器添加，另一个删除 | 保留添加操作 |
| 不同浏览器添加不同书签 | 合并所有书签 |
| 浏览器正在运行 | 跳过该浏览器，记录警告日志 |

## 目录结构

```
browser-bookmark-sync/
├── SKILL.md                          # 技能入口文件
├── README.md                         # 项目说明
├── LICENSE                           # MIT 许可证
├── .gitignore                        # Git 忽略规则
├── scripts/
│   ├── automated-sync.ps1            # 核心同步脚本
│   └── setup-scheduled-task.ps1      # 定时任务配置脚本
└── references/
    └── chrome-bookmark-api-research.md # API 研究报告
```

## 注意事项

1. **浏览器状态**：同步时浏览器应处于关闭状态
2. **定时任务权限**：创建定时任务需要管理员权限
3. **磁盘空间**：确保有足够空间存储备份

## 参考文档

- [Chrome 书签 API 研究报告](references/chrome-bookmark-api-research.md) - 详细的接口分析

## 许可证

本项目采用 [MIT 许可证](LICENSE) 开源。
