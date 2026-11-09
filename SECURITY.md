# Security

## Reporting a vulnerability

Please report security problems privately via GitHub's **Report a vulnerability** (Security → Advisories) on this repository rather than in a public issue. Include steps to reproduce and the affected version. You should receive a response within a week.

## Scope and trust model

This is a developer preview. Extensions are trusted code:

- Each extension's JavaScript runs in a separate, **sandboxed** process: macOS stops it from reading your files, writing files, using the network or starting programs.
- What an extension can do goes through the app: HTTPS to the hosts listed in its manifest, declared loopback services, secrets in its own Keychain items, opening a link right after you click, and its own storage.
- Native tools are declared in the manifest and require your consent before they start. A native tool you allow runs with your user account. It is **not sandboxed**.

Reports about escaping these boundaries (leaving the runner sandbox, reaching undeclared hosts or destinations, starting undeclared processes, reading another extension's secrets or storage, bypassing consent, or affecting other extensions) are in scope. Behavior of a native tool you allowed is not a vulnerability in NotchNotch.
