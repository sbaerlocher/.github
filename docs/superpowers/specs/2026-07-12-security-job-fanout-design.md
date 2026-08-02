# Security-Reusables: Job-Fan-out reduzieren gegen Minuten-Aufrundung

**Datum:** 2026-07-12
**Typ:** Refactor
**Notion:** https://app.notion.com/p/39abf097036e8133b4b4d95db8b56bee
**Pfad:** nicht-trivial · **Aufwand:** M · **Prio:** P2

## Problem

GitHub rundet jeden Job auf die volle billed Minute auf. Die vier geteilten
Security-Reusables splitten in viele separate Jobs (je eigener Runner-Spin-up

- Checkout + eigene Minuten-Aufrundung). Einzelne Scan-Jobs laufen teils nur
  6–13 s, werden aber jeder auf 1 volle Minute aufgerundet → der Split kostet
  fast reine Rundungs-Steuer. Gemessen ~902 billable min/mo fleetweit
  (367 secrets + 535 deps/config/containers).

## Ziel

Jobs, die keine eigene Permission-Isolation brauchen, in EINEN Job mit
sequenziellen Steps zusammenlegen. `security-report` als letzter Step statt
eigenem Job.

## Änderungen pro Workflow

| Workflow                  | Vorher | Nachher                                                                                                      | Runner gespart |
| ------------------------- | ------ | ------------------------------------------------------------------------------------------------------------ | -------------- |
| `security-secrets.yml`    | 4 Jobs | `gitleaks` (isoliert, `pull-requests:read`) + `secret-scan` (trufflehog + pattern + report, `contents:read`) | 2              |
| `security-deps.yml`       | 5 Jobs | 1 Job `dependency-scan`, Steps behalten ihre `if:`-Guards                                                    | 4              |
| `security-containers.yml` | 4 Jobs | 1 Job `container-scan`                                                                                       | 3              |
| `security-config.yml`     | 5 Jobs | 1 Job `config-scan`                                                                                          | 4              |

## Trade-off (nicht wegwischen)

Der Split ist bei `secrets` teils absichtlich: `gitleaks` läuft mit scoped
per-Job `pull-requests: read` (least-privilege, dokumentiert in REVIEW.md und
CHANGELOG.md — gitleaks-action v3 enumeriert PR-Commits über die pulls-API).
**Entscheidung: konservativ.** `gitleaks` bleibt eigener Job. `trufflehog` +
`pattern-detection` + `report` gehen in einen `secret-scan`-Job mit nur
`contents: read`. Least-Privilege bleibt sauber, spart 2 statt 3 Runner.

Bei `deps`/`containers`/`config` teilen sich alle Jobs bereits die
workflow-level Permissions; nur die `if:`-Conditions unterscheiden. Merge zu
je 1 Job ist permission-neutral.

## Mechanik

- **Merged Job = 1 Checkout + sequenzielle Steps.** Jeder Step behält seine
  ursprüngliche Job-`if:`-Bedingung, jetzt als Step-`if:`
  (z.B. `if: inputs.language == 'go' || inputs.language == 'multi'`).
- **Setup-Union:** deps-Job braucht Go+Node+Python-Setup, jeweils hinter dem
  passenden Step-`if:`. Die Sprach-Guards verhindern unnötige Installs.
- **`security-report` → letzter Step.** Job-Result-Refs (`needs.X.result`)
  gehen im Single-Job nicht. Ersatz: Step-`id:` + `steps.<id>.outcome` in der
  Report-Tabelle. Jeder Scan-Step, dessen Ergebnis in den Report soll, bekommt
  `id:`.
- **`continue-on-error`:** Steps laufen jetzt sequenziell — ein Step mit
  `exit 1` würde den Report-Step abbrechen. Die bestehenden Jobs nutzen bereits
  `|| true`/`continue-on-error` breit. Jeder Scan-Step, der fatal enden könnte
  und dessen Report trotzdem laufen muss, bekommt `continue-on-error: true`.
  Der Report-Step selbst läuft `if: always()`.
- **`timeout-minutes`:** Merged Job = Summe/Union der alten Step-Timeouts
  (obere Grenze, nicht knausern).

### Report-Referenz-Mapping

Statt `needs.<job>.result` → `steps.<id>.outcome`:

- secrets `secret-scan`: `trufflehog` + `pattern-detection` Step-Outcomes;
  gitleaks bleibt eigener Job, Report referenziert `needs.gitleaks.result`
  (secret-scan `needs: [gitleaks]` behalten, nur für die Report-Zeile).
- deps `dependency-scan`: `dependency-review`, `go-audit`, `js-audit`,
  `python-audit` Step-Outcomes.
- containers `container-scan`: `trivy`, `grype`, `image-analysis`.
- config `config-scan`: `trivy-config`, `terraform`, `kubernetes`, `ansible`.

Ein per-`if:` übersprungener Step hat Outcome `skipped` → korrekt in der
Tabelle.

## Breaking Change

Job-Merge ändert die Status-Check-Kontext-Namen. Alte Kontexte
(`Audit Go`, `Scan with Trivy`, `Create Report`, …) verschwinden, neuer
Kontext `<Scan-Job-Name>`. Branch-Protection/Ruleset-Anker in Consumer-Repos,
die auf die alten Namen zeigen, brechen.

**Handling:**

1. Neuen Datums-Tag cutten (kein `@main` für Consumer).
2. `### ⚠ BREAKING`-Heading im CHANGELOG-Eintrag des Tags: betroffene
   Workflows + neue Job-Namen + Migrationsschritt "Ruleset/branch-protection
   required-status-check-Anker auf neue Kontext-Namen umstellen".
3. AGENTS.md + README Job-Count-Referenzen aktualisieren (24 Workflows bleibt,
   aber Job-Zahlen/Beschreibungen anpassen).

## Neue Job-Namen (Status-Check-Kontexte)

- `security-secrets.yml`: `Scan with Gitleaks` (unverändert) + `Scan Secrets`
- `security-deps.yml`: `Scan Dependencies`
- `security-containers.yml`: `Scan Container Image`
- `security-config.yml`: `Scan Configuration`

## Testing

- `actionlint` auf die 4 geänderten Dateien (Syntax + Expression-Checks).
- YAML-Expression-Syntax manuell prüfen (Step-Outcome-Refs).
- **Kein** Consumer-Live-Test in dieser Session (bräuchte Tag-Push). Als
  manueller Schritt geflaggt: nach Tag-Cut in 1–2 Consumer-Repos gegen den
  neuen Tag testen, bevor breit ausgerollt wird.

## Scope-Grenzen (skipped)

- Matrix-basierter Merge — würde weiter auf N Runner fan-out, defeats purpose.
- `security-code.yml` / `security-sbom.yml` — nicht im Card-Scope.
- Kein Verhalten der Scans selbst geändert, nur Job-Topologie.
