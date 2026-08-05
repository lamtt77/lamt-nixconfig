# 1. Install OpenSSH Beta/Preview Server via Winget
winget install Microsoft.OpenSSH.Beta --override "ADDLOCAL=Client,Server" --accept-source-agreements --accept-package-agreements

# 2. Start Service & Set to Automatic
Set-Service -Name sshd -StartupType Automatic; Start-Service -Name sshd

# 3. Create Inbound Firewall Rule (Port 22)
New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22

# 4. Fix SSH Host Key Permissions
$KeyPath = "$env:ProgramData\ssh\ssh_host_ed25519_key"
if (Test-Path $KeyPath) {
    icacls $KeyPath /inheritance:r /grant "NT AUTHORITY\SYSTEM:(F)" /grant "BUILTIN\Administrators:(F)"
}

# 5. Hardware Power Adjustments (AC Power Only)
# Lid Close Action -> Do Nothing
powercfg -setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0

# System Sleep Timeout -> Never
powercfg -setacvalueindex SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0

# Display Sleep Timeout -> 5 Minutes (300 seconds)
powercfg -setacvalueindex SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 300

# Apply power modifications immediately
powercfg -SetActive SCHEME_CURRENT
