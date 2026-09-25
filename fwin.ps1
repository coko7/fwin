#  _____           _     __        ___           _
# |  ___|   _  ___| | __ \ \      / (_)_ __   __| | _____      _____
# | |_ | | | |/ __| |/ /  \ \ /\ / /| | '_ \ / _` |/ _ \ \ /\ / / __|
# |  _|| |_| | (__|   <    \ V  V / | | | | | (_| | (_) \ V  V /\__ \
# |_|   \__,_|\___|_|\_\    \_/\_/  |_|_| |_|\__,_|\___/ \_/\_/ |___/
#
# "Windows sucks ass, lets fix it for good." ~ @me
#
# Interactive flavour of fwin: pick what you want from packages.jsonc.
#
# Author: @coko7

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$PackagesUrl = 'https://raw.githubusercontent.com/coko7/fwin/refs/heads/main/packages.jsonc'

function Test-Command
{
  param(
    [Parameter(Mandatory=$true)]
    [string]$Name
  )

  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# Reload PATH to use newly installed tools
function Update-SessionPath
{
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = "$machine;$user"
}

# Pick the package manager. It tries winget first.
# If it cannot find winget, it fallbacks to scoop and installs the latter if also missing.
#
# It turns out some versions of Windows server do not come with winget by default.
# Hold up... Let me write that again:
# It turns out some versions of Windows serrver DO NOT come with a package manager.
# ...
# 🤦
if (Test-Command winget)
{
  $PackageManager = 'winget'
} else
{
  if (-not (Test-Command scoop))
  {
    Write-Host 'Neither winget nor scoop found, installing scoop...'
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    Update-SessionPath
  }

  if (-not (Test-Command scoop))
  {
    Write-Error 'Failed to install scoop, aborting.'
    exit 1
  }

  # Need git for buckets other than main
  if (-not (Test-Command git))
  {
    scoop install main/git
  }

  $buckets = @('main', 'extras')
  foreach ($bucket in $buckets)
  {
    if (-not (scoop bucket list | Select-String -Quiet "^\s*$bucket\b"))
    {
      scoop bucket add $bucket
      Write-Host "Added scoop bucket: $bucket"
    }
  }

  $PackageManager = 'scoop'
}

Write-Host "Using package manager: $PackageManager"

function Test-PackageInstalled
{
  param(
    [Parameter(Mandatory=$true)]
    [string]$Id
  )

  if ($PackageManager -eq 'winget')
  {
    winget list --id $Id --exact --accept-source-agreements *> $null
    return $LASTEXITCODE -eq 0
  }

  $name = ($Id -split '/')[-1]
  return [bool](scoop list $name 2>$null | Select-String -Quiet "^\s*$name(\s|$)")
}

function Install-Package
{
  param(
    [Parameter(Mandatory=$true)]
    [string]$Id
  )

  if (Test-PackageInstalled $Id)
  {
    Write-Host "$Id is already installed, skipping."
    return
  }

  Write-Host "Installing $Id..."
  if ($PackageManager -eq 'winget')
  {
    winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements
  } else
  {
    scoop install $Id
  }

  if ($LASTEXITCODE -ne 0)
  {
    Write-Warning "Failed to install $Id"
  }
}

# Since this script uses fzf and gum for its TUI, we need to install them first.
$bootstrap = @{
  winget = @('junegunn.fzf', 'charmbracelet.gum')
  scoop = @('main/fzf', 'main/gum')
}

foreach ($id in $bootstrap[$PackageManager])
{
  Install-Package $id
}

Update-SessionPath

foreach ($tool in @('fzf', 'gum'))
{
  if (-not (Test-Command $tool))
  {
    Write-Error "$tool is not available after install, aborting. Try opening a new shell and running the script again."
    exit 1
  }
}

# Load the packages list: Tries local file first, falls back to $PackagesUrl otherwise.
$localPackages = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'packages.jsonc' }
if ($localPackages -and (Test-Path $localPackages))
{
  $rawPackages = Get-Content -Raw -Path $localPackages
} else
{
  $rawPackages = (Invoke-WebRequest -Uri $PackagesUrl -UseBasicParsing).Content
}

# PowerShell 5.1 cannot parse comments in JSON, so we strip full-line // comments
$rawPackages = ($rawPackages -split "`r?`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
$catalog = $rawPackages | ConvertFrom-Json

$mode = gum choose --header 'Select install mode' 'desktop' 'server'
if (-not $mode)
{
  Write-Host 'No install mode selected, aborting.'
  exit 1
}

$candidates = @($catalog.all) + @($catalog.$mode) | Where-Object {
  if ($_.packageIds.$PackageManager) { return $true }
  Write-Warning "$($_.name) has no $PackageManager package, skipping."
  return $false
}

# Required packages are always installed, the rest is up to the user
$required = @($candidates | Where-Object { $_.importance -eq 'required' })

$selectable = @($candidates | Where-Object { $_.importance -ne 'required' })

$selected = @()
if ($selectable.Count -gt 0)
{
  $lines = for ($i = 0; $i -lt $selectable.Count; $i++)
  {
    $pkg = $selectable[$i]
    "{0}`t{1,-15} {2,-10} {3}" -f $i, $pkg.name, "[$($pkg.importance)]", $pkg.description
  }

  $picked = $lines | fzf --multi --delimiter "`t" --with-nth 2.. `
    --header 'TAB: toggle | CTRL-A: select all | ENTER: confirm' `
    --bind 'ctrl-a:select-all'

  $selected = @($picked | Where-Object { $_ } | ForEach-Object { $selectable[[int]($_ -split "`t")[0]] })
}

$toInstall = @($required) + @($selected)
Write-Host "`nAbout to install ($mode mode, via $PackageManager):"
$toInstall | ForEach-Object { Write-Host "  - $($_.name)" }

gum confirm 'Proceed?'
if ($LASTEXITCODE -ne 0)
{
  Write-Host 'Aborted.'
  exit 0
}

foreach ($pkg in $toInstall)
{
  Install-Package $pkg.packageIds.$PackageManager
}

Write-Host '🚀 Congratulations. Your Windows dev setup is now a tiny bit better ✨'
Write-Host "🐧 Don't forget to switch over to Linux when you get a chance 👋"
