# Security

## What the helper changes

The helper delegates patching to `dia-zh-patch`. Before writing, the bundled patch verifies Dia's official signature, bundle identifier, architecture and resource structure. It creates and verifies a complete same-build backup, installs localization resources, applies a unified ad-hoc signature, and performs a strict signature audit.

Automatic mode only runs when:

- `/Applications/Dia.app` has a recognized official signature;
- the current build passes the patch's compatibility checks;
- Dia is not running.

Unknown or incompatible structures fail closed. Restore never crosses build versions.

Status does not trust the saved `applied` flag alone: the helper checks the current signature, localization resources and menu translator. Repair archives stale state only when the current bundle has a valid official signature; otherwise recovery requires a matching-build backup. A kernel lock serializes helper operations. Legacy locks are archived only after checking their owner and other installer processes.

Background installation leaves Dia closed and reports startup verification as pending. Startup verification checks for a renderer process; it does not validate every site or browser feature. A failed automatic installation pauses retries for that build until a successful manual repair or a new build.

## Limitations

Ad-hoc signing removes Apple-team-bound capabilities such as keychain groups, associated domains, WebAuthn credentials and push-notification entitlement. These capabilities may not work in the patched app. Use **Restore Official Version** to return to the verified official bundle.

macOS may ask the user to authorize the re-signed Dia to access existing keychain items. Handle this only in the system dialog; never enter a password into the helper, logs or issue reports. The helper does not read passwords or modify keychain access controls.

The helper itself is ad-hoc signed and is not notarized by Apple. Core localization is partial; settings and AI pages may remain in English.

Do not attach Dia user data, a complete Dia application bundle, backups or unredacted logs to public issues.

## Reporting

Open a GitHub issue with the Dia version/build, macOS version, Apple Silicon model, coverage mode and redacted status/audit output.
