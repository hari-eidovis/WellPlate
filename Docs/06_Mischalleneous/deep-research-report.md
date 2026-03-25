# Improving an Agentic iOS Development Workflow with OpenAI Codex

## Executive summary

This project already has a strong foundation for agentic development: a strict, seven-stage workflow with explicit artifacts, a hard approval gate, and an Xcode verification contract that names schemes/targets and concrete `xcodebuild` commands. fileciteturn0file0 The highest-leverage improvements are to (a) make Codex “workflow-aware” via first-class agent guidance and configuration, (b) harden the agent’s operational envelope (sandbox, approvals, execution policy, secrets), (c) mechanize reliability via tests + CI gates, and (d) measure impact with a lightweight metrics pipeline.

Key recommendations (with trade-offs called out later):

- Treat Codex as a controlled “automation worker,” not a co-author: **default to sandboxed, least-privilege operation**, and require **evidence-based verification** (build/test logs, diffs) before merging. Codex’s sandbox + approval model is designed for exactly this separation of concerns. citeturn9search2turn9search0turn11view0  
- Make your existing seven-stage process “native” to Codex by adding **`AGENTS.md`** (and optionally layered overrides), and by converting stage prompts into **re-usable prompt files** consumed by `codex exec` (non-interactive) and the IDE/terminal UI (interactive). citeturn12search3turn12search5turn11view0turn12search14  
- For CI/CD, add a **two-lane gate**:
  - **Lane A (deterministic)**: Xcode build/test + lint + static analysis + coverage thresholds.
  - **Lane B (agentic augmentation)**: Codex-driven PR review comments and/or targeted fix suggestions under constrained permissions. citeturn8view1turn9search11turn6search2turn5search33turn7search13  
- Address modern agent failure modes explicitly (hallucination, wrong-file edits, prompt injection, overscoped tool access): apply OWASP LLM guidance, restrict tool access, and isolate untrusted inputs from privileged tools—especially if you introduce MCP-connected tools. citeturn2search12turn2search4turn2search6turn2search14turn4view3  
- Treat licensing/compliance as a first-class gate: you own output per OpenAI terms, but you still must prevent accidental inclusion of third-party licensed snippets and must perform due diligence (scanning, provenance, review). citeturn1search0turn1search2turn3search8turn3search4turn3search0  

Assumptions (explicit per request): iOS version unspecified; UI framework (SwiftUI vs UIKit) unspecified; team size unspecified (recommendations include “solo dev” and “small team” variants).

## Baseline workflow and integration points with Xcode and CI

Your current workflow (as captured in repo docs) is:

- **Seven required stages**: `brainstorm → planner → plan-auditor → resolve-audit → checklist-preparer → implementer → tester`. fileciteturn0file0  
- **Artifact chain** stored under `Docs/` with consistent naming, with `resolve-audit` as a **hard stop requiring user decisions** when scope/architecture/criteria are impacted. fileciteturn0file0  
- **Tester contract** explicitly requires building the relevant schemes/targets (including the widget as a target build due to lack of a shared scheme) with specific `xcodebuild` commands. fileciteturn0file0  
- Repository context includes **multiple targets** (app + extensions + widget) and **shared schemes** for the app, monitor, and report. fileciteturn0file0  

This is already close to a “reviewable agentic pipeline” because it bakes in:
- explicit plans + audits (hallucination mitigation by design),
- explicit verification scope (prevents “tests passed” claims without evidence),
- and a human-controlled gate where it matters.

Where Codex integration typically breaks down in iOS repos (and where your workflow can be strengthened):

- **Tooling impedance mismatch**: iOS work is gated by Xcode build/test, code signing, simulator state, and scheme configuration. If Codex runs without a canonical command set, it will frequently “do the right thing in the wrong way” (e.g., running `swift test` when the source of truth is `xcodebuild test`). Apple explicitly supports both Xcode-driven and `xcodebuild`-driven testing; your workflow already standardizes on `xcodebuild`, which is ideal for automation. citeturn5search33turn5search3turn0file0  
- **Agent context drift**: if plans/checklists live in docs but the agent isn’t reliably loading them, you lose the biggest advantage of a staged workflow.
- **Reliability gaps**: if parts of the repo lack test bundles or schemes, CI can only do build checks; that’s acceptable, but it must be explicit and measured (compile-pass rate becomes a KPI).
- **Security posture**: without explicit sandbox/approval policies and secret handling, “agentic” becomes synonymous with “over-privileged process,” which is a known class of LLM-agent failures. Codex provides sandboxing, approval policies, and execution/rule controls to avoid this outcome. citeturn9search2turn9search0turn12search2turn11view0  

Concrete integration points in your existing workflow:

- Stages 1–5 are mostly **text artifacts** → perfect to drive via **Codex prompts + stable templates**, and to store as “project memory” in the repo.
- Stages 6–7 are **code + verification** → perfect to drive via **Codex’s local execution loop** (read/edit/run) while locked into **repo-local sandboxes** and a known command allowlist. Codex’s non-interactive mode (`codex exec`) is specifically meant for scripted/CI-style runs. citeturn12search1turn11view0turn14view2  

## Recommended agent architecture and workflow design

### Architecture options and trade-offs

| Option | What it looks like | Strengths | Weaknesses | Best fit |
|---|---|---|---|---|
| Codex CLI + repo artifacts (single-operator) | You run Codex locally, the “memory” is your `Docs/` artifacts + `AGENTS.md`, and stage prompts are standardized. | Minimal infra; fast iteration; leverages Codex OS sandbox + approvals. citeturn9search2turn11view0turn12search3 | Harder to standardize across a team; weaker centralized auditing unless enforced via CI. | Solo iOS dev / early-stage repo. |
| Agents SDK orchestrator + Codex MCP server | Use OpenAI Agents SDK to orchestrate role agents and call Codex via MCP tools; store traces. | Deterministic orchestration, explicit handoffs, and reviewable traces. citeturn8view0turn2search6 | More moving parts; MCP introduces additional security surface; requires careful tool scoping. citeturn2search4turn2search6turn4view3 | Small team, repeated workflow, need “audit trails.” |
| Codex Cloud tasks + PR-based workflow | Delegate tasks to Codex’s cloud environment, review diffs, create PRs; optionally sync locally and run Xcode builds. | Isolated execution environments; verifiable evidence with logs/tests; parallel tasks. citeturn8view3turn12search22 | Cloud setup + governance; may not perfectly mirror local Xcode toolchain; requires extra care for secrets and repo access. citeturn12search22turn4view3 | Larger changes, parallelization, org needs. |

A pragmatic recommendation for your setup: **start with “Codex CLI + repo artifacts” as the default**, add **CI gating + Codex PR review augmentation**, and only adopt **Agents SDK orchestration** once you’ve stabilized prompts, guards, and build/test determinism.

### Make your workflow “native” to Codex via dedicated agent guidance

Codex explicitly supports repository guidance via `AGENTS.md` and layered overrides, with discovery/precedence rules and a size cap. citeturn12search3turn12search5 The cloud Codex agent is also designed to follow repository-provided guidance. citeturn8view3turn12search19

Recommended `AGENTS.md` content for your repo should encode:

- The **seven-stage contract** and paths (pointing to your existing `.codex/WORKFLOW.md`).
- Canonical **Xcode verification commands** (the exact `xcodebuild` commands you already require).
- Rules about dependency changes, test expectations, and when the agent must stop and ask.

Example `AGENTS.md` (repo root):

```markdown
# AGENTS.md

## Workflow contract (do not skip)
This repo follows a strict 7-stage workflow for feature work:
- brainstorm → planner → plan-auditor → resolve-audit → checklist-preparer → implementer → tester
Reference: .codex/WORKFLOW.md

Hard gate: resolve-audit must obtain user decisions for scope/architecture/tradeoffs/acceptance criteria.

## Xcode project context
Project: WellPlate.xcodeproj
Targets: WellPlate, ScreenTimeMonitor, ScreenTimeReport, WellPlateWidget

## Canonical verification commands
Use these exact commands for build verification (generic iOS Simulator destination):

xcodebuild -project WellPlate.xcodeproj -scheme WellPlate -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeMonitor -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -scheme ScreenTimeReport -destination 'generic/platform=iOS Simulator' build
xcodebuild -project WellPlate.xcodeproj -target WellPlateWidget -destination 'generic/platform=iOS Simulator' build

## Safety + scope
- Default to sandboxed operation; do not use full filesystem access.
- Do not change code signing, entitlements, or provisioning without explicit instruction.
- Ask before adding new third-party dependencies.
- Never claim tests passed unless you ran xcodebuild test and can name the exact scheme/test plan.
```

This aligns with how Codex discovers and applies agent instructions. citeturn12search3turn12search5turn12search20  

### Tool access, sandboxing, and execution policy as first-class controls

Codex’s security model has two complementary layers:

- **Sandbox mode** = what the agent can do technically (filesystem/network boundaries).
- **Approval policy** = when the agent must stop and ask before executing actions. citeturn9search0turn9search2turn11view0  

Codex supports:
- `--sandbox` values `read-only | workspace-write | danger-full-access` and `--ask-for-approval` values like `on-request | never | untrusted`. citeturn11view0turn14view2  
- A “shortcut” `--full-auto` that maps to workspace-write plus on-request approvals. citeturn11view0turn14view2  
- A non-interactive runner `codex exec` (stable) with JSONL output for automation and an output schema option for stricter downstream validation. citeturn14view2turn14view1turn11view0  
- Execution rules (`codex execpolicy`) to test and enforce command policies. citeturn12search2turn12search6turn11view0  

Recommended “default posture” by environment:

| Environment | Sandbox | Approval policy | Network | Notes |
|---|---|---:|---:|---|
| Local dev (interactive) | `workspace-write` | `on-request` | Off by default | Minimizes friction while retaining a “human consent” escape hatch. citeturn11view0turn9search2 |
| Planning/audit-only runs | `read-only` | `untrusted` (or `on-request`) | Off | Forces the agent to focus on analysis, not edits. citeturn11view0turn9search2 |
| CI automation (non-interactive) | `workspace-write` | `never` **only if** execpolicy is strict | Usually off; enable only in controlled jobs | Avoid `--yolo` except in externally hardened runners. citeturn11view0turn12search2turn9search2 |

A critical nuance: sandboxing applies not just to file edits but also to spawned commands (`git`, test runners, package managers). citeturn9search2 That’s exactly what you want for safe agentic automation.

### Where to put “memory” and how to prevent drift

Treat “memory” as a tiered system:

- **Tier 0 (source of truth)**: your structured artifacts (`Docs/...` specs, audits, checklists) and `AGENTS.md`. This is durable, reviewable, and versioned. fileciteturn0file0  
- **Tier 1 (session state)**: current working tree diff + build/test outputs. Codex can surface evidence, and `codex exec --json` allows capturing events. citeturn8view3turn14view1turn11view0  
- **Tier 2 (optional retrieval)**: if the repo is large, add a local indexer (ripgrep + curated file sets) rather than a vector store until you can justify the complexity; if you do use retrieval tools (MCP), treat them as untrusted inputs for a privileged agent (see security section). citeturn2search4turn2search6turn4view3  

image_group{"layout":"carousel","aspect_ratio":"16:9","query":["OpenAI Codex CLI terminal screenshot","AGENTS.md file example github","Xcode Cloud workflow screenshot","Xcode source editor extension XcodeKit"] ,"num_per_query":1}

### Mermaid flowchart of the improved workflow

```mermaid
flowchart TD
  A[Developer request / ticket] --> B[brainstorm (Codex read-only)]
  B --> C[planner (Codex read-only + writes spec artifact)]
  C --> D[plan-auditor (Codex read-only + writes audit)]
  D --> E{resolve-audit gate}
  E -->|user decisions required| E1[Ask developer questions]
  E1 --> E
  E -->|approved| F[checklist-preparer (writes checklist)]
  F --> G[implementer (workspace-write + approvals on-request)]
  G --> H[local verification: xcodebuild build/test + lint]
  H --> I{CI gates pass?}
  I -->|no| G
  I -->|yes| J[PR opened]
  J --> K[Codex PR review augmentation (CI, least privilege)]
  K --> L{Merge approved?}
  L -->|no| G
  L -->|yes| M[release pipeline: TestFlight / phased release]
```

This preserves your existing human-controlled gate while adding deterministic verification and optional CI-driven agent augmentation. fileciteturn0file0  

## Security, secrets management, data privacy, and compliance

### Secure API usage and secrets management

At minimum, treat Codex credentials like production credentials:

- Use **unique API keys per person** and **never ship keys in client-side code** (including mobile apps). citeturn10search0turn10search4  
- For CI systems, use first-party secret stores:
  - **GitHub Actions secrets** for keys and tokens, and mask any additional sensitive values in logs. citeturn6search0turn6search12  
  - **Xcode Cloud secret environment variables** for build scripts (encrypted, redacted in logs, only available in ephemeral build environments). citeturn1search11turn1search33turn1search19  

If your repo ever introduces runtime use of OpenAI services in the iOS app itself (not stated, but common), never embed the key on-device; route requests through your backend. citeturn10search0turn10search4  

### Codex sandboxing + approval policies as a security boundary

Codex’s sandbox/approvals system is explicitly designed to keep the agent operating within enforceable limits, with network disabled by default and “stop-and-ask” behaviors controlled by the approval policy. citeturn9search2turn9search0turn11view0  

Actions to take:

- Commit **project-scoped Codex config** under `.codex/config.toml` (and document that developers should “trust” the project so it loads). Project-scoped configs are a supported concept in Codex config layering. citeturn9search1turn9search4  
- Add an **execution policy rule file** (stored in a known path) that allows only the command set you want agents to run without approval (e.g., `xcodebuild`, `swiftlint`, `git diff`, etc.). Codex provides `codex execpolicy check` to test rule application. citeturn12search2turn12search6  

### Data privacy and retention for source code and user data

When using the OpenAI API, OpenAI states that API data is not used to train models by default, and that abuse monitoring logs may be retained for up to 30 days unless legally required otherwise. citeturn4view3turn0search1  
If you need stronger controls, OpenAI describes “Modified Abuse Monitoring” and “Zero Data Retention” as approval-based offerings, and also documents data residency. citeturn4view3turn0search1  

Important boundary: if you connect Codex to external tools via MCP, OpenAI notes that data sent to MCP servers is subject to those third-party servers’ retention policies. citeturn4view3turn2search6  

Practical privacy defaults for iOS repos:

- **Minimize context**: send only the files needed; avoid copying crash logs/analytics with user identifiers.  
- **Redaction**: strip tokens, signing materials, and user PII from prompts and artifacts.  
- **Split security domains**: if you want Codex to analyze user data flows, provide the code but not real production user datasets.

### Compliance and licensing for generated code

There are two distinct issues: contractual ownership vs. third-party rights.

- OpenAI’s Terms of Use explicitly state that you retain ownership of input and own the output (subject to law). citeturn1search0turn1search13  
- OpenAI’s Services Agreement emphasizes that the customer is responsible for evaluating output accuracy/appropriateness. citeturn1search2  
- Separately, research shows code LLMs can memorize training data and reproduce fragments, which can create license compliance risks (even absent intent). citeturn3search4turn3search8  

Recommended compliance controls:

- Add a “Generated code hygiene” policy to `AGENTS.md`:
  - no copying large blocks from unknown sources,
  - include attributions when you intentionally adapt known licensed code,
  - require a license scan on new third-party source inclusions.
- Run automated scans where possible (e.g., dependency license reporting; secret scanning; and (for Swift) CodeQL security suites if you have GitHub Advanced Security). CodeQL explicitly supports Swift analysis on macOS and provides Swift query suites including `security-extended`. citeturn6search2turn6search8turn6search5  
- Track provenance of agent changes: require that PR descriptions link back to the spec/audit/checklist artifacts and include the exact build/test commands executed.

For broader legal context on training/copyright debates (useful for internal governance), the U.S. Copyright Office has published multi-part AI reports, including training-focused analysis. citeturn3search0  

## Reliability, hallucination mitigation, and testing strategy

### Common failure modes in agentic iOS code changes

In iOS projects, the most expensive agent failures are usually not “obviously wrong code,” but workflow mismatches:

- **Compiles locally but fails in CI** due to scheme differences, missing shared schemes, simulator destinations, or code signing assumptions.
- **API hallucinations**: calling non-existent SDK symbols or using APIs gated by a higher iOS version than you ship.
- **Cross-target breakage**: app builds but extensions/widgets break (your tester contract already anticipates this). fileciteturn0file0  
- **Silent semantic regressions**: concurrency issues, state handling, and data model migrations that compile but fail at runtime.

Mitigations that map well to Codex capabilities:

- **Force evidence-based completion**: Codex is designed to read/edit/run in a loop, and cloud Codex can provide evidence via logs and test outputs for traceability. citeturn8view3turn12search1  
- **Constrain actions with sandbox/execution policy** so the agent cannot “fix” problems by widening privileges (e.g., using “danger-full-access”). citeturn9search2turn12search2turn11view0  
- **Keep your existing staged workflow**: planning + auditing before implementation is an effective structure for hallucination resistance.

### Prompt injection and “confused deputy” risks for coding agents

If you adopt MCP tooling (Agents SDK orchestration, external retrieval, GitHub API tools, etc.), you must model prompt injection as a first-class threat:

- OWASP categorizes prompt injection and sensitive information disclosure as top LLM risks; these become more severe when agents have tool permissions. citeturn2search12turn2search16  
- Recent academic work shows tool-using agents can be manipulated via external sources into wrong tool selection and unintended actions. citeturn2search4turn2search8  
- MCP-specific security guidance explicitly calls out prompt injection and emphasizes controls and authorization. citeturn2search6turn2search2  

Practical mitigations:

- Do **not** allow untrusted content (PR comments, issue bodies, HTML, external docs) to flow directly into a privileged “code-editing” agent without a guard step.
- Use a two-agent pattern where:
  - Agent A (untrusted input interpreter) has **no write/tool permissions** and produces a sanitized task spec.
  - Agent B (implementer) operates only on sanitized specs inside sandboxed boundaries.
- Prefer allowlisted commands (execpolicy) and low-privilege tokens for any CI-run agent.

### Testing strategy for iOS agentic development

Given iOS version and UI framework are unspecified, the best approach is a layered test pyramid with “build is always required” as the floor.

- **Build verification (required)**: Always run `xcodebuild` builds for affected schemes/targets; your workflow already names required coverage. fileciteturn0file0  
- **Unit tests**:
  - Use **Swift Testing** if you’re on Xcode 16+ (it’s intended to coexist with XCTest for incremental migration). citeturn13view0turn2search31turn2search3  
  - Use **XCTest** for established iOS unit/UI/performance tests. citeturn5search3turn13view0  
- **Integration tests**: (networking, persistence, data flow) built around dependency injection and mocked I/O.
- **Property-based tests**: use SwiftCheck (or a Swift Testing–native property-based library if you adopt one) to flush out boundary cases. SwiftCheck explicitly generates randomized data for property testing. citeturn7search2turn7search18  
- **Fuzzing (selective)**: fuzz parsers/decoders and other pure functions. LLVM libFuzzer provides in-process, coverage-guided fuzzing; Swift has documented libFuzzer integration in the compiler/toolchain docs. citeturn3search3turn3search11turn3search19  
- **Sanitizers**: Run Address/Thread/UB sanitizers in debug CI lanes where feasible; Apple documents these as early detection tools for memory/thread/crash issues. citeturn7search0turn7search20  

### Testing checklist and sample test cases

Testing checklist (agent-friendly; copy into your checklist-preparer stage):

- Verify affected targets:
  - [ ] `WellPlate` scheme build (if app code touched)
  - [ ] `ScreenTimeMonitor` scheme build (if monitor/shared dependencies touched)
  - [ ] `ScreenTimeReport` scheme build (if report/shared dependencies touched)
  - [ ] `WellPlateWidget` target build (if widget/shared widget data touched)
- If tests exist and are wired:
  - [ ] `xcodebuild test` for relevant scheme/test plan
  - [ ] Capture `.xcresult` bundle; extract failures and coverage deltas (optional)
- Quality gates:
  - [ ] SwiftLint (or equivalent) clean
  - [ ] Static analysis lane (Xcode analyze / CodeQL Swift)
  - [ ] Sanitizer lane (select targets)
- Regression:
  - [ ] At least one “golden path” manual check for core screens / flows affected

Sample unit test (Swift Testing; good for pure logic):

```swift
import Testing

struct NutritionMathTests {
  @Test
  func macros_sum_is_consistent() {
    let items: [(p: Int, c: Int, f: Int)] = [(10, 20, 5), (0, 15, 10)]
    let total = items.reduce((p: 0, c: 0, f: 0)) { acc, x in
      (p: acc.p + x.p, c: acc.c + x.c, f: acc.f + x.f)
    }

    #expect(total.p == 10)
    #expect(total.c == 35)
    #expect(total.f == 15)
  }
}
```

Swift Testing is supported in modern Xcode and is designed to run alongside XCTest during migration. citeturn13view0turn2search31turn2search3  

Sample property-based test (SwiftCheck + XCTest):

```swift
import XCTest
import SwiftCheck

final class NormalizationPropertyTests: XCTestCase {
  func test_normalize_is_idempotent() {
    property("normalize(normalize(x)) == normalize(x)") <- forAll { (s: String) in
      let once = normalize(s)
      let twice = normalize(once)
      return once == twice
    }
  }
}

// Example function under test
private func normalize(_ s: String) -> String {
  s.trimmingCharacters(in: .whitespacesAndNewlines)
   .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}
```

SwiftCheck’s stated purpose is automatically generating random data for property testing. citeturn7search2turn5search3  

Sample fuzz harness (Swift + libFuzzer) for a parser/decoder boundary:

```swift
import Foundation

@_cdecl("LLVMFuzzerTestOneInput")
public func LLVMFuzzerTestOneInput(_ data: UnsafePointer<UInt8>, _ size: Int) -> Int32 {
  let bytes = Data(bytes: data, count: size)

  // Example: fuzz a JSON decoder that should never crash
  do {
    _ = try JSONSerialization.jsonObject(with: bytes, options: [])
  } catch {
    // expected for most random inputs
  }
  return 0
}
```

This leverages libFuzzer’s model of feeding fuzzed inputs to a target function; Swift’s compiler repo documents libFuzzer integration, and LLVM documents libFuzzer’s coverage-guided design. citeturn3search3turn3search11turn3search19  

## CI/CD automation, gating, and developer UX

### CI/CD gating architecture for iOS + agents

The goal is: **agents can propose changes quickly, but only deterministic gates can merge them**.

Recommended gate stack:

- **Pre-commit (local, fast)**:
  - format/lint (SwiftLint),
  - compile-only “cheap” build for primary scheme,
  - optional “Codex review working tree” (`/review`) before commit. citeturn8view1turn7search3  

- **PR checks (CI, required)**:
  - Build matrix for app + extensions (+ widget build)
  - Unit tests + coverage (when present)
  - Static analysis lane:
    - Xcode “Analyze” action is supported in Xcode Cloud and runs `xcodebuild analyze`. citeturn7search13turn7search9  
    - CodeQL Swift security scanning if enabled. citeturn6search10turn6search8  
  - Optional sanitizers lane for concurrency/memory regressions. citeturn7search0turn7search20  

- **PR review augmentation (agentic, non-blocking at first)**:
  - Use Codex GitHub Action to post review comments with strict permissions, or use Codex’s workflow guidance for PR review. citeturn9search11turn8view1turn8view2  

- **Release gating / canary**:
  - TestFlight internal/external testing. citeturn3search2turn3search14turn3search6turn3search22  
  - Phased release for production rollout. citeturn3search18  

### Concrete implementation steps and scripts

#### Codex configuration and prompt scaffolding

1) Add repo-level Codex config under `.codex/config.toml` (safe defaults, plus a “CI profile”):

```toml
# .codex/config.toml
# Keep defaults safe; developers can override locally if needed.
model = "gpt-5-codex"

# Default: safe autonomy
sandbox_mode = "workspace-write"
approval_policy = "on-request"

# Optional: define profiles for different tasks
[profiles.readonly_audit]
sandbox_mode = "read-only"
approval_policy = "untrusted"

[profiles.ci_bot]
sandbox_mode = "workspace-write"
approval_policy = "never"
```

Codex supports user config and project-scoped overrides, with documented precedence and the notion of “trusted projects.” citeturn9search4turn9search1  

2) Add stage prompt templates as repo files (so CI and teammates use the same canonical prompts). Since `codex exec` can read the prompt from **stdin** by passing `-` as the prompt, you can store prompts in files and pipe them. citeturn14view1turn14view2  

Example: `.codex/prompts/implementer.md`:

```markdown
You are the implementer stage.
Inputs:
- Approved checklist: Docs/02_Planning/Specs/CHECKLIST-YYMMDD-[feature].md
Rules:
- Implement checklist items in order.
- Do not expand scope or change acceptance criteria.
- After changes, run the required xcodebuild verification for affected targets.
Output:
- Completed items, blocked items, files changed, verification performed (commands + results).
```

3) A small runner script to execute a stage non-interactively:

```bash
#!/usr/bin/env bash
set -euo pipefail

STAGE_PROMPT_FILE="${1:?path to prompt file}"
WORKDIR="${2:-.}"

# Use a stable, review-friendly mode: sandboxed, approvals on-request
# For CI automation, swap to profile ci_bot and ensure execpolicy is strict.
cd "$WORKDIR"
codex exec - \
  --profile readonly_audit \
  --json \
  < "$STAGE_PROMPT_FILE"
```

This uses `codex exec` (stable) and JSON events for logging. citeturn14view2turn14view1turn11view0  

#### iOS build verification script aligned with your repo’s tester contract

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT="WellPlate.xcodeproj"
DEST="generic/platform=iOS Simulator"

xcodebuild -project "$PROJECT" -scheme WellPlate -destination "$DEST" build
xcodebuild -project "$PROJECT" -scheme ScreenTimeMonitor -destination "$DEST" build
xcodebuild -project "$PROJECT" -scheme ScreenTimeReport -destination "$DEST" build
xcodebuild -project "$PROJECT" -target WellPlateWidget -destination "$DEST" build
```

These are exactly the preferred commands stated in your workflow contract. fileciteturn0file0  

#### GitHub Actions PR workflow skeleton (build + lint + CodeQL + Codex review comment)

```yaml
name: ios-pr-gates

on:
  pull_request:

jobs:
  build-and-test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode (example)
        run: sudo xcode-select -s /Applications/Xcode.app

      - name: Build required schemes/targets
        run: ./scripts/ci/build_all.sh

      - name: SwiftLint (if installed)
        run: swiftlint lint --strict

  codeql-swift:
    runs-on: macos-latest
    permissions:
      security-events: write
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: github/codeql-action/init@v3
        with:
          languages: swift
          queries: security-extended
      - uses: github/codeql-action/autobuild@v3
      - uses: github/codeql-action/analyze@v3

  codex-pr-review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v5
      - uses: openai/codex-action@v1
        with:
          prompt: |
            Review this PR for:
            - correctness (Swift/Xcode)
            - cross-target impact (app + extensions + widget)
            - security/privacy issues
            Return concise actionable comments.
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```

Rationale + primary-source support:

- `openai/codex-action` is designed to run Codex in GitHub Actions with controlled privileges and expects the API key to come from GitHub Secrets. citeturn8view2turn9search11turn6search0  
- GitHub documents secret usage and masking. citeturn6search0turn6search12  
- CodeQL supports Swift and has Swift query suites including `security-extended`. citeturn6search2turn6search8turn6search10  

#### Xcode Cloud integration points

If you use Xcode Cloud, use it for the deterministic lane:

- Configure actions to build/test/analyze and use secret environment variables for any required integrations. citeturn1search11turn1search33turn1search19  
- Xcode Cloud analyze action runs `xcodebuild analyze`. citeturn7search13  
- Document shared environment variables and workflows. citeturn1search23turn1search15  

### Developer UX recommendations

Xcode now supports leveraging coding models/agents and interacting with an LLM “of your choice,” including agents from OpenAI, directly in the source editor; this creates an obvious UX path for inline suggestions and “in-editor” Codex workflows. citeturn13view0  

If you want custom UX beyond what Xcode exposes:

- Build an internal macOS app with an Xcode Source Editor Extension target (XcodeKit) to add menu commands like “Run planner prompt,” “Run /review,” or “Generate checklist from resolved plan.” Apple documents creating source editor extensions via XcodeKit. citeturn0search3turn0search15  

Traceability + undo:

- Require the agent to work in a **branch or worktree**, produce **small diffs**, and never auto-commit without a human sign-off unless in a sandboxed CI bot.
- Enforce “one checklist task → one commit” locally; if Codex proposes multiple changes, split them.

## Metrics, rollout plan, and prioritized backlog

### Metrics and KPIs

To measure whether the workflow is actually improving outcomes, track both throughput and quality:

- **Adoption/usage**
  - % of PRs using the seven-stage artifacts (brainstorm/spec/audit/checklist present).
  - # of Codex-assisted runs per week (by stage).
- **Effectiveness**
  - **Time-to-merge** (median, P90) before vs after.
  - **Iteration count**: # of CI failures per PR (should drop).
  - **Build/test pass rate** on first try (compile-pass and test-pass).
- **Quality**
  - Post-merge defect rate (bugs per KLOC or per release).
  - Regression rate attributable to cross-target failures (extensions/widget).
- **Security**
  - Secret leakage incidents (should trend to zero).
  - Static analysis findings per PR (CodeQL, analyzer) and fix rate.
- **Cost**
  - Tokens/$ per merged PR (if metered), or per stage run.

Codex `codex exec --json` provides a path to collect machine-readable execution traces; use that for stage duration and iteration counting. citeturn14view1turn14view2turn11view0  

### Rollout timeline with milestones and estimated effort

| Milestone | Scope | Deliverables | Estimated effort (solo dev) | Rollback plan |
|---|---|---|---:|---|
| Baseline hardening | Make the workflow “Codex-native” | `AGENTS.md`, `.codex/config.toml`, prompt templates committed | 1–2 days | Remove config/templates; keep Docs workflow unchanged |
| Deterministic CI lane | Make PR gates reliable | GitHub Actions (or Xcode Cloud) build/test scripts aligned to schemes/targets | 2–4 days | Make CI non-blocking; keep manual builds |
| Lint + static analysis | Reduce style/security churn | SwiftLint gate; CodeQL Swift (if available); Xcode “Analyze” lane | 2–5 days | Keep lint as warning-only; disable CodeQL job |
| Agentic PR review augmentation | Add Codex review comments | `codex-action` job posting PR comments; prompt tuned to your repo | 1–2 days | Disable job; keep deterministic lane |
| Testing expansion | Shrink hallucination window | Add unit tests (Swift Testing / XCTest), property tests, smoke integration tests | 1–3 weeks (incremental) | Keep build-only gates; feature flags for tests |
| Release canary automation | Safer delivery | TestFlight group automation + phased release playbook | 2–5 days | revert to manual TestFlight + manual phased release |

Support for TestFlight distribution and phased releases is documented by Apple. citeturn3search10turn3search14turn3search18  

### Migration checklist

- Governance + safety
  - [ ] Unique API keys per developer; no shared keys. citeturn10search0  
  - [ ] GitHub/Xcode Cloud secrets set; keys never committed. citeturn6search0turn1search11turn10search0  
  - [ ] Codex sandbox + approvals configured; no `--yolo` outside hardened runners. citeturn11view0turn9search2  
  - [ ] If MCP tools used: documented threat model + prompt-injection mitigations. citeturn2search12turn2search6turn2search4  

- Workflow enablement
  - [ ] `AGENTS.md` added and validated (Codex can list loaded instruction sources). citeturn12search3turn12search5  
  - [ ] Stage prompt templates versioned in-repo.
  - [ ] CI scripts match your required scheme/target coverage. fileciteturn0file0  

- Measurement
  - [ ] Baseline PR cycle metrics captured pre-rollout.
  - [ ] Logging for `codex exec --json` runs stored as artifacts (optional).

### Prioritized backlog of improvements

Top priority (highest ROI, lowest risk):
1) **Add `AGENTS.md` + repo-scoped config** so Codex consistently respects your stages, artifact paths, and verification commands. citeturn12search3turn9search4turn11view0  
2) **Codify “build-the-right-things” in CI** using your exact scheme/target matrix (app + monitor + report + widget). fileciteturn0file0  
3) **Introduce strict secrets hygiene** (developer keys, CI secrets, log masking) and ban key exposure in mobile contexts. citeturn10search0turn6search0  
4) **Add non-blocking Codex PR review comments** via codex-action, tuned to cross-target iOS concerns. citeturn9search11turn8view2  

Medium priority (bigger wins, more effort):
5) Expand automated tests using Swift Testing or XCTest; migrate incrementally if needed. citeturn13view0turn2search31turn5search3  
6) Add **property-based tests** for pure logic and normalization layers (SwiftCheck or Swift Testing–native alternatives). citeturn7search2turn7search18  
7) Add **static analysis** (Xcode analyze, CodeQL Swift) as a required PR lane in security-sensitive code. citeturn7search13turn6search8turn6search10  

Lower priority / advanced (only after basics are stable):
8) Adopt Agents SDK orchestration for multi-agent handoffs and traceability, with strong MCP security controls. citeturn8view0turn2search6turn2search4  
9) Add fuzzing for parsers/decoders and sanitizer lanes for concurrency/memory regressions. citeturn3search3turn3search11turn7search0  

If you want, I can tailor the `AGENTS.md`, `.codex/config.toml`, and the first set of stage prompt templates to the actual repo layout and existing scripts (including making the CI build matrix automatically compute “affected targets” from `git diff`), but the report above is intentionally correct under the stated assumptions and anchored to the primary-source behaviors of Codex, Xcode, and modern agent security guidance. citeturn11view0turn12search3turn13view0turn2search12