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

# Older Windows PowerShell defaults to SSL3/TLS 1.0, which GitHub rejects.
# 3072 is Tls12: the enum member does not exist before .NET 4.5, but the protocol may still be supported by the OS.
try
{
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]3072
} catch
{
  Write-Error ('Could not enable TLS 1.2, which GitHub requires. ' +
    'Install .NET Framework 4.5+ (and the TLS 1.2 update for your Windows version), then try again.')
  exit 1
}

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
    $installer = [scriptblock]::Create((Invoke-RestMethod -Uri https://get.scoop.sh))

    # Scoop installer refuses to run elevated unless explicitly told to
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin)
    {
      & $installer -RunAsAdmin
    } else
    {
      & $installer
    }
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

# Since this script uses gum for its TUI, we need to install it first.
$bootstrap = @{
  winget = 'charmbracelet.gum'
  scoop = 'main/charm-gum'
}

Install-Package $bootstrap[$PackageManager]
Update-SessionPath

if (-not (Test-Command gum))
{
  Write-Error 'gum is not available after install, aborting. Try opening a new shell and running the script again.'
  exit 1
}

# Windows PowerShell pipes ASCII to native commands by default, which mangles emojis sent to gum
$OutputEncoding = New-Object System.Text.UTF8Encoding $false

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

# Every package is up to the user, nothing gets installed without being picked
$byLine = @{}
$lines = foreach ($pkg in $candidates)
{
  $line = '{0,-15} {1}' -f $pkg.name, $pkg.description
  $byLine[$line] = $pkg
  $line
}

$picked = $lines | gum filter --no-limit --header 'TAB: toggle | ENTER: confirm' --placeholder 'Search packages...'

$toInstall = @($picked | Where-Object { $_ } | ForEach-Object { $byLine[$_] } | Where-Object { $_ })
if ($toInstall.Count -eq 0)
{
  Write-Host 'No package selected, nothing to do.'
  exit 0
}

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
