param(
    [Parameter(Position=0)]
    [ValidateSet("dev", "status", "check", "save")]
    [string]$Action = "status",

    [Parameter(Position=1)]
    [string]$Message = ""
)

$ErrorActionPreference = "Stop"

$Repo = "C:\dev\youtube-dl-gui"
Set-Location $Repo

function Show-Status {
    Write-Host "`n=== Git status ==="
    git status --short

    Write-Host "`n=== Branch ==="
    git branch --show-current
}

function Test-DangerousChanges {
    $changed = git status --short

    $dangerous = $changed | Select-String -Pattern `
        "src-tauri/|package\.json|package-lock\.json|Cargo\.toml|Cargo\.lock"

    if ($dangerous) {
        Write-Host "`nWARNING: UI以外の重要ファイルに変更があります:" -ForegroundColor Yellow
        $dangerous
        return $false
    }

    return $true
}

switch ($Action) {

    "status" {
        Show-Status
    }

    "dev" {
        Show-Status

        Write-Host "`n=== Starting Tauri dev ==="
        npm run tauri dev
    }

    "check" {
        Show-Status

        Write-Host "`n=== git diff --check ==="
        git diff --check

        Write-Host "`n=== ESLint ==="
        npm run lint
    }

    "save" {
        if ([string]::IsNullOrWhiteSpace($Message)) {
            throw 'コミットメッセージを指定してください。例: .\ui.ps1 save "style: compact footer"'
        }

        Show-Status

        if (-not (Test-DangerousChanges)) {
            Write-Host "`n安全のためcommitを中止しました。" -ForegroundColor Red
            exit 1
        }

        Write-Host "`n=== git diff --check ==="
        git diff --check

        # UIファイルだけを対象にする
        git add src/components src/views src/app.css

        Write-Host "`n=== Commit対象 ==="
        git diff --cached --name-only

        $answer = Read-Host "`nこのファイルだけcommitしてよいですか？ (y/N)"

        if ($answer -ne "y") {
            git restore --staged .
            Write-Host "中止しました。"
            exit
        }

        git commit -m $Message

        $push = Read-Host "GitHubへpushしますか？ (y/N)"
        if ($push -eq "y") {
            git push
        }
    }
}