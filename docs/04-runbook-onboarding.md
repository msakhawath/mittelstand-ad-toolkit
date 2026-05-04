# Runbook: Onboarding (DE / EN)

> Standard operating procedure for onboarding a new employee at Schmidt & Partner GmbH.
> Standardprozedur für das Onboarding neuer Mitarbeiter bei Schmidt & Partner GmbH.

---

## 🇩🇪 Deutsch

### Voraussetzungen

- HR hat ein **Onboarding-Ticket** im Ticketsystem erstellt (Format: `TKT-YYYY-NNNN`)
- Mindestens **5 Werktage Vorlauf** vor dem Eintrittstermin
- Folgende Daten müssen im Ticket vorhanden sein:
  - Vor- und Nachname
  - Abteilung (IT, Finance, HR, Sales, Marketing, Operations)
  - Stellenbezeichnung
  - Vorgesetzte:r (Username im AD)
  - Standort (Berlin, München, Hamburg, Frankfurt)
  - Eintrittsdatum
  - Personalnummer

### Ablauf

#### Tag −5: Vorbereitung
1. CSV-Datei aus dem HR-System exportieren oder manuell anlegen.
2. CSV in `C:\IT\Onboarding\Pending\` ablegen.
3. **Trockenlauf** durchführen:
   ```powershell
   .\New-SPUser.ps1 -CsvPath C:\IT\Onboarding\Pending\YYYY-MM.csv -WhatIf
   ```
4. Bei Fehlern: CSV korrigieren oder Ticket zurück an HR.

#### Tag −1: Konto anlegen
1. Onboarding-Skript ausführen:
   ```powershell
   .\New-SPUser.ps1 -CsvPath C:\IT\Onboarding\Pending\YYYY-MM.csv
   ```
2. Ergebnis-CSV (`OnboardingResults_*.csv`) prüfen.
3. Initialpasswörter aus dem Ergebnis in einen verschlüsselten Container ablegen (z. B. KeePass).
4. Hardware aus Lager holen, gemäß Naming-Convention umbenennen, in passende OU verschieben.

#### Tag 0: Eintritt
1. Gemeinsam mit der/dem Vorgesetzten:
   - Hardware übergeben
   - Initialpasswort über sicheren Kanal mitteilen (nicht per E-Mail!)
   - Erstanmeldung begleiten
2. M365-Lizenz zuweisen (separates Skript).
3. Ticket im System schließen mit Verweis auf Audit-Log-Eintrag.

### Eskalation

| Problem                                       | Ansprechpartner       |
|-----------------------------------------------|-----------------------|
| Daten im HR-System fehlen                     | HR-Team               |
| AD-Skript schlägt fehl                        | Senior Sysadmin       |
| Lizenz nicht verfügbar                        | License-Manager       |
| Hardware nicht vorrätig                       | Beschaffung           |

---

## 🇬🇧 English

### Prerequisites

- HR has created an **onboarding ticket** (format: `TKT-YYYY-NNNN`)
- At least **5 business days** before the start date
- Ticket must contain:
  - First and last name
  - Department (IT, Finance, HR, Sales, Marketing, Operations)
  - Job title
  - Manager (AD username)
  - Office location (Berlin, Munich, Hamburg, Frankfurt)
  - Start date
  - Employee ID

### Procedure

#### Day −5: Preparation
1. Export the CSV from the HR system or create one manually.
2. Place the CSV in `C:\IT\Onboarding\Pending\`.
3. **Dry run**:
   ```powershell
   .\New-SPUser.ps1 -CsvPath C:\IT\Onboarding\Pending\YYYY-MM.csv -WhatIf
   ```
4. If errors: fix the CSV or send the ticket back to HR.

#### Day −1: Account creation
1. Run the onboarding script:
   ```powershell
   .\New-SPUser.ps1 -CsvPath C:\IT\Onboarding\Pending\YYYY-MM.csv
   ```
2. Review the result CSV (`OnboardingResults_*.csv`).
3. Store initial passwords in an encrypted container (KeePass / similar).
4. Prepare hardware: name according to convention, move to correct OU.

#### Day 0: Start date
1. Together with the manager:
   - Hand over hardware
   - Communicate the initial password via secure channel (not email!)
   - Walk through first logon
2. Assign M365 license (separate script).
3. Close the ticket, referencing the audit log entry.

### Escalation

| Problem                       | Contact            |
|-------------------------------|--------------------|
| HR data missing               | HR team            |
| AD script fails               | Senior sysadmin    |
| License not available         | License manager    |
| Hardware not in stock         | Procurement        |

---

## Audit / DSGVO

Each run of `New-SPUser.ps1` produces:
- A line in `Audit_Onboarding.csv` per user (operator, timestamp, target, ticket ID)
- A run log in `Onboarding_<timestamp>.log`
- A result CSV in `OnboardingResults_<timestamp>.csv`

**Retain for 6 years** per DSGVO § 17 / GoBD requirements.
