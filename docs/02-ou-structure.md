# OU Structure & Delegation Model

> Schmidt & Partner GmbH — Active Directory OU design.

## Design principles

1. **Separate users, computers, groups, and service accounts** — never mix object types.
2. **Group by function (department), not by location** — easier delegation and GPO targeting.
3. **A dedicated "Disabled" OU** — keeps offboarded users out of dynamic queries.
4. **Service accounts in their own OU** — for separate password policies and audit.
5. **Protected from accidental deletion** — every OU has the flag set.

---

## The structure

```
schmidt-partner.local
└── OU=SchmidtPartner
    ├── OU=Users
    │   ├── OU=IT
    │   ├── OU=Finance
    │   ├── OU=HR
    │   ├── OU=Sales
    │   ├── OU=Marketing
    │   ├── OU=Operations
    │   └── OU=Disabled         ← offboarded users land here
    │
    ├── OU=Computers
    │   ├── OU=Workstations
    │   │   ├── OU=Berlin
    │   │   ├── OU=Munich
    │   │   ├── OU=Hamburg
    │   │   └── OU=Frankfurt
    │   └── OU=Servers
    │       ├── OU=FileServers
    │       ├── OU=AppServers
    │       └── OU=DomainControllers   ← default; not moved
    │
    ├── OU=Groups
    │   ├── OU=Global             (GG-* groups)
    │   ├── OU=DomainLocal        (DL-* groups)
    │   └── OU=Distribution       (mail-enabled groups)
    │
    └── OU=ServiceAccounts
        ├── OU=Application
        ├── OU=Backup
        └── OU=Monitoring
```

---

## Delegation model

Following the principle of least privilege, delegations are made on OUs — **never on the domain root**.

### Tier 0 — Domain Admins
- Full control of the domain
- 2–3 named accounts maximum (`adm.firstname.lastname`)
- Separate workstation, no email, MFA required
- Never used for daily work

### Tier 1 — Server Admins
- Granted via `GG-ServerAdmins`
- Permissions on `OU=Servers`
- No rights on workstations or user objects

### Tier 2 — Helpdesk
- Granted via `GG-Helpdesk`
- Delegated rights on `OU=Users` (each department):
  - Reset passwords
  - Unlock accounts
  - Modify limited user properties (telephone, office)
- **Not** allowed: create / delete users, modify group membership, modify privileged users

### Tier 2 — Onboarding Operator
- Granted via `GG-Onboarding-Operators`
- Delegated rights:
  - Create user objects in `OU=Users\*`
  - Move user objects to `OU=Users\Disabled`
  - Add to GG-* groups within the same scope
- Used by the AD Toolkit service account

### HR Self-Service
- Granted via `GG-HR-ReadAccess`
- Read-only access to user attributes for HR reporting
- No write access

---

## Group Policy targeting

| GPO                            | Linked to                  | Filter                  |
|--------------------------------|----------------------------|-------------------------|
| `Computer-BaselineSecurity`    | `OU=Computers`             | (none — applies to all) |
| `Computer-BitLocker-Required`  | `OU=Workstations`          | (none)                  |
| `Computer-AppLocker-Production`| `OU=Servers`               | (none)                  |
| `User-DriveMapping-Finance`    | `OU=Users\Finance`         | (none)                  |
| `User-Disabled-LockdownDesktop`| `OU=Users\Disabled`        | (none)                  |

---

## Why not group by location?

Many German companies group AD by site (`OU=Berlin\Users`, `OU=Munich\Users`).
This works, but creates problems:

- **Cross-site moves require an OU change** — breaks GPOs and licensing.
- **Department-specific access controls become harder** to delegate.
- **Naming and reporting become inconsistent**.

This design uses **department-based OUs for users** and **site-based OUs for computers**, which is the more common and maintainable pattern.

---

## Initialization

The OU structure is created automatically by:
```powershell
.\scripts\Initialize-SPOUStructure.ps1
```

After creation, the toolkit relies on these paths being stable. If you need to rename or move an OU, **update `config/config.psd1`** before running any other script.
