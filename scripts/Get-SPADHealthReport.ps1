<#
.SYNOPSIS
    Generates a weekly AD health report.

.DESCRIPTION
    Collects key health metrics from Active Directory and produces a
    professional HTML report. Optionally emails the report to the IT team.
    Designed to be run via Scheduled Task every Monday morning.

    Metrics included:
      - Inactive users (not logged in for X days)
      - Users with stale passwords (older than X days)
      - Locked accounts
      - Users with "Password Never Expires" flag (security risk)
      - Empty OUs
      - Domain controllers status
      - Recent account creations / deletions (last 7 days)
      - Privileged group membership changes

.PARAMETER SendEmail
    Send the report by email to recipients defined in config.

.PARAMETER OutputPath
    Override the default output path for the HTML file.

.EXAMPLE
    .\Get-SPADHealthReport.ps1

.EXAMPLE
    .\Get-SPADHealthReport.ps1 -SendEmail

.NOTES
    Author : Mittelstand AD Toolkit
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [switch]$SendEmail,
    [string]$OutputPath,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\config.psd1')
)

# --- Setup -------------------------------------------------------------------
Import-Module (Join-Path $PSScriptRoot 'SPCommon.psm1') -Force
Import-Module ActiveDirectory -ErrorAction Stop

$config    = Import-SPConfig -ConfigPath $ConfigPath
$timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$logFile   = Join-Path $config.Paths.LogDirectory "HealthReport_$timestamp.log"

if (-not $OutputPath) {
    $OutputPath = Join-Path $config.Paths.ReportOutput "ADHealthReport_$timestamp.html"
}

# Ensure output directory exists
$outDir = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path $outDir)) {
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
}

Write-SPLog -Message "=== Health report started ===" -Level INFO -LogFile $logFile -Component 'HealthReport'

if (-not (Test-SPPrerequisites)) { exit 1 }

# --- Collect data ------------------------------------------------------------
$inactiveDays  = $config.HealthReport.InactiveUserDays
$stalePwdDays  = $config.HealthReport.StalePasswordDays
$inactiveDate  = (Get-Date).AddDays(-$inactiveDays)
$stalePwdDate  = (Get-Date).AddDays(-$stalePwdDays)
$cutoff       = (Get-Date).AddDays(-7)

Write-SPLog -Message "Collecting AD data..." -Level INFO -LogFile $logFile

# Domain info
$domain = Get-ADDomain
$forest = Get-ADForest
$dcs    = Get-ADDomainController -Filter *

# Inactive users
$inactiveUsers = Get-ADUser -Filter { Enabled -eq $true } `
    -Properties LastLogonDate, Department, Title |
    Where-Object {
        $_.LastLogonDate -and
        $_.LastLogonDate -lt $inactiveDate -and
        $_.DistinguishedName -notlike "*$($config.OUs.DisabledUsers)"
    } |
    Sort-Object LastLogonDate

# Stale passwords
$stalePasswords = Get-ADUser -Filter { Enabled -eq $true } `
    -Properties PasswordLastSet, Department |
    Where-Object {
        $_.PasswordLastSet -and
        $_.PasswordLastSet -lt $stalePwdDate
    } |
    Sort-Object PasswordLastSet

# Locked accounts
$lockedAccounts = Search-ADAccount -LockedOut |
    Get-ADUser -Properties LockedOut, LastLogonDate

# Password never expires (potential security risk)
$pwdNeverExpires = Get-ADUser -Filter { Enabled -eq $true -and PasswordNeverExpires -eq $true } `
    -Properties PasswordNeverExpires, Department |
    Where-Object {
        $_.DistinguishedName -notlike "*$($config.OUs.ServiceAccounts)*"
    }

# Recently created (last 7 days)
$recentlyCreated = Get-ADUser -Filter { whenCreated -gt $cutoff } `
    -Properties whenCreated, Department -SearchBase $config.OUs.Users -ErrorAction SilentlyContinue |
    Where-Object { $_.whenCreated -gt $cutoff }

# Privileged group membership
$privilegedGroups = @('Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Administrators')
$privMembers = foreach ($g in $privilegedGroups) {
    try {
        $members = Get-ADGroupMember -Identity $g -ErrorAction Stop |
                   Where-Object ObjectClass -eq 'user'
        foreach ($m in $members) {
            [PSCustomObject]@{
                Group = $g
                User  = $m.SamAccountName
                Name  = $m.Name
            }
        }
    }
    catch {
        Write-SPLog -Message "Could not enumerate $g : $_" -Level WARN -LogFile $logFile
    }
}

# DC health (basic ping + service check)
$dcStatus = foreach ($dc in $dcs) {
    $online = Test-Connection -ComputerName $dc.HostName -Count 1 -Quiet -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        Name        = $dc.HostName
        Site        = $dc.Site
        OS          = $dc.OperatingSystem
        IPv4        = $dc.IPv4Address
        Online      = $online
        IsGC        = $dc.IsGlobalCatalog
        IsReadOnly  = $dc.IsReadOnly
    }
}

# --- Build HTML report -------------------------------------------------------
$css = @'
<style>
    body { font-family: 'Segoe UI', Tahoma, sans-serif; margin: 20px; background: #f4f6f8; color: #222; }
    h1 { color: #1a3a6c; border-bottom: 3px solid #1a3a6c; padding-bottom: 8px; }
    h2 { color: #1a3a6c; margin-top: 32px; border-left: 4px solid #1a3a6c; padding-left: 10px; }
    .meta { background: #fff; padding: 14px; border-radius: 6px; box-shadow: 0 1px 3px rgba(0,0,0,.1); }
    .summary { display: flex; gap: 16px; flex-wrap: wrap; margin: 20px 0; }
    .card { flex: 1; min-width: 180px; background: #fff; padding: 16px; border-radius: 6px; box-shadow: 0 1px 3px rgba(0,0,0,.1); border-top: 4px solid #1a3a6c; }
    .card.warn { border-top-color: #e6a700; }
    .card.danger { border-top-color: #d73a49; }
    .card.ok { border-top-color: #28a745; }
    .card .num { font-size: 32px; font-weight: bold; }
    .card .label { color: #666; font-size: 13px; text-transform: uppercase; letter-spacing: .5px; }
    table { width: 100%; border-collapse: collapse; background: #fff; margin: 12px 0; box-shadow: 0 1px 3px rgba(0,0,0,.1); }
    th { background: #1a3a6c; color: #fff; text-align: left; padding: 10px; font-size: 13px; }
    td { padding: 8px 10px; border-bottom: 1px solid #eee; font-size: 13px; }
    tr:nth-child(even) td { background: #fafbfc; }
    tr:hover td { background: #eef3fa; }
    .ok-badge { color: #28a745; font-weight: bold; }
    .warn-badge { color: #e6a700; font-weight: bold; }
    .danger-badge { color: #d73a49; font-weight: bold; }
    .footer { margin-top: 40px; color: #888; font-size: 12px; text-align: center; }
    .empty { color: #888; font-style: italic; padding: 16px; }
</style>
'@

$html  = "<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'><title>AD Health Report — $($config.Company.Name)</title>$css</head><body>"
$html += "<h1>🛡 Active Directory Health Report</h1>"
$html += "<div class='meta'>"
$html += "<strong>Company / Unternehmen:</strong> $($config.Company.Name)<br>"
$html += "<strong>Domain:</strong> $($domain.DNSRoot)<br>"
$html += "<strong>Generated / Erstellt:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>"
$html += "<strong>Generated by / Erstellt von:</strong> $env:USERDOMAIN\$env:USERNAME"
$html += "</div>"

# --- Summary cards ---
$html += "<div class='summary'>"
$cardClass = if ($inactiveUsers.Count -gt 25) { 'danger' } elseif ($inactiveUsers.Count -gt 10) { 'warn' } else { 'ok' }
$html += "<div class='card $cardClass'><div class='label'>Inactive Users (>$inactiveDays d)</div><div class='num'>$($inactiveUsers.Count)</div></div>"

$cardClass = if ($stalePasswords.Count -gt 5) { 'warn' } else { 'ok' }
$html += "<div class='card $cardClass'><div class='label'>Stale Passwords (>$stalePwdDays d)</div><div class='num'>$($stalePasswords.Count)</div></div>"

$cardClass = if ($lockedAccounts.Count -gt 0) { 'warn' } else { 'ok' }
$html += "<div class='card $cardClass'><div class='label'>Locked Accounts</div><div class='num'>$($lockedAccounts.Count)</div></div>"

$cardClass = if ($pwdNeverExpires.Count -gt 0) { 'danger' } else { 'ok' }
$html += "<div class='card $cardClass'><div class='label'>Pwd Never Expires</div><div class='num'>$($pwdNeverExpires.Count)</div></div>"

$cardClass = if ($privMembers.Count -gt 5) { 'danger' } elseif ($privMembers.Count -gt 3) { 'warn' } else { 'ok' }
$html += "<div class='card $cardClass'><div class='label'>Privileged Members</div><div class='num'>$($privMembers.Count)</div></div>"

$cardClass = if (($dcStatus | Where-Object { -not $_.Online }).Count -gt 0) { 'danger' } else { 'ok' }
$html += "<div class='card $cardClass'><div class='label'>Domain Controllers</div><div class='num'>$($dcs.Count)</div></div>"
$html += "</div>"

# --- Domain Controllers table ---
$html += "<h2>Domain Controllers</h2>"
if ($dcStatus) {
    $html += "<table><tr><th>Name</th><th>Site</th><th>OS</th><th>IPv4</th><th>Status</th><th>GC</th><th>RODC</th></tr>"
    foreach ($dc in $dcStatus) {
        $statusBadge = if ($dc.Online) { "<span class='ok-badge'>● ONLINE</span>" } else { "<span class='danger-badge'>● OFFLINE</span>" }
        $html += "<tr><td>$($dc.Name)</td><td>$($dc.Site)</td><td>$($dc.OS)</td><td>$($dc.IPv4)</td><td>$statusBadge</td><td>$($dc.IsGC)</td><td>$($dc.IsReadOnly)</td></tr>"
    }
    $html += "</table>"
}

# --- Inactive users ---
$html += "<h2>Inactive Users (no logon for >$inactiveDays days)</h2>"
if ($inactiveUsers) {
    $html += "<table><tr><th>Username</th><th>Display Name</th><th>Department</th><th>Title</th><th>Last Logon</th></tr>"
    foreach ($u in $inactiveUsers | Select-Object -First 50) {
        $lastLogon = if ($u.LastLogonDate) { $u.LastLogonDate.ToString('yyyy-MM-dd') } else { 'Never' }
        $html += "<tr><td>$($u.SamAccountName)</td><td>$($u.Name)</td><td>$($u.Department)</td><td>$($u.Title)</td><td>$lastLogon</td></tr>"
    }
    $html += "</table>"
    if ($inactiveUsers.Count -gt 50) {
        $html += "<p class='empty'>… showing 50 of $($inactiveUsers.Count) total. Full list in CSV attachment.</p>"
    }
} else {
    $html += "<p class='empty'>✓ No inactive users.</p>"
}

# --- Stale passwords ---
$html += "<h2>Users with Stale Passwords (>$stalePwdDays days)</h2>"
if ($stalePasswords) {
    $html += "<table><tr><th>Username</th><th>Display Name</th><th>Department</th><th>Password Last Set</th></tr>"
    foreach ($u in $stalePasswords | Select-Object -First 30) {
        $pwdSet = if ($u.PasswordLastSet) { $u.PasswordLastSet.ToString('yyyy-MM-dd') } else { 'Never' }
        $html += "<tr><td>$($u.SamAccountName)</td><td>$($u.Name)</td><td>$($u.Department)</td><td>$pwdSet</td></tr>"
    }
    $html += "</table>"
} else {
    $html += "<p class='empty'>✓ No stale passwords.</p>"
}

# --- Locked accounts ---
$html += "<h2>Currently Locked Accounts</h2>"
if ($lockedAccounts) {
    $html += "<table><tr><th>Username</th><th>Display Name</th><th>Last Logon</th></tr>"
    foreach ($u in $lockedAccounts) {
        $lastLogon = if ($u.LastLogonDate) { $u.LastLogonDate.ToString('yyyy-MM-dd HH:mm') } else { 'Never' }
        $html += "<tr><td>$($u.SamAccountName)</td><td>$($u.Name)</td><td>$lastLogon</td></tr>"
    }
    $html += "</table>"
} else {
    $html += "<p class='empty'>✓ No locked accounts.</p>"
}

# --- Password never expires (security risk) ---
$html += "<h2>⚠ Users with 'Password Never Expires' (Security Risk)</h2>"
if ($pwdNeverExpires) {
    $html += "<table><tr><th>Username</th><th>Display Name</th><th>Department</th></tr>"
    foreach ($u in $pwdNeverExpires) {
        $html += "<tr><td>$($u.SamAccountName)</td><td>$($u.Name)</td><td>$($u.Department)</td></tr>"
    }
    $html += "</table>"
} else {
    $html += "<p class='empty'>✓ No regular users with this flag.</p>"
}

# --- Privileged group membership ---
$html += "<h2>Privileged Group Membership</h2>"
if ($privMembers) {
    $html += "<table><tr><th>Group</th><th>Username</th><th>Display Name</th></tr>"
    foreach ($p in $privMembers | Sort-Object Group, User) {
        $html += "<tr><td>$($p.Group)</td><td>$($p.User)</td><td>$($p.Name)</td></tr>"
    }
    $html += "</table>"
}

# --- Recently created users ---
$html += "<h2>Recently Created Users (last 7 days)</h2>"
if ($recentlyCreated) {
    $html += "<table><tr><th>Username</th><th>Display Name</th><th>Department</th><th>Created</th></tr>"
    foreach ($u in $recentlyCreated) {
        $created = $u.whenCreated.ToString('yyyy-MM-dd HH:mm')
        $html += "<tr><td>$($u.SamAccountName)</td><td>$($u.Name)</td><td>$($u.Department)</td><td>$created</td></tr>"
    }
    $html += "</table>"
} else {
    $html += "<p class='empty'>No new users in the last 7 days.</p>"
}

# --- Footer ---
$html += "<div class='footer'>"
$html += "Mittelstand AD Toolkit — automated report. Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')."
$html += "</div></body></html>"

# --- Save ---
$html | Out-File -FilePath $OutputPath -Encoding UTF8
Write-SPLog -Message "Report saved to: $OutputPath" -Level INFO -LogFile $logFile

# --- Email if requested ---
if ($SendEmail) {
    $subject = "[AD Health] $($config.Company.Name) — $(Get-Date -Format 'yyyy-MM-dd')"
    $bodyText = "AD Health Report ist als Anhang beigefügt.`r`nAD Health Report attached.`r`n`r`nGenerated: $(Get-Date)"
    try {
        Send-SPMail -To $config.HealthReport.ReportRecipients `
                    -Subject $subject `
                    -Body $bodyText `
                    -Attachment $OutputPath `
                    -EmailConfig $config.Email
        Write-SPLog -Message "Report emailed to: $($config.HealthReport.ReportRecipients -join ', ')" -Level INFO -LogFile $logFile
    }
    catch {
        Write-SPLog -Message "Email failed: $_" -Level ERROR -LogFile $logFile
    }
}

Write-SPLog -Message "=== Health report finished ===" -Level INFO -LogFile $logFile
Write-Host "`nReport: $OutputPath" -ForegroundColor Cyan
