using namespace System
using namespace System.IO
using namespace System.Linq
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

#Github Actions prepend $ErrorActionPreference = 'stop' to script contents.
$ErrorActionPreference = "Stop"

#If something is wrong, output info and stop executing
#(printing colored text doesn't work for Github Actions)
trap
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
}

Write-Host "Starting it"

[List[string]] $branch = 'wow', 'wow_classic', 'wow_classic_era'
[List[string]] $flavor = 'Retail', 'Wrath', 'ClassicEra'
[List[string]] $filenameSuffix = 'Retail', 'Wrath', 'Vanilla'

Write-Host ""

for ($i = 0; $i -lt 3; $i++)
{
  Write-Host "Version: $($flavor[$i])"
  Write-Host "Downloading files"

  Invoke-WebRequest -Uri "https://wago.tools/db2/UiTextureAtlas/csv?branch=$($branch[$i])" -OutFile "UiTextureAtlas_$($branch[$i]).csv"
  Invoke-WebRequest -Uri "https://wago.tools/db2/UiTextureAtlasMember/csv?branch=$($branch[$i])" -OutFile "UiTextureAtlasMember_$($branch[$i]).csv"
  Invoke-WebRequest -Uri "https://wago.tools/db2/UiTextureAtlasElement/csv?branch=$($branch[$i])" -OutFile "UiTextureAtlasElement_$($branch[$i]).csv"

  Write-Host "Getting data from files"

  [List[PSCustomObject]] $tableA = Import-Csv -Path "UiTextureAtlas_$($branch[$i]).csv" -Delimiter ',' -Encoding utf8
  [List[PSCustomObject]] $tableM = Import-Csv -Path "UiTextureAtlasMember_$($branch[$i]).csv" -Delimiter ',' -Encoding utf8
  [List[PSCustomObject]] $tableE = Import-Csv -Path "UiTextureAtlasElement_$($branch[$i]).csv" -Delimiter ',' -Encoding utf8
  [List[PSCustomObject]] $tableL = Import-Csv -Path "Listfile_$($branch[$i]).csv" -Delimiter ';' -Header 'FileDataID', 'Filename' -Encoding utf8

  Write-Host "Correlating table records based on matching keys"

  #Can't chain method calls. Nested calls -> It will be a mess. So, step by step

  # Join method syntax in C#
  #
  # IEnumerable<TResult> Join<TOuter,TInner,TKey,TResult>(
  #   IEnumerable<TOuter> outer,
  #   IEnumerable<TInner> inner,
  #   Func<TOuter,TKey> outerKeySelector,
  #   Func<TInner,TKey> innerKeySelector,
  #   Func<TOuter,TInner,TResult> resultSelector
  # )

  [IEnumerable[PSCustomObject]] $step1 = [Enumerable]::Join(
    $tableL,
    $tableA,
    [Func[PSCustomObject, int]] { param($itemL) $itemL.FileDataID -as [int] },
    [Func[PSCustomObject, int]] { param($itemA) $itemA.FileDataID -as [int] },
    [Func[PSCustomObject, PSCustomObject, PSCustomObject]] { param($itemL, $itemA) $itemA }
  )
  [IEnumerable[PSCustomObject]] $step2 = [Enumerable]::Join(
    $step1,
    $tableM,
    [Func[PSCustomObject, int]] { param($previous) $previous.ID -as [int] },
    [Func[PSCustomObject, int]] { param($itemM) $itemM.UiTextureAtlasID -as [int] },
    [Func[PSCustomObject, PSCustomObject, PSCustomObject]] { param($previous, $itemM) $itemM }
  )
  [IEnumerable[string]] $step3 = [Enumerable]::Join(
    $step2,
    $tableE,
    [Func[PSCustomObject, int]] { param($preceding) $preceding.UiTextureAtlasElementID -as [int] },
    [Func[PSCustomObject, int]] { param($itemE) $itemE.ID -as [int] },
    [Func[PSCustomObject, PSCustomObject, string]] { param($preceding, $itemE); $itemE.Name }
  )
  [IEnumerable[string]] $step4 = [Enumerable]::Distinct($step3, [StringComparer]::Ordinal)
  [IOrderedEnumerable[string]] $step5 = [Enumerable]::OrderBy($step4, [Func[string, string]] { $args[0] }, [StringComparer]::Ordinal)
  [List[string]] $result = [Enumerable]::ToList($step5)

  Write-Host "Writing result to file"

  try
  {
    #Don't write BOM when creating file (https://en.wikipedia.org/wiki/Byte_order_mark)
    [StreamWriter] $streamWriter = [StreamWriter]::new("AtlasList_$($filenameSuffix[$i]).lua", $false)
    $streamWriter.WriteLine("if not WeakAuras.IsLibsOK() then return end")
    $streamWriter.WriteLine("--- @type string, Private")
    $streamWriter.WriteLine("local AddonName, Private = ...")
    $streamWriter.WriteLine("")
    $streamWriter.Write("Private.AtlasList = {")
    [int] $commaCount = $result.Count

    foreach ($item in $result)
    {
      $streamWriter.Write("'$item'")
      $commaCount -= 1

      if ($commaCount -gt 0)
      {
        $streamWriter.Write(",")
      }
    }

    $streamWriter.WriteLine("}")
  }
  finally
  {
    if ($null -ne $streamWriter)
    {
      $streamWriter.Dispose()
    }
  }

  Write-Host "Moving the file"
  Move-Item -Path "AtlasList_$($filenameSuffix[$i]).lua" -Destination "../../WeakAuras/" -Force

  #Cleaning up
  Clear-Variable -Name step1, step2, step3, step4, step5, commaCount -Scope Script

  $tableL.Clear()
  $tableL.TrimExcess()
  $tableA.Clear()
  $tableA.TrimExcess()
  $tableM.Clear()
  $tableM.TrimExcess()
  $tableE.Clear()
  $tableE.TrimExcess()
  $result.Clear()
  $result.TrimExcess()

  Write-Host "Done"
  Write-Host ""
}

Write-Host "Cleaning up"

Remove-Item -Path "UiTextureAtlas_*.csv" -Force
Remove-Item -Path "UiTextureAtlasMember_*.csv" -Force
Remove-Item -Path "UiTextureAtlasElement_*.csv" -Force
Remove-Item -Path "Listfile_*.csv" -Force

#Remove files from previous step of workflow

if (Test-Path "CascLib_Debug_*.log" -PathType Leaf)
{
  Remove-Item -Path "CascLib_Debug_*.log" -Force
}

if (Test-Path "*.dll" -PathType Leaf)
{
  Remove-Item -Path "*.dll" -Force
}

Write-Host ""

Write-Host "Task has been successfully completed!"

exit 0
