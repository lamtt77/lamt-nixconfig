# New Features Coding Plan

This document is a scratchpad and tracking plan for designing and implementing upcoming features, refactoring tasks, or architectural changes in `installer-rs` and `lamd`.

---

## 1. Feature Requirements

_Describe the requirements for the new feature or change here. Include user commands, CLI flags, expected behaviors, and constraints._

```text
Example CLI syntax:
lamd <command> --new-flag
```

---

## 2. Technical Design

_Outline the technical approach, file placements, module dependencies, changes to internal data structures, and trade-offs._

### Module Modifications & New Files

- `src/module/new_file.rs`: _Description of the new file's role._
- `src/module/existing_file.rs`: _Description of the changes required in the existing file._

---

## 3. Implementation Tasks Checklist

- [ ] **Phase 1: Design & Scope**
  - [ ] Detail the API and data structure modifications.
  - [ ] Review against architecture guidelines (modular, reusable, no secrets in logs).
- [ ] **Phase 2: Implementation**
  - [ ] Implement core logic and helpers.
  - [ ] Add unit and integration tests.
- [ ] **Phase 3: Integration & Wiring**
  - [ ] Wire the features into commands and CLI parsing.
  - [ ] Refactor existing call sites to use new shared abstractions.
- [ ] **Phase 4: Cleanup & Documentation**
  - [ ] Run formatter (`cargo fmt`).
  - [ ] Update `docs/Installer Rust Architecture and Implementation Plan.md` to reflect permanent changes.

---

## 4. Verification & Testing Checklist

- [ ] **Unit Tests**
  - [ ] Run `cargo test` and ensure all tests pass.
- [ ] **Manual Verification**
  - [ ] Verify using plan/dry-run options.
  - [ ] Test deployment scenarios on virtual or test targets.

## 5. Test Coverage

Increase test coverage where appropriate and sensible, prioritizing planning helpers, command construction, and workspace/build-strategy regressions.
