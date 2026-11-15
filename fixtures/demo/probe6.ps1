function T {
    param([string]$Text)
    $chars = $Text.ToCharArray()
    [Console]::Error.WriteLine("type={0} len={1}" -f @($chars.GetType().FullName, $chars.Length))
    try {
        $s = New-Object System.String($chars, 3, 0)
        [Console]::Error.WriteLine("top-call ok <{0}>" -f $s)
    } catch { [Console]::Error.WriteLine("top-call FAIL: {0}" -f $_.Exception.Message) }
    $j = 2; $k = 3
    try {
        $s2 = New-Object System.String($chars, $j + 1, $k - $j - 1)
        [Console]::Error.WriteLine("expr-call ok <{0}>" -f $s2)
    } catch { [Console]::Error.WriteLine("expr-call FAIL: {0}" -f $_.Exception.Message) }
    try {
        $lc = "]" + (New-Object System.String($chars, $j + 1, $k - $j - 1)) + "]"
        [Console]::Error.WriteLine("concat ok <{0}>" -f $lc)
    } catch { [Console]::Error.WriteLine("concat FAIL: {0}" -f $_.Exception.Message) }
}
$nl = [string][char]10
T ("--[[b]]" + $nl)