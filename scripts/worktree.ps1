# Git 并行工作树管理脚本
# 用法: .\scripts\worktree.ps1 <命令> [参数]
#
# 命令:
#   new   <名称> [基准分支]   创建新工作树（默认从 main 分出 wt/<名称> 分支）
#   list                      列出所有工作树
#   merge <名称> [目标分支]   将工作树分支合并回主干（默认合并到 main）
#   remove <名称>             删除工作树（不删分支，加 -DeleteBranch 可删分支）
#   open  <名称>              在 Cursor/VS Code 中打开工作树

param(
    [Parameter(Position = 0)]
    [ValidateSet("new", "list", "merge", "remove", "open")]
    [string]$Command,

    [Parameter(Position = 1)]
    [string]$Name,

    [Parameter(Position = 2)]
    [string]$Extra,

    [switch]$DeleteBranch
)

$ErrorActionPreference = "Stop"
$RepoRoot = git rev-parse --show-toplevel 2>$null
if (-not $RepoRoot) { Write-Error "请在 Git 仓库内运行此脚本"; exit 1 }

$WorktreeBase = Join-Path (Split-Path $RepoRoot -Parent) "git-worktrees"

function Get-WorktreePath($wtName) {
    Join-Path $WorktreeBase $wtName
}

function Get-BranchName($wtName) {
    "wt/$wtName"
}

switch ($Command) {
    "new" {
        if (-not $Name) { Write-Error "用法: worktree.ps1 new <名称> [基准分支]"; exit 1 }
        $BaseBranch = if ($Extra) { $Extra } else { "main" }
        $WtPath = Get-WorktreePath $Name
        $Branch = Get-BranchName $Name

        if (Test-Path $WtPath) { Write-Error "工作树已存在: $WtPath"; exit 1 }

        New-Item -ItemType Directory -Path $WorktreeBase -Force | Out-Null
        git fetch origin 2>$null

        Write-Host "创建分支 ${Branch} (基于 ${BaseBranch})..."
        git branch $Branch $BaseBranch 2>$null
        if ($LASTEXITCODE -ne 0) {
            git branch $Branch $BaseBranch
        }

        Write-Host "创建工作树: $WtPath"
        git worktree add $WtPath $Branch

        Write-Host ""
        Write-Host "工作树已就绪:" -ForegroundColor Green
        Write-Host "  路径:   $WtPath"
        Write-Host "  分支:   $Branch"
        Write-Host "  主干:   $RepoRoot  (main)"
        Write-Host ""
        Write-Host "进入工作树:  cd $WtPath"
        Write-Host "完成后合并:  .\scripts\worktree.ps1 merge $Name"
    }

    "list" {
        Write-Host "工作树目录: $WorktreeBase"
        Write-Host ""
        git worktree list
    }

    "merge" {
        if (-not $Name) { Write-Error "用法: worktree.ps1 merge <名称> [目标分支]"; exit 1 }
        $TargetBranch = if ($Extra) { $Extra } else { "main" }
        $Branch = Get-BranchName $Name
        $WtPath = Get-WorktreePath $Name

        Push-Location $RepoRoot
        try {
            git checkout $TargetBranch
            Write-Host "合并 $Branch -> $TargetBranch ..."
            git merge $Branch --no-edit
            if ($LASTEXITCODE -ne 0) {
                Write-Host "存在冲突，请手动解决后执行 git commit" -ForegroundColor Yellow
                exit 1
            }
            Write-Host "合并成功" -ForegroundColor Green

            if (Test-Path $WtPath) {
                Write-Host "移除工作树 $WtPath ..."
                git worktree remove $WtPath
            }
        } finally {
            Pop-Location
        }
    }

    "remove" {
        if (-not $Name) { Write-Error "用法: worktree.ps1 remove <名称> [-DeleteBranch]"; exit 1 }
        $Branch = Get-BranchName $Name
        $WtPath = Get-WorktreePath $Name

        if (Test-Path $WtPath) {
            git worktree remove $WtPath
            Write-Host "已移除工作树: $WtPath" -ForegroundColor Green
        } else {
            Write-Host "工作树不存在: $WtPath" -ForegroundColor Yellow
        }

        if ($DeleteBranch) {
            git branch -d $Branch 2>$null
            if ($LASTEXITCODE -ne 0) { git branch -D $Branch }
            Write-Host "已删除分支: $Branch" -ForegroundColor Green
        }
    }

    "open" {
        if (-not $Name) { Write-Error "用法: worktree.ps1 open <名称>"; exit 1 }
        $WtPath = Get-WorktreePath $Name
        if (-not (Test-Path $WtPath)) { Write-Error "工作树不存在: $WtPath"; exit 1 }

        $cursor = Get-Command cursor -ErrorAction SilentlyContinue
        $code = Get-Command code -ErrorAction SilentlyContinue
        if ($cursor) { & cursor $WtPath }
        elseif ($code) { & code $WtPath }
        else { Write-Host "请手动打开: $WtPath" }
    }

    default {
        Write-Host @"
Git 并行工作树 — 像 Codex 一样在独立目录开发，不影响主干

  .\scripts\worktree.ps1 new    <名称> [基准分支]   创建
  .\scripts\worktree.ps1 list                      列出
  .\scripts\worktree.ps1 merge  <名称> [目标分支]   合并回主干
  .\scripts\worktree.ps1 remove <名称> [-DeleteBranch]  删除
  .\scripts\worktree.ps1 open   <名称>              用编辑器打开

工作树目录: $WorktreeBase\<名称>
每个工作树对应分支: wt/<名称>
"@
    }
}
