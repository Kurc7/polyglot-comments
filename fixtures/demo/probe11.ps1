$ErrorActionPreference = 'Stop'
. C:\PROJECTS\check_comments\demo\functions_utf8.ps1
$r = Get-Comments -Text "x # one`n" -Style "hash"
[Console]::Error.WriteLine("type={0} count={1}" -f @($r.GetType().Name, $r.Count))
foreach ($c in $r) { [Console]::Error.WriteLine("item type={0} Line={1}" -f @($c.GetType().Name, $c.Line)) }