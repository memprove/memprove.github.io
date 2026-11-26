# M3 v2 results

## claude-opus-5-5

| task | kind | none | claude-md | memprove |
|---|---|---|---|---|
| port | needs-memory | 0/5 | 5/5 | 5/5 |
| staging-url | needs-memory | 0/5 | 5/5 | 5/5 |
| ratelimit-docs | memory-outdated | 5/5 | 5/5 | 5/5 |
| free-shipping-faq | memory-outdated | 5/5 | 5/5 | 5/5 |
| refund-rounding | memory-outdated | 5/5 | 5/5 | 5/5 |
| partners-doc | memory-outdated | 5/5 | 5/5 | 5/5 |
| discount | control | 5/5 | 5/5 | 5/5 |
| zone-validation | control | 5/5 | 5/5 | 5/5 |
| **all needs-memory** | | 0/10 | 10/10 | 10/10 |
| **all memory-outdated** | | 20/20 | 20/20 | 20/20 |
| **all control** | | 10/10 | 10/10 | 10/10 |
| mean cost per trial (USD) | | 0.119 | 0.117 | 0.129 |
| mean turns per trial | | 4.3 | 4.2 | 4.4 |

| comparison | tasks | pairs | only first passed | only second passed | verdict |
|---|---|---|---|---|---|
| memprove vs claude-md | memory-outdated | 20 | 0 | 0 | no difference shown (p 1.0 / 1.0) |
| claude-md vs none | needs-memory | 10 | 10 | 0 | claude-md better (p 0.001 / 1.0) |
| memprove vs none | needs-memory | 10 | 10 | 0 | memprove better (p 0.001 / 1.0) |

## claude-haiku-5-5

| task | kind | none | claude-md | memprove |
|---|---|---|---|---|
| port | needs-memory | 0/5 | 5/5 | 5/5 |
| staging-url | needs-memory | 0/5 | 5/5 | 5/5 |
| ratelimit-docs | memory-outdated | 5/5 | 5/5 | 5/5 |
| free-shipping-faq | memory-outdated | 5/5 | 4/5 | 5/5 |
| refund-rounding | memory-outdated | 5/5 | 5/5 | 5/5 |
| partners-doc | memory-outdated | 5/5 | 5/5 | 5/5 |
| discount | control | 5/5 | 5/5 | 5/5 |
| zone-validation | control | 5/5 | 5/5 | 5/5 |
| **all needs-memory** | | 0/10 | 10/10 | 10/10 |
| **all memory-outdated** | | 20/20 | 19/20 | 20/20 |
| **all control** | | 10/10 | 10/10 | 10/10 |
| mean cost per trial (USD) | | 0.004 | 0.004 | 0.005 |
| mean turns per trial | | 6.2 | 6.0 | 6.6 |

| comparison | tasks | pairs | only first passed | only second passed | verdict |
|---|---|---|---|---|---|
| memprove vs claude-md | memory-outdated | 20 | 1 | 0 | no difference shown (p 0.5 / 1.0) |
| claude-md vs none | needs-memory | 10 | 10 | 0 | claude-md better (p 0.001 / 1.0) |
| memprove vs none | needs-memory | 10 | 10 | 0 | memprove better (p 0.001 / 1.0) |

Trials: 240; spent: 15.12 USD (Claude Code's own count, at API prices).
