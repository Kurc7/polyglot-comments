$a = @("console.txt","LICENSE","pom.xml.versionsBackup","README.md","tokens/StoredCredential")
[Array]::Sort($a, [System.StringComparer]::Ordinal)
[Console]::Error.WriteLine(("ORD: " + ($a -join ",")))