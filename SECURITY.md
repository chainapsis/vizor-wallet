# Security Policy

Vizor is a self-custody wallet. We take reports about vulnerabilities that
could affect wallet funds, keys, privacy, availability, or software integrity
seriously.

## Supported versions

| Version | Support |
| --- | --- |
| Latest stable release | Supported |
| Pre-release, release-candidate, internal, and mobile builds | Best effort |
| Older stable releases | Not supported; upgrade to the latest stable release |

## Reporting a vulnerability

Do not report suspected vulnerabilities in a public GitHub issue, pull request,
discussion, social-media post, or other public channel.

Email reports to [security@keplr.app](mailto:security@keplr.app). If GitHub
displays a **Report a vulnerability** button for this repository, you may use
that private reporting channel instead.

Include as much of the following as is safely available:

- A concise description of the vulnerability and its potential impact.
- The affected Vizor version or commit.
- The operating system, architecture, device, and relevant OS version.
- Whether the issue affects mainnet, testnet, regtest, or all networks.
- Reproduction steps or a minimal proof of concept.
- Any conditions required to exploit or reproduce the issue.
- Suggested mitigations or fixes, if known.
- Sanitized logs, screenshots, or crash reports when useful.
- A secure way to contact you for follow-up questions.

Never send real wallet secrets or production wallet data. This includes
mnemonic phrases, BIP39 passphrases, passwords or passcodes, spending keys,
viewing keys, addresses, transaction IDs, wallet databases, API credentials,
or any other information that could identify a wallet or its activity. If we
need additional artifacts, we will first agree on a safe way to provide them.

## What to expect

We aim to:

- Acknowledge a report within three business days.
- Provide an initial assessment within seven business days.
- Keep the reporter informed when the status materially changes.
- Coordinate disclosure after a fix and user guidance are ready.

Resolution time depends on severity, complexity, affected platforms, and the
need to coordinate a release. Please keep the report confidential until we
agree that it can be disclosed. We may ask you to delay publication when users
would otherwise remain exposed.

## Scope

Security reports may include, but are not limited to:

- Unauthorized access to wallet secrets, funds, or protected application data.
- Incorrect transaction construction, signing, broadcast, or wallet accounting
  that could put funds at risk.
- Authentication, password, passcode, biometric, Keychain, or secure-storage
  bypasses.
- Privacy leaks involving addresses, transactions, balances, network activity,
  or wallet-identifying metadata.
- Unsafe wallet database migrations, account deletion, reset, backup, or
  recovery behavior.
- Supply-chain, update, release-signing, or native platform vulnerabilities.
- Denial-of-service issues that can persistently prevent access to wallet
  functionality or funds.

Ordinary bugs without a security or privacy impact should be reported through
GitHub issues when issue creation is available.

## Research guidelines

- Use test wallets and testnet or regtest whenever possible.
- Do not access, modify, retain, or disclose another person's data or funds.
- Do not degrade third-party services or perform denial-of-service testing.
- Stop testing and contact us if you encounter real user data or secrets.
- Give us a reasonable opportunity to investigate and address the report before
  public disclosure.

Vizor does not currently operate a public bug-bounty program. Submission of a
report does not create an entitlement to payment or other compensation.
