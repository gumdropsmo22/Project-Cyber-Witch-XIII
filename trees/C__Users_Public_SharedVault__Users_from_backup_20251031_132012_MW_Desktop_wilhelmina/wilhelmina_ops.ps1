param(
  [switch]$IncludeC7,
  [switch]$SkipPush,
  [switch]$StatusOnly
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

function Section { param([string]$t) Write-Host ""; Write-Host ("=== {0} ===" -f $t) -ForegroundColor Cyan }
function Ensure-Dir { param([string]$p) if (!(Test-Path $p)) { New-Item -ItemType Directory -Force $p | Out-Null } }

function Get-ProjectPython {
  $venv = Join-Path $PSScriptRoot ".venv"
  $py = Join-Path $venv "Scripts\python.exe"
  if (!(Test-Path $py)) { throw "Python venv not found at .venv. Run your setup script first." }
  return $py
}

function Read-DotEnv {
  $envPath = Join-Path $PSScriptRoot ".env"
  $map = @{}
  if (Test-Path $envPath) {
    Get-Content $envPath -Encoding UTF8 | ForEach-Object {
      $line = $_.Trim()
      if (-not $line -or $line.StartsWith("#")) { return }
      $kv = $line -split "=", 2
      if ($kv.Count -eq 2) { $map[$kv[0].Trim()] = $kv[1].Trim() }
    }
  }
  return $map
}

function Find-BaseRef {
  git fetch origin | Out-Null
  $cands = git branch -r --list "origin/chore/C3-C5-skeleton*"
  if ($cands) { return ($cands | Select-Object -First 1).ToString().Trim() }
  else { return "origin/main" }
}

function Push-C6 {
  Section "Push C6 - core slash commands"
  $baseRef = Find-BaseRef
  Write-Host ("Base: {0}" -f $baseRef) -ForegroundColor DarkGray
  git fetch origin | Out-Null
  git checkout -B chore-base $baseRef | Out-Null
  git checkout -B feat/C6-core-commands chore-base | Out-Null

  if (!(Test-Path ".\bot.py")) { throw "Missing bot.py - run next_core.ps1 first." }
  if (!(Test-Path ".\cogs\core.py")) { throw "Missing cogs\core.py - run next_core.ps1 first." }

  git add -A
  $pending = git status --porcelain
  if ($pending) { git commit -m "feat(core): add /about, /uptime, /sync and dev copy_global_to" | Out-Null }
  git push -u origin feat/C6-core-commands
  Write-Host "Pushed branch feat/C6-core-commands to origin." -ForegroundColor Green
}

function Setup-C7 {
  Section "C7 - dev QoL (ruff/black, pre-commit, CI)"
  $py = Get-ProjectPython
  Ensure-Dir ".github"
  Ensure-Dir ".github\workflows"

  Set-Content -Path ".\pyproject.toml" -Value @"
[tool.black]
line-length = 100
target-version = ["py312"]

[tool.ruff]
line-length = 100
target-version = "py312"
select = ["E","F","I","B","BLE","UP"]
ignore = ["E501"]

[tool.ruff.lint.isort]
known-first-party = ["cogs","config","utils"]
"@ -Encoding UTF8

  Set-Content -Path ".\.pre-commit-config.yaml" -Value @"
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.8
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
  - repo: https://github.com/psf/black
    rev: 24.8.0
    hooks:
      - id: black
"@ -Encoding UTF8

  Set-Content -Path ".github\workflows\ci.yml" -Value @"
name: ci
on:
  push: { branches: ["**"] }
  pull_request:
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - name: Install dev tools
        run: |
          python -m pip install --upgrade pip
          pip install ruff black
      - name: Ruff
        run: ruff check .
      - name: Black
        run: black --check .
"@ -Encoding UTF8

  & $py -m pip install -U ruff black pre-commit | Out-Null
  try { & $py -m pre_commit install | Out-Null } catch {}
  & $py -m ruff check --fix . | Out-Null
  & $py -m black . | Out-Null

  git add -A
  $pending = git status --porcelain
  if ($pending) {
    if (-not (git branch --list feat/C7-dev-qol)) { git checkout -b feat/C7-dev-qol | Out-Null } else { git checkout feat/C7-dev-qol | Out-Null }
    git commit -m "chore(dev): add ruff/black, pre-commit, CI; format codebase" | Out-Null
    git push -u origin feat/C7-dev-qol
    Write-Host "Pushed branch feat/C7-dev-qol to origin." -ForegroundColor Green
  } else {
    Write-Host "No changes for C7." -ForegroundColor Yellow
  }
}

function Show-WilhelminaStatus {
  Section "Repo & runtime status (Fonzie)"
  try {
    $branch = git branch --show-current
    $remote = git remote -v | Select-String "origin" | Select-Object -First 1
    Write-Host ("Branch: {0}" -f $branch)
    if ($remote) { Write-Host ("Remote: {0}" -f ($remote -replace '\s+fetch.*','')) }
    Write-Host "Recent commits:"
    git log --oneline -n 5 --decorate --graph
  } catch { Write-Host ("Git info unavailable: {0}" -f $_) -ForegroundColor Yellow }

  try {
    $p = Get-ProjectPython
    Write-Host ("Python: {0}" -f (& $p -V))
    $dp = & $p -m pip show discord.py | Select-String "^Version:"
    if ($dp) { Write-Host ("discord.py: {0}" -f ($dp.ToString().Split(':')[1].Trim())) }
  } catch { Write-Host "Python/venv check failed." -ForegroundColor Yellow }

  $dotenv = Read-DotEnv
  $gid = $dotenv["DEV_GUILD_ID"]
  $tok = if ($dotenv.ContainsKey("DISCORD_TOKEN")) { $dotenv["DISCORD_TOKEN"] } else { $env:DISCORD_TOKEN }
  $envName = if ($dotenv.ContainsKey("APP_ENV")) { $dotenv["APP_ENV"] } else { $env:APP_ENV }
  if ($tok) {
    $masked = if ($tok.Length -ge 8) { $tok.Substring(0,4) + "…" + $tok.Substring($tok.Length-4) } else { "***" }
    Write-Host ("Token: present ({0})" -f $masked)
  } else { Write-Host "Token: MISSING" -ForegroundColor Yellow }
  Write-Host ("APP_ENV: {0}" -f $envName)
  Write-Host ("DEV_GUILD_ID: {0}" -f $gid)

  if ($tok -and $gid) {
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      $h = @{ Authorization = "Bot $tok" }
      $me = Invoke-RestMethod -Method GET -Uri "https://discord.com/api/v10/users/@me" -Headers $h
      $app = Invoke-RestMethod -Method GET -Uri "https://discord.com/api/v10/oauth2/applications/@me" -Headers $h
      Write-Host ("Bot user: {0}#{1} (id {2}); App id: {3}" -f $me.username,$me.discriminator,$me.id,$app.id)
      $url = "https://discord.com/api/v10/applications/$($app.id)/guilds/$gid/commands"
      $cmds = Invoke-RestMethod -Method GET -Uri $url -Headers $h
      $names = ($cmds | ForEach-Object { $_.name }) -join ", "
      Write-Host ("Guild slash-commands ({0}): {1}" -f ($cmds.Count), $names)
    } catch {
      Write-Host ("Discord API status check failed: {0}" -f $_) -ForegroundColor Yellow
    }
  }

  $must = @("bot.py","cogs\core.py","config\settings.py",".env")
  $ok = @(); foreach($f in $must){ $ok += ("{0}: {1}" -f $f, (Test-Path $f)) }
  Write-Host ("Files: " + ($ok -join " | "))
}

# MAIN
if (-not $StatusOnly -and -not $SkipPush) { Push-C6 }
if ($IncludeC7 -and -not $StatusOnly) { Setup-C7 }
Show-WilhelminaStatus
