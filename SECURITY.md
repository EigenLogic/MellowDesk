# Security Policy

MellowDesk handles camera access, local notifications, login-item registration, and local workout history. Security and privacy reports are welcome.

## Supported versions

| Version | Support |
|---|---|
| Latest `0.1.x` beta | Supported on a best-effort basis |
| Older snapshots and forks | Not supported |

## Report a vulnerability privately

Do not open a public issue for a vulnerability.

Use GitHub private vulnerability reporting from the repository's **Security** tab when it is available. Otherwise, use the private contact method published on the profile of the organization hosting this repository. If neither channel is available, open a minimal public issue requesting a private security contact and include no technical or personal details.

Please include:

- affected version or commit;
- macOS version and Mac model;
- impact and realistic attack scenario;
- minimal reproduction steps;
- suggested mitigation, if known.

Do not send real faces, camera recordings, raw pose streams, personal workout history, credentials, or secrets. Use synthetic or redacted material.

## What belongs here

Examples include:

- camera remaining active outside an expected workout lifecycle;
- images, face data, or frame-by-frame pose data being persisted or transmitted;
- unintended network access or data disclosure;
- sandbox, permission, notification-action, or local-file vulnerabilities;
- release-signing or update-channel compromise.

Ordinary recognition inaccuracies, UI defects, and feature requests can use the public issue tracker as long as the report contains no sensitive data.

## Response

Maintainers aim to acknowledge a private report within seven days and provide an initial assessment within fourteen days. These are best-effort targets for an open-source beta, not a service-level agreement. Please allow time for a fix and coordinated disclosure before publishing details.
