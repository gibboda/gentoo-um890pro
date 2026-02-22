# Phase 2 Next Step Proposal

## Current status observed in codebase

- The modular pipeline exists (`run_phase0_pipeline`) and executes wrapper modules in a fixed order. It currently provides **Phase 0 extraction** only.
- Profile resolution logic exists in `gentoo-um890pro-install.sh` (`resolve_profile`), but that logic is only guaranteed on the monolithic fallback path. The modular Phase 0 runner path does not call it.
- No dedicated dependency resolver module or checkpoint state module exists yet under `installer/core/`.

## Proposed next step to complete Phase 2

Implement a **minimal checkpoint-aware phase executor** in `installer/core/runner.sh` and use it from `main`.

This should be done in one narrow vertical slice:

1. Introduce `installer/core/state.sh` with:
   - `state_dir_init`
   - `checkpoint_done <phase>`
   - `checkpoint_mark <phase>`
   - `checkpoint_clear_from <phase>` (for rerun safety)
2. Introduce `installer/core/resolver.sh` with:
   - a dependency map of logical phases to required features/modules
   - a resolver that expands `INSTALL_PROFILE` into a deterministic ordered phase list
3. Update startup flow so `resolve_profile` always runs before module execution, including the modular path.
4. Execute phases through runner checkpoints (skip completed phases unless `--force-from <phase>` is passed).

## Why this is the best Phase 2 increment

- It delivers the core Phase 2 goal (dependency resolver + checkpoints) without rewriting module internals.
- It keeps destructive operations safer by enabling resume semantics at explicit phase boundaries.
- It reduces migration risk by preserving current module wrappers and behavior.

## Acceptance criteria for this step

- Fresh run writes checkpoints for each completed phase.
- Interrupted run can resume and skips already completed phases.
- Unsupported profile still hard-fails before any destructive phase.
- Resolved profile and resolved phase plan are printed before execution.
- Modular and fallback paths both apply identical profile resolution semantics.
