using namespace System
using namespace System.IO
using namespace System.Linq
using namespace System.Text
using namespace System.Collections.Generic

Set-StrictMode -Version Latest

#Github Actions prepend $ErrorActionPreference = 'stop' to script contents.
#$ErrorActionPreference = "Stop"

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
[List[string]] $filenameSuffix = 'Retail', 'Wrath', 'Vanilla'

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

  # Join method syntax in C#
  #
  # IEnumerable<TResult> Join<TOuter,TInner,TKey,TResult>(
  #   IEnumerable<TOuter> outer,
  #   IEnumerable<TInner> inner,
  #   Func<TOuter,TKey> outerKeySelector,
  #   Func<TInner,TKey> innerKeySelector,
  #   Func<TOuter,TInner,TResult> resultSelector
  # )

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

  Write-Host "Excluding textures that are not available"

  #One such group of textures is currently known - CGuy_*
  #Based on the file name (Interface/CameraGuy/CameraGuyAsset) we can assume that they are intended for commentator mode
  #Listfile of the current build is required for the others
  $result.RemoveAll([Predicate[string]] { param($x) $x.Contains("CGuy_") }) | Out-Null

  Write-Host "Writing result to file"

  [bool] $isLineFound = $false
  try
  {
    #Don't write BOM when creating file (https://en.wikipedia.org/wiki/Byte_order_mark)
    #In the line below:
    #the 1st param - encoder should emit UTF8 identifier
    #the 2nd param - throw an exception on invalid bytes
    [UTF8Encoding] $UTF8NoBOM = [UTF8Encoding]::new($false, $true)
    [StreamWriter] $streamWriter = [StreamWriter]::new("Types_$($filenameSuffix[$i]).lua", $false, $UTF8NoBOM)
    [StreamReader] $streamReader = [StreamReader]::new("../../WeakAuras/Types_$($filenameSuffix[$i]).lua", [Encoding]::UTF8)

    while ($streamReader.Peek() -gt -1)
    {
      [string] $line = $streamReader.ReadLine()

      if ($line.Contains("Private.AtlasList = {"))
      {
        $isLineFound = $true
        [int] $commaCount = $result.Count
        $streamWriter.Write("Private.AtlasList = {")

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
      else
      {
        $streamWriter.WriteLine($line)
      }
    }
  }
  finally
  {
    if ($null -ne $streamReader)
    {
      $streamReader.Dispose()
    }
    if ($null -ne $streamWriter)
    {
      $streamWriter.Dispose()
    }
  }

  if (-not $isLineFound)
  {
    #We only created a clone instead of updating the file -> throw an error
    throw (New-Object -TypeName Exception -ArgumentList "Atlas list is no longer located in Types_$($filenameSuffix[$i]).lua")
  }

  Move-Item -Path "Types_$($filenameSuffix[$i]).lua" -Destination "../../WeakAuras/" -Force

  Write-Host "Cleaning up"
  Clear-Variable -Name step1, step2, step3, step4, UTF8NoBOM, line, commaCount -Scope Script

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

#Set an environment variable for next step of workflow
#Comment out the line to debug script on your computer
"current_date=$(Get-Date -Format "d MMMM")" | Out-File -FilePath $env:GITHUB_ENV -Append

Write-Host "Task has been successfully completed!"

exit 0
