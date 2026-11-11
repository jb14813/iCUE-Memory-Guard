# Security

For a security issue that could expose users to harm, contact [support@jzbapps.com](mailto:support@jzbapps.com) with a concise description, affected version and reproduction details. Avoid posting sensitive details in a public issue before a fix can be assessed. Ordinary bugs and compatibility reports can use [GitHub issues](https://github.com/jb14813/iCUE-Memory-Guard/issues).

Version 0.1.0 is experimental. Compatibility is limited to the exact original and patched image hashes in [VALIDATION.md](VALIDATION.md). There is no promise of support for future iCUE updates.

The tool runs elevated when changing protected vendor files or recovery data. It preserves verified originals, rejects unknown contents and unsafe file links, and avoids restoring older images over a vendor update. Retain recovery data if an operation reports a conflict. An update can remove the fix; there is no automatic unsafe reapplication.

Locally modified vendor files lose valid vendor signatures and may be blocked by application-control policies. The tool must not require disabling Windows security or trusting a new certificate. Verify release assets as described in [SIGNING.md](SIGNING.md).

Do not submit private keys, credentials, raw diagnostic captures or unreviewed reports containing personal paths. Public support requests should contain only the minimum information needed to reproduce the issue.
