# Lab Setup Guide / Lab-Aufbau

> How to build a self-contained test lab to run this toolkit safely.

---

## Goal

A standalone Windows AD lab where you can:
- Run all toolkit scripts without touching production
- Reset and start over in 5 minutes
- Demo the toolkit during interviews

---

## Hardware

| Option | Specs                                           | Notes                       |
|--------|-------------------------------------------------|-----------------------------|
| Mini-PC| Used Lenovo ThinkCentre / HP EliteDesk, 32 GB RAM, 512 GB SSD | ~150–250 € on eBay Kleinanzeigen |
| Laptop | Anything with 16 GB RAM, virtualization support | Sufficient for 2 VMs        |
| Cloud  | Azure Pay-As-You-Go, free credit                | See Azure section below     |

---

## Hypervisor options

### Option A — Hyper-V on Windows 11 Pro (recommended for this lab)
- Free, built-in
- Native PowerShell management
- Best AD experience

### Option B — Proxmox VE on dedicated hardware
- Free, mature
- Requires a dedicated machine
- Better for a permanent home lab

### Option C — VirtualBox / VMware Workstation
- Works on any host, Windows or Linux
- Slightly slower than Hyper-V or Proxmox

---

## VM specifications

### DC01 — Domain Controller
- **OS**: Windows Server 2022 Standard (Evaluation, 180-day free)
- **vCPU**: 2
- **RAM**: 4 GB
- **Disk**: 60 GB (dynamic)
- **Network**: Internal switch + NAT for updates
- **IP**: Static `192.168.50.10/24`, gateway `192.168.50.1`, DNS `127.0.0.1`

### CLIENT01 — Test workstation
- **OS**: Windows 11 Enterprise Evaluation (90 days)
- **vCPU**: 2
- **RAM**: 4 GB
- **Disk**: 60 GB (dynamic)
- **IP**: DHCP from DC01

### Optional FS01 — File Server
- **OS**: Windows Server 2022 Standard (Evaluation)
- **vCPU**: 2
- **RAM**: 2 GB
- **Disk**: 60 GB system + 100 GB data
- Hosts `\\fs01\home$` and `\\fs01\dept-*$` shares

---

## Step-by-step setup

### 1. Download ISOs
- Windows Server 2022 Evaluation: <https://www.microsoft.com/evalcenter>
- Windows 11 Enterprise Evaluation: same source

### 2. Install DC01
1. Boot the VM from the ISO and install Windows Server.
2. After first logon: rename to `DC01`, set static IP, disable IPv6 if not used.
3. Install AD DS role: Server Manager → Add Roles → Active Directory Domain Services.
4. Promote to DC: forest = `schmidt-partner.local`, NetBIOS = `SCHMIDTPARTNER`.
5. After reboot, verify with:
   ```powershell
   Get-ADDomain
   dcdiag /v
   ```

### 3. Configure DNS
- Confirm the forward zone `schmidt-partner.local` exists.
- Add a forwarder to `1.1.1.1` and `8.8.8.8` for external resolution.

### 4. Install RSAT and required tooling
On DC01 (already present) and on any management workstation:
```powershell
Install-WindowsFeature RSAT-AD-PowerShell, RSAT-AD-Tools, GPMC
```

### 5. Configure DHCP (optional, on DC01)
```powershell
Install-WindowsFeature DHCP -IncludeManagementTools
Add-DhcpServerInDC -DnsName 'dc01.schmidt-partner.local' -IPAddress 192.168.50.10
Add-DhcpServerv4Scope -Name 'Lab' -StartRange 192.168.50.100 -EndRange 192.168.50.200 -SubnetMask 255.255.255.0
Set-DhcpServerv4OptionValue -Router 192.168.50.1 -DnsServer 192.168.50.10 -DnsDomain 'schmidt-partner.local'
```

### 6. Deploy the toolkit
1. Clone or copy the repo to `C:\IT\ADToolkit\` on DC01.
2. Update `config\config.psd1` if your domain or paths differ.
3. Run:
   ```powershell
   cd C:\IT\ADToolkit\scripts
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   .\Initialize-SPOUStructure.ps1 -WhatIf      # preview
   .\Initialize-SPOUStructure.ps1              # execute
   ```

### 7. Test the toolkit
```powershell
# Onboarding (dry run first!)
.\New-SPUser.ps1 -CsvPath ..\examples\new-hires-2026-01.csv -WhatIf
.\New-SPUser.ps1 -CsvPath ..\examples\new-hires-2026-01.csv

# Health report
.\Get-SPADHealthReport.ps1

# Password reset
.\Reset-SPPassword.ps1 -Username max.mustermann -TicketId TKT-2026-0001

# Offboarding
.\Disable-SPUser.ps1 -Username max.mustermann -TicketId TKT-2026-0042 -Reason Resignation -LastDay 2026-05-31
```

### 8. Take a clean snapshot
After the structure is initialized but before testing, take a **Hyper-V checkpoint** of DC01.
You can revert to this state in seconds when demoing.

---

## Azure alternative (cloud lab)

If you don't have hardware:

1. Create an Azure free account (200 € credit for 30 days).
2. Deploy a single Windows Server 2022 VM (B2s size, ~30 €/month).
3. Promote to DC in a separate VNet.
4. **Stop (deallocate) the VM when not using it** — costs only the disk (~3 €/month).

Pros: accessible from anywhere, easy to share for interviews.
Cons: needs careful cost management.

---

## Reset / cleanup

To start fresh:
- **Hyper-V**: revert to your clean snapshot
- **Azure**: redeploy from your saved ARM template

---

## Common pitfalls

| Symptom                                   | Cause / fix                                   |
|-------------------------------------------|-----------------------------------------------|
| `Get-ADDomain` errors                     | Service `Active Directory Domain Services` not running, or DC promotion incomplete |
| Scripts fail with "module not found"       | Run `Install-WindowsFeature RSAT-AD-PowerShell` |
| Password complexity errors when creating users | Domain default policy too strict; either weaken in lab or change `Password.InitialLength` in config.psd1 |
| Email features fail                       | No SMTP server in lab; this is expected. Disable email in config or set up `Papercut SMTP` for testing. |

---

## What this proves in an interview

When demoing this lab during an interview:

1. **Show the OU tree** in `dsa.msc` — proves you understand AD structure.
2. **Run the onboarding script** in `-WhatIf` mode — proves you script defensively.
3. **Show the audit CSV** — proves you understand DSGVO requirements.
4. **Open the HTML health report** — proves you can build operational reporting.
5. **Mention the GitHub repo** — proves you can document your work professionally.
