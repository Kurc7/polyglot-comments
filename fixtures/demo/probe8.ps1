function T {
    param([string]$Text)
    $chars = $Text.ToCharArray()
    $a = 3; $b = 0
    try {
        $s = New-Object System.String($chars, $a, $b)
        [Console]::Error.WriteLine("V1: ($chars, $a, $b): ok type={0} val=[{1}]" -f @($s.GetType().Name, ($s -join ",")))
    } catch { [Console]::Error.WriteLine("V1: ($chars, $a, $b): FAIL {0}" -f $_.Exception.Message) }
    try {
        $s = New-Object System.String($chars, 3, $b)
        [Console]::Error.WriteLine("V2: ($chars, 3, $b): ok type={0} val=[{1}]" -f @($s.GetType().Name, ($s -join ",")))
    } catch { [Console]::Error.WriteLine("V2: ($chars, 3, $b): FAIL {0}" -f $_.Exception.Message) }
    try {
        $s = New-Object System.String($chars, $a, 0)
        [Console]::Error.WriteLine("V3: ($chars, $a, 0): ok type={0} val=[{1}]" -f @($s.GetType().Name, ($s -join ",")))
    } catch { [Console]::Error.WriteLine("V3: ($chars, $a, 0): FAIL {0}" -f $_.Exception.Message) }
    try {
        $s = New-Object System.String($chars, $a + 0, $b)
        [Console]::Error.WriteLine("V4: ($chars, $a + 0, $b): ok type={0} val=[{1}]" -f @($s.GetType().Name, ($s -join ",")))
    } catch { [Console]::Error.WriteLine("V4: ($chars, $a + 0, $b): FAIL {0}" -f $_.Exception.Message) }
    try {
        $s = New-Object System.String($chars, $a, $b - 0)
        [Console]::Error.WriteLine("V5: ($chars, $a, $b - 0): ok type={0} val=[{1}]" -f @($s.GetType().Name, ($s -join ",")))
    } catch { [Console]::Error.WriteLine("V5: ($chars, $a, $b - 0): FAIL {0}" -f $_.Exception.Message) }
    try {
        $s = New-Object 'System.Collections.Generic.List[int]'($a, $b)
        [Console]::Error.WriteLine("V6: List[object] ($a,$b): ok type={0} val=[{1}]" -f @($s.GetType().Name, ($s -join ",")))
    } catch { [Console]::Error.WriteLine("V6: List[object] ($a,$b): FAIL {0}" -f $_.Exception.Message) }
    try {
        $s = [int[]](1 + 1, 2)
        [Console]::Error.WriteLine("V7: Array (1+1, 2): ok type={0} val=[{1}]" -f @($s.GetType().Name, ($s -join ",")))
    } catch { [Console]::Error.WriteLine("V7: Array (1+1, 2): FAIL {0}" -f $_.Exception.Message) }
}
$nl = [string][char]10
T ("--[[b]]" + $nl)