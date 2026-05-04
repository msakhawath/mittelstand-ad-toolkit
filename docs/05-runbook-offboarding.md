# Runbook: Offboarding (DE / EN)

> Standard operating procedure for offboarding employees.
> Procedure for both planned (resignation, retirement) and immediate (termination) cases.

---

## 🇩🇪 Deutsch

### Auslöser

Ein Offboarding wird ausgelöst durch:
- **Reguläre Kündigung** (Mitarbeiter:in oder AG) — geplant, mit Vorlauf
- **Aufhebungsvertrag** — geplant
- **Außerordentliche Kündigung** — sofort, ggf. nach Feierabend
- **Vertragsende (befristet)** — geplant
- **Tod eines Mitarbeiters** — sofortige Sperrung, sehr sensibel

### Klassifizierung

| Typ      | Reaktionszeit | Verfahren           |
|----------|---------------|---------------------|
| Standard | Letzter AT 17:00 | Skript am letzten Arbeitstag |
| Sofort   | < 1 Stunde       | Manuell + Skript    |

### Standardablauf (geplante Trennung)

#### Vorlaufzeit (T −7 bis T 0)
1. HR erstellt Offboarding-Ticket mit:
   - Username
   - Letzter Arbeitstag
   - Grund (Kündigung MA, Kündigung AG, Vertragsende, Ruhestand)
   - Hardware-Rückgabe geplant: ja/nein
2. IT prüft Sonderzugriffe (Admin-Rechte, externe Systeme).
3. Postfach-Weiterleitung mit Vorgesetzte:r abstimmen.

#### Letzter Arbeitstag (17:00)
1. Skript ausführen:
   ```powershell
   .\Disable-SPUser.ps1 -Username max.mustermann `
                        -TicketId TKT-2026-0042 `
                        -Reason Resignation `
                        -LastDay 2026-05-31
   ```
2. Postfach-Weiterleitung an Vorgesetzte:r einrichten (90 Tage).
3. Hardware-Rückgabe quittieren.
4. Ticket schließen.

#### Tag T +1 bis T +30
- Postfach bleibt aktiv mit Out-of-Office.
- Daten in `\\fs01\home$\<username>` archivieren.

#### Tag T +90
- Postfach exportieren und löschen.
- Lizenz freigeben.

#### Tag T +6 Monate
- Heimverzeichnis archivieren und vom Server entfernen.

#### Tag T +6 Jahre (DSGVO)
- AD-Konto endgültig löschen.
- Audit-Log bleibt.

### Sofort-Offboarding (Risiko-Fälle)

Bei außerordentlicher Kündigung oder Sicherheitsvorfall:

1. **Sofort, vor allem anderen**:
   ```powershell
   .\Disable-SPUser.ps1 -Username verdacht.user `
                        -TicketId TKT-2026-9999 `
                        -Reason Termination `
                        -LastDay 2026-05-03
   ```
2. Aktive Sessions trennen:
   ```powershell
   # An jeder DC und Citrix-Server
   quser /server:dc01 | ... | logoff
   ```
3. VPN-Verbindungen kappen.
4. Mobile Device Management: Wipe oder Lock auslösen.
5. M365: Aktive Sessions widerrufen:
   ```powershell
   Revoke-AzureADUserAllRefreshToken -ObjectId <userObjectId>
   ```
6. Hardware sofort einziehen.
7. Vorgesetzte:r und Datenschutzbeauftragte:r informieren.

---

## 🇬🇧 English

### Triggers

Offboarding is triggered by:
- **Standard resignation** (employee or employer) — planned, with notice
- **Mutual separation agreement** — planned
- **Termination for cause** — immediate, possibly after hours
- **End of fixed-term contract** — planned
- **Death of an employee** — immediate disable, highly sensitive

### Classification

| Type     | Response time     | Process                  |
|----------|-------------------|--------------------------|
| Standard | Last day 17:00    | Script on last work day  |
| Urgent   | < 1 hour          | Manual + script          |

### Standard procedure (planned separation)

#### Lead time (T −7 to T 0)
1. HR creates an offboarding ticket with:
   - Username
   - Last work day
   - Reason
   - Hardware return planned: yes/no
2. IT reviews special access (admin rights, external systems).
3. Coordinate mailbox forwarding with the manager.

#### Last work day (17:00)
1. Run the script:
   ```powershell
   .\Disable-SPUser.ps1 -Username max.mustermann `
                        -TicketId TKT-2026-0042 `
                        -Reason Resignation `
                        -LastDay 2026-05-31
   ```
2. Set up mailbox forwarding to manager (90 days).
3. Acknowledge hardware return.
4. Close the ticket.

#### T +1 to T +30
- Mailbox remains active with auto-reply.
- Archive data in `\\fs01\home$\<username>`.

#### T +90
- Export and delete the mailbox.
- Release license.

#### T +6 months
- Archive home directory, remove from server.

#### T +6 years (GDPR)
- Permanently delete the AD account.
- Audit log retained.

### Urgent offboarding (high-risk cases)

For termination for cause or security incidents:

1. **Immediately, before anything else**:
   ```powershell
   .\Disable-SPUser.ps1 -Username suspect.user `
                        -TicketId TKT-2026-9999 `
                        -Reason Termination `
                        -LastDay 2026-05-03
   ```
2. Terminate active sessions on every DC and Citrix server.
3. Cut VPN connections.
4. Trigger MDM wipe or lock.
5. M365 / Azure AD: revoke all refresh tokens:
   ```powershell
   Revoke-AzureADUserAllRefreshToken -ObjectId <userObjectId>
   ```
6. Collect hardware immediately.
7. Inform the manager and data protection officer.

---

## What the script does (technical)

1. Captures original state (groups, manager, DN) → JSON archive
2. Disables the AD account
3. Resets the password to a random 32-character string
4. Removes membership from all security groups (except `Domain Users`)
5. Updates the description with offboarding metadata
6. Moves the user to the `Disabled` OU
7. Writes an audit log entry
8. Sends notification email to HR, IT, and manager

The JSON archive allows **restoring the user with all original group memberships** within the retention period — useful when the offboarding was a mistake.

---

## Audit / DSGVO

Each run of `Disable-SPUser.ps1` produces:
- An entry in `Audit_Offboarding.csv`
- A JSON archive of the original state in `C:\IT\Archive\OffboardedUsers\`
- A run log

**Retain for 6 years** per DSGVO § 17 / GoBD.
