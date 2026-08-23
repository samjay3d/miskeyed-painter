# Rez boundary evaluation

This document answers the architectural question behind the `misapp-rez` experiment: is
`rez-env` already enough, is the YAML adapter useful, and should this project extend Rez instead
of becoming a separate environment system?

## Executive answer

`rez-env` is enough for **environment composition and process launch**. Rez packages can declare
requirements, compose environment commands, expose tools, resolve a context, and launch a DCC.
misapp should not duplicate those features merely with a smaller schema.

`rez-env` is not, by itself, the same **distribution workflow** as `uvx`. The unresolved boundary
is how a wheel that already lives in a disposable uv environment contributes DCC-specific launch
metadata without also requiring the author and user to maintain that payload as a Rez package.

The most promising Rez-based answer is the one suggested in community feedback:

1. let pip/uv install the wheel;
2. extend `rez-pip` or `rez-pip2` to generate the additional `package.py` environment commands;
3. let Rez own resolution and `rez-env` own the process context.

If that preserves the desired one-command installation experience, the generic recipe resolver in
misapp should be deleted. The correct outcome is the smallest maintained system, not necessarily a
new project.

## Is `rez-env` enough?

### Yes, when Rez owns the context

Rez already covers:

- versioned package requirements and conflicts;
- Python and DCC package variants;
- deterministic environment composition;
- executable/tool exposure;
- context inspection and reproduction; and
- child-process launch.

For a studio already using a Rez repository, expressing Painter, Maya, Houdini, and plugin paths in
`package.py` is more capable and more mature than recreating those semantics here.

### Not quite, when uv must remain the owner

The desired user story begins with a PyPI distribution:

```console
uvx miskeyed-workbench
uvx miskeyed substancepainter
```

In that model, uv has already selected Python, installed wheels, and created a cached disposable
environment. A plain `rez-env` invocation does not automatically know:

- which uv environment is active;
- where its `site-packages` and native wheel payloads live;
- which installed wheel contributes a DCC adapter;
- how that payload should enter the DCC's official plugin mechanism; or
- whether adopting a Rez repository is acceptable for an indie, tools vendor, or game team that
  otherwise uses only PyPI.

That is an integration gap, not evidence that another resolver is needed.

## Is the YAML method better?

Not generally. It is better only for the deliberately narrow wheel-to-DCC adapter boundary.

### Advantages of a data-only sidecar

- It can ship inside the same wheel as the payload.
- It is reviewable and writable by a future UI.
- It cannot execute arbitrary Python during parsing.
- It maps directly to a few child-only `set`, `prepend`, and `append` operations.
- A tiny native host can read it without starting Python or installing Rez.
- A PyPI publisher does not need to publish the payload again into a second repository.

### Advantages of Rez `package.py`

- Mature requirement and variant semantics.
- Existing context diagnostics and tooling.
- Arbitrary logic when a package genuinely requires it.
- Established repository, release, and studio override workflows.
- Consistent resolution across artists rather than mutable per-user virtual environments.
- A much larger body of production use and edge-case handling.

YAML stops being the better option as soon as it grows a general solver, variants, conflicts,
optional requirements, or package discovery rules. At that point it is a less mature Rez frontend.

## Can the YAML extend Rez?

Yes. That may be the best outcome.

The YAML can remain a safe authoring/sidecar format while a Rez integration compiles it into a
generated package:

```text
wheel sidecar -> rez-pip hook -> generated package.py -> rez-env -> DCC
```

This division would allow:

- uv/pip to remain the publishing format;
- `rez-pip` to import the payload into a Rez-controlled installation when desired;
- Rez to own requirements, variants, context resolution, and launch; and
- the small YAML subset to describe only DCC discovery and environment attachment.

The sidecar must not retain its own generic `requires`/`provides` solver in that design. Python and
DCC requirements should compile to Rez requirements, and Rez should be the single authority.

## What does native misapp offer that `rez-env` does not?

When used without Rez, misapp offers:

1. **No second package universe.** The wheel in the uv environment is the installed artifact.
2. **No persistent package repository.** `uvx` owns downloading and caching.
3. **No Python startup in the host.** The normal launcher is a small native executable.
4. **A constrained configuration surface.** Recipes cannot execute arbitrary code.
5. **A direct user configuration target.** A UI can write one application sidecar.
6. **A PyPI-native sharing story.** A TA can publish a standard wheel rather than first adopting a
   studio pipeline package repository.

Those advantages matter primarily to individuals, tools vendors, open-source projects, and teams
that have not already standardized on Rez. They are much less compelling inside an established Rez
studio.

## What the current experiment proves—and does not prove

`misapp-rez` currently:

1. asks native misapp to inspect an application;
2. writes the resulting child environment into a temporary Rez `package.py`; and
3. lets `rez-env` create the context and launch the executable.

This proves that an already-resolved uv payload can be handed to Rez without modifying a global
repository. It does **not** prove that Rez can replace misapp yet, because misapp still performs
discovery, recipe composition, and validation first.

CI includes a real `rez-env` probe on Python 3.11. It is intentionally reported as an experimental,
non-blocking job: core native CI must not become dependent on Rez while this decision is being
evaluated, but changes to Rez packaging or command behavior remain visible in every pull request.

The next experiment should generate the Rez package during `rez-pip` installation and launch the
DCC without calling native `misapp inspect`. That is the meaningful deletion test.

## Decision criteria

Prefer the Rez extension if it can demonstrate all of the following:

- one user command starting from a PyPI requirement;
- no manually maintained duplicate payload;
- automatic DCC/Python version selection;
- generated plugin/native environment commands;
- reproducible contexts across artists; and
- acceptable startup and operational overhead for the target users.

Keep a standalone native adapter only if the Rez path necessarily requires users to adopt a
repository, package conversion, or runtime footprint that defeats the simple `uvx` experience.

Do not maintain both systems as equal production backends. Run the comparison, select one owner for
environment resolution, and delete the duplicate implementation.
