$ErrorActionPreference = 'Stop'
. C:\PROJECTS\check_comments\demo\functions_utf8.ps1
$r = Get-Comments -Text "a // one`nb /* two */`n" -Style "c"
[Console]::Error.WriteLine("count={0}" -f @($r.Count))
foreach ($x in @($r)) { [Console]::Error.WriteLine("item: {0} :: {1}" -f @($x.GetType().Name, ([string]$x).Substring(0, [Math]::Min(30, ([string]$x).Length)))) }