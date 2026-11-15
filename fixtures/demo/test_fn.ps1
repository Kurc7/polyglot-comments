
$ErrorActionPreference = 'Stop'
. C:\PROJECTS\check_comments\demo\functions.ps1
$cases = @(
  @("C-line",    'C',    "int a = 1; // hi`nint b;`n"),
  @("C-string",  'C',    "String s = `"a//b`"; // real`n"),
  @("C-block",   'C',    "/* x */ int y;`n"),
  @("C-javadoc", 'C',    "/** doc */`nclass A {}`n"),
  @("HASH",      'HASH', "# c`nx=1`n"),
  @("XML",       'XML',  "<!-- c --><a b=`"<!--`"/>`n"),
  @("SQL",       'SQL',  "-- c`n/* b */ select 1;`n"),
  @("LUA",       'LUA',  "-- c`n--[[b]]`nlocal x=1`n"),
  @("BAT",       'BAT',  "REM c`n:: d`necho ok`n")
)
foreach ($t in $cases) {
    try {
        $r = Get-Comments -Text $t[2] -Style $t[1]
        Write-Output ("{0}: OK ({1})" -f $t[0], $r.Count)
    } catch {
        Write-Output ("{0}: FAIL {1}" -f $t[0], $_.Exception.Message)
    }
}
