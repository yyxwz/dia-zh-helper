# Security

## What the helper changes

The helper delegates patching to `dia-zh-patch`. Before writing, the bundled patch verifies Dia's official signature, bundle identifier, architecture and resource structure. It creates and verifies a complete same-build backup, installs localization resources, applies a unified ad-hoc signature, and performs a strict signature audit.

Automatic mode only runs when:

- `/Applications/Dia.app` has a recognized official signature;
- the current build passes the patch's compatibility checks;
- Dia is not running.

Unknown or incompatible structures fail closed. Restore never crosses build versions.

## Limitations

Ad-hoc signing removes Apple-team-bound capabilities such as keychain groups, associated domains, WebAuthn credentials and push-notification entitlement. These capabilities may not work in the patched app. Use **Restore Official Version** to return to the verified official bundle.

Do not attach Dia user data, a complete Dia application bundle, backups or unredacted logs to public issues.

## Reporting

Open a GitHub issue with the Dia version/build, macOS version, Apple Silicon model, coverage mode and redacted status/audit output.
