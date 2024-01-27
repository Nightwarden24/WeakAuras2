using namespace CASCLib
using namespace System
using namespace System.IO
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

#Github Actions prepend $ErrorActionPreference = 'stop' to script contents.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

#If something is wrong, output info and stop executing
#(printing colored text doesn't work for Github Actions)
<# trap
{
  Write-Host
  Write-Host "| AN ERROR HAS OCCURRED"
  Write-Host "| Type: $($_.Exception.GetType().Name)"
  Write-Host "| Message: $($_.Exception.Message)"
  #Workaround: PositionMessage instead of Statement
  #Currently VM images for GitHub-hosted runners used for Actions contain PowerShell version 7.2
  #It will be updated on January, 28
  #InvocationInfo.Statement property is available since 7.4
  #Write-Host "| Statement: $($_.InvocationInfo.Statement)"
  Write-Host "| Line: $($_.InvocationInfo.PositionMessage.Split([Environment]::NewLine)[1].TrimStart('+', ' '))"
  Write-Host "| Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber):$($_.InvocationInfo.OffsetInLine)"
  Write-Host

  exit 1
} #>

Write-Host "Starting it"
Write-Host ""

[List[string]] $branches = 'wow', 'wow_classic', 'wow_classic_era'

New-Item -Path "Temp" -ItemType Directory -Force | Out-Null
Set-Location -Path "Temp"

Write-Host "Downloading community listfile"
Invoke-WebRequest -Uri "https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv" -OutFile "community-listfile.csv"

Write-Host "Getting data from the file"
[List[PSCustomObject]] $communityLF = Import-Csv -Path "community-listfile.csv" -Delimiter ';' -Header 'FileDataID', 'Filename' -Encoding utf8

Write-Host "Cloning CascLib repository"
git clone https://github.com/WoW-Tools/CascLib.git --quiet

Set-Location -Path "CascLib/CascLib"

Write-Host "Building the library and its dependencies. Dotnet output:"
Write-Host ""
dotnet publish CascLib.csproj --configuration Release --framework net8.0
Write-Host ""

Write-Host "Сonfiguring CascLib"

if (-not (Test-Path "../../../*.dll" -PathType Leaf))
{
  Move-Item -Path "bin/Release/net8.0/publish/*.dll" -Destination "../../../" -Force
}
Set-Location -Path "../../"

Add-Type -Path "../CascLib.dll"
Add-Type -Path "../MimeKitLite.dll"
# Import-Module -Name "../CascLib.dll" -Scope Local
# Import-Module -Name "../MimeKitLite.dll" -Scope Local

$source = @"
using CASCLib;
using System;
using System.IO;

public class CustomLoggerOptions : ILoggerOptions
{
    public string LogFileName { get; private set; }
    public bool TimeStamp => true;

    public CustomLoggerOptions(string path, string filenameSuffix)
    {
      LogFileName = Path.Combine(path, $"CascLib_Debug_{filenameSuffix}.log");
    }
}
"@

if (-not ('CustomLoggerOptions' -as [type]))
{
  Add-Type -TypeDefinition $source -ReferencedAssemblies "../CascLib.dll"
}

[CASCConfig]::LoadFlags = [LoadFlags]::FileIndex -bor [LoadFlags]::Install
[CASCConfig]::ThrowOnFileNotFound = $true
[CASCConfig]::ThrowOnMissingDecryptionKey = $true
[CASCConfig]::ValidateData = $true
[CASCConfig]::UseWowTVFS = $false
[CDNCache]::CachePath = "$PWD/CascLib_Cache"

Write-Host "Opening online storages"
Write-Host ""

foreach ($branch in $branches)
{
  [CustomLoggerOptions] $loggerOptions = [CustomLoggerOptions]::new("$PWD/../", $branch)
  [CASCConfig] $config = [CASCConfig]::LoadOnlineStorageConfig($branch, "eu", $false, $loggerOptions)

  [string[]] $parts = $($config.BuildName) -replace ".+-|_.+", "" -split "patch"

  Write-Host "Branch: $($branch)"
  Write-Host "Build: $($parts[1]).$($parts[0])"
  Write-Host "CascLib output:"
  Write-Host ""

  [CASCHandler] $handler = [CASCHandler]::OpenStorage($config)

  [WowRootHandler] $wowRoot = [WowRootHandler] $handler.Root
  $wowRoot.LoadListFile("$PWD/community-listfile.csv")
  $wowRoot.SetFlags([LocaleFlags]::enUS, $false, $true) | Out-Null
  $wowRoot.MergeInstall($handler.Install)

  Write-Host ""

  Write-Host "Creating listfile"
  [List[string]] $currentLF = [List[string]]::new()

  foreach ($item in $communityLF)
  {
    if ($wowRoot.RootEntries.ContainsKey($item.FileDataID -as [int]))
    {
      $currentLF.Add("$($item.FileDataID);$($item.Filename)")
    }
  }

  Write-Host "Writing result to file"
  [File]::WriteAllLines("$PWD/Listfile_$branch.csv", $currentLF)

  Write-Host "Moving the file"
  Move-Item -Path "Listfile_$branch.csv" -Destination "../" -Force

  #Cleaning up
  Clear-Variable -Name branch, loggerOptions, config, parts, item -Scope Script

  $currentLF.Clear()
  $currentLF.TrimExcess()
  $handler.Clear()

  Write-Host "Done"
  Write-Host ""
}

Write-Host "Cleaning up"

# Remove-Module -Name "CascLib"
# Remove-Module -Name "MimeKitLite"

Set-Location -Path "../"
Remove-Item -Path "Temp" -Recurse -Force

Write-Host ""
Write-Host "Task has been successfully completed!"

exit 0
