# misapp

> See [VISION.md](VISION.md) for the long-term product boundary and why `uv`, rather than
> misapp, owns dependency resolution and deployment.

`misapp` is a small native application host written in **Zig**. [`uvx`](https://docs.astral.sh/uv/concepts/tools/)
creates the isolated package environment; `misapp` validates one application recipe, composes
its parent recipes, changes only the child environment, and launches the DCC.

The distribution includes a reusable `miskeyed-python-base` recipe. A future recommended
`miskeyed` meta-package can depend on `misapp` plus all approved integrations, so one
`uvx miskeyed ...` installation owns the complete tool payload while each DCC still uses its
vendor-provided interpreter and SDK.

The short version is: **`uv` installs the pipeline; misapp connects that installed payload to an
external creative application.** Recipes describe only that last environment boundary.

```console
uvx misapp substancepainter
uvx misapp substancepainter -- --mesh model.fbx
uvx misapp validate substancepainter
uvx misapp inspect substancepainter
uvx misapp get substancepainter executable
uvx misapp help substancepainter
uvx misapp config-path substancepainter
```

There are no environment or discovery pipelines on the launch command. Application arguments
must follow `--`. The separate `validate` command parses the complete recipe chain without
launching the application.

## Reusing resolved features

Recipes are also a small discovery API. `inspect` shows the values produced by the complete
recipe chain—including the selected executable and composed child environment—without launching
the DCC:

```console
$ uvx misapp inspect substancepainter
application=substancepainter
executable=/opt/Adobe/Adobe_Substance_3D_Painter/Adobe_Substance_3D_Painter
site_packages=/home/artist/.cache/uv/.../site-packages
python_env=/home/artist/.cache/uv/.../
python_executable=/home/artist/.cache/uv/.../bin/python
environment.SUBSTANCE_PAINTER_PLUGINS_PATH=/home/artist/.cache/uv/.../startup
```

Automation should use `get`, which returns exactly one unadorned value and is therefore safe to
capture without parsing the inspection display:

```console
uvx misapp get substancepainter executable
uvx misapp get substancepainter environment.SUBSTANCE_PAINTER_PLUGINS_PATH
```

The stable built-in variables are `application`, `executable`, `site_packages`, `recipe_root`,
`python_env`, `python_executable`, and `recipe_count`. Every environment name touched by the
recipe is available as `environment.NAME`. Unknown and unavailable variables fail with a nonzero
status, so another command can reuse discovery without copying DCC paths or silently accepting
an empty value.

`help APPLICATION` (also available as `APPLICATION --help`) is recipe-aware rather than generic
CLI help. It lists the complete recipe
chain, every environment variable used as an input (executable overrides and conditions), every
child environment variable the recipe can produce, and all available substitutions. It does not
need the DCC executable to exist, so an artist or UI can examine an integration before setup.

## User configuration for a UI

`config-path APPLICATION` prints the exact file a UI should create. It works for applications
that do not have a packaged recipe yet and prints only the path, making it safe for automation:

```console
$ uvx misapp config-path substancepainter
/home/artist/.config/misapp/applications/substancepainter.yml
```

The platform-native roots are:

- Linux: `$XDG_CONFIG_HOME/misapp`, or `~/.config/misapp` when XDG is unset;
- macOS: `~/Library/Application Support/misapp`;
- Windows: `%APPDATA%\\misapp`.

`MISAPP_CONFIG_HOME` overrides that root for a studio, portable installation, or test. The UI
only needs to create the parent `applications` directory and write the validated YAML recipe;
it does not need its own registry, database, or discovery implementation.

## Lightweight YAML recipes

Python-backed integrations extend the shared environment recipe instead of rebuilding virtual
environment discovery in every DCC recipe:

```yaml
schema: 1
name: Miskeyed managed Python environment
requires:
  python: ">=3.9,<3.14"
environment:
  set:
    MISAPP_SITE_PACKAGES: ${site_packages}
    MISAPP_PYTHON_ENV: ${python_env}
    MISAPP_PYTHON_EXECUTABLE: ${python_executable}
```

These values describe the `uvx`-managed environment. They do **not** set `PYTHONPATH` and do not
replace the DCC's embedded Python executable. A DCC-specific bootstrap decides how to make the
managed site-packages visible after the vendor interpreter starts.

Requirements use comma-separated `>=`, `>`, `==`, `<`, or `<=` constraints. Before
launch, `misapp` reads the managed environment's `pyvenv.cfg` and rejects an incompatible Python
version. It never starts that interpreter to perform the check. This makes the recipe the shared
compatibility contract: `uv` selects the environment, while the integration gates wheels that
require a different Python ABI before they reach the DCC.

The base constraint is mirrored by the distribution's `requires-python` metadata. That lets `uv`
select a compatible interpreter up front; a DCC overlay may narrow `requires.python` further when
its embedded interpreter or native plugin wheels require one exact Python minor version.

The same API gates application and integration versions without turning misapp into a solver. A
versioned Painter discovery sidecar can provide a capability, while an integration requires it:

```yaml
# painter-10.yml
provides:
  substancepainter: 10.1.1

# an integration overlay
requires:
  substancepainter: "==10.1.1"
```

Providers and consumers compose through `extends`. A missing or incompatible capability stops
the launch before environment injection. `uv` still decides which distributions are installed;
misapp only validates that the sidecars in that installed set agree.

Integration distributions can ship lightweight sidecars into the shared
`miskeyed/applications/` package directory. When a future `miskeyed` meta-package depends on
`misapp`, Workbench, Painter, and other integration wheels, `uvx` installs those sidecars into the
same isolated environment. The native launcher discovers them there, so adding an installed tool
does not require registering it in a second database.

The packaged Painter integration is an overlay:

```yaml
schema: 1
name: Miskeyed Substance Painter
extends:
  - miskeyed-python-base
  - painter-base
environment:
  prepend:
    SUBSTANCE_PAINTER_PLUGINS_PATH: ${site_packages}/miskeyed/plugins/startup
conditions:
  - when: env.MISKEYED_DEBUG
    set:
      MISKEYED_DEBUG: enabled
```

`extends` provides deterministic chaining. Parents are loaded first and the current recipe is
applied last. Cycles are rejected. This allows executable discovery to live in a base recipe
while a PyPI integration adds only its plugin and API environment.

Conditions are deliberately not a programming language. The accepted forms are:

```yaml
- when: platform == windows
- when: env.STUDIO
- when: env.PIPELINE == film
```

A matching condition may contain `set`, `prepend`, and `append` mappings. There are no shell
expressions, subprocesses, Boolean operators, or arbitrary code.

The schema validator rejects unsupported schema versions, unknown top-level keys, odd
indentation, invalid condition expressions, invalid environment names, unsupported operations,
missing names, malformed chains, and chain cycles. Validation happens on every launch as well
as through `misapp validate APPLICATION`.

The remaining data surface is intentionally small:

- `requires` declares versioned capabilities a recipe consumes;
- `provides` declares versioned capabilities supplied by an application or integration sidecar;
- `executable_env` names an optional executable override variable;
- platform groups under `executables` contain names to check on `PATH`;
- platform groups under `search` contain conventional absolute paths;
- `${site_packages}`, `${python_env}`, `${python_executable}`, `${home}`, and `${program_files}`
  are safe launcher substitutions.

Users—or a future `uvx miskeyapp` UI—can override packaged recipes in
`applications/<name>.yml` under `$XDG_CONFIG_HOME/misapp`,
`~/Library/Application Support/misapp`, or `%APPDATA%\misapp`. `MISAPP_CONFIG_HOME` selects an
explicit recipe root for farms, tests, and portable deployments.

## Dependency boundary

`uvx` installs the Python dependency graph and the platform-specific `misapp` wheel. Zig is a
**build-only** dependency supplied by the `ziglang` build requirement; no Zig runtime or Python
interpreter is involved when the installed launcher runs.

Native Python extensions still require wheels matching the DCC's Python ABI and target
platform. Their shared libraries must follow the platform wheel rules described by PyPA's
[platform compatibility tags](https://packaging.python.org/en/latest/specifications/platform-compatibility-tags/)
and [binary extension guide](https://packaging.python.org/en/latest/guides/packaging-binary-extensions/).
The DCC executable, embedded interpreter, Qt, and vendor SDK remain host-provided and are
therefore discovered by YAML instead of being modeled as `uv` dependencies.

Painter receives the packaged bootstrap through its plugin path. Only after Painter initializes
its embedded interpreter does that bootstrap call `site.addsitedir()`; `misapp` never sets
`PYTHONPATH` or mutates the parent shell.

## Rez comparison experiment

This branch keeps the native implementation, but also ships an intentionally separate
`misapp-rez` comparison harness. It lets Rez own the final process context while `uvx` still owns
installation of the Python payload:

```console
uvx --from 'misapp[rez]' misapp-rez substancepainter -- --mesh model.fbx
uvx --from 'misapp[rez]' misapp-rez --dry-run substancepainter
```

The bridge asks native `misapp inspect` for the discovered executable and resolved child
environment, writes a temporary `misapp_uv_context/0.1.0/package.py`, and launches the executable
through `rez-env`. `--dry-run` prints both the generated Rez package and command for comparison.
It does not modify a global Rez repository or the parent shell.

This is deliberately a migration experiment rather than a second production path. It answers two
questions with running code:

1. Is Rez's context/launch machinery small enough when installed ephemerally by `uvx`?
2. Can a future `rez-pip`/`rez-pip2` hook generate the DCC-specific `package.py` directly, making
   most of the custom recipe engine unnecessary?

The experiment currently uses misapp for discovery so the outputs can be compared exactly. If Rez
is adopted, discovery and environment declarations should move into generated Rez packages and
the duplicate recipe implementation should be deleted—not maintained indefinitely.

## Development

A Zig 0.13 toolchain is required:

```console
cmake -S . -B build -DSKBUILD_SCRIPTS_DIR=bin
cmake --build build
ctest --test-dir build --output-on-failure
```

Zig may be installed either as a system executable or through the `ziglang` Python package used
by isolated wheel builds. CMake checks `PATH` first and then resolves the compiler bundled inside
`ziglang`; installing the build dependency does not require its package directory to be added to
`PATH`.

## Release automation

This repository starts at version `0.1.0`. Pull requests build the launcher, execute its native
tests, build a wheel on Linux, macOS, and Windows, and validate the source distribution. When an
unpublished version reaches `main`, `release.yml` publishes the same three platform wheels and
sdist to TestPyPI and then PyPI through Trusted Publishing before creating the matching Git tag
and GitHub Release.

Maintainers must create the `testpypi` and `pypi` GitHub environments and register
`.github/workflows/release.yml` as a trusted publisher on the corresponding package indexes. No
PyPI token or personal access token is stored in the repository.
