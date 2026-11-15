function T {
    param([string]$Text)
    $chars = $Text.ToCharArray()
    $j = 2; $k = 3; $x = 0
    try {
        $s = New-Object System.String($chars, $j + 1, 0)
        [Console]::Error.WriteLine("A: ($chars, $j+1, 0): ok <{0}>" -f $s)
    } catch { [Console]::Error.WriteLine("A: ($chars, $j+1, 0): FAIL {0}" -f $_.Exception.Message) }
    try {
        $s = New-Object System.String($chars, 3, $k - $j - 1)
        [Console]::Error.WriteLine("B: ($chars, 3, $k-$j-1): ok <{0}>" -f $s)
    } catch { [Console]::Error.WriteLine("B: ($chars, 3, $k-$j-1): FAIL {0}" -f $_.Exception.Message) }
    try {
        $s = New-Object System.String($chars, 3, $x)
        [Console]::Error.WriteLine("C: ($chars, 3, $x): ok <{0}>" -f $s)
    } catch { [Console]::Error.WriteLine("C: ($chars, 3, $x): FAIL {0}" -f $_.Exception.Message) }
    try {
        $s = New-Object System.String($chars, $j, $k)
        [Console]::Error.WriteLine("D: ($chars, $j, $k): ok <{0}>" -f $s)
    } catch { [Console]::Error.WriteLine("D: ($chars, $j, $k): FAIL {0}" -f $_.Exception.Message) }
    try {
        $s = New-Object System.String($chars, 3, 0)
        [Console]::Error.WriteLine("E: ($chars, 3, 0) literal: ok <{0}>" -f $s)
    } catch { [Console]::Error.WriteLine("E: ($chars, 3, 0) literal: FAIL {0}" -f $_.Exception.Message) }
}
$nl = [string][char]10
T ("--[[b]]" + $nl)