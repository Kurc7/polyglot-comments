
$ErrorActionPreference = 'Stop'
. C:\PROJECTS\check_comments\demo\functions_utf8.ps1
$cases = @(
  @("abc-lua",  'lua',  "abc`n"),
  @("C-line",   'c',    "int a = 1; // hi`nint b;`n"),
  @("C-string", 'c',    "String s = `"a//b`"; // real`n"),
  @("C-block",  'c',    "/* x */ int y;`n"),
  @("C-jdoc",   'c',    "/** doc */`nclass A {}`n"),
  @("HASH",     'hash', "# c`nx=1`n"),
  @("XML",      'xml',  "<!-- c --><a b=`"<!--`"/>`n"),
  @("SQL",      'sql',  "-- c`n/* b */ select 1;`n"),
  @("LUA-line", 'lua',  "-- c`nlocal x=1`n"),
  @("LUA-long", 'lua',  "--[[b]]`n"),
  @("LUA-eq",   'lua',  "--[=[b]=]`n"),
  @("BAT",      'bat',  "REM c`n:: d`necho ok`n")
)
foreach ($t in $cases) {
    try {
        $r = @(Get-Comments -Text $t[2] -Style $t[1])
        Write-Output ("{0}: OK ({1})" -f $t[0], $r.Count)
    } catch {
        Write-Output ("{0}: FAIL {1}" -f $t[0], $_.Exception.Message)
    }
}
