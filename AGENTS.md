# Repository agent guide

Read [VISION.md](VISION.md) before changing architecture or recipe semantics.

## Ownership boundary

- `uv` and standard Python package metadata own dependency resolution, interpreter selection,
  downloads, environment creation, and caching.
- The Zig launcher owns recipe validation, DCC discovery, child-only environment composition,
  inspection, and process launch.
- DCC-side Python owns the vendor API integration after the DCC initializes its interpreter.
- Do not add a dependency solver, shell activation system, arbitrary recipe code, or global
  environment mutation to misapp.
- Do not make the native launcher import or start Python during a normal launch. Managed Python
  compatibility is checked from `pyvenv.cfg` metadata.

## Source layout

- `native/launcher.zig`: dependency-free native host and recipe parser.
- `src/miskeyed/applications/`: packaged, data-only recipes.
- `src/miskeyed/plugins/`: code loaded inside the DCC, never by the host CLI.
- `tests/config/applications/`: recipe fixtures.
- `tests/recipe.cmake`: cross-platform launch integration test.
- `.github/workflows/`: the supported build and release commands.
- `src/miskeyed/rez_bridge.py`: optional comparison harness; it must remain separate from the
  dependency-free native launch path.

## Recipe changes

- Keep schema 1 intentionally small and deterministic.
- Reject unknown keys and malformed values; never silently ignore configuration.
- Conditions must remain side-effect-free and must not execute commands.
- Environment edits apply only to the child process.
- Add parser unit coverage and a recipe integration case for every schema feature.
- Update recipe-aware `help` whenever a new configurable input is introduced.
- Treat `requires`/`provides` as a compatibility API between installed sidecars, not as a package
  solver. Package selection and installation remain `uv` responsibilities.

## Compatibility invariants

- Keep the project version synchronized in `pyproject.toml` and `CMakeLists.txt`.
- Keep the broad `requires-python` metadata compatible with
  `miskeyed-python-base.yml:requires.python`; DCC overlays may narrow it.
- A wheel may expose the managed site-packages location, but it must not inject that location into
  global `PYTHONPATH`.
- Host-side modules must remain importable without the vendor `substance_painter` module.
- Never put try/catch blocks around imports.

## Required checks

With Zig 0.13 available, run:

```console
cmake -S . -B build -DSKBUILD_SCRIPTS_DIR=bin -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
ctest --test-dir build -C Release --output-on-failure
python -m build
python -m twine check dist/*
```

Also run `git diff --check` and `python -m compileall -q src`. Do not claim native tests passed
when the Zig compiler was unavailable.
