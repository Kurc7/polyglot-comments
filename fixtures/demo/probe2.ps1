
$ErrorActionPreference = 'Stop'
. C:\PROJECTS\check_comments\demo\functions.ps1
try {
    $r = Get-Comments -Text "--[[b]]`n" -Style 'lua'
} catch {
    Write-Output ("MSG: {0}" -f $_.Exception.Message)
    Write-Output ("STACK: {0}" -f ($_.ScriptStackTrace -replace "`n", " | "))
    Write-Output ("POS: {0}" -f $_.InvocationInfo.PositionMessage)
}
