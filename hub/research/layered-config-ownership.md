# Layered Configuration Ownership in Non-Commentable Formats

Research into how established tools solve the problem of sharing structured config files (JSON, YAML) between an upstream "hub" and downstream "projects", where the hub owns some keys and the project owns others, and upstream updates must flow without overwriting project-specific values.

**Core tension:** JSON has no comment delimiters, so text-based section markers (like `<!-- NODE-SPECIFIC-START -->` in markdown) are not available. Ownership boundaries must be expressed through file structure, key conventions, merge algorithms, or schema metadata.

---

## System-by-System Analysis

### 1. Helm (Kubernetes)

**Merge strategy:** Deep merge for maps/objects; full replacement for lists/arrays.

**Precedence order (highest to lowest):**
1. `--set` / `--set-string` / `--set-file` flags (rightmost wins)
2. `-f` / `--values` files (rightmost wins)
3. Parent chart's `values.yaml`
4. Subchart's `values.yaml`

**Ownership model:** File-level separation. The chart author provides `values.yaml` with defaults. The deployer provides override files (`-f myvalues.yaml`). The chart author owns the schema and defaults; the deployer owns the overrides. There is no formal key-level ownership declaration -- any key can be overridden.

**Conflict resolution:** Last-wins. Later files and flags override earlier ones. Within a single merge, maps are recursively merged (new keys added, existing keys overridden), but arrays are replaced wholesale.

**Null handling:** Setting a key to `null` deletes it from the merged result.

**Global values:** `Values.global` is a special namespace accessible from all subcharts, flowing downward from parent to children -- the reverse of normal value precedence.

**Gotchas and failure modes:**
- **List replacement is the #1 source of surprises.** If a chart defines a list of containers/ports/env vars, an override file must include the _entire_ list, not just the items to change. There is no way to append to or patch individual list items. This was filed as [helm/helm#3486](https://github.com/helm/helm/issues/3486) and remains a fundamental limitation.
- Deep merge means you cannot remove a nested key without explicitly setting it to `null`.
- The `mergeOverwrite` template function has a [known bug](https://github.com/helm/helm/issues/9591) where it cannot override a boolean to `false` (falsy values are treated as "unset").

**Architectural classification:** File-level separation + deep merge at key level.

---

### 2. Kustomize (Kubernetes)

**Merge strategy:** Two mechanisms -- Strategic Merge Patch (SMP) and JSON Patch (RFC 6902).

**Strategic Merge Patch:**
- Scalars: overlay replaces base
- Maps/objects: fields are recursively merged, overlay overrides base
- Lists: merge strategy is field-specific, defined in the Kubernetes API schema via `patchMergeKey` annotations. For example, `containers` merges by `name`, while `args` replaces the entire list.

**JSON Patch (RFC 6902):**
- Explicit operations: `add`, `remove`, `replace`, `move`, `copy`, `test`
- Path-based addressing (`/spec/containers/0/image`)
- No implicit merge -- every change is an explicit operation

**Ownership model:** Directory-level separation. `base/` contains the upstream/shared configuration. `overlays/{env}/` contains environment-specific patches. The base author owns the base; the overlay author owns the patches. Ownership is structural (directory hierarchy), not declared in the files themselves.

**Conflict resolution:** Overlay always wins over base. Patches are applied in the order listed in `kustomization.yaml`.

**Gotchas and failure modes:**
- SMP's list merge behavior is determined by Kubernetes API schema annotations, which are opaque to users. It is not obvious whether a given list field will merge-by-key or replace-entirely without consulting the API docs.
- JSON Patch uses positional array indices (`/spec/containers/0`), which break if the base changes array ordering.
- No built-in conflict detection between overlays -- if two overlays modify the same field, the last one applied wins silently.

**Architectural classification:** File-level separation (base/overlay directories) + key-level patching.

---

### 3. Docker Compose

**Merge strategy:** Type-dependent, three rules:

| Value type | Merge behavior |
|---|---|
| Scalars (strings, numbers, booleans) | Override: later file wins |
| Mappings (objects) | Deep merge: missing entries added, conflicting entries use later file |
| Sequences (lists) | Append: items accumulate (with uniqueness constraints for ports, volumes, secrets, configs) |

**Special attributes:** `command`, `entrypoint`, and `healthcheck.test` are always replaced, not merged, even though they could be lists.

**Ownership model:** Convention-based file separation. `docker-compose.yml` is the base (upstream/shared). `docker-compose.override.yml` is automatically loaded and merged on top. Additional files via `-f` flag.

**Conflict resolution:** Later files override scalars, merge maps, append lists.

**Escape hatches:**
- `!reset` custom YAML tag: removes an attribute entirely (set to type default/null)
- `!override` custom YAML tag: fully replaces an attribute, bypassing normal merge rules

These escape hatches are significant because they acknowledge that the default merge strategy is not always correct and provide explicit per-key override semantics.

**Gotchas and failure modes:**
- List appending can lead to duplicate entries if the same override file is applied multiple times.
- `!reset` and `!override` are custom YAML tags not supported by all YAML parsers. Tools like Dockge, podman-compose, and VS Code's Docker extension have had [compatibility issues](https://github.com/louislam/dockge/issues/448).
- No way to remove a single item from a list without `!override` on the entire list.
- When using `extends` with YAML anchors, `!override` and `!reset` [may be ignored](https://github.com/docker/compose/issues/11706).

**Architectural classification:** File-level separation + type-dependent key-level merge.

---

### 4. Terraform

**Merge strategy:** Whole-value replacement (NOT deep merge). Since Terraform 0.12, complex types (maps, objects, lists) are replaced entirely by higher-precedence sources, not merged.

**Precedence order (highest to lowest):**
1. `-var` flag (last one wins)
2. `-var-file` flag (last one wins)
3. `*.auto.tfvars` / `*.auto.tfvars.json` (lexical order, later wins)
4. `terraform.tfvars` / `terraform.tfvars.json`
5. `TF_VAR_*` environment variables
6. Variable `default` value in declaration

**Ownership model:** File-level separation by convention. Module authors define variables with defaults and descriptions. Module consumers provide values via `.tfvars` files, environment variables, or CLI flags. The module author owns the variable schema (type constraints, validation rules, descriptions). The consumer owns the values.

**Conflict resolution:** Strict last-wins at the variable level. No per-key merging within a variable's value.

**Breaking change history:** Before Terraform 0.12, map variables _were_ merged across sources. This was [intentionally changed](https://github.com/hashicorp/terraform/issues/8540) to replacement semantics. Teams that relied on partial map overrides had to restructure their configurations. The `merge()` function is available for explicit merging within HCL expressions.

**Gotchas and failure modes:**
- The 0.12 breaking change (maps replaced instead of merged) caught many teams off guard. Workflows built around partial map overrides in separate `.tfvars` files broke silently.
- No deep merge means you cannot override a single nested key in a complex object without restating the entire object.
- The `merge()` function only does shallow merge of the top-level keys. Deep merge requires custom logic using `for` expressions.

**Architectural classification:** File-level separation + whole-value replacement per variable.

---

### 5. ESLint Flat Config

**Merge strategy:** Deep merge with last-wins for conflicts. The config array is processed top-to-bottom; later entries override earlier ones.

**Merge behavior by property type:**
- `rules`: deep merged (key = rule name, value = severity + options). A later config can override a single rule without affecting others.
- `languageOptions.globals`: merged across matching configs
- `settings`: deep merged (nested objects combined)
- `plugins`: shallow merged (later wins for same plugin name)
- `files`/`ignores`: not merged (each config object has its own matching scope)

**Ownership model:** Array-position within a single file. Shared/upstream configs are typically imported and spread into the array first, followed by project-specific overrides. There is no file-level separation -- everything lives in `eslint.config.js`. Ownership is implicit in array ordering.

```js
export default [
  ...upstreamConfig,     // hub-owned rules
  {                      // project-owned overrides
    rules: { "no-console": "off" }
  }
];
```

**Conflict resolution:** Later array entries override earlier ones. Per-rule granularity.

**`extends` (added 2025):** `defineConfig()` supports an `extends` array, enabling composition similar to the old `.eslintrc` pattern but within flat config.

**Gotchas and failure modes:**
- Before the [deep merge fix](https://github.com/eslint/eslint/pull/18065) (merged Feb 2024), flat config had inconsistent merge behavior for nested objects vs. the old eslintrc system. Early adopters experienced rules disappearing.
- No directory-based cascade (unlike eslintrc). Monorepos must explicitly compose configs, which is more verbose but more predictable.
- Arrays within config objects are NOT deep-merged -- they are replaced. This is intentional to avoid unpredictable list concatenation.

**Architectural classification:** Single-file, array-position ownership + deep merge at key level.

---

### 6. Spring Boot

**Merge strategy:** Flat key-value replacement. Properties are not deep-merged; each property key is independently resolved by precedence. YAML structure is flattened to dot-notation keys (`server.port`, `spring.datasource.url`).

**Precedence order (highest to lowest, ~17 levels):**
1. Command-line arguments
2. JNDI attributes
3. Java System properties
4. OS environment variables
5. Profile-specific properties outside jar (`application-{profile}.yml`)
6. Profile-specific properties inside jar
7. Application properties outside jar (`application.yml`)
8. Application properties inside jar
9. `@PropertySource` annotations
10. Default properties (`SpringApplication.setDefaultProperties`)

**Ownership model:** Layer-based file separation. The application author owns the defaults inside the jar. Operations/deployment owns external config files, environment variables, and command-line arguments. Profile-specific files (`application-prod.yml`) bridge the two -- the author defines the profiles, but the deployer selects which profile activates.

**Conflict resolution:** Higher-precedence source wins for each individual property key. No merging of complex values.

**Spring Cloud Config Server:** Adds another layer -- a centralized config server that serves properties to multiple applications. This creates a hub-and-spoke model where the server owns shared properties and each application can override with local properties.

**Gotchas and failure modes:**
- The 17-level precedence hierarchy is a common source of confusion. Teams regularly struggle to determine which source a particular property came from.
- Profile activation order matters: if multiple profiles are active, the last profile in the list takes precedence for conflicting keys.
- YAML maps appear to be "deep merged" but are actually flattened to individual keys. This means you cannot override a single key in a nested YAML map without also inheriting all the defaults for sibling keys -- which can be surprising.

**Architectural classification:** File-level separation + flat key-value replacement (no deep merge).

---

### 7. Chrome/Firefox Managed Preferences

**Merge strategy:** Three-tier override with enforcement semantics.

**Precedence (highest to lowest):**
1. **Mandatory policies** (`/etc/opt/chrome/policies/managed/`) -- admin-set, user cannot change
2. **User preferences** -- user-set via the UI or `Preferences` file
3. **Recommended policies** (`/etc/opt/chrome/policies/recommended/`) -- admin-suggested defaults that users CAN override

**Ownership model:** Directory-level separation with semantic enforcement.
- `managed/` directory: admin owns these keys absolutely. The browser UI grays out the corresponding settings.
- `recommended/` directory: admin provides defaults, but the user can change them.
- User preferences: user owns these.

This is the only system studied that has a **three-tier ownership model** with both "enforced" and "suggested" upstream defaults.

**Firefox variant:** Uses `policies.json` with explicit `"locked": true` to distinguish mandatory vs. recommended. Also supports `autoconfig.cfg` for legacy preference management.

**Conflict resolution:**
- Mandatory policy > user preference > recommended policy (always, no exceptions)
- Within the same tier, Chrome uses `PolicyListMultipleSourceMergeList` and `PolicyDictionaryMultipleSourceMergeList` to control merging behavior for list and dict policies
- Security constraint: policies from different admin consoles cannot be merged (prevents cross-domain policy injection)

**Gotchas and failure modes:**
- Some policies are "recommended only" -- they silently do nothing if placed in `managed/`.
- Policy merge across sources (cloud + local + GPO) requires explicit opt-in via `CloudUserPolicyMerge`. This is off by default for security.
- JSON files in the policy directories must be valid JSON with no comments, no trailing commas. A single malformed file can prevent all policies from loading.

**Architectural classification:** Directory-level separation with per-key enforcement semantics.

---

### 8. Nix / NixOS Module System

**Merge strategy:** Type-driven merge with explicit priority annotations.

**Priority system (lower number = higher priority):**
- `mkForce`: priority 50 (highest practical priority)
- Direct assignment: priority 100
- `mkDefault`: priority 1000 (intended for module defaults)
- `mkOverride N`: custom priority N

**Merge behavior by option type:**

| Option type | Merge behavior |
|---|---|
| `bool`, `int`, `str`, `path` | No merge -- conflict at same priority is an error |
| `listOf t` | Concatenation across all definitions |
| `attrsOf t` | Attribute set union; values for same key merged recursively using type `t`'s merge function |
| `submodule` | Deep merge with per-option type-driven behavior |

**Ownership model:** Module-level separation with priority annotations. Base modules use `mkDefault` for their values. Higher-level modules (user config, machine-specific) use direct assignment (priority 100) or `mkForce` (priority 50). Ownership is expressed through the priority system, not through file structure.

**Conflict resolution:** Same-priority conflicts are errors (fail-fast), not silent overrides. This is unique among all systems studied. To resolve, one party must explicitly set a different priority.

**Order control:** `mkBefore` (priority 500) and `mkAfter` (priority 1500) for controlling merge order of list-type options, separate from value priority.

**`mkMerge`:** Allows a single module to return multiple option definition sets, merged as if from separate modules. Useful for conditional configuration.

**Gotchas and failure modes:**
- The priority system is counterintuitive (lower number = higher priority).
- `mkDefault` and `mkForce` work recursively on nested attribute sets, which can cause surprises when only part of a nested structure should be forced.
- Equal-priority conflicts produce error messages that can be confusing to diagnose in large configurations with many imported modules.
- No way to express "merge this map but replace this specific key" without using `mkForce` on the specific key.

**Architectural classification:** Module-level separation + type-driven merge + explicit priority annotations.

---

### 9. VS Code Settings

**Merge strategy:** Type-dependent:
- Primitive types (strings, numbers, booleans): override (higher-precedence scope wins)
- Array types: override (higher-precedence scope wins, NOT merged/appended)
- Object types: deep merge (keys from both scopes are combined)

**Precedence (highest to lowest):**
1. Folder settings (`.vscode/settings.json` in a folder of a multi-root workspace)
2. Workspace settings (`.vscode/settings.json` or `.code-workspace` file)
3. User settings (`~/Library/Application Support/Code/User/settings.json`)
4. Default settings (built into VS Code or extensions)

**Ownership model:** File-level separation by scope. VS Code owns defaults. The user owns user settings. The project/team owns workspace settings (committed to repo). Individual developers can override at folder level.

**Language-specific settings:** Scoped by language ID (e.g., `"[typescript]": {...}`). These are deep-merged across scopes, with higher-precedence scope winning for conflicts.

**Gotchas and failure modes:**
- The Object-merge behavior means that if workspace settings define `"editor.tokenColorCustomizations": { "comments": "#FF0000" }` and user settings define `"editor.tokenColorCustomizations": { "strings": "#00FF00" }`, both apply. This is powerful but can make it hard to determine the effective value of a complex object setting.
- Arrays are overridden, not merged. This means workspace `"files.exclude"` patterns replace user patterns entirely, which surprises users who expect additive behavior.
- No cascade within folder hierarchies (unlike `.editorconfig`). This is a [known feature request](https://github.com/microsoft/vscode/issues/111884).
- No concept of "locked" or "enforced" settings. Workspace settings can always override user settings, which means a malicious repo's `.vscode/settings.json` can change user behavior.

**Architectural classification:** File-level separation by scope + type-dependent key-level merge.

---

## Cross-System Comparison

### Merge Strategies

| System | Maps/Objects | Lists/Arrays | Scalars |
|---|---|---|---|
| **Helm** | Deep merge | Replace entirely | Last-wins |
| **Kustomize SMP** | Deep merge | Field-specific (schema-driven) | Last-wins |
| **Docker Compose** | Deep merge | Append (with uniqueness) | Last-wins |
| **Terraform** | Replace entirely | Replace entirely | Last-wins |
| **ESLint flat** | Deep merge | Replace entirely | Last-wins |
| **Spring Boot** | N/A (flattened to keys) | N/A | Last-wins per key |
| **Chrome policies** | Per-policy behavior | Opt-in merge | Tier-based |
| **NixOS** | Union + recursive merge | Concatenate | Error on conflict |
| **VS Code** | Deep merge | Replace entirely | Last-wins |

### Ownership Boundary Mechanisms

| System | Boundary mechanism | Granularity | Enforceability |
|---|---|---|---|
| **Helm** | Separate files (`-f`) | File-level | None (any key overridable) |
| **Kustomize** | Directory structure (base/overlay) | File-level | None |
| **Docker Compose** | Convention (`*.override.yml`) | File-level | None |
| **Terraform** | Variable declarations + `.tfvars` | Variable-level | Type constraints + validation rules |
| **ESLint** | Array position in config | Config-object-level | None |
| **Spring Boot** | File location + profile naming | File-level + key-level | None |
| **Chrome/Firefox** | `managed/` vs `recommended/` dirs | Directory-level (per-key) | Yes (mandatory vs. recommended) |
| **NixOS** | Priority annotations (`mkDefault`/`mkForce`) | Per-key | Yes (priority system) |
| **VS Code** | Scope hierarchy (user/workspace/folder) | File-level | None |

### Conflict Resolution Philosophy

| Philosophy | Systems | Tradeoff |
|---|---|---|
| **Silent last-wins** | Helm, Docker Compose, Terraform, ESLint, Spring Boot, VS Code | Simple, predictable, but conflicts are invisible |
| **Tier-based enforcement** | Chrome/Firefox | Admin intent is preserved, but complex to configure |
| **Fail-fast on conflict** | NixOS | Bugs are caught early, but requires explicit conflict resolution |
| **Schema-driven** | Kustomize SMP | Correct per-field behavior, but opaque to users |

---

## Patterns and Insights for the Scaffold Problem

### Pattern 1: Separate Files with Merge (Helm, Docker Compose, VS Code, Spring Boot)

The most common approach. The hub provides a base file; the project provides an override file. A merge algorithm combines them.

**Pros:** Simple mental model. Works with existing tools. Each party edits their own file.
**Cons:** Deep merge behavior varies wildly across implementations and is a constant source of bugs. List/array handling is the universal pain point. No way to express "hub owns this key" vs "project owns this key" within a single file.

**Applicability to scaffold:** This maps to a `settings.base.json` (hub-owned) + `settings.json` (project-owned) pattern, with a merge script that combines them. The merge script would need clear rules for each value type.

### Pattern 2: Schema-Declared Ownership (Terraform, Chrome Managed Preferences)

The schema itself declares which keys are hub-owned vs project-owned. Terraform does this through variable declarations (with defaults and type constraints). Chrome does this through the `managed/` vs `recommended/` directory split.

**Pros:** Ownership is explicit and machine-readable. Enforcement is possible.
**Cons:** Requires a schema definition language or directory convention. More infrastructure to maintain.

**Applicability to scaffold:** A `scaffold.schema.json` could declare each key's ownership (`"hub"`, `"node"`, `"merged"`), and the sync script would enforce it. This is the most robust approach but requires the most tooling.

### Pattern 3: Priority Annotations (NixOS)

Each value carries a priority tag. The merge algorithm uses priorities to resolve conflicts. Higher-priority values win; equal-priority conflicts are errors.

**Pros:** Fine-grained control. Fail-fast on ambiguous conflicts. No separate override file needed.
**Cons:** Priority system adds cognitive overhead. Does not work with standard JSON (requires a wrapper format or sidecar metadata).

**Applicability to scaffold:** Not directly applicable to JSON (no way to annotate values with priorities). Could be emulated with a sidecar lockfile that records per-key ownership.

### Pattern 4: Overlay Patches (Kustomize, JSON Patch RFC 6902)

Instead of merging two complete files, the project provides a patch document that describes changes to the hub's base file.

**Pros:** Precise control over every change. Supports add, remove, replace, move operations. Hub file is never modified.
**Cons:** Patches use path-based addressing that breaks if the base structure changes. More complex to author and review than simple key-value overrides. JSON Patch is verbose.

**Applicability to scaffold:** A `settings.patch.json` (JSON Patch format) that the project maintains, applied on top of the hub's `settings.json` during sync. Clean separation but poor ergonomics for simple overrides.

### Pattern 5: Key Namespace Convention (Helm global, Spring Boot profiles)

Certain key prefixes or namespaces are reserved for the hub, others for the project. No tooling enforces this -- it is a convention.

**Pros:** Zero tooling overhead. Works with any format.
**Cons:** Convention violations are silent. No enforcement. Namespace collisions are inevitable as the system grows.

**Applicability to scaffold:** Reserve top-level keys like `"hub"` and `"node"` in `scaffold.json`. Simple but fragile.

---

## Recommended Approach for the Scaffold

Based on this research, the approach that best fits the scaffold's constraints (JSON format, deterministic sync, hub/node ownership model, minimal tooling) is a **hybrid of Pattern 1 and Pattern 2**:

### Separate files with schema-declared ownership

**File structure:**
```
.claude/
  scaffold.json          # Merged result (generated, gitignored or git-tracked)
  scaffold.hub.json      # Hub-owned keys (synced from scaffold)
  scaffold.node.json     # Node-owned keys (project-specific, never synced)
  scaffold.schema.json   # Optional: declares key ownership and merge rules
```

**Merge algorithm:**
1. Start with `scaffold.hub.json` (hub defaults)
2. Deep-merge `scaffold.node.json` on top (node overrides)
3. For keys declared as `"hub-only"` in the schema, node values are ignored (hub wins)
4. For keys declared as `"node-only"`, hub values are ignored (node wins)
5. For keys declared as `"merged"`, apply type-dependent merge (objects: deep merge, arrays: configurable -- append or replace)
6. Write result to `scaffold.json`

**Why this approach:**
- **Deterministic:** The merge is a pure function of two input files. A shell script with `jq` can implement it.
- **Ownership is explicit:** Each party edits their own file. No conflicts during sync.
- **No format hacks:** No comments, annotations, or custom tags needed in JSON.
- **Graceful degradation:** If only `scaffold.json` exists (no split), the system works as today.
- **Precedent:** Docker Compose (`docker-compose.yml` + `docker-compose.override.yml`), Helm (`values.yaml` + `-f override.yaml`), and VS Code (user + workspace settings) all use this pattern successfully.

**Key lessons from the research:**
- **Lists are the universal gotcha.** Every system handles them differently and teams are surprised by the behavior. The scaffold should have an explicit, documented policy for each array-typed key (append vs. replace).
- **Silent last-wins hides bugs.** NixOS's fail-fast approach (error on same-priority conflicts) is better than silent override for a system where ownership matters. The merge script should warn when a node file overrides a hub-owned key.
- **Chrome's three-tier model is worth studying** for settings where the hub wants to provide defaults that projects CAN override vs. settings that projects MUST NOT override.
- **Terraform's 0.12 breaking change** (maps merged -> maps replaced) shows that changing merge semantics is extremely disruptive. The scaffold should document and lock its merge semantics from day one.
- **Docker Compose's `!reset` and `!override`** show that even well-designed merge systems eventually need per-key escape hatches. Plan for them.

---

## Alternative: The Simpler "Two-File Flat Merge" Approach

If schema-declared ownership is too much tooling for the current stage, a simpler variant:

**File structure:**
```
.claude/
  scaffold.json       # The actual config (what tools read)
  scaffold.lock       # Already exists -- extend with key ownership metadata
```

**Rules:**
1. Hub-owned keys are listed in the lockfile under a `"hub_keys"` array
2. Node-owned keys are everything else
3. During `scaffold-pull`: hub-owned keys are updated from the scaffold; node-owned keys are preserved
4. During `scaffold-push`: only hub-owned keys are candidates for pushing upstream
5. New keys from the hub are added with a notice; new keys from the node are node-owned by default

This is essentially what the markdown section-merge system does, but expressed as key-lists rather than text delimiters.

---

## Sources

- [Helm Values Files](https://helm.sh/docs/chart_template_guide/values_files/)
- [Helm Deep Merge Issue #3486](https://github.com/helm/helm/issues/3486)
- [Helm Deep Merge Issue #1620](https://github.com/helm/helm/issues/1620)
- [Helm Boolean Override Bug #9591](https://github.com/helm/helm/issues/9591)
- [Kustomize Strategic Merge Patches](https://www.fosstechnix.com/strategic-merge-patches-in-kubernetes-using-kustomize/)
- [Kustomize Patching Tutorial](https://glasskube.dev/blog/patching-with-kustomize/)
- [Docker Compose Merge Rules](https://docs.docker.com/reference/compose-file/merge/)
- [Docker Compose !reset and !override](https://docs.docker.com/compose/how-tos/multiple-compose-files/merge/)
- [Docker Compose !override Bug with extends #11706](https://github.com/docker/compose/issues/11706)
- [Terraform Variables and Precedence](https://developer.hashicorp.com/terraform/language/values/variables)
- [Terraform Map Merge Breaking Change #8540](https://github.com/hashicorp/terraform/issues/8540)
- [ESLint Flat Config Introduction](https://eslint.org/blog/2022/08/new-config-system-part-2/)
- [ESLint Deep Merge Fix #18065](https://github.com/eslint/eslint/pull/18065)
- [ESLint Flat Config Deep Merge Discussion #17689](https://github.com/eslint/eslint/discussions/17689)
- [ESLint Evolving Flat Config with Extends](https://eslint.org/blog/2025/03/flat-config-extends-define-config-global-ignores/)
- [Spring Boot Externalized Configuration](https://docs.spring.io/spring-boot/reference/features/external-config.html)
- [Chrome Enterprise Policy Management](https://support.google.com/chrome/a/answer/9037717)
- [Chrome Policy Precedence](https://cloud.google.com/blog/products/chrome-enterprise/understanding-policy-precedence-for-chrome-browser)
- [Chromium Policy Settings](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/docs/enterprise/add_new_policy.md)
- [NixOS Module System Deep Dive](https://nix.dev/tutorials/module-system/deep-dive.html)
- [NixOS Properties Wiki](https://nixos.wiki/wiki/NixOS:Properties)
- [NixOS mkDefault Discussion](https://discourse.nixos.org/t/what-does-mkdefault-do-exactly/9028)
- [VS Code Settings Documentation](https://code.visualstudio.com/docs/configure/settings)
- [VS Code Folder Settings Cascade Request #111884](https://github.com/microsoft/vscode/issues/111884)
- [JSON Merge Patch RFC 7396](https://datatracker.ietf.org/doc/html/rfc7396)
- [JSON Patch vs Merge Patch Comparison](https://erosb.github.io/json-patch-vs-merge-patch/)
- [Hierarchical Configuration Inheritance Pattern](https://configcraft.readthedocs.io/en/latest/01-Hierarchy-Configuration-Inheritance-Pattern/index.html)
- [JSON Schema readOnly Property](https://tour.json-schema.org/content/08-Annotating-JSON-Schemas/02-deprecated-readOnly-and-writeOnly)
