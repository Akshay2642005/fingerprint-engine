# Fingerprint Engine Style Guide

## The Essence Of Style

The Fingerprint Engine's coding style is evolving. A collective give-and-take at
the intersection of engineering and art. Numbers and human intuition. Reason and
experience. First principles and knowledge. Precision and poetry. This is what
we've learned along the way. The best is yet to come.

## Why Have Style?

Another word for style is design.

> "The design is not just what it looks like and feels like. The design is how it
> works." — Steve Jobs

Our design goals are **safety, performance, and developer experience**. In that
order. All three are important. Good style advances these goals. Does the code
make for more or less safety, performance or developer experience? That is why
we need style.

Put this way, style is more than readability, and readability is table stakes, a
means to an end rather than an end in itself.

## On Simplicity And Elegance

Simplicity is not a free pass. It's not in conflict with our design goals. It
need not be a concession or a compromise.

Rather, simplicity is how we bring our design goals together, how we identify
the "super idea" that solves the axes simultaneously, to achieve something
elegant.

> "Simplicity and elegance are unpopular because they require hard work and
> discipline to achieve" — Edsger Dijkstra

Contrary to popular belief, simplicity is also not the first attempt but the
hardest revision. It's easy to say "let's do something simple", but to do that
in practice takes thought, multiple passes, many sketches, and still we may have
to throw one away.

The hardest part, then, is how much thought goes into everything.

We spend this mental energy upfront, proactively rather than reactively, because
we know that when the thinking is done, what is spent on the design will be
dwarfed by the implementation and testing, and then again by the costs of
operation and maintenance.

An hour or day of design is worth weeks or months in production:

> "The simple and elegant systems tend to be easier and faster to design and get
> right, more efficient in execution, and much more reliable" — Edsger Dijkstra

## Technical Debt

What could go wrong? What's wrong? Which question would we rather ask? The
former, because code, like steel, is less expensive to change while it's hot. A
problem solved in production is many times more expensive than a problem solved
in implementation, or a problem solved in design.

Since it's hard enough to discover showstoppers, when we do find them, we solve
them. We don't allow potential latency spikes, exponential complexity
algorithms, or reproducible gate failures to slip through.

> "You shall not pass!" — Gandalf

The Fingerprint Engine has a **"zero technical debt" policy**. We do it right
the first time. This is important because the second time may not transpire, and
because doing good work, that we can be proud of, builds momentum.

We know that what we ship is solid. We may lack crucial features, but what we
have meets our design goals. This is the only way to make steady incremental
progress, knowing that the progress we have made is indeed progress.

## Safety

> "The rules act like the seat-belt in your car: initially they are perhaps a
> little uncomfortable, but after a while their use becomes second-nature and
> not using them becomes unimaginable." — Gerard J. Holzmann

[NASA's Power of Ten — Rules for Developing Safety Critical
Code](https://spinroot.com/gerard/pdf/P10.pdf) will change the way you code
forever. To expand:

- Use **only very simple, explicit control flow** for clarity. **Do not use
  recursion** to ensure that all executions that should be bounded are bounded.
  Use **only a minimum of excellent abstractions** but only if they make the
  best sense of the domain. Abstractions are never zero cost. Every abstraction
  introduces the risk of a leaky abstraction.

- **Put a limit on everything** because, in reality, this is what we
  expect—everything has a limit. For example, all loops and all queues must have
  a fixed upper bound to prevent infinite loops or tail latency spikes. The FPKG
  frame payload cap (16 MiB) and the ring buffer depths exist for this reason.
  This follows the fail-fast principle so that violations are detected sooner
  rather than later. Where a loop cannot terminate (e.g. an event loop), this
  must be asserted.

- Use explicitly-sized types like `u32` and `i64` everywhere, avoid
  architecture-specific `usize`. The wire format's integer sizes are part of the
  stable ABI and are breaking if changed.

- **Assertions detect programmer errors. Unlike operating errors, which are
  expected and which must be handled, assertion failures are unexpected. The
  only correct way to handle corrupt code is to crash. Assertions downgrade
  catastrophic correctness bugs into liveness bugs. Assertions are a force
  multiplier for discovering bugs by fuzzing.**

  - **Assert all function arguments and return values, pre/postconditions and
    invariants.** A function must not operate blindly on data it has not
    checked. The purpose of a function is to increase the probability that a
    program is correct. Assertions within a function are part of how functions
    serve this purpose. The assertion density of the code must average a
    minimum of two assertions per function.

  - **Pair assertions.** For every property you want to enforce, try to find at
    least two different code paths where an assertion can be added. For example,
    assert integrity of a frame right before writing it to the wire, and also
    immediately after reading it from the wire.

  - On occasion, you may use a blatantly true assertion instead of a comment as
    stronger documentation where the assertion condition is critical and
    surprising.

  - Split compound assertions: prefer `assert(a); assert(b);` over
    `assert(a and b);`. The former is simpler to read, and provides more precise
    information if the condition fails.

  - Use single-line `if` to assert an implication: `if (a) assert(b)`.

  - **Assert the relationships of compile-time constants** as a sanity check,
    and also to document and enforce subtle invariants or type sizes. Our
    project is compile-time-first by design: the feature registry, the operation
    dispatch table, and the codec table are all validated at comptime, before
    the program even executes. Compile-time assertions check the program's
    design integrity _before_ it runs.

  - **The golden rule of assertions is to assert the _positive space_ that you
    do expect AND to assert the _negative space_ that you do not expect**
    because where data moves across the valid/invalid boundary between these
    spaces is where interesting bugs are often found. This is also why **tests
    must test exhaustively**, not only with valid data but also with invalid
    data, and as valid data becomes invalid.

  - Assertions are a safety net, not a substitute for human understanding.
    Build a precise mental model of the code first, encode your understanding in
    the form of assertions, write the code and comments to explain and justify
    the mental model to your reviewer, and use the fuzzers as the final line of
    defense, to find bugs in your and your reviewer's understanding of code.

- **Determinism is a correctness property.** The engine's promise is: same
  input, same output, any platform. Every code path that could make output
  platform-, pointer- or iteration-order-dependent is a bug. Sort features by
  `FeatureID` before hashing; never rely on hash-map iteration order in the
  wire format.

- All core algorithm memory must be allocated up front. **No heap allocation in
  core algorithms where avoidable.** This avoids unpredictable behavior that can
  significantly affect performance, and avoids use-after-free. As a second-order
  effect, it is our experience that this also makes for more efficient, simpler
  designs that are more performant and easier to maintain and reason about.

- Declare variables at the **smallest possible scope**, and **minimize the
  number of variables in scope**, to reduce the probability that variables are
  misused.

- There's a sharp discontinuity between a function fitting on a screen, and
  having to scroll to see how long it is. For this physical reason we enforce a
  **hard limit of 70 lines per function** (target 4–20). Art is born of
  constraints. There are many ways to cut a wall of code into chunks of 70
  lines, but only a few splits will feel right. Some rules of thumb:

  * Good function shape is often the inverse of an hourglass: a few parameters,
    a simple return type, and a lot of meaty logic between the braces.
  * Centralize control flow. When splitting a large function, try to keep all
    `switch`/`if` statements in the "parent" function, and move non-branchy
    logic fragments to helper functions. Divide responsibility. All control flow
    should be handled by _one_ function, the rest shouldn't care about control
    flow at all. In other words, "push `if`s up and `for`s down".
  * Similarly, centralize state manipulation. Let the parent function keep all
    relevant state in local variables, and use helpers to compute what needs to
    change, rather than applying the change directly. Keep leaf functions pure.

- Appreciate, from day one, **all compiler warnings at the compiler's strictest
  setting**. The build fails on warnings, not just errors.

- Whenever your program has to interact with external entities, **don't do
  things directly in reaction to external events**. Instead, your program should
  run at its own pace. The worker's executor batches inbound frames; it does not
  context-switch on every event. Not only does this make your program safer by
  keeping the control flow under your control, it also improves performance for
  the same reason, and makes it easier to maintain bounds on work done per time
  period.

Beyond these rules:

- Compound conditions that evaluate multiple booleans make it difficult for the
  reader to verify that all cases are handled. Split compound conditions into
  simple conditions using nested `if/else` branches. Split complex `else if`
  chains into `else { if { } }` trees. This makes the branches and cases clear.
  Again, consider whether a single `if` does not also need a matching `else`
  branch, to ensure that the positive and negative spaces are handled or
  asserted.

- Negations are not easy! State invariants positively. When working with lengths
  and indexes, this form is easy to get right (and understand):

  ```zig
  if (index < length) {
      // The invariant holds.
  } else {
      // The invariant doesn't hold.
  }
  ```

  This form is harder, and also goes against the grain of how `index` would
  typically be compared to `length`, for example, in a loop condition:

  ```zig
  if (index >= length) {
      // It's not true that the invariant holds.
  }
  ```

- All errors must be handled. An analysis of production failures in distributed
  data-intensive systems found that the majority of catastrophic failures could
  have been prevented by simple testing of error handling code.

  > "Specifically, we found that almost all (92%) of the catastrophic system
  > failures are the result of incorrect handling of non-fatal errors explicitly
  > signaled in software."

- **Always motivate, always say why.** Never forget to say why. Because if you
  explain the rationale for a decision, it not only increases the hearer's
  understanding, and makes them more likely to adhere or comply, but it also
  shares criteria with them with which to evaluate the decision and its
  importance.

- **Explicitly pass options to library functions at the call site, instead of
  relying on the defaults.** For example, pass `.{}` options explicitly where
  the API supports them. This improves readability but most of all avoids
  latent, potentially catastrophic bugs in case the library ever changes its
  defaults.

## Performance

> "The lack of back-of-the-envelope performance sketches is the root of all
> evil." — Rivacindela Hudsoni

- Think about performance from the outset, from the beginning. **The best time
  to solve performance, to get the huge 1000x wins, is in the design phase,
  which is precisely when we can't measure or profile.** It's also typically
  harder to fix a system after implementation and profiling, and the gains are
  less. So you have to have mechanical sympathy. Like a carpenter, work with the
  grain.

- **Perform back-of-the-envelope sketches with respect to the four resources
  (network, disk, memory, CPU) and their two main characteristics (bandwidth,
  latency).** Sketches are cheap. Use sketches to be "roughly right" and land
  within 90% of the global maximum.

- Optimize for the slowest resources first (network, disk, memory, CPU) in that
  order, after compensating for the frequency of usage, because faster resources
  may be used many times more.

- Distinguish between the control plane and data plane. A clear delineation
  between control plane and data plane through the use of batching enables a
  high level of assertion safety without losing performance.

- Amortize network, disk, memory and CPU costs by batching accesses. The worker
  processes frames in batches; the executor batches completions.

- Let the CPU be a sprinter doing the 100m. Be predictable. Don't force the CPU
  to zig zag and change lanes. Give the CPU large enough chunks of work. This
  comes back to batching.

- Be explicit. Minimize dependence on the compiler to do the right thing for
  you. In particular, extract hot loops into stand-alone functions with
  primitive arguments without `self`. That way, the compiler doesn't need to
  prove that it can cache struct fields in registers, and a human reader can
  spot redundant computations easier.

- The algorithms are SIMD-ready: prefer flat arrays of explicitly-sized
  integers over linked structures, keep hot data contiguous, and keep the
  cache footprint small.

## Developer Experience

> "There are only two hard things in Computer Science: cache invalidation,
> naming things, and off-by-one errors." — Phil Karlton

### Naming Things

- **Get the nouns and verbs just right.** Great names are the essence of great
  code, they capture what a thing is or does, and provide a crisp, intuitive
  mental model. They show that you understand the domain. Take time to find the
  perfect name, to find nouns and verbs that work together, so that the whole is
  greater than the sum of its parts.

- Use `snake_case` for function, variable, and file names. The underscore is
  the closest thing we have as programmers to a space, and helps to separate
  words and encourage descriptive names. We don't use Zig's `CamelCase.zig`
  style for "struct" files to keep the convention simple and consistent.

- Do not abbreviate variable names, unless the variable is a primitive integer
  type used as an argument to a sort function or matrix calculation. Use long
  form arguments in scripts: `--transport`, not `-t`. Single letter flags are
  for interactive usage.

- Use proper capitalization for acronyms (`FeatureID`, not `FeatureId`).

- For the rest, follow the Zig style guide.

- Add units or qualifiers to variable names, and put the units or qualifiers
  last, sorted by descending significance, so that the variable starts with the
  most significant word, and ends with the least significant word. For example,
  `latency_ms_max` rather than `max_latency_ms`. This will then line up nicely
  when `latency_ms_min` is added, as well as group all variables that relate to
  latency.

- Infuse names with meaning. For example, `allocator: Allocator` is a good, if
  boring name, but `gpa: Allocator` and `arena: Allocator` are excellent. They
  inform the reader whether `deinit` should be called explicitly.

- When choosing related names, try hard to find names with the same number of
  characters so that related variables all line up in the source. For example,
  `source` and `target` are better than `src` and `dest` because they have the
  second-order effect that any related variables such as `source_offset` and
  `target_offset` will all line up in calculations and slices. This makes the
  code symmetrical, with clean blocks that are easier for the eye to parse and
  for the reader to check.

- When a single function calls out to a helper function or callback, prefix the
  name of the helper function with the name of the calling function to show the
  call history. For example, `read_frame()` and `read_frame_callback()`.

- Callbacks go last in the list of parameters. This mirrors control flow:
  callbacks are also _invoked_ last.

- _Order_ matters for readability (even if it doesn't affect semantics). On the
  first read, a file is read top-down, so put important things near the top. The
  `main` function goes first.

  The same goes for `structs`, the order is fields then types then methods:

  ```zig
  time: Time,
  process_id: ProcessID,

  const ProcessID = struct { cluster: u128, replica: u8 };
  const Tracer = @This(); // This alias concludes the types section.

  pub fn init(gpa: std.mem.Allocator, time: Time) !Tracer {
      ...
  }
  ```

  If a nested type is complex, make it a top-level struct.

- Don't overload names with multiple meanings that are context-dependent. For
  example, `fingerprint` is the computation result, not the browser signals that
  feed it; keep the two distinct in naming and in code.

- Think of how names will be used outside the code, in documentation or
  communication. For example, a noun is often a better descriptor than an
  adjective or present participle, because a noun can be directly used in
  correspondence without having to be rephrased. Noun names compose more clearly
  for derived identifiers, e.g. `config.worker_ports_max`.

- Zig has named arguments through the `options: struct` pattern. Use it when
  arguments can be mixed up. A function taking two `u64` must use an options
  struct. If an argument can be `null`, it should be named so that the meaning
  of `null` literal at the call site is clear.

  Because dependencies like an allocator are singletons with unique types, they
  should be threaded through constructors positionally, from the most general to
  the most specific.

- **Write descriptive commit messages** that inform and delight the reader,
  because your commit messages are being read. Note that a pull request
  description is not stored in the git repository and is invisible in `git
  blame`, and therefore is not a replacement for a commit message. See
  [Conventional Commits](#conventional-commits--semantic-versioning) below.

- Don't forget to say why. Code alone is not documentation. Use comments to
  explain why you wrote the code the way you did. Show your workings.

- Don't forget to say how. For example, when writing a test, think of writing a
  description at the top to explain the goal and methodology of the test, to
  help your reader get up to speed, or to skip over sections, without forcing
  them to dive in.

- Comments are sentences, with a space after the slash, with a capital letter
  and a full stop, or a colon if they relate to something that follows. Comments
  are well-written prose describing the code, not just scribblings in the
  margin. Comments after the end of a line _can_ be phrases, with no
  punctuation.

### Cache Invalidation

- Don't duplicate variables or take aliases to them. This will reduce the
  probability that state gets out of sync.

- If you don't mean a function argument to be copied when passed by value, and
  if the argument type is more than 16 bytes, then pass the argument as
  `*const`. This will catch bugs where the caller makes an accidental copy on
  the stack before calling the function.

- Construct larger structs _in-place_ by passing an _out pointer_ during
  initialization. In-place initializations can assume pointer stability and
  immovable types while eliminating intermediate copy-move allocations, which
  can lead to undesirable stack growth.

  Keep in mind that in-place initializations are viral — if any field is
  initialized in-place, the entire container struct should be initialized
  in-place as well.

  **Prefer:**
  ```zig
  fn init(target: *LargeStruct) !void {
      target.* = .{
          // in-place initialization.
      };
  }

  fn main() !void {
      var target: LargeStruct = undefined;
      try target.init();
  }
  ```

  **Over:**
  ```zig
  fn init() !LargeStruct {
      return LargeStruct{
          // moving the initialized object.
      };
  }

  fn main() !void {
      var target = try LargeStruct.init();
  }
  ```

- **Shrink the scope** to minimize the number of variables at play and reduce
  the probability that the wrong variable is used.

- Calculate or check variables close to where/when they are used. **Don't
  introduce variables before they are needed.** Don't leave them around where
  they are not. This will reduce the probability of a place-of-check to
  place-of-use bug, a distant cousin to the infamous TOCTOU. Most bugs come down
  to a semantic gap, caused by a gap in time or space, because it's harder to
  check code that's not contained along those dimensions.

- Use simpler function signatures and return types to reduce dimensionality at
  the call site, the number of branches that need to be handled at the call
  site, because this dimensionality can also be viral, propagating through the
  call chain. For example, as a return type, `void` trumps `bool`, `bool` trumps
  `u64`, `u64` trumps `?u64`, and `?u64` trumps `!u64`.

- Ensure that functions run to completion without suspending, so that
  precondition assertions are true throughout the lifetime of the function.
  These assertions are useful documentation without a suspend, but may be
  misleading otherwise.

- Be on your guard for **buffer bleeds** — a buffer underflow, the opposite of
  a buffer overflow, where a buffer is not fully utilized, with padding not
  zeroed correctly. This may not only leak sensitive information, but may cause
  the deterministic guarantees the engine depends on to be violated.

- Use newlines to **group resource allocation and deallocation**, i.e. before
  the resource allocation and after the corresponding `defer` statement, to make
  leaks easier to spot.

### Off-By-One Errors

- **The usual suspects for off-by-one errors are casual interactions between an
  `index`, a `count` or a `size`.** These are all primitive integer types, but
  should be seen as distinct types, with clear rules to cast between them. To go
  from an `index` to a `count` you need to add one, since indexes are _0-based_
  but counts are _1-based_. To go from a `count` to a `size` you need to
  multiply by the unit. Again, this is why including units and qualifiers in
  variable names is important.

- Show your intent with respect to division. For example, use `@divExact()`,
  `@divFloor()` or `div_ceil()` to show the reader you've thought through all
  the interesting scenarios where rounding may be involved.

### Style By The Numbers

- Run `zig fmt`.

- Use 4 spaces of indentation, rather than 2 spaces, as that is more obvious to
  the eye at a distance.

- Hard limit all line lengths, without exception, to at most 100 columns for a
  good typographic "measure". Use it up. Never go beyond. Nothing should be
  hidden by a horizontal scrollbar. Let your editor help you by setting a
  column ruler. To wrap a function signature, call or data structure, add a
  trailing comma, close your eyes and let `zig fmt` do the rest.

  Similar to function length, the motivation behind the number 100 is physical:
  just enough to fit two copies of the code side-by-side on a screen.

- Add braces to the `if` statement unless it fits on a single line for
  consistency and defense in depth against "goto fail;" bugs.

### Dependencies

The Fingerprint Engine has **a "zero dependencies" policy**, apart from the Zig
toolchain. Dependencies, in general, inevitably lead to supply chain attacks,
safety and performance risk, and slow install times. For foundational
infrastructure in particular, the cost of any dependency is further amplified
throughout the rest of the stack.

Documented exceptions (each requires a note in the README and a decision in
`specs/`):

- `tsc` — the browser SDK's TypeScript compile step (`zig build clients:browser`).
- `node --test` — the TS SDK test suite.
- `npm publish` — the manual npm publishing step.
- Docker — for building and running worker images (`zig build docker:worker`).

### Tooling

Similarly, tools have costs. A small standardized toolbox is simpler to operate
than an array of specialized instruments each with a dedicated manual. Our
primary tool is Zig. It may not be the best for everything, but it's good enough
for most things. We invest into our Zig tooling to ensure that we can tackle new
problems quickly, with a minimum of accidental complexity in our local
development environment.

> "The right tool for the job is often the tool you are already using—adding new
> tools has a higher cost than many people appreciate" — John Carmack

For example, the next time you write a script, instead of a bash script, add a
subcommand to `zig build scripts -- <cmd>`. This not only makes your script
cross-platform and portable, but introduces type safety and increases the
probability that running your script will succeed for everyone on the team,
instead of hitting a Bash/Shell/OS-specific issue.

Standardizing on Zig for tooling is important to ensure that we reduce
dimensionality, as the team, and therefore the range of personal tastes, grows.
This may be slower for you in the short term, but makes for more velocity for
the team in the long term.

## Project Operations

### Conventional Commits & Semantic Versioning

All changes to this repository MUST follow the [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) specification. Versioning MUST strictly adhere to [Semantic Versioning 2.0.0](https://semver.org/).

#### Commit Message Format

`<type>(<scope>): <description>` (Space after colon is MANDATORY)

#### Types & Version Bumps

- `feat`: Minor (x.Y.z) - New feature
- `fix`: Patch (x.y.Z) - Bug fix
- `perf`: Patch (x.y.Z) - Performance improvement
- `docs`, `chore`, `style`, `refactor`, `test`: No bump (unless breaking)
- `BREAKING CHANGE:` (or `!` after type): Major (X.y.z)

### Git Operations

- `master` is **locked**: no direct pushes, no direct work, no force
  pushes, no deletions. It only receives merges — from `develop` — after
  the full gate (test suite, simulations, regression testing) is green.
- `develop` is the **integration branch**: all commits, features, and
  fixes land here first, either directly or via feature branches that
  branch off `develop`. `master` never receives work-in-progress.
- Every task MUST start with a feature branch or worktree off `develop`
  via `kickoff-branch`.
- **Integrate (solo profile):** Ship with `bash scripts/land-branch.sh <branch> "<conventional message>"` after `release-branch` gates.
- `git push origin <feature-branch>` is allowed for backup; never push
  directly to `master`, and never push to `develop` around a red gate.
- **Git Attribution:** NEVER include `Co-authored-by`, `Co-Authored-By`, or any other footer that attributes code to an AI agent.
- Never create GitHub issues from automated workflows — produce local .md files in `specs/` instead.

### Always Green / Shift Left

Solo developers own the whole codebase. **Always Green** means Preflight and CI are green before any forward work — not "green enough for this task."

**Shift Left (1-10-100):** Defects cost roughly 1× to fix in development, 10× in integration, 100× in production. Fixing a red gate now is cheaper than shipping and debugging later.

**Preflight** — `zig build test` MUST pass before kickoff, develop, or verify phases advance.

### Discovered Defects

Any **reproducible gate failure** encountered during unrelated work is a discovered defect — not optional background noise.

**fix-or-log ladder (mandatory):**

1. **quick-fix** — trivial, data-only, or single-file fixes within guardrails.
2. **fix-bug** — when quick-fix guardrails abort, or the failure needs investigation (`specs/bugs/BUG-*.md` + TDD).
3. **Log** — only when reproduction is blocked after good-faith attempt; write a BUG spec and stop forward work.

Discovered fixes ship in the **same PR** but in **separate commits**. Never narrate a failure and continue.

**Hard block:** Red Preflight blocks forward progress until fix-or-log produces green.

#### Banned dismissive phrases

| Banned phrase | Required behavior instead |
| --------------- | --------------------------- |
| Pre-existing / pre-existing issues | Run fix-or-log; prove with a passing repro after revert |
| unrelated to this session | Same — session boundaries do not waive green gates |
| not introduced by my changes | Bisect or fix anyway; solo-owner owns the whole tree |
| out of scope (ignoring a red gate) | Invoke quick-fix or fix-bug |

### specs/ — All Planning Output Goes Here

All domain docs, plans, and investigation outputs go in `specs/` at the project root.

| Layer | File | Purpose |
| ------- | ------ | --------- |
| Session | `specs/state.yaml` | Active flow, epic/bug, git, handoff |
| Release index | `specs/release-plan.yaml` | Target semver, WSJF epic list |
| Progress | `specs/execution-status.yaml` | Flat story/epic status |
| Intent | `specs/product/SCOPE_LATEST.yaml` | What should the product do? |
| North star | `specs/product/VISION_LATEST.yaml` | Initiative direction |
| Glossary | `specs/product/GLOSSARY_LATEST.yaml` | Domain terms |
| Architecture | `specs/tech-architecture/tech-stack.md` | Stack + architecture |
| Epics | `specs/epics/eNN-slug/` | Stories and tasks with `verify:` |

### Code Style

- Functions: target 4–20 lines; hard limit 70 lines. Split if longer.
- Files: under 300 lines. Split by responsibility.
- One thing per function, one responsibility per module (SRP).
- Names: specific and unique. Avoid `data`, `handler`, `Manager`, `Service`.
- Types: explicit. No `any`, no untyped public functions.
- No code duplication. Extract shared logic into a function/module.
- Early returns over nested ifs. Max 2 levels of indentation.
- Conditionals: expressed as positives. Avoid negative flags.
- The Stepdown Rule: functions should descend exactly one level of abstraction.
- No magic strings or numbers — extract to named constants.
- Boolean logic in named functions — complex boolean expressions must be extracted into a named predicate.
- Remove dead code: unused functions, unreachable branches, stale imports must be deleted.
- Boy Scout Rule: leave every file you touch at least as clean as you found it.
- Law of Demeter: call only immediate collaborators.

### Comments

- Write WHY, not WHAT.
- Complex or non-obvious logic must include provenance links.
- Docstrings on public functions: intent + one usage example.
- No obvious comments that restate the code.
- No commented-out code — delete it; use git history to recover.

### Tests

- Tests live outside `src/` in `tests/`, mirroring production module structure.
- Tests run headless with a single command: `zig build test`.
- Every new function gets a test. Every bug fix gets a regression test.
- Tests are **F**ast, **I**ndependent, **R**epeatable, **S**elf-Validating, **T**imely.
- Test boundary conditions: empty input, maximum, minimum, off-by-one — and both the positive and negative space (valid and invalid data, and valid data becoming invalid).
- Test through public interfaces only — assert on observable outcomes.
- Never skip or @ignore a test without an explicit ambiguity note.
- Every change must be verifiable with a single runnable command before done.

### Build Philosophy

| Step | Command |
| ------ | --------- |
| Build | `zig build` |
| Test | `zig build test --summary all` |
| Integration | `zig build test-integration` |
| WASM | `zig build wasm` |
| Worker | `zig build worker --release=safe` |
| Bench | `zig build bench` |
| Browser SDK | `zig build clients:browser` |
| Docs | `zig build docs` |
| Scripts | `zig build scripts -- <cmd>` |
| Docker | `zig build docker:worker` |

Incremental development. One module at a time. Every commit must compile and
must pass tests; the migration stays bisectable.

### Architecture Invariants

- **Everything depends inward.** `model` → `core`/`serialization` → `engine`;
  `io` → `adapter` → `worker`. Nothing depends outward; no circular imports.
- **No transport in the core.** The engine never knows about HTTP, AMQP,
  WebSockets, databases, auth, users, or business logic. Adapters own every
  transport concern.
- **The browser never computes the canonical fingerprint.** It collects,
  packages, and ships; the workers compute.
- **Stable ABI.** Integer sizes in the wire format are intentional and breaking
  if changed. Message schemas are versioned.
- **Deterministic everywhere.** Same input, same output, any platform.

### Optimization Philosophy

Prefer compile-time work over runtime work:

- ✅ compile-time lookup tables
- ✅ compile-time validation
- ✅ immutable metadata
- ❌ runtime registration
- ❌ reflection
- ❌ dynamic dispatch
- ❌ unnecessary heap allocation

### Defensive Code

Where applicable in this project:

- **Retry with backoff** — the AMQP adapter owns reconnect, retry, and dead
  letter concerns; the engine never sees them.
- **Timeout** — for long-running operations
- **Graceful degradation** — when external dependencies fail

## The Last Stage

At the end of the day, keep trying things out, have fun, and remember — it's
called Fingerprint Engine not only because it fingerprints browsers, but because
it is fast, deterministic, and small.
