# GitHub Workflows & Release Management

Releases werden über die Datei `VERSION` im Repository-Root ausgelöst, nicht mehr durch manuelles Taggen.

## Release erstellen

1. `VERSION` auf die neue Version setzen (SemVer, ohne `v`), z. B. `2.2.0` oder `2.2.0-beta.1`.
2. In `CHANGELOG.md` den Abschnitt `[Unreleased]` in `[2.2.0] - <Datum>` umbenennen.
3. Auf `main` committen und pushen.

Der Workflow `.github/workflows/build-and-release.yml` startet bei jedem Push auf `main`, der `VERSION` ändert:

1. **Version lesen**: `VERSION` wird geprüft (SemVer). Existiert der Tag `v<VERSION>` schon, passiert nichts (z. B. bei einer reinen Korrektur der Datei).
2. **Versionen eintragen**: `Install-ADSK.ps1` und `CIDEON.AutodeskDeployment.psm1` erhalten die Version in der Zeile `ModuleVersion:`.
3. **Modul signieren**: `CIDEON.AutodeskDeployment.psm1` wird mit den GitHub Secrets signiert und geprüft.
4. **Paket bauen**: `Autodesk-Deployment-<VERSION>.zip` mit `Install-ADSK.ps1`, `Copy-Local.ps1`, `New-DeploymentImage.ps1`, `New-DeploymentImage.cmd`, Modul, Zertifikat, `readme.md`, `CHANGELOG.md` und `samples/`.
5. **Release anlegen**: Der Tag `v<VERSION>` wird auf dem gepushten Commit erstellt, der Release-Text kommt aus dem passenden `CHANGELOG.md`-Abschnitt (`[<VERSION>]`, sonst `[Unreleased]`).

Eine Version mit Suffix (`-alpha`, `-beta.1`, `-rc1`) wird automatisch als Pre-Release markiert.

## Pre-Release testen, ohne nach main zu mergen

Ein Push auf einen Branch `release/**` (z. B. `release/3.0.0-beta`), der `VERSION` ändert, startet denselben Workflow. Dort sind nur Pre-Release-Versionen erlaubt (z. B. `3.0.0-beta.1`), eine stabile Version wird abgelehnt. Der Tag entsteht auf dem Commit des Branches. `workflow_dispatch` wird bewusst nicht benutzt: GitHub verlangt dafür, dass der Workflow schon auf dem Default-Branch liegt.

## Release-Assets

- `Autodesk-Deployment-<VERSION>.zip` (komplettes Paket)
- `Install-ADSK.ps1`, `New-DeploymentImage.ps1`, `New-DeploymentImage.cmd`
- `CIDEON.AutodeskDeployment.psm1` (signiert), `CIDEON-CodeSigning.cer`

## Häufige Probleme

- **Workflow startet nicht**: Der Push muss `main` betreffen und `VERSION` ändern.
- **Run ist grün, aber es gibt kein Release**: Der Tag `v<VERSION>` existiert schon. `VERSION` erhöhen.
- **Ein Release ist fehlgeschlagen**: Der Tag wird erst im letzten Schritt erstellt. Den fehlgeschlagenen Run in GitHub Actions erneut starten (Re-run), es muss nichts gelöscht werden.
- **Ein Tag wurde fälschlich erstellt**: `git push origin --delete v<VERSION>` und das GitHub-Release löschen.
