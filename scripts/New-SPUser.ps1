<#
.SYNOPSIS
    Creates Active Directory users in bulk from a CSV file.

.DESCRIPTION
    Reads a CSV of new hires and creates AD users following the company
    naming convention (firstname.lastname), places them in the correct
    department OU, adds them to default groups, creates a home directory,
    and writes a full audit log. Designed for the onboarding workflow at
    Schmidt & Partner GmbH.

.PARAMETER CsvPath
    Path to the CSV file containing new hires.
    Required columns: GivenName, Surname, Department, JobTitle, Manager,
                      Office, StartDate, EmployeeId

.PARAMETER WhatIf
    Show what would happen without making changes.

.PARAMETER ConfigPath
    Path to config.psd1 (defaults to ..\config\config.psd1)

.EXAMPLE
    .\New-SPUser.ps1 -CsvPath .\examples\new-hires-2026-01.csv -WhatIf

.EXAMPLE
    .\New-SPUser.ps1 -CsvPath .\examples\new-hires-2026-01.csv

.NOTES
    Author : Mittelstand AD Toolkit
    Version: 1.0.0
    Requires: ActiveDirectory module, Domain Admin or delegated rights
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ })]
    [string]$CsvPath,

    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\config.psd1')
)

# --- Setup -------------------------------------------------------------------
Import-Module (Join-Path $PSScriptRoot 'SPCommon.psm1') -Force
Import-Module ActiveDirectory -ErrorAction Stop

$config       = Import-SPConfig -ConfigPath $ConfigPath
$timestamp    = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$logFile      = Join-Path $config.Paths.LogDirectory "Onboarding_$timestamp.log"
$auditLog     = Join-Path $config.Paths.LogDirectory "Audit_Onboarding.csv"
$resultsFile  = Join-Path $config.Paths.LogDirectory "OnboardingResults_$timestamp.csv"

Write-SPLog -Message "=== Onboarding script started ===" -Level INFO -LogFile $logFile -Component 'New-SPUser'
Write-SPLog -Message "CSV file: $CsvPath" -Level INFO -LogFile $logFile -Component 'New-SPUser'

# --- Prerequisites -----------------------------------------------------------
if (-not (Test-SPPrerequisites)) {
    Write-SPLog -Message "Prerequisites check failed. Exiting." -Level ERROR -LogFile $logFile
    exit 1
}

# --- Import CSV --------------------------------------------------------------
try {
    $newHires = Import-Csv -Path $CsvPath -Delimiter ';' -Encoding UTF8
    Write-SPLog -Message "Imported $($newHires.Count) records from CSV" -Level INFO -LogFile $logFile
}
catch {
    Write-SPLog -Message "Failed to import CSV: $_" -Level ERROR -LogFile $logFile
    exit 1
}

# Validate required columns
$required = @('GivenName', 'Surname', 'Department', 'JobTitle', 'Manager', 'Office', 'StartDate', 'EmployeeId')
$missing  = $required | Where-Object { $_ -notin $newHires[0].PSObject.Properties.Name }
if ($missing) {
    Write-SPLog -Message "CSV missing required columns: $($missing -join ', ')" -Level ERROR -LogFile $logFile
    exit 1
}

# --- Process each hire -------------------------------------------------------
$results = @()

foreach ($hire in $newHires) {
    $result = [PSCustomObject]@{
        EmployeeId   = $hire.EmployeeId
        GivenName    = $hire.GivenName
        Surname      = $hire.Surname
        Username     = $null
        UPN          = $null
        Email        = $null
        OU           = $null
        InitialPwd   = $null
        Status       = 'Pending'
        Message      = $null
    }

    try {
        # --- Validate department ---
        if (-not $config.OUs.Departments.ContainsKey($hire.Department)) {
            throw "Unknown department: $($hire.Department)"
        }
        $targetOU = $config.OUs.Departments[$hire.Department]

        # --- Generate username (handles umlauts and collisions) ---
        $username = New-SPUsername -GivenName $hire.GivenName -Surname $hire.Surname
        $upn      = "$username@$($config.Company.UpnSuffix)"
        $email    = $upn
        $displayName = "$($hire.GivenName) $($hire.Surname)"

        $result.Username = $username
        $result.UPN      = $upn
        $result.Email    = $email
        $result.OU       = $targetOU

        # --- Generate initial password ---
        $initialPassword = New-SPSecurePassword -Length $config.Password.InitialLength
        $securePwd       = ConvertTo-SecureString -String $initialPassword -AsPlainText -Force
        $result.InitialPwd = $initialPassword

        # --- Build user attributes ---
        $userParams = @{
            Name              = $displayName
            GivenName         = $hire.GivenName
            Surname           = $hire.Surname
            DisplayName       = $displayName
            SamAccountName    = $username
            UserPrincipalName = $upn
            EmailAddress      = $email
            Title             = $hire.JobTitle
            Department        = $hire.Department
            Office            = $hire.Office
            Company           = $config.Company.Name
            Country           = $config.Company.Country
            EmployeeID        = $hire.EmployeeId
            Path              = $targetOU
            AccountPassword   = $securePwd
            Enabled           = $true
            ChangePasswordAtLogon = $config.Password.MustChangeAtLogon
            HomeDrive         = 'H:'
            HomeDirectory     = "$($config.Paths.HomeShareRoot)\$username"
            ScriptPath        = 'logon.bat'
        }

        # --- Set manager if provided ---
        if ($hire.Manager) {
            $mgr = Get-ADUser -Filter "SamAccountName -eq '$($hire.Manager)'" -ErrorAction SilentlyContinue
            if ($mgr) {
                $userParams.Manager = $mgr.DistinguishedName
            } else {
                Write-SPLog -Message "Manager '$($hire.Manager)' not found for $username — continuing without manager." -Level WARN -LogFile $logFile
            }
        }

        # --- Create user ---
        if ($PSCmdlet.ShouldProcess($username, "Create AD User")) {
            New-ADUser @userParams -ErrorAction Stop
            Write-SPLog -Message "Created user: $username ($displayName)" -Level INFO -LogFile $logFile
        } else {
            Write-SPLog -Message "[WhatIf] Would create user: $username ($displayName)" -Level INFO -LogFile $logFile
        }

        # --- Add to default groups ---
        $groups = $config.DepartmentGroups[$hire.Department]
        foreach ($group in $groups) {
            if ($PSCmdlet.ShouldProcess($username, "Add to group $group")) {
                try {
                    Add-ADGroupMember -Identity $group -Members $username -ErrorAction Stop
                    Write-SPLog -Message "Added $username to $group" -Level INFO -LogFile $logFile
                }
                catch {
                    Write-SPLog -Message "Could not add $username to $group : $_" -Level WARN -LogFile $logFile
                }
            }
        }

        # --- Create home directory ---
        $homePath = "$($config.Paths.HomeShareRoot)\$username"
        if ($PSCmdlet.ShouldProcess($homePath, "Create home directory")) {
            try {
                if (-not (Test-Path $homePath)) {
                    New-Item -Path $homePath -ItemType Directory -Force | Out-Null
                    # NOTE: in production, also set NTFS ACLs to grant the user Modify
                    Write-SPLog -Message "Created home directory: $homePath" -Level INFO -LogFile $logFile
                }
            }
            catch {
                Write-SPLog -Message "Home directory creation failed: $_" -Level WARN -LogFile $logFile
            }
        }

        # --- Audit entry ---
        Write-SPAuditEntry -Action 'USER_CREATED' `
                          -Target $username `
                          -Details "Department=$($hire.Department); Manager=$($hire.Manager); StartDate=$($hire.StartDate); EmployeeId=$($hire.EmployeeId)" `
                          -TicketId $hire.EmployeeId `
                          -AuditLogPath $auditLog | Out-Null

        $result.Status  = 'Success'
        $result.Message = 'User created and configured.'
    }
    catch {
        $result.Status  = 'Failed'
        $result.Message = $_.Exception.Message
        Write-SPLog -Message "Failed to create user for $($hire.GivenName) $($hire.Surname): $_" -Level ERROR -LogFile $logFile
    }

    $results += $result
}

# --- Export results ----------------------------------------------------------
$results | Export-Csv -Path $resultsFile -NoTypeInformation -Encoding UTF8 -Delimiter ';'
Write-SPLog -Message "Results written to: $resultsFile" -Level INFO -LogFile $logFile

# --- Summary -----------------------------------------------------------------
$success = ($results | Where-Object Status -eq 'Success').Count
$failed  = ($results | Where-Object Status -eq 'Failed').Count

Write-SPLog -Message "=== Summary: $success succeeded, $failed failed ===" -Level INFO -LogFile $logFile

# --- Send notification email -------------------------------------------------
if (-not $WhatIfPreference -and $config.Email.SmtpServer) {
    $body = @(
        'Onboarding-Lauf abgeschlossen / Onboarding run completed',
        '',
        "Erfolgreich / Successful: $success",
        "Fehlgeschlagen / Failed:  $failed",
        '',
        "Details: $resultsFile",
        "Logfile: $logFile",
        '',
        '---',
        'Automatisch generiert vom AD Toolkit'
    ) -join [Environment]::NewLine
    try {
        Send-SPMail -To $config.Email.ITTeam `
                    -Subject "[AD Toolkit] Onboarding: $success OK / $failed FAIL" `
                    -Body $body `
                    -Attachment $resultsFile `
                    -EmailConfig $config.Email
    }
    catch {
        Write-SPLog -Message "Notification email failed (non-fatal): $_" -Level WARN -LogFile $logFile
    }
}

Write-SPLog -Message "=== Onboarding script finished ===" -Level INFO -LogFile $logFile
