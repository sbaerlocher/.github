# Lint/Fast-Checks vor Heavy-Jobs in ci-*-Reusables gaten

**Datum:** 2026-07-12
**Typ:** Refactor
**Notion:** https://app.notion.com/p/39abf097036e81d099f6c430062282f5
**Pfad:** nicht-trivial · **Aufwand:** M · **Prio:** P2

## Problem

In den geteilten `ci-*.yml`-Reusables laufen teure Jobs (Security-Scan, CodeQL,
Terraform-Plan/Trivy, Ansible-Lint, Helm-Render/Kubeconform) teils parallel zu
oder unabhängig von einem billigen Lint/Format/Validate. Ein Lint-Fehler stoppt
den teuren Job nicht früh → verschwendete Minuten. Aus dem Minuten-Audit
(Massnahme 2): failed+cancelled Runs zogen fleetweit ~433 min/mo Compute.

## Ziel

Teure Jobs erst NACH einem schnellen Gate laufen lassen (`needs:`). Lint-Fehler
bricht früh ab, statt dass ein teurer Job parallel durchläuft und eh verworfen
wird.

## Änderungen pro Workflow

| Workflow           | Änderung                                                                                                             |
| ------------------ | -------------------------------------------------------------------------------------------------------------------- |
| `ci-go.yml`        | Keine — `security-scan` + `codeql-analysis` gaten bereits (`needs: [setup, test-and-lint, test-and-lint-postgres]`). |
| `ci-js.yml`        | Keine — `security-scan` gatet bereits (`needs: [setup, quality-and-test]`).                                          |
| `ci-terraform.yml` | `lint` + `trivy` bekommen `needs: validation`.                                                                       |
| `ci-ansible.yml`   | `lint` + `yamllint` bekommen `needs: validation`.                                                                    |
| `ci-gitops.yml`    | Alle 6 Nicht-Gate-Jobs bekommen `needs: [validate-yaml]` + Guard-`if:`.                                              |

## Zwei needs-Muster

**terraform / ansible — plain `needs`:** Der `validation`-Job ist
unbedingt (kein `if:`). `needs: validation` reicht: bricht `validation`, werden
die abhängigen Jobs übersprungen. `lint` behält sein bestehendes
`if: inputs.enable-*`.

**gitops — `needs` + always()-Guard:** Der Gate-Job `validate-yaml` ist
bedingt (`if: inputs.enable-yaml-lint`). Plain `needs` würde die abhängigen
Jobs mit-skippen, wenn das Gate _deaktiviert_ ist. Guard:

```yaml
needs: [validate-yaml]
if: >-
  always() && !failure() && !cancelled()
  && inputs.enable-<eigenes-flag>
```

Läuft, wenn das Gate **success** ODER **skipped** ist; blockt nur bei Gate-
**failure**. Jeder Job behält sein eigenes `enable-*` im selben `if:`.

Betroffene gitops-Jobs (alle ausser `validate-yaml` und `summary`):
`validate-fleet-configs`, `validate-gitrepo`, `validate-helm`,
`validate-helm-template`, `validate-kubernetes`, `check-documentation`.
`summary` behält sein bestehendes `needs: [...]` + `if: always()`.

## go/js: warum keine Änderung

`dependency-review` in ci-go (Zeile 528) und ci-js (Zeile 521) hat kein
`needs:` — läuft parallel. Es ist aber **kein Heavy-Job**: reine
`dependency-review-action`, PR-only + public-only, kein Build/Scan-Compute. Das
Card-Ziel sind die teuren Jobs (Security-Scan, CodeQL), die bereits gegatet
sind. `dependency-review` zu gaten fügt nur Wall-Clock für einen ohnehin
billigen Check hinzu → bewusst ungegatet gelassen (YAGNI).

## Status-Checks / BREAKING

Es ändern sich **keine Job-Namen**, nur `needs:` (+ bei gitops die `if:`-
Guards). Status-Check-Kontext-Namen bleiben stabil → **keine** Ruleset-/
Branch-Protection-Anker-Migration nötig. Damit ist das **kein** Breaking Change
im CHANGELOG-Sinn → regulärer Datums-Tag, kein `⚠ BREAKING`.

Verhaltensänderung (nicht-breaking, dokumentieren): Ein Run, der vorher einen
Heavy-Job unabhängig als `failure` zeigte, zeigt ihn jetzt `skipped`, wenn das
Gate vorher failt. Erfolgreiche Runs werden sequenziell etwas langsamer
(Gate zuerst, dann Heavy) — Trade-off gegen die Minuten-Ersparnis bei
Fehlläufen.

## Testing

- `actionlint` auf ci-terraform, ci-ansible, ci-gitops (Syntax +
  needs-Referenzen + Expression-Guards).
- Verifizieren, dass go/js-Heavy-Jobs weiterhin voll gegatet sind (nur Lesen).
- **Kein** Consumer-Live-Test in dieser Session (bräuchte Tag-Push). Manueller
  Schritt: nach Tag-Cut in 1–2 Consumer-Repos testen.

## Scope-Grenzen (skipped)

- Dedizierter `gate`-Job in gitops — grösserer Umbau, `validate-yaml`-Name
  würde sich ändern (mehr BREAKING). `needs`+Guard ist der kleinere Eingriff.
- go/js-Code-Änderungen — Heavy-Jobs bereits gegatet.
- Keine Änderung an Job-Logik, nur Abhängigkeits-Topologie.
