Diagnose and fix TLS certificate issues caused by Cloudflare WARP VPN.

1. Read `.claude/rules/tls-troubleshooting.md` for full context on the problem and remediation steps.

2. Run the diagnosis first:
   ```bash
   bash scripts/fix-cloudflare-certs.sh --check
   ```
   If the script doesn't exist in the current project, run the manual steps from the rule file.

3. If the combined bundle doesn't exist or is stale, build it:
   ```bash
   bash scripts/fix-cloudflare-certs.sh
   ```

4. Set the environment variables for the current session by running each export from the script output.

5. If the user reported a specific tool failing (pip, npm, git, cargo, etc.), retry the failing command with the env vars set.

6. Check if the user's `~/.zshrc` already has the Cloudflare cert exports. If not, suggest making them permanent:
   ```bash
   bash scripts/fix-cloudflare-certs.sh >> ~/.zshrc
   ```

7. Report what was fixed and what the user should verify.
