# =============================================================================
# Mittelstand AD Toolkit — Central Configuration
# =============================================================================
# Edit this file to match your environment. All scripts read from here.
# =============================================================================

@{
    # --- Company / Domain -----------------------------------------------------
    Company = @{
        Name        = 'Schmidt & Partner GmbH'
        ShortName   = 'SP'
        Domain      = 'schmidt-partner.local'
        UpnSuffix   = 'schmidt-partner.de'
        Country     = 'DE'
        DefaultCity = 'Berlin'
    }

    # --- Organizational Units -------------------------------------------------
    # All OUs are relative to the domain root.
    OUs = @{
        Root            = 'OU=SchmidtPartner,DC=schmidt-partner,DC=local'
        Users           = 'OU=Users,OU=SchmidtPartner,DC=schmidt-partner,DC=local'
        DisabledUsers   = 'OU=Disabled,OU=Users,OU=SchmidtPartner,DC=schmidt-partner,DC=local'
        ServiceAccounts = 'OU=ServiceAccounts,OU=SchmidtPartner,DC=schmidt-partner,DC=local'
        Computers       = 'OU=Computers,OU=SchmidtPartner,DC=schmidt-partner,DC=local'
        Groups          = 'OU=Groups,OU=SchmidtPartner,DC=schmidt-partner,DC=local'

        # Department-specific user OUs
        Departments = @{
            'IT'         = 'OU=IT,OU=Users,OU=SchmidtPartner,DC=schmidt-partner,DC=local'
            'Finance'    = 'OU=Finance,OU=Users,OU=SchmidtPartner,DC=schmidt-partner,DC=local'
            'HR'         = 'OU=HR,OU=Users,OU=SchmidtPartner,DC=schmidt-partner,DC=local'
            'Sales'      = 'OU=Sales,OU=Users,OU=SchmidtPartner,DC=schmidt-partner,DC=local'
            'Marketing'  = 'OU=Marketing,OU=Users,OU=SchmidtPartner,DC=schmidt-partner,DC=local'
            'Operations' = 'OU=Operations,OU=Users,OU=SchmidtPartner,DC=schmidt-partner,DC=local'
        }
    }

    # --- Default group memberships per department -----------------------------
    DepartmentGroups = @{
        'IT'         = @('GG-AllStaff', 'GG-IT', 'GG-VPN-Users', 'GG-AdminTools')
        'Finance'    = @('GG-AllStaff', 'GG-Finance', 'GG-VPN-Users')
        'HR'         = @('GG-AllStaff', 'GG-HR', 'GG-VPN-Users')
        'Sales'      = @('GG-AllStaff', 'GG-Sales', 'GG-VPN-Users', 'GG-CRM-Users')
        'Marketing'  = @('GG-AllStaff', 'GG-Marketing')
        'Operations' = @('GG-AllStaff', 'GG-Operations')
    }

    # --- File paths -----------------------------------------------------------
    Paths = @{
        LogDirectory   = 'C:\IT\Logs\ADToolkit'
        HomeShareRoot  = '\\fs01\home$'
        ProfileShare   = '\\fs01\profiles$'
        ReportOutput   = 'C:\IT\Reports'
        ArchivePath    = 'C:\IT\Archive\OffboardedUsers'
    }

    # --- Email / SMTP ---------------------------------------------------------
    Email = @{
        SmtpServer   = 'smtp.schmidt-partner.local'
        Port         = 25
        UseSSL       = $false
        From         = 'ad-toolkit@schmidt-partner.de'
        ITTeam       = 'it-team@schmidt-partner.de'
        HRTeam       = 'hr@schmidt-partner.de'
        AuditMailbox = 'audit@schmidt-partner.de'
    }

    # --- Naming conventions (regex patterns enforced by scripts) --------------
    Naming = @{
        UserPattern     = '^[a-z]{2,8}\.[a-z]{2,15}$'        # firstname.lastname (lowercase)
        ComputerPattern = '^SP-(BER|MUC|HAM|FRA)-(LT|DT|SV)-\d{4}$'
        GroupPrefix     = @{
            DomainLocal = 'DL-'
            Global      = 'GG-'
            Universal   = 'UG-'
        }
    }

    # --- Password policy (defaults for new users) -----------------------------
    Password = @{
        InitialLength       = 14
        MustChangeAtLogon   = $true
        CannotChangePassword = $false
        PasswordNeverExpires = $false
    }

    # --- Health report thresholds ---------------------------------------------
    HealthReport = @{
        InactiveUserDays      = 90
        StalePasswordDays     = 180
        LockedAccountAlert    = $true
        ReportRecipients      = @('it-team@schmidt-partner.de')
    }
}
