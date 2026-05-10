# ============================================================
# Chrome/Edge/豆包浏览器书签自动化同步脚本
# 基于直接文件操作的定时任务同步方案
# ============================================================
# 研究结论：
# 1. Chrome 无官方 CLI 接口用于书签导入/导出
# 2. 所有 Chromium 系浏览器使用相同 JSON 格式的 Bookmarks 文件
# 3. 最佳方案：直接读写 Bookmarks JSON 文件
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Export","Import","Sync","Status")]
    [string]$Action = "Sync",
    
    [string]$ChromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default",
    [string]$EdgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default",
    [string]$DoubaoPath = "$env:LOCALAPPDATA\Doubao\User Data\Default",
    [string]$TempDir = "$env:TEMP\BookmarkSync",
    [string]$LogDir = "D:\BrowserBookmarks\logs",
    [string]$CentralStorage = "D:\BrowserBookmarks\shared\bookmarks",
    [switch]$Force,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

# ============================================================
# 颜色输出函数
# ============================================================
function Write-Step { param($msg) Write-Host ""; Write-Host "[Step] $msg" -ForegroundColor Cyan }
function Write-OK { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-SKIP { param($msg) Write-Host "  [SKIP] $msg" -ForegroundColor Gray }
function Write-WARN { param($msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-ERR { param($msg) Write-Host "  [ERR] $msg" -ForegroundColor Red }
function Write-INFO { param($msg) Write-Host "  [INFO] $msg" -ForegroundColor White }
function Write-DRY { param($msg) Write-Host "  [DRY-RUN] $msg" -ForegroundColor Magenta }

# ============================================================
# 日志函数
# ============================================================
function Write-Log {
    param($Message, $Level = "INFO")
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $logFile = Join-Path $LogDir "automated-sync.log"
    $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content $logFile $logEntry -Encoding UTF8
}

# ============================================================
# 浏览器配置
# ============================================================
$BrowserConfigs = @(
    @{
        Name = "Chrome"
        Key = "chrome"
        Path = $ChromePath
        BookmarkFile = Join-Path $ChromePath "Bookmarks"
        ProfilePaths = @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Profile 1",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Profile 2"
        )
    },
    @{
        Name = "Edge"
        Key = "edge"
        Path = $EdgePath
        BookmarkFile = Join-Path $EdgePath "Bookmarks"
        ProfilePaths = @(
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Profile 1",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Profile 2"
        )
    },
    @{
        Name = "Doubao"
        Key = "doubao"
        Path = $DoubaoPath
        BookmarkFile = Join-Path $DoubaoPath "Bookmarks"
        ProfilePaths = @(
            "$env:LOCALAPPDATA\Doubao\User Data\Default",
            "$env:LOCALAPPDATA\ByteDance\Doubao\User Data\Default"
        )
    }
)

# ============================================================
# 工具函数
# ============================================================
function Find-BookmarkFile {
    param($Config)
    if (Test-Path $Config.BookmarkFile) {
        return $Config.BookmarkFile
    }
    foreach ($profilePath in $Config.ProfilePaths) {
        $path = Join-Path $profilePath "Bookmarks"
        if (Test-Path $path) {
            return $path
        }
    }
    return $null
}

function Test-BrowserRunning {
    param($BrowserKey)
    $processPatterns = @{
        "chrome" = @("chrome")
        "edge" = @("msedge")
        "doubao" = @("doubao", "bytedance")
    }
    $patterns = $processPatterns[$BrowserKey]
    if (-not $patterns) { return $false }
    foreach ($pattern in $patterns) {
        $processes = Get-Process -Name $pattern -ErrorAction SilentlyContinue
        if ($processes) { return $true }
    }
    return $false
}

function Get-FileHashFast {
    param($FilePath)
    if (-not (Test-Path $FilePath)) { return $null }
    $stream = [System.IO.FileStream]::new(
        $FilePath, 
        [System.IO.FileMode]::Open, 
        [System.IO.FileAccess]::Read, 
        [System.IO.FileShare]::Read
    )
    $hash = [System.Security.Cryptography.MD5]::Create().ComputeHash($stream)
    $stream.Close()
    return ($hash | ForEach-Object { $_.ToString("x2") }) -join ""
}

function ConvertTo-ChromeJson {
    param($FilePath)
    if (-not (Test-Path $FilePath)) { return $null }
    $content = Get-Content $FilePath -Raw -Encoding UTF8
    return $content | ConvertFrom-Json -Depth 20
}

function ConvertFrom-ChromeJson {
    param($FilePath, $OutputPath)
    $data = ConvertTo-ChromeJson $FilePath
    if ($data) {
        $jsonOutput = $data | ConvertTo-Json -Depth 20
        $jsonOutput | Set-Content -Path $OutputPath -Encoding UTF8
        return $data
    }
    return $null
}

# ============================================================
# 书签合并逻辑
# ============================================================
function Merge-BookmarkNodes {
    param(
        $CentralNode,
        $BrowserNode,
        [string]$MergeStrategy = "Timestamp"  # Timestamp | BrowserPriority
    )
    
    if (-not $CentralNode -and $BrowserNode) { return $BrowserNode }
    if ($CentralNode -and (-not $BrowserNode)) { return $CentralNode }
    if (-not $CentralNode -and -not $BrowserNode) { return $null }
    
    # 类型不同，保留浏览器版本（用户最新操作）
    if ($CentralNode.type -ne $BrowserNode.type) {
        return $BrowserNode
    }
    
    # 如果是 URL 类型，保留两者（去重）
    if ($BrowserNode.type -eq "url") {
        # 检查 URL 是否已存在
        $existingUrl = $CentralNode | Where-Object { $_.url -eq $BrowserNode.url } -ErrorAction SilentlyContinue
        if ($existingUrl) {
            # URL 已存在，保留时间戳较新的
            if ([long]$BrowserNode.date_added -gt [long]$existingUrl.date_added) {
                return $BrowserNode
            }
            return $existingUrl
        }
        return $BrowserNode
    }
    
    # 如果是文件夹，递归合并子节点
    if ($BrowserNode.type -eq "folder") {
        $result = $CentralNode | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        
        if ($BrowserNode.children -and $CentralNode.children) {
            $mergedChildren = New-Object System.Collections.ArrayList
            
            foreach ($child in $BrowserNode.children) {
                $existingChild = $CentralNode.children | Where-Object { $_.id -eq $child.id } -ErrorAction SilentlyContinue
                if ($existingChild) {
                    $mergedChild = Merge-BookmarkNodes $existingChild $child $MergeStrategy
                    # 更新 ID 映射
                    $mergedChildren.Add($mergedChild) | Out-Null
                } else {
                    $mergedChildren.Add($child) | Out-Null
                }
            }
            
            # 添加中央存储中独有的子节点
            foreach ($child in $CentralNode.children) {
                $exists = $BrowserNode.children | Where-Object { $_.id -eq $child.id } -ErrorAction SilentlyContinue
                if (-not $exists) {
                    $mergedChildren.Add($child) | Out-Null
                }
            }
            
            $result.children = $mergedChildren
        }
        
        return $result
    }
    
    # 默认返回浏览器版本
    return $BrowserNode
}

function Merge-BookmarkData {
    param(
        [string]$CentralFile,
        [string]$BrowserFile,
        [string]$MergeStrategy = "Timestamp"
    )
    
    try {
        $centralData = ConvertTo-ChromeJson $CentralFile
        $browserData = ConvertTo-ChromeJson $BrowserFile
        
        if (-not $centralData -or -not $browserData) {
            return $null
        }
        
        # 合并 bookmark_bar
        if ($browserData.roots.bookmark_bar) {
            if ($centralData.roots.bookmark_bar) {
                $centralData.roots.bookmark_bar = Merge-BookmarkNodes `
                    $centralData.roots.bookmark_bar `
                    $browserData.roots.bookmark_bar `
                    $MergeStrategy
            } else {
                $centralData.roots.bookmark_bar = $browserData.roots.bookmark_bar
            }
        }
        
        # 合并 other_bookmarks
        if ($browserData.roots.other_bookmarks) {
            if ($centralData.roots.other) {
                $centralData.roots.other = Merge-BookmarkNodes `
                    $centralData.roots.other `
                    $browserData.roots.other_bookmarks `
                    $MergeStrategy
            } else {
                $other = New-Object PSObject
                Add-Member -InputObject $other -MemberType NoteProperty -Name id -Value "2"
                Add-Member -InputObject $other -MemberType NoteProperty -Name name -Value "Other bookmarks"
                Add-Member -InputObject $other -MemberType NoteProperty -Name type -Value "folder"
                Add-Member -InputObject $other -MemberType NoteProperty -Name date_added -Value "0"
                Add-Member -InputObject $other -MemberType NoteProperty -Name date_last_used -Value "0"
                Add-Member -InputObject $other -MemberType NoteProperty -Name children -Value $browserData.roots.other_bookmarks.children
                $centralData.roots.other = $other
            }
        }
        
        # 合并 synced_bookmarks
        if ($browserData.roots.synced_bookmarks) {
            if ($centralData.roots.synced) {
                $centralData.roots.synced = Merge-BookmarkNodes `
                    $centralData.roots.synced `
                    $browserData.roots.synced_bookmarks `
                    $MergeStrategy
            } else {
                $synced = New-Object PSObject
                Add-Member -InputObject $synced -MemberType NoteProperty -Name id -Value "3"
                Add-Member -InputObject $synced -MemberType NoteProperty -Name name -Value "Mobile bookmarks"
                Add-Member -InputObject $synced -MemberType NoteProperty -Name type -Value "folder"
                Add-Member -InputObject $synced -MemberType NoteProperty -Name date_added -Value "0"
                Add-Member -InputObject $synced -MemberType NoteProperty -Name date_last_used -Value "0"
                Add-Member -InputObject $synced -MemberType NoteProperty -Name children -Value $browserData.roots.synced_bookmarks.children
                $centralData.roots.synced = $synced
            }
        }
        
        return $centralData
    } catch {
        Write-ERR "合并书签数据失败: $_"
        Write-Log "Merge failed: $_" -Level "ERROR"
        return $null
    }
}

# ============================================================
# 导出书签
# ============================================================
function Export-Bookmarks {
    param(
        [string]$OutputDir,
        [switch]$ExportAll
    )
    
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }
    
    $exported = @{}
    
    foreach ($config in $BrowserConfigs) {
        $bookmarkFile = Find-BookmarkFile $config
        if ($bookmarkFile -and (Test-Path $bookmarkFile)) {
            $outputFile = Join-Path $OutputDir "bookmarks_$($config.Key)_$Timestamp.json"
            Copy-Item -Path $bookmarkFile -Destination $outputFile -Force
            $exported[$config.Key] = @{
                Source = $bookmarkFile
                Destination = $outputFile
                Size = (Get-Item $bookmarkFile).Length
                Hash = Get-FileHashFast $bookmarkFile
            }
            Write-OK "已导出 $($config.Name) 书签: $outputFile"
        } else {
            Write-WARN "未找到 $($config.Name) 书签文件"
        }
    }
    
    return $exported
}

# ============================================================
# 导入书签到浏览器
# ============================================================
function Import-Bookmarks {
    param(
        [string]$SourceFile,
        [string]$TargetBrowser = "all"
    )
    
    if (-not (Test-Path $SourceFile)) {
        Write-ERR "源文件不存在: $SourceFile"
        return $false
    }
    
    $imported = 0
    
    foreach ($config in $BrowserConfigs) {
        if ($TargetBrowser -ne "all" -and $config.key -ne $TargetBrowser) { continue }
        
        $bookmarkFile = Find-BookmarkFile $config
        if (-not $bookmarkFile) {
            Write-WARN "未找到 $($config.Name) 书签路径"
            continue
        }
        
        # 检查浏览器是否运行
        if (Test-BrowserRunning $config.key) {
            Write-WARN "$($config.Name) 正在运行，跳过导入"
            Write-Log "$($config.Name) is running, skip import" -Level "WARN"
            continue
        }
        
        if ($DryRun) {
            Write-DRY "将导入 $($config.Name) 书签: $bookmarkFile"
        } else {
            try {
                # 备份原始文件
                $backupFile = "$bookmarkFile.backup.$Timestamp"
                Copy-Item -Path $bookmarkFile -Destination $backupFile -Force
                Write-OK "已备份 $($config.Name) 原始书签"
                
                # 复制新书签文件
                Copy-Item -Path $SourceFile -Destination $bookmarkFile -Force
                Write-OK "已导入 $($config.Name) 书签"
                $imported++
            } catch {
                Write-ERR "导入 $($config.Name) 书签失败: $_"
                Write-Log "Import failed for $($config.Name): $_" -Level "ERROR"
            }
        }
    }
    
    return $imported -gt 0
}

# ============================================================
# 同步书签（核心功能）
# ============================================================
function Sync-Bookmarks {
    param(
        [string]$MergeStrategy = "Timestamp",
        [string]$SyncDirection = "Bidirectional"  # Bidirectional | CentralToBrowser | BrowserToCentral
    )
    
    Write-Step "开始书签同步..."
    
    # 创建临时目录
    if (-not (Test-Path $TempDir)) {
        New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    }
    
    # 步骤 1: 导出所有浏览器书签
    Write-Step "步骤 1: 导出所有浏览器书签"
    $exports = Export-Bookmarks -OutputDir $TempDir
    Write-OK "导出完成"
    
    # 步骤 2: 检查中央存储
    Write-Step "步骤 2: 检查中央存储"
    $centralFile = Join-Path $CentralStorage "Bookmarks"
    $hasCentral = Test-Path $centralFile
    
    if ($hasCentral) {
        Write-OK "中央存储存在: $centralFile"
    } else {
        Write-WARN "中央存储不存在，将创建新的中央存储"
    }
    
    # 步骤 3: 合并书签
    Write-Step "步骤 3: 合并书签数据"
    
    if ($hasCentral) {
        # 读取中央存储
        $centralData = ConvertTo-ChromeJson $centralFile
        if (-not $centralData) {
            Write-ERR "无法读取中央存储文件"
            return $false
        }
        Write-OK "中央存储书签数据已加载"
        
        # 找出修改过的浏览器
        $modifiedBrowsers = @()
        foreach ($config in $BrowserConfigs) {
            $exported = $exports[$config.key]
            if ($exported) {
                $centralHash = Get-FileHashFast $centralFile
                if ($exported.Hash -ne $centralHash) {
                    $modifiedBrowsers += $config
                    Write-INFO "$($config.Name) 书签已修改"
                } else {
                    Write-SKIP "$($config.Name) 书签未修改"
                }
            }
        }
        
        if ($modifiedBrowsers.Count -eq 0) {
            Write-OK "所有书签均为最新，无需同步"
            return $true
        }
        
        # 合并修改过的浏览器书签
        foreach ($browser in $modifiedBrowsers) {
            $exportFile = $exports[$browser.key].Destination
            Write-INFO "合并 $($browser.Name) 书签..."
            
            $mergedData = Merge-BookmarkData $centralFile $exportFile $MergeStrategy
            if ($mergedData) {
                $centralData = $mergedData
                Write-OK "$($browser.Name) 书签合并完成"
            }
        }
    } else {
        # 创建新的中央存储，使用修改最多的浏览器作为基准
        Write-INFO "创建新的中央存储..."
        
        # 选择文件最大的浏览器作为基准
        $baseBrowser = $null
        $maxSize = 0
        foreach ($config in $BrowserConfigs) {
            $exported = $exports[$config.key]
            if ($exported -and $exported.Size -gt $maxSize) {
                $maxSize = $exported.Size
                $baseBrowser = $config
            }
        }
        
        if ($baseBrowser) {
            Copy-Item -Path $exports[$baseBrowser.key].Destination -Destination $centralFile -Force
            Write-OK "已使用 $($baseBrowser.Name) 书签创建中央存储"
        } else {
            Write-ERR "未找到任何书签文件"
            return $false
        }
    }
    
    # 步骤 4: 写回中央存储
    Write-Step "步骤 4: 更新中央存储"
    if (-not $DryRun) {
        $jsonOutput = $centralData | ConvertTo-Json -Depth 20
        $jsonOutput | Set-Content -Path $centralFile -Encoding UTF8
        Write-OK "中央存储已更新"
    } else {
        Write-DRY "将更新中央存储"
    }
    
    # 步骤 5: 写回浏览器
    Write-Step "步骤 5: 同步到浏览器"
    
    foreach ($config in $BrowserConfigs) {
        $bookmarkFile = Find-BookmarkFile $config
        if (-not $bookmarkFile) { continue }
        
        # 检查浏览器是否运行
        if (Test-BrowserRunning $config.key) {
            Write-WARN "$($config.Name) 正在运行，跳过同步"
            Write-Log "$($config.Name) is running, skip sync" -Level "WARN"
            continue
        }
        
        if ($DryRun) {
            Write-DRY "将同步到 $($config.Name): $bookmarkFile"
        } else {
            try {
                # 备份原始文件
                $backupDir = Join-Path $LogDir "backup_$Timestamp"
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                $backupFile = Join-Path $backupDir "Bookmarks_$($config.key).json"
                Copy-Item -Path $bookmarkFile -Destination $backupFile -Force
                Write-OK "已备份 $($config.Name) 原始书签"
                
                # 同步中央存储到浏览器
                Copy-Item -Path $centralFile -Destination $bookmarkFile -Force
                Write-OK "已同步 $($config.Name) 书签"
            } catch {
                Write-ERR "同步 $($config.Name) 书签失败: $_"
                Write-Log "Sync failed for $($config.Name): $_" -Level "ERROR"
            }
        }
    }
    
    Write-Step "同步完成!"
    Write-OK "时间戳: $Timestamp"
    
    return $true
}

# ============================================================
# 状态检查
# ============================================================
function Get-BookmarkStatus {
    Write-Step "检查书签状态..."
    
    foreach ($config in $BrowserConfigs) {
        $bookmarkFile = Find-BookmarkFile $config
        if ($bookmarkFile -and (Test-Path $bookmarkFile)) {
            $hash = Get-FileHashFast $bookmarkFile
            $size = (Get-Item $bookmarkFile).Length
            $modified = (Get-Item $bookmarkFile).LastWriteTime
            $running = Test-BrowserRunning $config.key
            
            Write-INFO "$($config.Name):"
            Write-INFO "  文件: $bookmarkFile"
            Write-INFO "  大小: $size bytes"
            Write-INFO "  哈希: $hash"
            Write-INFO "  修改时间: $modified"
            Write-INFO "  运行状态: $($(if($running){'运行中'}else{'已停止'}))"
        } else {
            Write-WARN "$($config.Name): 未找到书签文件"
        }
    }
    
    # 检查中央存储
    $centralFile = Join-Path $CentralStorage "Bookmarks"
    if (Test-Path $centralFile) {
        $hash = Get-FileHashFast $centralFile
        $size = (Get-Item $centralFile).Length
        Write-INFO "中央存储:"
        Write-INFO "  文件: $centralFile"
        Write-INFO "  大小: $size bytes"
        Write-INFO "  哈希: $hash"
    } else {
        Write-WARN "中央存储不存在"
    }
}

# ============================================================
# 主入口
# ============================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  浏览器书签自动化同步工具" -ForegroundColor Cyan
Write-Host "  Browser Bookmark Automated Sync" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

switch ($Action) {
    "Export" {
        Export-Bookmarks -OutputDir $TempDir
    }
    "Import" {
        # 需要先指定源文件
        Write-ERR "请使用 -SourceFile 参数指定要导入的书签文件"
        Write-INFO "示例: $0 -Action Import -SourceFile D:\path\to\Bookmarks"
    }
    "Sync" {
        Sync-Bookmarks -MergeStrategy "Timestamp" -SyncDirection "Bidirectional"
    }
    "Status" {
        Get-BookmarkStatus
    }
}

Write-Host ""
Write-Host "同步完成!" -ForegroundColor Green
Write-Host ""
