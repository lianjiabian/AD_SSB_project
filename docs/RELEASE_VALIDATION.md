# Local release validation

Date: 2026-10-22 21:46:36 CST

- Public file/pattern checks passed: no matched restricted data types, literal clinical IDs, workstation paths or credential/key signatures.
- PASS R parse: 311 files; Bash syntax: 12 files
- Python AST parsing passed; four legacy annotation-interface synthetic tests passed.
- Base-R synthetic LPKM/shared-GENE Ri/log-signal identities and the standalone synthetic example passed.
- Authorized private preflight passed for the fixed 261-person cohort and 261 BED inputs; no clinical values are included in this report.
- Twelve externalized review assertions matched the archived records. Statistical/model source matched the original after reversing privacy-only substitutions; counting/profile/clinical/enrichment core sources remained unchanged.
- Upstream execution plan and all seven downstream dry-run plans passed. An attempt to select the original analysis root as output was rejected.
- GitHub workflow YAML and read-only permissions were checked locally. GitHub Actions itself has not been run, and no upload was performed.
- Original source-file checksums remain unchanged. No patient-level recount, statistical fit, enrichment query or publication figure rerender was started.

These checks are not an end-to-end validation of recomputed participant findings or a legal/consent review. Full reproduction requires authorized inputs, the recorded environment and matching external database versions.

License status: intentionally unspecified at the author’s request. No DOI, remote URL, access approval or software author attribution has been fabricated.
