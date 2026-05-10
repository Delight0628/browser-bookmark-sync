# ============================================================
# Windows 定时任务配置脚本
# 用于自动化定期同步 Chrome/Edge/豆包浏览器书签
# ============================================================
# 本脚本创建 Windows 计划任务，定期调用 automated-sync.ps1
# 支持多种同步频率：每日、每周、每月、自定义间隔
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Daily","Weekly","Monthly","Custom")]
    [string]$Frequency = "Daily",
    
    [int]$Hour = 3,  # 默认凌晨 3 点执行
    [int]$Minute = 0,
    
    [string]$SyncDirection = "Bidirectional",  # Bidirectional | CentralToBrowser
    
    [string]$ScriptPath = "$PSScriptRoot\automated-sync.ps1",
    [string]$TaskName = "BrowserBookmarkSync",
    [string]$LogDir = "D:\BrowserBookmarks\logs",
    [switch]$RemoveTask,
    [switch]$ListTasks,
    [string]$CustomIntervalHours = "6"  # 自定义间隔（小时）
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# ============================================================
# 颜色输出函数
# ============================================================
function Write-Step { param($msg) Write-Host ""; Write-Host "[Step] $msg" -ForegroundColor Cyan }
function Write-OK { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-WARN { param($msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-ERR { param($msg) Write-Host "  [ERR] $msg" -ForegroundColor Red }
function Write-INFO { param($msg) Write-Host "  [INFO] $msg" -ForegroundColor White }

# ============================================================
# 检查管理员权限
# ============================================================
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ============================================================
# 验证脚本路径
# ============================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  浏览器书签同步 - 定时任务配置" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $ScriptPath)) {
    Write-ERR "同步脚本不存在: $ScriptPath"
    Write-INFO "请确保 automated-sync.ps1 已正确安装"
    exit 1
}

Write-INFO "同步脚本路径: $ScriptPath"
Write-INFO "任务名称: $TaskName"
Write-INFO "同步频率: $Frequency"

# ============================================================
# 列出现有任务
# ============================================================
if ($ListTasks) {
    Write-Step "列出现有书签同步任务"
    $tasks = Get-ScheduledTask -TaskName "*$TaskName*" -ErrorAction SilentlyContinue
    if ($tasks) {
        foreach ($task in $tasks) {
            Write-INFO "任务: $($task.TaskName)"
            Write-INFO "状态: $($task.State)"
            Write-INFO "作者: $($task.Author)"
            Write-INFO "描述: $($task.Description)"
            
            $triggers = $task.Triggers
            foreach ($trigger in $triggers) {
                Write-INFO "触发器: $($trigger.RepetitionInterval) $($trigger.StartBoundary)"
            }
        }
    } else {
        Write-INFO "未找到现有任务"
    }
    exit 0
}

# ============================================================
# 移除现有任务
# ============================================================
if ($RemoveTask) {
    Write-Step "移除定时任务"
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-OK "已移除任务: $TaskName"
    } else {
        Write-INFO "任务不存在: $TaskName"
    }
    exit 0
}

# ============================================================
# 检查管理员权限
# ============================================================
if (-not (Test-Administrator)) {
    Write-ERR "请以管理员身份运行此脚本!"
    Write-INFO "右键点击 PowerShell，选择'以管理员身份运行'"
    exit 1
}

# ============================================================
# 创建日志目录
# ============================================================
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    Write-OK "已创建日志目录: $LogDir"
}

# ============================================================
# 创建触发器
# ============================================================
Write-Step "创建定时任务触发器"

$repetitionInterval = "PT1H"  # 默认 1 小时
$repetitionDuration = "P1D"    # 持续 1 天
$startTime = "{0:HH:mm}" -f (Get-Date).AddHours($Hour).AddMinutes($Minute)

switch ($Frequency) {
    "Daily" {
        $trigger = New-ScheduledTaskTrigger -Daily -At "$startTime"
        $description = "每日 $startTime 执行书签同步"
    }
    "Weekly" {
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "$startTime"
        $description = "每周日 $startTime 执行书签同步"
    }
    "Monthly" {
        $trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At "$startTime"
        $description = "每月 1 日 $startTime 执行书签同步"
    }
    "Custom" {
        $repetitionInterval = "PT$($CustomIntervalHours)H"
        $trigger = New-ScheduledTaskTrigger -Once -At "$startTime" -RepetitionInterval $repetitionInterval -RepetitionDuration $repetitionDuration
        $description = "每 $CustomIntervalHours 小时执行书签同步"
    }
}

Write-OK "触发器已创建: $description"

# ============================================================
# 创建操作
# ============================================================
Write-Step "创建定时任务操作"

# 构建 PowerShell 命令
$psArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Action Sync -SyncDirection $SyncDirection"

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $psArgs -WorkingDirectory $PSScriptRoot

Write-OK "操作已创建"

# ============================================================
# 设置任务设置
# ============================================================
Write-Step "配置任务设置"

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable:$false `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 5)

Write-OK "任务设置已配置"

# ============================================================
# 注册任务
# ============================================================
Write-Step "注册定时任务"

$userId = "$env:COMPUTERNAME\$env:USERNAME"

try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Trigger $trigger `
        -Action $action `
        -Settings $settings `
        -Description $description `
        -UserId $userId `
        -RunLevel Highest `
        -Force
    
    Write-OK "定时任务已创建: $TaskName"
    Write-OK "描述: $description"
    Write-OK "触发器: $($trigger.RepetitionInterval)"
} catch {
    Write-ERR "注册任务失败: $_"
    exit 1
}

# ============================================================
# 验证任务
# ============================================================
Write-Step "验证任务"

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    Write-OK "任务状态: $($task.State)"
    Write-OK "任务已就绪"
} else {
    Write-ERR "无法验证任务"
}

# ============================================================
# 显示使用说明
# ============================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  配置完成!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "管理命令:" -ForegroundColor Yellow
Write-Host "  查看任务: Get-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host "  运行任务: Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host "  移除任务: .\setup-scheduled-task.ps1 -RemoveTask" -ForegroundColor White
Write-Host ""
Write-Host "手动运行同步:" -ForegroundColor Yellow
Write-Host "  .\automated-sync.ps1 -Action Sync" -ForegroundColor White
Write-Host "  .\automated-sync.ps1 -Action Status" -ForegroundColor White
Write-Host "  .\automated-sync.ps1 -Action Export" -ForegroundColor White
Write-Host ""
Write-Host "查看日志:" -ForegroundColor Yellow
Write-Host "  Get-Content '$LogDir\automated-sync.log' -Tail 50" -ForegroundColor White
Write-Host ""

# ============================================================
# 记录配置
# ============================================================
$configFile = Join-Path $LogDir "sync-config.json"
$config = @{
    timestamp = $Timestamp
    frequency = $Frequency
    hour = $Hour
    minute = $Minute
    syncDirection = $SyncDirection
    scriptPath = $ScriptPath
    taskName = $TaskName
    logDir = $LogDir
}

$configJson = $config | ConvertTo-Json
$configJson | Set-Content -Path $configFile -Encoding UTF8
Write-OK "配置已保存到: $configFile"

Write-Host ""
Write-Host "定时任务配置完成!" -ForegroundColor Green
Write-Host ""
