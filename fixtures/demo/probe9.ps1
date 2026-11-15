$ErrorActionPreference = "Continue"
try { $r = "a{0} b{1}" -f 1, 2; [Console]::Error.WriteLine("F1 ok: [{0}]" -f @($r)) } catch { [Console]::Error.WriteLine("F1 FAIL: {0}" -f $_.Exception.Message) }
try { $r = ("TRACE i={0} state={1} ch=[{2}]" -f 0, 0, "-"); [Console]::Error.WriteLine("F2 ok: [{0}]" -f @($r)) } catch { [Console]::Error.WriteLine("F2 FAIL: {0}" -f $_.Exception.Message) }
try { $r = ('L{0,-4} [{1}]' -f 5, 'line').PadRight(15); [Console]::Error.WriteLine("F3 ok: [{0}]" -f @($r)) } catch { [Console]::Error.WriteLine("F3 FAIL: {0}" -f $_.Exception.Message) }
try { $r = ('{0}: {1}' -f "x", 3); [Console]::Error.WriteLine("F4 ok: [{0}] type={1}" -f @($r, $r.GetType().Name)) } catch { [Console]::Error.WriteLine("F4 FAIL: {0}" -f $_.Exception.Message) }