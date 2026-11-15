
$ErrorActionPreference = 'Continue'
Write-Output "=== probe New-Object System.String(char[],int,int) ==="
try {
    $ca = "abcdef".ToCharArray()
    $s = New-Object System.String($ca, 1, 3)
    Write-Output ("result=<{0}>" -f $s)
} catch { Write-Output ("FAIL: {0}" -f $_.Exception.Message) }

Write-Output "=== probe StartsWith(string,int) ==="
try {
    $r = "hello world".StartsWith("world", 6)
    Write-Output ("result={0}" -f $r)
} catch { Write-Output ("FAIL: {0}" -f $_.Exception.Message) }

Write-Output "=== probe StartsWith(string,int) at index 9 ==="
try {
    $r = "hello world".StartsWith("ld", 9)
    Write-Output ("result={0}" -f $r)
} catch { Write-Output ("FAIL: {0}" -f $_.Exception.Message) }

Write-Output "=== bisection LUA ==="
. C:\PROJECTS\check_comments\demo\functions.ps1
$cases = @(
  @("A-no-long",  "-- c`nlocal x=1`n"),
  @("B-long-only", "--[[b]]`n"),
  @("C-mid",      "x--[[b]]y`n"),
  @("D-eq-level", "--[=[b]=]`n")
)
foreach ($t in $cases) {
    try {
        $r = Get-Comments -Text $t[1] -Style 'lua'
        Write-Output ("{0}: OK ({1})" -f $t[0], $r.Count)
    } catch {
        Write-Output ("{0}: FAIL {1}" -f $t[0], $_.Exception.Message)
    }
}
