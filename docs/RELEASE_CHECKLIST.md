# Public Release Checklist

Run this checklist before creating a public GitHub repository or release.

- [ ] Run `pwsh -File tests/validate.ps1`.
- [ ] Run `bash tests/validate.sh` on a Bash capable environment.
- [ ] Run `pwsh -File tests/public-safety.ps1`.
- [ ] Review `git diff --check` and `git status`.
- [ ] Verify no private paths, names, tenant data, credentials, raw transcripts, or internal URLs are tracked.
- [ ] Review every extension ID and MCP template.
- [ ] Confirm MCP examples have no active secrets and use least privilege.
- [ ] Confirm README commands use placeholder repository URLs, not a private remote.
- [ ] Verify Windows, macOS, and Linux documentation is current.
- [ ] Configure the repository security contact and private vulnerability reporting before publishing.
- [ ] Add a real repository URL to README only after public repository creation.
