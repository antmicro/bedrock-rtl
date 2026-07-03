---
name: write-br-testbench
description: Write or refactor Bedrock-RTL SystemVerilog simulation testbenches that use br_dv_lib class-based infrastructure. Use when Codex needs to create or update DUT-specific items, sequences, drivers, monitors, scoreboards, envs, br_dv_context/br_dv_env usage, br_dv_lib docs, or Bazel sim targets for a Bedrock RTL testbench.
---

# Write BR Testbench

Use this skill for Bedrock-RTL testbenches that should follow `br_dv_lib`
rather than older procedural helpers. Also use the repo's `write-sim-testbench`
skill when the task is mainly about simulator portability, Bazel target shape,
or existing non-`br_dv_lib` benches.

## First Reads

Before editing, inspect:

- `br_dv_lib/doc/user_guide.md` as the source of truth for current library API.
- The DUT RTL and closest analogous sim bench.
- The nearest `sim/BUILD.bazel`.
- The current `br_dv_lib/*.svh` classes if changing library infrastructure.

For compact br_dv_lib patterns from the RAM addr decoder work, read
`references/br-dv-lib-testbench-patterns.md`.

## Preferred Shape

Keep roles crisp:

- The top `*_tb.sv` module owns DUT/interfaces, test parameters, lifecycle, and
  scenario flow.
- `br_dv_context` owns checks, component registration, and shared orchestration
  helpers such as bounded sequence waits.
- A DUT-specific `br_dv_env` subclass owns topology only: object handles,
  `build()`, and `connect()`.
- Drivers are BFMs only. They drive protocol signals from items and put the
  interface idle on a `null` item.
- Monitors observe interfaces and publish captured items. They should not embed
  DUT prediction or protocol assertions that already belong to RTL assertions.
- Scoreboards own prediction, semantic port routing, matching, latency checks,
  and data-integrity checks.

## Implementation Workflow

1. Create a DUT-local package directory under `*/sim/<dut>_tb/`.
2. Put one class per `.svh` file: item, sequence, driver, monitor, scoreboard,
   and env when topology is nontrivial.
3. Add a local `BUILD.bazel` in that directory for the package, interface, TB,
   elaboration test, and sim suites. Keep outer `sim/BUILD.bazel` free of those
   DUT-local recipes.
4. Include class files from `<dut>_tb_pkg.sv`; import that package in the TB.
5. Instantiate DUT and virtual interfaces in `<dut>_tb.sv`.
6. Construct `ctx = new(test);`, then construct the DUT env with `ctx` and the
   interfaces.
7. Keep reset, sequence filling, iteration loops, drain cycles, and scoreboard
   checks in the TB scenario, not in the env.
8. Run the narrowest Bazel build/sim targets and `pre-commit run` on touched
   files.

## Coding Rules

- Use positive clock edges only in drivers and monitors.
- Use nonblocking assignments when driving DUT pins from BFMs.
- Never add `#1` or `@(negedge ...)` unless the user explicitly asks; if a
  temporary delay is required, leave a precise TODO explaining the tool issue.
- Do not bake traffic policy into drivers. Put policy in sequence constraints or
  `fill_*` helpers.
- Prefer random constraints for item legality and traffic knobs instead of
  ad-hoc post-random mutation.
- Keep overrideable testbench parameters meaningful for coverage; derive helper
  widths and latencies with `localparam`.
- Do not enable waves by default. Add plusarg-based VCD dumping only when useful
  and keep Bazel `waves = True` out of tests.

## Standard Scenario Skeleton

```systemverilog
task automatic run_all_tests();
  br_dv_context ctx;
  my_env env;

  ctx = new(test);
  env = new(ctx, clk_rst_if, input_if, output_if);

  env.clk_rst_driver.reset_dut();
  env.clk_rst_driver.wait_cycles();

  for (int i = 0; i < SequenceIterations; i++) begin
    env.input_sequence.fill_random($urandom_range(1, MaxTransactionsPerIteration));

    fork
      env.input_sequence.start();
    join_none

    ctx.wait_for_sequences(env.clk_rst_driver, SequenceTimeoutCycles);
    env.clk_rst_driver.wait_cycles(DrainCycles);
  end

  env.scoreboard.check_all();
endtask
```

Use `BR_DEFINE_TEST` and `BR_RUN_TEST` for test creation.
