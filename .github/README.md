# GitHub Workflows & Release Management

Diese Dokumentation erklärt den automatisierten Release-Prozess für das Autodesk Deployment Tools Repository.

## 🎯 Übersicht

Das Repository verwendet einen **tag-basierten Release-Flow**. Releases werden durch Git-Tags ausgelöst, nicht durch Änderungen an `VERSION.txt`. Der Workflow erstellt automatisch:

- ✅ GitHub Release mit angepasstem Release-Namen
- ✅ ZIP-Asset mit produktiven Dateien
- ✅ Automatische Versions-Updates in Skriptdateien
- ✅ Unterstützung für Pre-Releases (z.B. `-beta`, `-rc`)

## 📋 Release-Workflow

### Schritt 1: Commits vorbereiten

Machen Sie Ihre Commits normal auf dem `main`-Branch:

```bash
git add .
git commit -m "Beschreibung der Änderungen"
git push origin main
```

### Schritt 2: Release-Tag erstellen

Es gibt drei Möglichkeiten, je nach Art der Änderungen:

#### Option A: Patch-Release (Bug-Fixes)
```bash
# Erhöht die Patch-Version: 1.0.0 → 1.0.1
git tag -a v1.0.1 -m "Release version 1.0.1"
```

#### Option B: Minor-Release (Neue Features)
```bash
# Erhöht die Minor-Version: 1.0.0 → 1.1.0
git tag -a v1.1.0 -m "Release version 1.1.0"
```

#### Option C: Major-Release (Breaking Changes)
```bash
# Erhöht die Major-Version: 1.0.0 → 2.0.0
git tag -a v2.0.0 -m "Release version 2.0.0"
```

### Schritt 3: Tag pushen

```bash
# Push den erstellten Tag
git push origin v1.0.1
```

**Alternativ:** Alle Tags auf einmal pushen:
```bash
git push origin --tags
```

## 🤖 Automatisierung mit VS Code Tasks

Statt manuelle Git-Befehle auszuführen, können Sie die vordefinierten Tasks in VS Code nutzen:

### Release-Tag erstellen

1. Öffnen Sie die **Command Palette** (`Ctrl+Shift+P`)
2. Geben Sie `Tasks: Run Task` ein
3. Wählen Sie eine der folgenden Aufgaben:
   - `🔧 Create Patch Release Tag` - für Bug-Fixes
   - `⚡ Create Minor Release Tag` - für neue Features
   - `🚀 Create Major Release Tag` - für Breaking Changes

### Tag pushen

Task: `🚢 Push Tags to Remote`

Diese Aktion pushed automatisch alle erstellten Tags zu GitHub und triggert den Release-Workflow.

### Vollständige Release-Workflow (Ein-Klick)

Die folgenden Compound-Tasks führen beide Schritte in Folge aus:

1. `🔄 Complete Release (Patch)` - Patch-Tag erstellen + pushen
2. `🔄 Complete Release (Minor)` - Minor-Tag erstellen + pushen
3. `🔄 Complete Release (Major)` - Major-Tag erstellen + pushen

## 🔄 Was passiert automatisch?

Wenn Sie einen Tag mit dem Muster `v*` pushen, triggert der Workflow `.github/workflows/build-and-release.yml`:

1. **Tag analysieren**: Die Version wird aus dem Tag-Namen extrahiert
2. **Skripte aktualisieren**: `Install-ADSK.ps1` erhält die aktuelle Version
3. **Deployment-Paket erstellen**: ZIP-Datei mit folgenden Dateien:
   - `Install-ADSK.ps1`
   - `Copy-Local.ps1`
   - `readme.md`
   - `CHANGELOG.md` (optional)
   - `samples/` (kompletter Ordner)
4. **GitHub Release erstellen**: Mit Tag-Name, automatischer Versionsnummer und Asset-Upload
5. **Pre-Release kennzeichnen**: Automatisch erkannt (z.B. `-beta`, `-rc`, `-alpha`)

## 📝 Tag-Namenskonventionen

Verwenden Sie folgende Muster für konsistente Versionierung:

### Stabile Releases
```
v1.0.0          # Patch-Release
v1.1.0          # Minor-Release (neue Features)
v2.0.0          # Major-Release (Breaking Changes)
```

### Pre-Releases
```
v1.0.0-alpha    # Alpha-Version
v1.0.0-beta     # Beta-Version
v1.0.0-rc1      # Release Candidate
```

Der Workflow erkennt Pre-Release-Versionen automatisch und markiert die GitHub Release entsprechend.

## 🛑 Alten Workflow (Veraltet)

Der alte Workflow in `.github/workflows/release.yml` ist **DEPRECATED** und wird nicht mehr verwendet. Dieser basierte auf `VERSION.txt`-Änderungen und ist durch den tag-basierten Ansatz ersetzt worden.

### Wichtig:
- `Manage-Version.ps1` ist veraltet und sollte nicht mehr verwendet werden
- VERSION.txt wird nicht mehr automatisch aktualisiert
- Verwenden Sie stattdessen Git-Tags für Releases

## 📦 Release-Assets

Jedes Release erhält ein ZIP-Archiv mit dem Namen:
```
Autodesk-Deployment-<VERSION>.zip
```

**Beispiel:** Für Tag `v1.0.5` wird erstellt:
```
Autodesk-Deployment-1.0.5.zip
```

### Inhalt des ZIP-Archives:
```
Autodesk-Deployment-1.0.5/
├── Install-ADSK.ps1      (mit aktualisierter Version)
├── Copy-Local.ps1
├── readme.md
├── CHANGELOG.md
└── samples/
    ├── Copy-Local.bat
    └── INSTALL.bat
```

## 🔍 Monitoring & Debugging

### Workflow-Status anzeigen

In GitHub:
1. Gehen Sie zu **Actions** im Repository
2. Suchen Sie nach dem Workflow `Build and Release`
3. Klicken Sie auf den entsprechenden Run, um Details zu sehen

### Häufige Probleme

#### ❌ Workflow startet nicht nach Tag-Push
- Überprüfen Sie, dass der Tag-Name mit `v*` beginnt
- Beispiel: `v1.0.0` ✅, `1.0.0` ❌

#### ❌ Release-Asset ist leer
- Überprüfen Sie, dass alle produktiven Dateien vorhanden sind
- Der Workflow benötigt mindestens: `Install-ADSK.ps1`, `Copy-Local.ps1`, `readme.md`, `samples/`

#### ❌ Versionsnummer in `Install-ADSK.ps1` wird nicht aktualisiert
- Der Workflow sucht nach der Zeile `Version: X.Y.Z`
- Stellen Sie sicher, dass diese in den `.NOTES` der Datei vorhanden ist

## 🚀 Beispiel-Workflow Schritt für Schritt

```
1. [Lokal] Entwicklung abschließen
   git add .
   git commit -m "Neue Feature XYZ hinzugefügt"
   git push origin main

2. [Lokal / VS Code] Patch-Release vorbereiten
   Task: "🔄 Complete Release (Minor)"
   
3. [Lokal / Git] Tag wird erstellt und gepusht
   git tag -a v1.1.0 -m "Release version 1.1.0"
   git push origin v1.1.0

4. [GitHub Actions] Workflow wird automatisch gestartet
   - Version wird extrahiert (1.1.0)
   - Install-ADSK.ps1 wird aktualisiert
   - ZIP-Paket wird erstellt
   - GitHub Release wird veröffentlicht

5. [GitHub] Release ist live
   - Tag: v1.1.0
   - Name: Autodesk Deployment Tools 1.1.0
   - Asset: Autodesk-Deployment-1.1.0.zip
```

## 📚 Weitere Ressourcen

- [Semantic Versioning (SemVer)](https://semver.org/) - Versionierungskonventionen
- [Git Tags](https://git-scm.com/book/en/v2/Git-Basics-Tagging) - Git Tag-Dokumentation
- [GitHub Actions](https://docs.github.com/actions) - Workflow-Dokumentation
- [softprops/action-gh-release](https://github.com/softprops/action-gh-release) - Release Action

## ❓ FAQs

**F: Kann ich einen bereits gepushten Tag ändern?**
A: Generell sollten Sie das nicht tun. Wenn nötig, löschen Sie den Tag lokal und remote und erstellen ihn neu:
```bash
git tag -d v1.0.0
git push origin --delete v1.0.0
```

**F: Was passiert, wenn ich mehrere Tags auf einmal pushe?**
A: Der Workflow wird für jeden Tag einzeln ausgelöst. Jedes Release wird separat erstellt.

**F: Kann ich automatische Releases deaktivieren?**
A: Ja, indem Sie den Workflow `.github/workflows/build-and-release.yml` deaktivieren oder ändern.

**F: Wie erstelle ich ein Draft-Release (nicht sofort veröffentlicht)?**
A: Der aktuelle Workflow erstellt nur veröffentlichte Releases. Um ein Draft zu erstellen, müssen Sie es manuell in GitHub erstellen.
