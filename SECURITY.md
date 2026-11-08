# Security

## Reporting a vulnerability

Please report security problems privately via GitHub's **Report a vulnerability** (Security → Advisories) on this repository rather than in a public issue. Include steps to reproduce and the affected version. You should receive a response within a week.

## Scope and trust model

This is a developer preview. Extensions are trusted code:

- Each extension's JavaScript runs in a separate process without Node, filesystem or general network access.
- Network access is limited to declared loopback services; native tools are declared in the manifest and require your consent before they start.
- A native tool you allow runs with your user account. It is **not sandboxed**.

Reports about escaping these boundaries (reaching undeclared destinations, starting undeclared processes, bypassing consent, or affecting other extensions) are in scope. Behavior of a native tool you allowed is not a vulnerability in NotchNotch.
