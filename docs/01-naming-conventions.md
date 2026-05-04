# Naming Conventions / Namenskonventionen

> Schmidt & Partner GmbH — Active Directory naming standards.
> Version 1.0 — applied by the AD Toolkit scripts.

---

## 1. Users / Benutzer

### Format
```
firstname.lastname
```
- All lowercase
- Period as separator
- No umlauts (ä → ae, ö → oe, ü → ue, ß → ss)
- No spaces, hyphens, or apostrophes

### Examples
| Real name              | Username                  |
|------------------------|---------------------------|
| Max Mustermann         | `max.mustermann`          |
| Anna Müller            | `anna.mueller`            |
| Jürgen Weiß            | `juergen.weiss`           |
| Mary O'Brien           | `mary.obrien`             |
| Hans-Peter Schmidt     | `hanspeter.schmidt`       |

### Collision handling
If `firstname.lastname` already exists, append a digit starting at 2:
- First Anna Schmidt → `anna.schmidt`
- Second Anna Schmidt → `anna.schmidt2`
- Third Anna Schmidt → `anna.schmidt3`

### UPN / Email
- UPN suffix: `@schmidt-partner.de`
- Email: same as UPN

---

## 2. Computers / Computer

### Format
```
SP-<SITE>-<TYPE>-<NUMBER>
```

| Component | Values                                                      |
|-----------|-------------------------------------------------------------|
| Prefix    | `SP` (Schmidt & Partner)                                    |
| Site      | `BER` (Berlin), `MUC` (Munich), `HAM` (Hamburg), `FRA` (Frankfurt) |
| Type      | `LT` (Laptop), `DT` (Desktop), `SV` (Server), `VM` (Virtual) |
| Number    | 4-digit zero-padded sequential number                       |

### Examples
- `SP-BER-LT-0042` → Laptop #42 in Berlin
- `SP-MUC-DT-0117` → Desktop #117 in Munich
- `SP-FRA-SV-0003` → Server #3 in Frankfurt

---

## 3. Groups / Gruppen

Follow the **AGDLP** model (Account → Global → Domain Local → Permission).

### Format
```
<SCOPE-PREFIX>-<NAME>[-<QUALIFIER>]
```

### Scope prefixes
| Prefix | Scope         | Use for                                 |
|--------|---------------|-----------------------------------------|
| `GG-`  | Global        | User collections (departments, roles)   |
| `DL-`  | Domain Local  | Resource access (file shares, printers) |
| `UG-`  | Universal     | Cross-domain (rare in single-domain)    |

### Examples

**Global groups (GG-)** — collect users:
- `GG-AllStaff`
- `GG-Finance`
- `GG-IT`
- `GG-Sales`
- `GG-VPN-Users`
- `GG-AdminTools`

**Domain Local groups (DL-)** — grant permissions:
- `DL-FS01-Finance-RW`        → Read/Write on `\\fs01\Finance$`
- `DL-FS01-Finance-RO`        → Read-Only on `\\fs01\Finance$`
- `DL-Print-BER-3rdFloor`     → Berlin 3rd floor printers
- `DL-VPN-Access`             → Allowed to use VPN

### Permission flow (AGDLP)
```
User → GG-Finance → DL-FS01-Finance-RW → Permission on Finance share
```
*Never* assign permissions directly to users or to global groups.

---

## 4. Service Accounts

### Format
```
svc-<service-or-system>[-<role>]
```

### Examples
- `svc-backup-veeam`
- `svc-monitoring-prtg`
- `svc-sql-erp`
- `svc-sso-azuread-connect`

### Rules
- Must be in `OU=ServiceAccounts`
- Description field MUST contain: owner, system, purpose, ticket of last change
- Password length: 32+ characters
- `Cannot change password` ON, `Password never expires` OFF (rotate annually)
- gMSA preferred where supported

---

## 5. Organizational Units

### Format
- PascalCase, no spaces
- Singular for containers, plural for collections

### Examples
- ✓ `Users`, `Computers`, `Groups`
- ✓ `Finance`, `IT`, `Sales`
- ✗ `User Accounts` (no spaces)
- ✗ `finance` (use PascalCase)

---

## 6. File Shares / Dateifreigaben

### Format
```
\\<server>\<share>$
```
- All shares are hidden (`$` suffix) by default
- Lowercase share names

### Examples
- `\\fs01\home$` → user home directories
- `\\fs01\dept-finance$` → Finance department share
- `\\fs01\projects$` → cross-department projects

---

## 7. Group Policy Objects

### Format
```
<scope>-<purpose>-[-<setting>]
```

### Examples
- `Computer-BaselineSecurity`
- `Computer-BitLocker-Required`
- `User-StartMenuLayout`
- `User-DriveMapping-Finance`

---

## Audit / Enforcement

These conventions are enforced programmatically by the toolkit:
- `New-SPUser.ps1` validates against `config.psd1` → `Naming.UserPattern`
- A weekly script (`Get-SPADHealthReport.ps1`) flags non-conforming objects
- All deviations require an exception entry in the IT wiki with justification.

---

## Change Log

| Date       | Author | Change          |
|------------|--------|-----------------|
| 2026-01-15 | IT-Team| Initial version |
