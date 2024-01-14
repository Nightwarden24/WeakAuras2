using namespace System
using namespace System.IO
using namespace System.Linq
using namespace System.Text
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

#Github Actions prepend $ErrorActionPreference = 'stop' to script contents.
#$ErrorActionPreference = "Stop"

#If something is wrong, stop executing
trap
{
  Write-Host
  Write-Host "| AN ERROR HAS OCCURRED"
  Write-Host "| Type: $($_.Exception.GetType().Name)"
  Write-Host "| Message: $($_.Exception.Message)"
  #Write-Host "Statement: $($_.InvocationInfo.Statement)"
  #Workaround
  #Currently VM images for GitHub-hosted runners used for Actions contain PowerShell version 7.2
  #It will be updated on January, 28
  #Statement property of InvocationInfo is available since 7.4
  Write-Host "| Line: $($_.InvocationInfo.PositionMessage.Split([Environment]::NewLine)[1].TrimStart('+', ' '))"
  Write-Host "| Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber):$($_.InvocationInfo.OffsetInLine)"
  Write-Host

  exit 1
}

Write-Host "Starting it"

Class UiTextureAtlas
{
  [int] $ID;
  [int] $FileDataID;
  [int] $AtlasWidth;
  [int] $AtlasHeight;
  [int] $UiCanvasID;
}

Class UiTextureAtlasMember
{
  [string] $CommittedName;
  [int] $ID;
  [int] $UiTextureAtlasID;
  [int] $CommittedLeft;
  [int] $CommittedRight;
  [int] $CommittedTop;
  [int] $CommittedBottom;
  [int] $UiTextureAtlasElementID;
  [int] $OverrideWidth;
  [int] $OverrideHeight;
  [int] $CommittedFlags;
  [int] $UiCanvasID;
}

Class UiTextureAtlasElement
{
  [string] $Name;
  [int] $ID;
}

[List[string]] $branch = 'wow', 'wow_classic', 'wow_classic_era'
[List[string]] $flavor = 'Retail', 'Wrath', 'ClassicEra'

Write-Host ""

for ($i = 0; $i -lt 3; $i++)
{
  Write-Host "Version: $($flavor[$i])"
  Write-Host "Downloading files"

  Invoke-WebRequest -Uri "https://wago.tools/db2/UiTextureAtlas/csv?branch=$($branch[$i])" -OutFile "UiTextureAtlas_$($flavor[$i]).csv"
  Invoke-WebRequest -Uri "https://wago.tools/db2/UiTextureAtlasMember/csv?branch=$($branch[$i])" -OutFile "UiTextureAtlasMember_$($flavor[$i]).csv"
  Invoke-WebRequest -Uri "https://wago.tools/db2/UiTextureAtlasElement/csv?branch=$($branch[$i])" -OutFile "UiTextureAtlasElement_$($flavor[$i]).csv"

  Write-Host "Getting data from files"

  [List[UiTextureAtlas]] $tableA = Import-Csv -Path "UiTextureAtlas_$($flavor[$i]).csv" -Delimiter ',' -Encoding utf8
  [List[UiTextureAtlasMember]] $tableM = Import-Csv -Path "UiTextureAtlasMember_$($flavor[$i]).csv" -Delimiter ',' -Encoding utf8
  [List[UiTextureAtlasElement]] $tableE = Import-Csv -Path "UiTextureAtlasElement_$($flavor[$i]).csv" -Delimiter ',' -Encoding utf8

  Write-Host "Correlating table records based on matching keys"

  #Can't chain method calls. Nested calls -> It will be a mess. So, step by step

  # Syntax Join method
  #
  # IEnumerable<TResult> Join<TOuter,TInner,TKey,TResult>(
  #   IEnumerable<TOuter> outer,
  #   IEnumerable<TInner> inner,
  #   Func<TOuter,TKey> outerKeySelector,
  #   Func<TInner,TKey> innerKeySelector,
  #   Func<TOuter,TInner,TResult> resultSelector)

  [IEnumerable[UiTextureAtlasMember]] $step1 = [Enumerable]::Join(
    $tableA,
    $tableM,
    [Func[UiTextureAtlas, int]] { param($itemA) $itemA.ID },
    [Func[UiTextureAtlasMember, int]] { param($itemM) $itemM.UiTextureAtlasID },
    [Func[UiTextureAtlas, UiTextureAtlasMember, UiTextureAtlasMember]] { param($itemA, $itemM) $itemM }
  )

  [IEnumerable[string]] $step2 = [Enumerable]::Join(
    $step1,
    $tableE,
    [Func[UiTextureAtlasMember, int]] { param($previous) $previous.UiTextureAtlasElementID },
    [Func[UiTextureAtlasElement, int]] { param($itemE) $itemE.ID },
    [Func[UiTextureAtlasMember, UiTextureAtlasElement, string]] { param($previous, $itemE); $itemE.Name }
  )

  [IEnumerable[string]] $step3 = [Enumerable]::Distinct($step2, [StringComparer]::Ordinal)

  [IOrderedEnumerable[string]] $step4 = [Enumerable]::OrderBy($step3, [Func[string, string]] { $args[0] }, [StringComparer]::Ordinal)

  [List[string]] $result = [Enumerable]::ToList($step4)

  Write-Host "Writing result in a file"

  try
  {
    [StreamWriter] $streamWriter = [StreamWriter]::new("AtlasList_$($flavor[$i]).lua", $false, [Encoding]::UTF8)
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

  Move-Item -Path "AtlasList_$($flavor[$i]).lua" -Destination "../../WeakAuras/" -Force

  Write-Host "Cleaning up"

  Clear-Variable -Name step1, step2, step3, step4, commaCount -Scope Script

  $tableA.Clear()
  $tableA.TrimExcess()
  $tableM.Clear()
  $tableM.TrimExcess()
  $tableE.Clear()
  $tableE.TrimExcess()
  $result.Clear()
  $result.TrimExcess()

  Remove-Item -Path "UiTextureAtlas_$($flavor[$i]).csv"
  Remove-Item -Path "UiTextureAtlasMember_$($flavor[$i]).csv"
  Remove-Item -Path "UiTextureAtlasElement_$($flavor[$i]).csv"

  Write-Host "Done"
  Write-Host ""
}

Write-Host "Task has been successfully completed!"
exit 0
