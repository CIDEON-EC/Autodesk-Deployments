---
description: 'Automatically update CHANGELOG.md and documentation files when PowerShell code changes require documentation updates'
applyTo: '**/*.ps1,**/*.psm1'
---

# Update Documentation on PowerShell Code Change

## Overview

Ensure documentation stays synchronized with PowerShell code changes by automatically detecting when
CHANGELOG.md, script usage guides, parameter documentation, and configuration docs need updates.

## Instruction Sections and Configuration

The following parts of this section, `Instruction Sections and Configurable Instruction Sections`
and `Instruction Configuration` are only relevant to THIS instruction file, and are meant to be a
method to easily modify how the Copilot instructions are implemented. Essentially the two parts
are meant to turn portions or sections of the actual Copilot instructions on or off, and allow for
custom cases and conditions for when and how to implement certain sections of this document.

### Instruction Sections and Configurable Instruction Sections

There are several instruction sections in this document. The start of an instruction section is
indicated by a level two header. Call this an **INSTRUCTION SECTION**. Some instruction sections
are configurable. Some are not configurable and will always be used.

Instruction sections that ARE configurable are not required, and are subject to additional context
and/or conditions. Call these **CONFIGURABLE INSTRUCTION SECTIONS**.

**Configurable instruction sections** will have the section's configuration property appended to
the level two header, wrapped in backticks (e.g., `apply-this`). Call this the
**CONFIGURABLE PROPERTY**.

The **configurable property** will be declared and defined in the **Instruction Configuration**
portion of this section. They are booleans. If `true`, then apply, utilize, and/or follow the
instructions in that section.

Each **configurable instruction section** will also have a sentence that follows the section's
level two header with the section's configuration details. Call this the **CONFIGURATION DETAIL**.

The **configuration detail** is a subset of rules that expand upon the configurable instruction
section. This allows for custom cases and/or conditions to be checked that will determine the final
implementation for that **configurable instruction section**.

Before resolving on how to apply a **configurable instruction section**, check the
**configurable property** for a nested and/or corresponding `apply-condition`, and utilize the
`apply-condition` when settling on the final approach for the **configurable instruction
section**. By default the `apply-condition` for each **configurable property** is unset.

The sum of all the **constant instructions sections**, and **configurable instruction sections**
will determine the complete instructions to follow. Call this the **COMPILED INSTRUCTIONS**.

The **compiled instructions** are dependent on the configuration. Each instruction section included
in the **compiled instructions** will be interpreted and utilized AS IF a separate set of
instructions that are independent of the entirety of this instruction file. Call this the
**FINAL PROCEDURE**.

### Instruction Configuration

- **apply-doc-file-structure** : true
  - **apply-condition** : unset
- **apply-doc-verification** : true
  - **apply-condition** : unset
- **apply-doc-quality-standard** : true
  - **apply-condition** : unset
- **apply-automation-tooling** : true
  - **apply-condition** : unset
- **apply-doc-patterns** : true
  - **apply-condition** : unset
- **apply-best-practices** : true
  - **apply-condition** : unset
- **apply-validation-commands** : true
  - **apply-condition** : unset
- **apply-maintenance-schedule** : true
  - **apply-condition** : unset
- **apply-git-integration** : false
  - **apply-condition** : unset

## When to Update Documentation

### Trigger Conditions

Automatically check if documentation updates are needed when:

- New PowerShell functions, scripts, or modules are added
- Cmdlet parameters, defaults, validation attributes, or return objects change
- Breaking changes are introduced (renamed functions, removed parameters, changed output shape)
- Required modules, minimum PowerShell version, or execution prerequisites change
- Configuration values, script arguments, or environment variables are modified
- Installation or setup procedures for script execution change
- Task or CLI usage examples in README become outdated
- Comment-based help (`.SYNOPSIS`, `.PARAMETER`, `.EXAMPLE`) becomes inaccurate

## Documentation Update Rules

### README.md Updates

**Always update README.md when:**

- Adding new scripts/functions
  - Add capability description to features or usage section
  - Include example invocation with realistic parameters

- Modifying installation or setup
  - Update required PowerShell version and modules
  - Update execution policy or permission prerequisites if needed

- Changing command usage
  - Document new/changed parameters and defaults
  - Update examples for local and CI/CD usage where relevant

- Changing configuration
  - Update environment variable examples
  - Keep sample config snippets aligned with current script behavior

### Script/Module Documentation Updates

**Sync PowerShell documentation when:**

- Public function signatures change
  - Update parameter lists and expected types
  - Update output object examples
  - Document any breaking changes

- Module behavior changes
  - Update import requirements and version constraints
  - Document side effects, safety behavior, and `SupportsShouldProcess`

### Code Example Synchronization

**Verify and update PowerShell examples when:**

- Parameter names, ValidateSet values, or defaults change
  - Update all command snippets using those parameters
  - Ensure snippets execute without syntax errors

- Output shape changes
  - Update examples that parse properties or pipeline output

- Recommended practices evolve
  - Prefer full cmdlet names over aliases in docs
  - Keep examples non-interactive and automation-friendly

### Configuration Documentation

**Update configuration docs when:**

- New environment variables are added
  - Add to README or docs/configuration section
  - Include default values and valid options

- Script configuration structure changes
  - Update sample hashtables/JSON snippets used by scripts
  - Mark deprecated options and replacement path

### Migration and Breaking Changes

**Create migration guidance when:**

- Public function names or parameters are changed/removed
  - Document before/after command examples
  - Include exact replacement usage

- Behavior changes can break existing automation
  - Provide upgrade checklist for pipelines and scheduled tasks

## Documentation File Structure `apply-doc-file-structure`

If `apply-doc-file-structure == true`, then apply the following configurable instruction section.

### Standard Documentation Files

Maintain these documentation files and update as needed:

- **README.md**: Project overview, prerequisites, quick start for scripts
- **CHANGELOG.md**: Version history and user-facing changes
- **docs/** (if present):
  - `installation.md`: Setup and installation guide
  - `configuration.md`: Parameters, environment variables, examples
  - `scripts.md` or `module.md`: Script/cmdlet reference
  - `migration-guides/`: Version migration guides
- **samples/** or **examples/**: Working PowerShell usage examples

### Changelog Management

**Add changelog entries for:**

- New scripts/cmdlets (under "Added")
- Bug fixes (under "Fixed")
- Breaking parameter/output changes (under "Changed" with **BREAKING** prefix)
- Deprecations/removals (under "Deprecated" / "Removed")
- Security fixes (under "Security")

**Changelog format:**

    ```markdown
    ## [Version] - YYYY-MM-DD

    ### Added
    - Added `Get-ExampleData` script support for ...

    ### Changed
    - **BREAKING**: Renamed `-ConfigPath` to `-SettingsPath` in `Install-ADSK.ps1`

    ### Fixed
    - Fixed parameter validation for ...
    ```

## Documentation Verification `apply-doc-verification`

If `apply-doc-verification == true`, then apply the following configurable instruction section.

### Before Applying Changes

**Check documentation completeness:**

1. All changed public PowerShell functions/scripts are documented
2. Comment-based help matches current parameters and behavior
3. Usage examples are executable and current
4. Configuration examples match script expectations
5. README prerequisites and setup steps are current
6. CHANGELOG entry exists for user-facing changes

### Documentation Tests

**Include documentation validation:**

- Run script analyzer for changed scripts
- Validate examples for syntax/runtime where possible
- Check documentation links and command accuracy

## Documentation Quality Standards `apply-doc-quality-standard`

If `apply-doc-quality-standard == true`, then apply the following configurable instruction section.

### Writing Guidelines

- Use clear, concise language
- Include runnable PowerShell examples
- Use consistent parameter names and terminology
- Show error handling and safe execution patterns where relevant
- Mention edge cases and limitations that affect automation

### PowerShell Example Format

    ```markdown
    ### Example: Run script with explicit configuration

    ```powershell
    .\Install-ADSK.ps1 -SettingsPath '.\config.json' -Verbose
    ```

    **Expected result:**
    ```text
    Installation completed successfully.
    ```
    ```

### Cmdlet Documentation Format

    ```markdown
    ### `Set-DeploymentState`

    Brief description of the cmdlet.

    **Parameters:**
    - `Name` (`string`): Deployment name.
    - `State` (`string`): Target state (`Enabled`, `Disabled`).

    **Returns:**
    - `PSCustomObject`: Updated deployment state.

    **Example:**
    ```powershell
    Set-DeploymentState -Name 'CoreApp' -State 'Enabled' -PassThru
    ```
    ```

## Automation and Tooling `apply-automation-tooling`

If `apply-automation-tooling == true`, then apply the following configurable instruction section.

### Documentation Generation

**Use automated tools when available:**

- Comment-based help (`Get-Help`) for script/cmdlet reference
- PlatyPS (if used) for Markdown help generation

### Documentation Linting

**Validate documentation with:**

- PSScriptAnalyzer for script quality and conventions
- Markdown linting and link checking for docs
- Optional spell checking for Markdown files

### Pre-update Hooks

**Prefer checks before merge:**

- Script analysis passes
- Documentation links are valid
- Updated usage examples are syntactically correct
- Changelog contains user-facing changes

## Common Documentation Patterns `apply-doc-patterns`

If `apply-doc-patterns == true`, then apply the following configurable instruction section.

### Script Feature Template

    ```markdown
    ## Script Name

    Brief description of what the script does.

    ### Prerequisites

    Required PowerShell version, modules, permissions.

    ### Usage

    Basic command example.

    ### Parameters

    Important parameters and defaults.

    ### Troubleshooting

    Common failures and suggested fixes.
    ```

### Function/Cmdlet Template

    ```markdown
    ### `Get-ResourceStatus`

    Description of what the function returns.

    **Example:**
    ```powershell
    Get-ResourceStatus -Name 'MainService'
    ```

    **Output:**
    ```text
    Name        Status
    ----        ------
    MainService Running
    ```
    ```

## Best Practices `apply-best-practices`

If `apply-best-practices == true`, then apply the following configurable instruction section.

### Do's

- ✅ Update docs in the same change set as PowerShell code updates
- ✅ Keep README usage examples aligned with real script behavior
- ✅ Keep comment-based help synchronized with parameters/output
- ✅ Prefer automation-safe examples (no interactive prompts)
- ✅ Document breaking changes and migration steps clearly

### Don'ts

- ❌ Leave stale command examples after parameter changes
- ❌ Use aliases in docs where full cmdlet names are clearer
- ❌ Document behavior that scripts do not implement
- ❌ Skip CHANGELOG updates for user-facing script changes

## Validation Example Commands `apply-validation-commands`

If `apply-validation-commands == true`, then apply the following configurable instruction section.

Example commands to apply for documentation and script validation:

```powershell
# Analyze PowerShell scripts
Get-ChildItem -Recurse -Filter *.ps1 |
    ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Settings ./.scripts/PSScriptAnalyzerSettings.psd1 }

# Validate comment-based help for a script
Get-Help .\Install-ADSK.ps1 -Full

# Optional: markdown checks (if configured)
# npm run docs:lint
```

## Maintenance Schedule `apply-maintenance-schedule`

If `apply-maintenance-schedule == true`, then apply the following configurable instruction section.

### Regular Reviews

- **Monthly**: Review PowerShell usage docs for accuracy
- **Per release**: Update parameter examples and version notes
- **Quarterly**: Review deprecated script patterns and aliases
- **Annually**: Full audit of script docs and migration notes

### Deprecation Process

When deprecating script features:

1. Add deprecation notice in script docs and README
2. Update examples to recommended alternatives
3. Add migration notes with before/after commands
4. Update changelog with deprecation timeline
5. Remove deprecated docs in next major version

## Git Integration `apply-git-integration`

If `apply-git-integration == true`, then apply the following configurable instruction section.

### Pull Request Requirements

**Documentation must be updated in the same PR as script changes:**

- Document new scripts/functions
- Update examples for changed parameters/outputs
- Add changelog entries for user-visible behavior changes

### Documentation Review

**During code review, verify:**

- Docs describe current script behavior
- Examples are complete and executable
- Breaking changes include migration guidance
- Changelog entry is appropriate

## Review Checklist

Before considering documentation complete, and concluding on the **final procedure**:

- [ ] **Compiled instructions** are based on active instruction sections
- [ ] README reflects current PowerShell script capabilities
- [ ] Public scripts/functions are documented
- [ ] Comment-based help is synchronized
- [ ] Examples are valid and current
- [ ] Configuration and prerequisites are documented
- [ ] Breaking changes include migration guidance
- [ ] CHANGELOG.md is updated
- [ ] Links are valid and not broken

## Updating Documentation on Code Change GOAL

- Keep PowerShell documentation close to scripts and modules
- Use comment-based help as the source of truth where possible
- Maintain living documentation that evolves with script behavior
- Treat documentation updates as part of feature completeness