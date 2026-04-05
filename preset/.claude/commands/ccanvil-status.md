Show the current sync state between this project and the scaffold hub.

1. Run `./.ccanvil/scripts/ccanvil-sync.sh status` and present the output.
2. If any files show MODIFIED* (changed since last sync but not yet recorded), mention these are local changes that haven't been synced.
3. If the scaffold has new commits since last sync, suggest running `/ccanvil-pull` to review updates.
4. If there are SCAFFOLD-ONLY files, suggest running `/ccanvil-pull` to add them.
5. If there are LOCAL files, mention they can be promoted to the scaffold with `/ccanvil-push`.

Do NOT make any changes. Report only.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
