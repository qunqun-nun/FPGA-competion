# Contributing

Thanks for helping improve FengYan.

## Development Workflow

1. Keep changes focused and document hardware/runtime version impact.
2. Do not commit Vivado/Vitis generated directories, local board captures, or Python cache files.
3. Put board evidence under a clearly named report file when it is needed for review.
4. For runtime changes, run Python syntax checks and relevant pytest tests before opening a pull request.
5. For hardware changes, include the Vivado/Vitis version, target board, build command, and timing/license status in the PR notes.

## Pull Request Checklist

- README or docs updated when behavior changes.
- Validation boundary stated clearly: offline, simulation, board retest, or full system retest.
- Third-party source or binary additions include license/provenance notes.
- Generated output is either excluded or intentionally placed under `hardware/artifacts/` with a reason.

