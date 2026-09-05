# Runbook index

Operational documentation for the Z13 platform. Markdown only (§F.1).

| Doc | Purpose | SOW |
|---|---|---|
| `build.md` | How llama.cpp is built (Vulkan/RADV), pinned tag + flags | §D.5 |
| `rebuild.md` | Rebuild the whole platform on a fresh Ubuntu host (packaging/migration spec) | §A.3, §B.2 |
| `benchmarking.md` | §I.1 binding conditions + how to reproduce §I.2 numbers | §I.1–I.4 |
| `power-profiles.md` | The two profiles + measured §I.5 brackets + soak evidence | §I.5, §J.1 |
| `backup-restore.md` | restic two-repo + airplane-mode restore drill | §B.1 (M3) |
| `secrets.md` | age keyring + Owner-only entry at go-live | §0.4, §B.4 |

Status snapshot lives in `../vault/audits/`.
