
Write-Output "=== dot-source only ==="
try { . C:\PROJECTS\check_comments\demo\functions_dbg.ps1; Write-Output "LOADED OK" } catch { Write-Output ("LOAD FAIL: {0}" -f $_.Exception.Message) }
Write-Output "=== simple call abc ==="
try { $r = Get-Comments -Text "abc`n" -Style 'lua'; Write-Output ("OK count={0}" -f $r.Count) } catch { Write-Output ("CALL FAIL: {0}" -f $_.Exception.Message) }
