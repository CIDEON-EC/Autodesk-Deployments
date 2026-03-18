# Certificate Setup for Install-ADSK

This project uses a signed PowerShell module (`CIDEON.AutodeskDeployment.psm1`) and a public certificate file (`CIDEON-CodeSigning.cer`).

The installer script (`Install-ADSK.ps1`) downloads the module from GitHub Release assets, validates the signature and imports it only when the signature is valid.

## Included files

- `Install-ADSK.ps1` (installer)
- `CIDEON.AutodeskDeployment.psm1` (signed module)
- `CIDEON-CodeSigning.cer` (public certificate)

## Customer setup (recommended)

Run once on each client (PowerShell with user or admin context, depending on policy):

```powershell
Import-Certificate -FilePath ".\CIDEON-CodeSigning.cer" -CertStoreLocation "Cert:\CurrentUser\TrustedPublisher"
```

If your company policy requires machine-wide trust:

```powershell
Import-Certificate -FilePath ".\CIDEON-CodeSigning.cer" -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher"
```

## Verify certificate import

```powershell
Get-ChildItem -Path Cert:\CurrentUser\TrustedPublisher | Where-Object { $_.Subject -eq "CN=CIDEON-EC Code Signing" }
```

## Verify script/module signatures

```powershell
Get-AuthenticodeSignature .\Install-ADSK.ps1
Get-AuthenticodeSignature .\CIDEON.AutodeskDeployment.psm1
```

Expected status for trusted environments: `Valid`.

## Runtime behavior

1. `Install-ADSK.ps1` downloads `CIDEON-CodeSigning.cer` and module from GitHub Release assets.
	- default: latest release
	- optional pin: `-ModuleVersionPin <x.y.z>` (for example `-ModuleVersionPin 1.2.0`)
2. Installer ensures certificate is available in `TrustedPublisher` (CurrentUser).
3. Installer validates module signature.
4. If remote loading fails, installer tries local fallback module (`$PSScriptRoot\CIDEON.AutodeskDeployment.psm1`) and validates signature there too.

## Troubleshooting

- `Module signature is invalid`: module was changed after signing or certificate mismatch.
- `Failed to load module from remote`: network/proxy/firewall issue, use local fallback copy.
- Signature status `UnknownError` or `NotTrusted`: import `CIDEON-CodeSigning.cer` into `TrustedPublisher`.

## Security notes

- Only the public certificate (`.cer`) is stored in this repository.
- Never commit private keys (`.pfx`) to the repository.
- Re-sign changed scripts/modules after modifications.
