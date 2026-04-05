# Contributing to [Project Name]

## Development Workflow

This project uses a specification-driven, test-first workflow:

1. **Spec** — Define acceptance criteria before coding
2. **Plan** — Break work into TDD steps
3. **Build** — Red-green-refactor cycle for each step
4. **Review** — Code review + security audit before merging

## Getting Started

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/my-feature`
3. Make changes following the workflow above
4. Run tests: `[test command]`
5. Run security audit: `bash scripts/security-audit.sh`
6. Commit with conventional format: `feat(scope): description`
7. Push and open a pull request

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

| Type | When |
|------|------|
| `feat` | New feature |
| `fix` | Bug fix |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or updating tests |
| `docs` | Documentation only |
| `chore` | Build process, tooling, dependencies |
| `perf` | Performance improvement |

Format: `type(scope): description`

Example: `feat(auth): add JWT refresh token rotation`

## Code Quality

- Follow existing patterns in the codebase
- All functions that can fail must have explicit error paths
- Write tests for new behavior
- Run the full test suite before submitting

## Security

- Never commit secrets, tokens, or credentials
- Use `~/` instead of absolute paths in configuration
- Run `bash scripts/security-audit.sh` before pushing
- See `.claude/rules/code-quality.md` for full guidelines
