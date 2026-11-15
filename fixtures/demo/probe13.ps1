$ErrorActionPreference = 'Stop'
function Sort-Ordinal { param([string[]]$Items) $a = @($Items).Clone(); [Array]::Sort($a, [System.StringComparer]::Ordinal); return , $a }
# empty case
$allDirs = @()
$n = @($allDirs.Name)
[Console]::Error.WriteLine("empty: names-count={0} first-type={1}" -f @(@($n).Count, $(if (@($n)[0] -eq $null) {"NULL"} else {@($n)[0].GetType().Name})))
try {
  $dirMap = @{}
  $subdirs = @((Sort-Ordinal ($n)) | ForEach-Object { $dirMap[$_] })
  [Console]::Error.WriteLine("EMPTY OK count={0}" -f @($subdirs.Count))
} catch { [Console]::Error.WriteLine('EMPTY FAIL: ' + $_.Exception.Message) }
# single case
$one = New-Object PSObject -Property @{ Name = 'a' }
$allDirs2 = @($one)
$n2 = @($allDirs2.Name)
try {
  $dirMap2 = @{}; $dirMap2['a'] = $one
  $subdirs2 = @((Sort-Ordinal ($n2)) | ForEach-Object { $dirMap2[$_] })
  [Console]::Error.WriteLine("SINGLE OK count={0} val-type={1}" -f @($subdirs2.Count, $(if ($subdirs2[0]) {$subdirs2[0].GetType().Name} else {"NULL"})))
} catch { [Console]::Error.WriteLine('SINGLE FAIL: ' + $_.Exception.Message) }