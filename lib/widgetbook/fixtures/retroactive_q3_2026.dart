import '../../src/features/voting/voting_flow_models.dart';

// Public ballot snapshot retrieved 2026-09-21 from https://prod.vote-chain-primary.valargroup.org/shielded-vote/v1/rounds
// Round: 2cba66eb16c7581a1692cb0b033785da0131059f645a0d2fb4dc2a5131505e01
// Announcement: https://forum.zcashcommunity.com/t/57650
// Vote ends: 2026-09-29 20:00 UTC. Preserve the published ballot wording.
// Index omitted by protobuf JSON means zero (Accept), not unanswered.
// Widgetbook data only; no live voting server is contacted by the preview.
const retroactiveQ3Title = "Coinholder Retroactive Grants Q3";
const retroactiveQ3Intro =
    '37 proposals · Voting closes Sep 29, 2026 at 20:00 UTC.\n'
    'Simulation only — no votes are submitted. Both Reject choices are no votes.';
const _retroactiveOptions = <VotingOptionView>[
  VotingOptionView(index: 0, label: "Accept"),
  VotingOptionView(
    index: 1,
    label: "Reject - Do Not Support the Proposed Project",
  ),
  VotingOptionView(
    index: 2,
    label: "Reject - Would Reconsider in a Future Round at a Lower Amount",
  ),
  VotingOptionView(index: 3, label: "Abstain"),
];

const retroactiveQ3Proposals = <VotingProposalView>[
  VotingProposalView(
    id: 1,
    title: "Zcash Grants Hub — \$3,050 USD (Daniel Goh)",
    description:
        "Built and shipped an open-source unified grants platform aggregating ZCG, Coinholder Grants, and ZecHub DAO proposals into a single interface, with filtering/sorting, grant detail pages, analytics views, GitHub-based submission UX improvements, and ZecHub DAO participation guidance — completed April 2026.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-zcash-grants-hub-coinholder-program/55372",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 2,
    title: "ShieldedScan — \$4,060 USD (ShieldedScan)",
    description:
        "A free, no-tracker, cypherpunk-styled Zcash block explorer for blocks, transactions, cross-chain transfers, shielded pools, and network analytics (charts, tables, Sankey diagrams), plus a free keyless API.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-shieldedscan/57051",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 3,
    title:
        "ZecKit Post-M3 Stabilization and Developer Adoption — \$5,000 USD (Dapps over Apps)",
    description:
        "Open-source Zcash developer toolkit for a local Zebra regtest environment and reusable CI workflow. This retroactive request covers post-M3 work improving documentation, installability, reliability, and maintainability.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-zeckit-post-m3-stabilization-and-developer-adoption-work/56992",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 4,
    title: "zcashtocash via ZcashLabs — \$6,000 USD (ZcashLabs)",
    description:
        "zcashto.cash lets anyone exchange ZEC for fiat via 100+ geographies and 6 fiat apps (Cash App, Chime, Monzo, Revolut, Venmo, Zelle), non-custodial via the Peer protocol. Funded by the new ZcashLabs program managing Coinholder Retroactive Grants.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-zcash-labs-for-zcashto-cash/57047",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 5,
    title: "zec-ironwood-reconcile — \$8,250 USD (Steven Hert)",
    description:
        "Completed open-source Rust CLI that reconstructs Orchard and Ironwood value-pool changes from raw public Zcash block data and compares calculated balances with Zebra's reported balances. v1.0.0 release includes offline-verifiable evidence archives, deterministic reports, and reproduction instructions.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-zec-ironwood-reconcile-reproducible-orchard-ironwood-value-pool-reconciliation/56998",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 6,
    title: "Gleyo — \$9,081.20 USD (Gleyo)",
    description:
        "A Zcash-native community quest platform where members earn shielded ZEC rewards without upfront wallet setup — live in closed beta with 38 weekly active users, 33 mainnet transactions spanning the Ironwood upgrade, and upstream contributions to Nozy Wallet.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-gleyo/56977",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 7,
    title: "Self-Sovereign Zcash Testnet Faucet — \$9,280 USD (Jino Labs)",
    description:
        "A complete, self-hosted, self-sovereign Zcash testnet faucet (own Zebra node, Zallet wallet, Zaino indexer, solo miner) with shielded z-to-z payouts, an honest control plane, two upstream Crosslink bug-fix PRs, and the zsnap snapshot tool.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-self-sovereign-zcash-testnet-faucet/57002",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 8,
    title: "CyphZec.com — \$10,000 USD (Thomas Zarebczan)",
    description:
        "A free, no-account site for watching ZEC and CYPH: live prices, shielding and Ironwood stats, treasury, network stats, and an on-device portfolio.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-cyphzec-com/57035",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 9,
    title: "ZecLedger — \$10,000 USD (ZecLedger)",
    description:
        "A read-only shielded wallet accounting CLI (Unified Full Viewing Key, key never leaves device) producing cost-basis/gain-loss reports, payment reconciliation, privacy checks, and ZIP-321 payment request generation — verified against a real 108-transaction mainnet wallet — plus ZecLedger Web, a public network dashboard.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-zecledger/56969",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 10,
    title: "lightwalletd-rs — \$10,720 USD (jpgonzalezra)",
    description:
        "An independent Rust implementation of the Zcash light-client server (caching proxy between zebrad and shielded wallets), built June–August 2026, implementing all 20 CompactTxStreamer gRPC methods, public under MIT, CI-tested, and benchmarked against the Go reference implementation.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-lightwalletd-rs/56955",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 11,
    title: "Blindvault — \$17,000 USD (TIDJANI Walid)",
    description:
        "A privacy-preserving credential issuance service allowing applications to issue and verify one-time anonymous credentials without tracking users, using BLS12-381 blind signatures and DLEQ proofs. Serves as middleware for private airdrops, access controls, community votes, and similar apps.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-blindvault/56932",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 12,
    title: "Zallet RPC Parity Harness — \$20,000 USD (Creativesonchain)",
    description:
        "A completed standalone Rust CLI that compares results from operator-supplied zcashd and Zallet JSON-RPC endpoints and generates normalized JSON/Markdown reports. Includes a 24-entry comparison manifest, six result classifications, automated tests, mock-node E2E validation, CI, and an operator runbook.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-zallet-rpc-parity-harness/56993",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 13,
    title: "Zecmap — \$21,300 USD (Batuhan)",
    description:
        "A discovery platform (zecmap.com, Android, iOS) that lists Zcash-accepting businesses on an interactive map to drive real-world adoption of privacy-focused crypto payments.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-zecmap/56999",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 14,
    title: "Connaugh Zcash Videos — \$22,000 USD (Connaugh)",
    description:
        "Editing and re-architecting Zcash ecosystem video footage into short, single-argument films for audiences unlikely to watch long-form content — five films published 28 July–12 August 2026, reaching 45,811 impressions and 9,931 views.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-zkmarketer-videos/57031",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 15,
    title: "ZAP1 — \$28,000 USD (Frontier Compute)",
    description:
        "A Zcash application-layer attestation protocol built March–May 2026 using BLAKE2b Merkle commitments anchored to mainnet via Orchard shielded memos, with a Rust reference implementation, verification crate, JS/NPM package, and live public API.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-zap1-attestation-protocol-and-verification-tooling/55664",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 16,
    title: "ZecBooks — \$32,000 USD (SaneApps)",
    description:
        "A Mac-native, local-first bookkeeping layer for shielded Zcash: import a viewing key, classify income/change/expense, and export a scoped, expiring proof pack for an accountant. Cannot spend ZEC; not a merchant checkout product.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-zecbooks/56914",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 17,
    title: "CipherPay — \$35,000 USD (Atmosphere Labs (Kenbak))",
    description:
        "A non-custodial Zcash commerce platform built February–May 2026, shipping six MIT-licensed repositories covering payment processing, subscriptions, e-commerce plugins (Shopify, WooCommerce), event ticketing, AI agent payments (x402, MCP), and a point-of-sale interface — live with real merchants.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-cipherpay/55612",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 18,
    title: "Zafu Browser Extension — \$38,000 USD (Rotko Networks OU)",
    description:
        "A privacy-centric Chrome MV3 browser wallet built around Zcash (with Penumbra as a second chain), delivering sub-12-second client-side Halo2 proving via parallelized WASM, FROST t-of-n Orchard multisig, an air-gapped signer (Zigner), and a per-site identity SDK (ZID) — published as an open-source beta on the Chrome Web Store.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/zafu-wallet-retroactive-grant-application/55551",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 19,
    title: "Zapp — \$40,000 USD (Renee Chiu)",
    description:
        "A serverless, end-to-end encrypted P2P messenger fusing chat with shielded Zcash payments, enabling in-thread transactions and scan-and-pay. Live on Google Play, supporting fiat offramps across seven emerging-market rails without a phone number or central server.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-zapp/56937",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 20,
    title: "Open-Source Zcash Hardware-Wallet SDK — \$40,000 USD (wh00hw)",
    description:
        "The first portable, vendor-neutral, plain-C Orchard hardware wallet stack (~20,300 LOC across four MIT-licensed repos): a C11 crypto library, a Rust signing SDK, a Flipper Zero app, and an ESP32-S2 port — culminating in the first Orchard-shielded spend signed offline by a Flipper Zero, broadcast on mainnet 2026-03-30.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/application-for-coinholder-directed-retroactive-grants-program-q2-2026-open-source-zcash-hardware-wallet-sdk/55550",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 21,
    title: "Nozy Wallet — \$60,000 USD (Leonine DAO)",
    description:
        "A self-hosted, shielded-first Zcash wallet running on the user's own Zebrad/Zakura + lightwalletd, with local witnesses rather than a hosted light wallet — CLI, Desktop, and companion API on the same core.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/nozy-wallet-retroactive-grant/52417/26",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 22,
    title: "THORSwap/Metro — \$60,000 USD (THORSwap Labs)",
    description:
        "Integration of native ZEC cross-chain swaps into THORSwap and Metro wallet (launched October 2025), reporting \$50M+ in ZEC volume, a \$520K largest single swap, 24+ supported chains, and dual routing via Maya Protocol and NEAR Intents — no KYC, no custody, hardware wallet support.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-thorswap-metro/55675",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 23,
    title:
        "Expanding Zcash In Unstoppable Wallet — \$80,000 USD (Horizontal Systems - Unstoppable Wallet)",
    description:
        "Q1–Q3 2026 work covering expanded swap aggregation, Zcash wallet reliability improvements (server selection, transaction resend, address rotation, SDK migration), and full NU6.3/Ironwood migration support.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/expanding-zcash-in-unstoppable-wallet-liquidity-swaps-distribution-retroactive-grant/55529/3",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 24,
    title: "ZcashNames — \$122,400 USD (ZcashMe, Inc.)",
    description:
        "An on-chain Zcash naming system (ZNS) mapping human-readable names like alice.zcash to shielded addresses, delivered as a live beta web app, public explorer, docs portal, and developer SDK — framed as the trust-minimized successor to ZcashMe.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/coinholder-directed-retroactive-grants-program-q2-2026-now-accepting-proposals/55328/9",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 25,
    title:
        "Frontier Compute Zcash Security Research and Remediation Pack — \$136,250 USD (Frontier Compute LLC.)",
    description:
        "A completed security-research and remediation pack covering concrete security failures found in Zcash infrastructure and wallet code, responsibly disclosed and verified through to shipped remediation.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/call-for-proposals-coinholder-directed-retroactive-grants-program-q3/56885/29",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 26,
    title:
        "Zebra Critical Vulnerability Bug Bounty (CVE-2026-34202) — \$150,000 USD (robustfengbin)",
    description:
        "Bug bounty request for CVE-2026-34202, a Critical (CVSS 9.2) vulnerability allowing any unauthenticated peer to crash any Zebra node with a single P2P message, found via coverage-guided fuzzing, reported privately, and fixed in Zebra 4.3.0. No bounty was previously paid; ZCG's bounty program launched after this report and does not apply retroactively.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-cve-2026-34202-zebra-remote-denial-of-service-critical/57024",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 27,
    title:
        "Bonus Grant for Ironwood zk-SNARK Formal Verification — \$261,058 USD (Jason McGee)",
    description:
        "A bonus grant nomination (not a standard application) arguing Tachyon Foundation's \$738,942 application for leading Ironwood zk-SNARK formal verification underprices real absorbed costs and emergency-rate work; this adds \$261,058 to bring total recognition to \$1,000,000.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/project-tachyon-bonus-grant-for-ironwood-zk-snark-formal-verification/57021",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 28,
    title: "CipherScan — \$375,000 USD (Kenbak)",
    description:
        "A production Zcash block explorer and privacy-intelligence platform (cipherscan.app) covering completed, previously unfunded work: a custom Rust chain indexer, privacy-linkage analysis, wallet-fingerprint research, mining intelligence, an automated public data bot, and analytics tools.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-cipherscan/56997",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 29,
    title:
        "Temporary Detectable Unlimited mint and sell Exploit — \$400,000 USD (Alex Sol)",
    description:
        "Retroactive bounty request for multiple responsibly disclosed vulnerabilities across zcashd and Zebra, including a Sprout proof-verification bypass, a ZIP 209 turnstile-disabling duplicate-header bug, and consensus-divergence/node-crash findings composing into a temporary undetectable mint-and-sell exploit of counterfeit ZEC.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-temporary-detectable-unlimited-mint-and-sell-bug-bount/57033",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 30,
    title:
        "Five Critical Zebra Consensus Divergence Vulnerabilities — \$425,000 USD (sangsoo-osec)",
    description:
        "Net retroactive security award request for five responsibly disclosed Zebra vulnerabilities (each published by ZF as Critical) found via LLM-assisted differential review, validated, reported privately, and remediated; a separate \$100,000 third-party payment is disclosed and deducted from the request.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-five-critical-zebra-consensus-divergence-vulnerabilities/57034",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 31,
    title:
        "Zec.rocks (16 months of uptime for Zcash wallets) — \$584,992 USD (Zec.rocks)",
    description:
        "Infrastructure powering 16 months of uptime for every major Zcash wallet: global edge monitoring, on-call support, testing new software at scale, and deploying critical updates including the Orchard security response before it was published.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-16-months-of-uptime-for-zcash-wallets-zec-rocks/57048",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 32,
    title: "Ironwood external audit reimbursement — \$599,000 USD (ValarGroup)",
    description:
        "Retroactive reimbursement for \$599,000 of external security review costs incurred during the Ironwood incident response, engaging cryptography/blockchain auditors and AI tools to confirm no second soundness bug existed. Excludes any margin to Valargroup or costs to Valargroup team members.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-ironwood-external-audits/57032",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 33,
    title:
        "Ironwood zk-SNARK Formal Verification (Project Tachyon) — \$738,942 USD (Tachyon Foundation)",
    description:
        "After the Orchard counterfeiting vulnerability disclosure, Project Tachyon paused its roadmap to lead formal verification of Ironwood (NU6.3), implementing the new circuit, funding two independent verification firms, and producing machine-checked Lean proofs demonstrating no undetectable-counterfeiting vulnerabilities in the Ironwood zk-SNARK.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-ironwood-zk-snark-formal-verification-project-tachyon/57007",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 34,
    title:
        "Orchard Counterfeiting Vulnerability Bug Bounty — \$750,000 USD (Taylor Hornby)",
    description:
        "Bug bounty request for responsibly disclosing the Orchard counterfeiting vulnerability, which likely prevented the loss of \$2.3B USD worth of ZEC. Intended to incentivize future responsible disclosure of devastating counterfeiting vulnerabilities.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-orchard-counterfeiting-vulnerability-bug-bounty/57008",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 35,
    title:
        "Taylor Hornby - Bonus Grant for Orchard Counterfeiting Vulnerability Bug Bounty — \$750,000 USD (Jason McGee)",
    description:
        "A bonus grant nomination (not a standard application) arguing Taylor Hornby's \$750,000 bounty ask for the Orchard counterfeiting vulnerability (application #51) is far below industry norms for a finding of this severity; adds \$750,000 to bring the total to \$1,000,000.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/taylor-hornby-bonus-grant-for-orchard-counterfeiting-vulnerability-bug-bounty/57025",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 36,
    title: "ValarGroup Ironwood Work — \$1,203,000 USD (ValarGroup)",
    description:
        "Retroactive compensation for Valargroup's emergency development, integration, testing, infrastructure, and activation work for Ironwood (NU6.3): consensus rules, production full node, wallet/migration tooling, transaction hashing, hardware signing, miner compatibility, public test infrastructure, and mainnet operations on an under-two-month emergency schedule.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-valargroup-ironwood-work/57053",
    options: _retroactiveOptions,
  ),
  VotingProposalView(
    id: 37,
    title: "ZODL Q1 2026 Core Protocol Development — \$1,950,000 USD (ZODL)",
    description:
        "Amended retroactive grant covering January–June 2026, narrowed to three workstreams: remediation of 10 major vulnerabilities (including 4 critical), Zallet v0.1.0-alpha.4 delivery with integration test suite, and ZIP 2005 (Quantum Recoverability) reaching Proposed / ZIP 256 reaching Final.",
    forumUrl:
        "https://forum.zcashcommunity.com/t/retroactive-grant-application-zodl-q1-q2-2026-core-protocol-development/57027",
    options: _retroactiveOptions,
  ),
];
