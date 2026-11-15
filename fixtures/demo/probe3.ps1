
$ErrorActionPreference = 'Continue'
$ca = "abcdef".ToCharArray()
Write-Output "=== len=3 ==="
try { $s = New-Object System.String($ca, 1, 3); Write-Output ("<{0}> type={1}" -f $s, $s.GetType().Name) } catch { Write-Output ("FAIL: {0}" -f $_.Exception.Message) }
Write-Output "=== len=0 ==="
try { $s = New-Object System.String($ca, 3, 0); Write-Output ("<{0}> type={1}" -f $s, $s.GetType().Name) } catch { Write-Output ("FAIL: {0}" -f $_.Exception.Message) }
Write-Output "=== concat with len=0 result ==="
try {
    $x = New-Object System.String($ca, 3, 0)
    $y = ']' + $x + ']'
    Write-Output ("<{0}> type={1}" -f $y, $y.GetType().Name)
} catch { Write-Output ("FAIL: {0}" -f $_.Exception.Message) }
