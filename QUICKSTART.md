# Quickstart — 30 minutes from zero to demo

This guide gets you from a fresh Windows Server install to a fully working demo of the toolkit.

## Prerequisites
- Windows Server 2019 / 2022 (Evaluation is fine)
- Admin rights
- Internet access (for RSAT install)

## Steps

### 1. Promote to Domain Controller (10 min)
```powershell
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Install-ADDSForest -DomainName 'schmidt-partner.local' `
                   -DomainNetbiosName 'SCHMIDTPARTNER' `
                   -InstallDNS `
                   -SafeModeAdministratorPassword (Read-Host -AsSecureString) `
                   -Force
# Server reboots automatically
```

### 2. After reboot, confirm AD is healthy (1 min)
```powershell
Get-ADDomain
dcdiag /v
```

### 3. Copy the toolkit (1 min)
```powershell
# From your repo / USB / network share
Copy-Item -Path 'X:\mittelstand-ad-toolkit' -Destination 'C:\IT\' -Recurse
cd C:\IT\mittelstand-ad-toolkit\scripts
```

### 4. Allow scripts to run (30 sec)
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 5. Initialize OUs and groups (1 min)
```powershell
.\Initialize-SPOUStructure.ps1 -WhatIf       # preview
.\Initialize-SPOUStructure.ps1               # execute
```

### 6. Onboard 8 sample users (1 min)
```powershell
.\New-SPUser.ps1 -CsvPath ..\examples\new-hires-2026-01.csv -WhatIf
.\New-SPUser.ps1 -CsvPath ..\examples\new-hires-2026-01.csv
```

Open `dsa.msc` (Active Directory Users and Computers) and verify the users
appeared in the right department OUs.

### 7. Generate a health report (30 sec)
```powershell
.\Get-SPADHealthReport.ps1
```

The HTML file opens in your browser. **This is the screenshot you put in your CV.**

### 8. Try a password reset (10 sec)
```powershell
.\Reset-SPPassword.ps1 -Username max.mustermann -TicketId TKT-2026-0001
```

### 9. Try an offboarding (10 sec)
```powershell
.\Disable-SPUser.ps1 -Username max.mustermann `
                     -TicketId TKT-2026-0099 `
                     -Reason Resignation `
                     -LastDay 2026-12-31
```

### 10. Review the audit logs (1 min)
```powershell
Get-Content C:\IT\Logs\ADToolkit\Audit_Onboarding.csv
Get-Content C:\IT\Logs\ADToolkit\Audit_Offboarding.csv
Get-Content C:\IT\Logs\ADToolkit\Audit_PasswordReset.csv
```

## Done

You now have a working AD lab with:
- 8 users across 6 departments
- Audit logs for every action
- An HTML health report
- Documentation in DE/EN

**Take a snapshot of the VM now** so you can reset for the next demo.

## Demo script for interviews (5 minutes)

1. **Show the OU structure** in `dsa.msc` — “This follows the AGDLP model and separates users by department.”
2. **Open `config.psd1`** — “All scripts read from one config file. Reuse on any company in 30 seconds.”
3. **Run `New-SPUser.ps1 -WhatIf`** — “Every action supports `-WhatIf` for safe testing.”
4. **Open the HTML report** in browser — “Weekly via Scheduled Task. Stale passwords, locked accounts, privileged group changes.”
5. **Show the audit CSV** — “Every change is logged with operator, timestamp, ticket ID. DSGVO retention: 6 years.”
6. **Show the README** — “Bilingual runbooks for the team. Self-service.”
