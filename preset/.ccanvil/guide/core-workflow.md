# The Core Workflow

Every feature follows this sequence. No exceptions.

```mermaid
flowchart TD
    DESC["1. DESCRIBE<br/><i>'I want the app to do X'</i>"]
    SPEC["2. SPEC<br/><i>spec-writer agent creates docs/spec.md<br/>with acceptance criteria</i>"]
    REV_SPEC{"Review spec?"}
    ADJ["Adjust criteria<br/><i>'Add a criterion for...'</i>"]
    PLAN["3. PLAN<br/><i>/plan creates docs/plan.md<br/>ordered TDD steps</i>"]
    REV_PLAN{"Review plan?"}
    BUILD["4. BUILD<br/><i>TDD cycles for each step</i>"]
    TDD_CYCLE["Red → Green → Refactor → Commit"]
    MORE{"More steps<br/>in plan?"}
    REVIEW["5. REVIEW<br/><i>/review spawns code-reviewer agent</i>"]
    REV_FB{"Issues found?"}
    FIX["Fix issues"]
    DONE["6. DONE<br/><i>/clear for next feature</i>"]

    DESC --> SPEC
    SPEC --> REV_SPEC
    REV_SPEC -->|"Looks good"| PLAN
    REV_SPEC -->|"Needs changes"| ADJ
    ADJ --> SPEC
    PLAN --> REV_PLAN
    REV_PLAN -->|"Looks good"| BUILD
    REV_PLAN -->|"Needs changes"| PLAN
    BUILD --> TDD_CYCLE
    TDD_CYCLE --> MORE
    MORE -->|"Yes"| BUILD
    MORE -->|"No"| REVIEW
    REVIEW --> REV_FB
    REV_FB -->|"PASS"| DONE
    REV_FB -->|"CONCERNS"| FIX
    FIX --> REVIEW

    style DESC fill:#e3f2fd,stroke:#333,stroke-width:2px
    style SPEC fill:#e8f4e8
    style PLAN fill:#e8f4e8
    style BUILD fill:#fff3e0
    style TDD_CYCLE fill:#fff3e0
    style REVIEW fill:#f3e5f5
    style DONE fill:#e3f2fd,stroke:#333,stroke-width:2px
    style REV_SPEC fill:#fffde7
    style REV_PLAN fill:#fffde7
    style REV_FB fill:#fffde7
```

## The TDD Cycle (Step 4 in detail)

Each step in the plan goes through this exact sequence. The TDD skill enforces it automatically.

```mermaid
flowchart TD
    START["Pick next acceptance criterion"]
    RED["RED: Write ONE failing test"]
    RUN1["Run test suite"]
    FAIL{"New test fails?"}
    REWRITE["Rewrite test —<br/>if it passes without<br/>implementation,<br/>the test is wrong"]
    COMMIT_TEST["Commit failing test"]
    GREEN["GREEN: Write MINIMUM code<br/>to make test pass"]
    RUN2["Run FULL test suite"]
    PASS{"ALL tests pass?"}
    FIX_IMPL["Fix implementation<br/><i>not the tests</i>"]
    COMMIT_IMPL["Commit implementation"]
    REFACTOR["REFACTOR: Improve code quality<br/><i>extract, rename, simplify</i>"]
    RUN3["Run tests after EACH change"]
    COMMIT_REF["Commit refactoring<br/><i>if non-trivial</i>"]
    NEXT{"More criteria?"}
    DONE["All criteria met"]

    START --> RED
    RED --> RUN1
    RUN1 --> FAIL
    FAIL -->|"Yes ✓"| COMMIT_TEST
    FAIL -->|"No — passes already"| REWRITE
    REWRITE --> RED
    COMMIT_TEST --> GREEN
    GREEN --> RUN2
    RUN2 --> PASS
    PASS -->|"Yes ✓"| COMMIT_IMPL
    PASS -->|"No"| FIX_IMPL
    FIX_IMPL --> RUN2
    COMMIT_IMPL --> REFACTOR
    REFACTOR --> RUN3
    RUN3 --> COMMIT_REF
    COMMIT_REF --> NEXT
    NEXT -->|"Yes"| START
    NEXT -->|"No"| DONE

    style RED fill:#ffcdd2
    style GREEN fill:#c8e6c9
    style REFACTOR fill:#e3f2fd
    style COMMIT_TEST fill:#e0e0e0
    style COMMIT_IMPL fill:#e0e0e0
    style COMMIT_REF fill:#e0e0e0
```

**Why TDD matters here:** Without tests, Claude's only verification is its own judgment — which degrades as context fills. At 80% accuracy per decision, 20 sequential decisions yield 1.2% overall success. Tests provide ground truth that survives context compaction and session resets.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
