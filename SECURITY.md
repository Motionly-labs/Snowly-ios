# Security Policy

## Supported Versions

Only the latest release on the `main` branch receives security fixes.

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report security issues privately via [GitHub Security Advisories](../../security/advisories/new). Include:

- A description of the vulnerability
- Steps to reproduce or a proof-of-concept
- Potential impact

You'll receive a response within 72 hours. If confirmed, we'll work with you on a coordinated disclosure timeline before publishing a fix.

## Scope

This policy covers the Snowly iOS app codebase. For vulnerabilities in the backend API ([Snowly-Server](https://github.com/Motionly-labs/Snowly-Server)), please report there instead.

## Privacy Architecture

Snowly is privacy-first by design:

- All location data is stored locally on-device (`NSFileProtectionComplete`).
- iCloud sync uses your private CloudKit container — data is never accessible to Snowly.
- Crew location sharing is opt-in, ephemeral (last known position only), and scoped to your crew token.
- No telemetry, no analytics SDKs, no third-party data collection.
