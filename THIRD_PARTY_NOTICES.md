# Third-party notices

This project downloads and bundles [`AYangZi/dia-zh-patch`](https://github.com/AYangZi/dia-zh-patch) v0.1.0-rc.2 at build time.

`dia-zh-patch` is distributed under the MIT License. Its original `LICENSE`, source, translations and documentation remain inside the application bundle at `Contents/Resources/Patch/`.

The helper applies one compatibility patch before building: it removes the restricted `com.apple.developer.aps-environment` entitlement when converting Dia 1.56+ to a local ad-hoc signature. Without this change, macOS rejects the re-signed application at launch.
