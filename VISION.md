# misapp vision

## The outcome

An artist should be able to run one command and receive the studio's tools in the DCC they
already use:

```console
uvx misapp substancepainter
```

In the future, a recommended `miskeyed` distribution can depend on `misapp` and the supported
integration packages, making `uvx miskeyed APPLICATION` the single on-ramp for the complete
Miskeyed toolset. Artists should not need to understand virtual environments, `PYTHONPATH`, ABI
tags, plugin search paths, or installation layouts.

## The division of responsibility

Rez proved the value of declarative environments, composable packages, reproducible contexts,
and inspecting what a launch will receive. It also became responsible for solving packages,
installing them, describing variants, constructing environments, and launching applications.
That breadth is powerful, but it is more infrastructure than this project needs.

The Python packaging ecosystem already has package metadata, dependency constraints, platform
wheels, indexes, and installer interoperability. `uv` adds fast resolution, downloads, caching,
locked environments, and disposable tool execution on top of that ecosystem. **misapp must not
build a second package manager beside it.**

The boundary is therefore:

### `uv` owns deployment

- resolve Python dependencies and version constraints;
- select a compatible Python interpreter;
- download packages and platform-native wheels;
- create, cache, and reuse the isolated tool environment;
- expose the installed console command; and
- eventually install the recommended set of Miskeyed integrations from one meta-package.

### `misapp` owns the application boundary

- discover the externally installed DCC executable;
- validate a small, data-only application recipe;
- compose recipe inheritance in a deterministic order;
- connect the `uv` environment to the DCC's supported plugin or startup mechanism;
- modify only the child process environment;
- expose the resolved context for diagnostics and UI tooling; and
- launch the DCC with unchanged arguments and exit status.

### The DCC owns its runtime

- its executable and installation;
- its embedded Python interpreter and ABI;
- its Qt, vendor SDK, and native libraries; and
- the point at which its official plugin bootstrap enters that runtime.

misapp passes the location of the managed payload to that bootstrap. It does not replace the
DCC interpreter, globally set `PYTHONPATH`, or attempt to model the vendor SDK as a Python
dependency.

## What we keep from Rez

We keep the artist-facing ideas that remain useful when `uv` owns package deployment:

- **Declarative contexts:** a reviewable recipe describes discovery and child environment edits.
- **Composition:** small base recipes can be extended by DCC and studio overlays.
- **Isolation:** edits affect only the launched child, never the artist's shell.
- **Inspection:** `help`, `inspect`, and `get` explain inputs and resolved values.
- **Validation:** malformed recipes and incompatible managed Python environments fail before the
  DCC starts.
- **Versioned capabilities:** lightweight sidecars declare what an installed application or
  integration provides and what an overlay requires, without solving or installing packages.
- **Portability:** the same schema works across user workstations, CI, and farms.

## What we intentionally do not rebuild

- a dependency solver or package repository;
- package variants already expressible as wheel tags and Python requirements;
- a shell activation language;
- arbitrary Python in configuration files;
- a general pipeline executor;
- a second lockfile or installation database;
- a replacement for the DCC's embedded runtime; or
- a large environment framework that artists must administer.

If a proposed feature belongs to dependency resolution or installation, it should normally be
implemented in package metadata or delegated to `uv`. A recipe feature is justified only when it
describes the boundary between an installed payload and an external application.

## Product direction

1. Incubate the native host and Painter recipe in this repository.
2. Publish the initial `misapp` platform wheels and prove `uvx misapp substancepainter`.
3. Add integrations as small packages containing payloads and recipes, not launcher forks.
4. Add a UI that reads the same inspection API and writes the same per-user recipe files.
5. Extract the host into its own application package once multiple DCCs share the contract.
6. Publish a recommended `miskeyed` meta-package so one `uvx` command installs the supported
   creative pipeline.

Success means adding another DCC usually requires a recipe and a narrow bootstrap—not another
environment manager.

## Rez exit test

The project must remain willing to delete itself. The optional `misapp-rez` harness installs Rez
alongside the wheel with `uvx`, translates the already-resolved child environment into a temporary
Rez package, and lets `rez-env` launch the DCC. This provides an executable comparison rather than
an architectural argument.

If a small `rez-pip` or `rez-pip2` customization can preserve the PyPI/`uvx` user experience while
handling DCC discovery, Python ABI gating, and environment injection, Rez should own that work and
misapp should shrink to a generator or be removed. The experiment succeeds by finding the smallest
maintained solution, even when that solution is Rez.
