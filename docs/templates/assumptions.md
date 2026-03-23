# Assumptions & Decisions

Judgment calls made during this feature's implementation. Each entry records a decision made without explicit user guidance. These surface in the PR body so reviewers see what was decided and can challenge or confirm.

## Format

- **[topic]**: [decision made] — [why this was chosen over alternatives]

## Example

- **Auth storage**: Chose JWT in httpOnly cookies over localStorage — XSS resistance outweighs the complexity of refresh token rotation
- **Error format**: Used `{error: string, code: number}` over RFC 7807 — simpler for MVP, can upgrade later

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
