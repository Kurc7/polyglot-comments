
$ErrorActionPreference = 'Stop'
. C:\PROJECTS\check_comments\demo\functions_dbg.ps1
try {
    $r = Get-Comments -Text "--[[b]]`n" -Style 'lua'
    Write-Output ("R type={0} count={1}" -f $r.GetType().Name, @($r).Count)
} catch {
    Write-Output ("ERR: {0}" -f $_.Exception.Message)
    Write-Output ("STACK: {0}" -f ($_.ScriptStackTrace -replace "`n", " | "))
}
