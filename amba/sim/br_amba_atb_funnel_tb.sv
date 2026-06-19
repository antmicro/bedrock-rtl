// SPDX-License-Identifier: Apache-2.0

// Directed simulation testbench for br_amba_atb_funnel.
//
// Scope:
// - Idle scenario with no enabled sources and no expected transfers.
// - Single-source and aligned multi-source packet preservation.
// - Destination backpressure with periodic ready stalls and source stability.
// - Staggered source starts with alternating destination readiness.
// - Stress traffic with continuous source valid and destination ready.
// - Reset asserted after traffic starts, followed by post-reset completion.
// - Bazel-swept source count, data width, user width, and ready registration.

import br_amba_atb_funnel_sim_pkg::*;

module br_amba_atb_funnel_tb;
  parameter int NumSources = 3;
  parameter int DataWidth = 32;
  parameter int UserWidth = 2;
  parameter bit RegisterAtReady = 0;

  localparam int ByteCountWidth = $clog2(DataWidth / 8);
  localparam int ResetCycles = 5;
  localparam int TimeoutCycles = 2000;
  localparam int ResetWhileBusyMinAccepts = 12;

  logic clk;
  logic rst;

  logic [NumSources-1:0] src_atvalid;
  logic [NumSources-1:0] src_atready;
  logic [NumSources-1:0][br_amba::AtbIdWidth-1:0] src_atid;
  logic [NumSources-1:0][DataWidth-1:0] src_atdata;
  logic [NumSources-1:0][ByteCountWidth-1:0] src_atbytes;
  logic [NumSources-1:0][UserWidth-1:0] src_atuser;
  logic dst_atvalid;
  logic dst_atready;
  logic [br_amba::AtbIdWidth-1:0] dst_atid;
  logic [DataWidth-1:0] dst_atdata;
  logic [ByteCountWidth-1:0] dst_atbytes;
  logic [UserWidth-1:0] dst_atuser;

  logic scenario_active;
  logic scenario_timeout_seen;
  int unsigned scenario_id;
  int unsigned bench_seed;

  logic driver_run_done;
  logic [NumSources-1:0] driver_source_enable;
  int unsigned driver_beats_per_source;
  int unsigned driver_valid_gap_cycles;
  int unsigned driver_idle_cycles_after_valid;
  atb_funnel_source_mode_t driver_source_mode;
  atb_funnel_dst_ready_pattern_t driver_dst_ready_pattern;
  int unsigned driver_data_seed;

  logic input_monitor_run_done;
  int unsigned input_monitor_expected_accepts;
  int unsigned input_monitor_accepted_count;
  int unsigned input_monitor_error_count;

  logic scoreboard_run_done;
  int unsigned scoreboard_expected_transfers;
  int unsigned scoreboard_observed_count;
  int unsigned scoreboard_error_count;

  br_amba_atb_funnel #(
      .NumSources(NumSources),
      .DataWidth(DataWidth),
      .UserWidth(UserWidth),
      .RegisterAtReady(RegisterAtReady)
  ) dut (
      .clk,
      .rst,
      .src_atvalid,
      .src_atready,
      .src_atid,
      .src_atdata,
      .src_atbytes,
      .src_atuser,
      .dst_atvalid,
      .dst_atready,
      .dst_atid,
      .dst_atdata,
      .dst_atbytes,
      .dst_atuser
  );

  br_test_driver #(
      .ResetCycles(ResetCycles)
  ) td (
      .clk,
      .rst
  );

  br_amba_atb_funnel_driver #(
      .NumSources(NumSources),
      .DataWidth (DataWidth),
      .UserWidth (UserWidth)
  ) driver (
      .clk,
      .rst,
      .scenario_id,
      .run_done(driver_run_done),
      .scenario_active,
      .source_enable(driver_source_enable),
      .beats_per_source(driver_beats_per_source),
      .valid_gap_cycles(driver_valid_gap_cycles),
      .idle_cycles_after_valid(driver_idle_cycles_after_valid),
      .source_mode(driver_source_mode),
      .dst_ready_pattern(driver_dst_ready_pattern),
      .data_seed(driver_data_seed),
      .src_atvalid,
      .src_atready,
      .src_atid,
      .src_atdata,
      .src_atbytes,
      .src_atuser,
      .dst_atready
  );

  br_amba_atb_funnel_input_monitor #(
      .NumSources(NumSources),
      .DataWidth (DataWidth),
      .UserWidth (UserWidth)
  ) input_monitor (
      .clk,
      .rst,
      .scenario_id,
      .run_done(input_monitor_run_done),
      .scenario_active,
      .driver_done(driver_run_done),
      .expected_accepts(input_monitor_expected_accepts),
      .src_atvalid,
      .src_atready,
      .src_atid,
      .src_atdata,
      .src_atbytes,
      .src_atuser,
      .accepted_count(input_monitor_accepted_count),
      .error_count(input_monitor_error_count)
  );

  br_amba_atb_funnel_scoreboard #(
      .NumSources(NumSources),
      .DataWidth (DataWidth),
      .UserWidth (UserWidth)
  ) scoreboard (
      .clk,
      .rst,
      .scenario_id,
      .run_done(scoreboard_run_done),
      .scenario_active,
      .driver_done(driver_run_done),
      .expected_transfers(scoreboard_expected_transfers),
      .src_atvalid,
      .src_atready,
      .src_atid,
      .src_atdata,
      .src_atbytes,
      .src_atuser,
      .dst_atvalid,
      .dst_atready,
      .dst_atid,
      .dst_atdata,
      .dst_atbytes,
      .dst_atuser,
      .observed_count(scoreboard_observed_count),
      .error_count(scoreboard_error_count)
  );

  function automatic int unsigned count_enabled(input logic [NumSources-1:0] source_enable);
    int unsigned count = 0;
    for (int source = 0; source < NumSources; source++) begin
      count += source_enable[source];
    end
    return count;
  endfunction

  function automatic int unsigned next_tb_random();
    int unsigned value;
    value = $urandom(bench_seed);
    bench_seed = value;
    return value;
  endfunction

  function automatic int unsigned random_range(input int unsigned min_value,
                                               input int unsigned max_value);
    return min_value + (next_tb_random() % (max_value - min_value + 1));
  endfunction

  function automatic logic [NumSources-1:0] random_source_mask(input int unsigned min_enabled,
                                                               input int unsigned max_enabled);
    logic [NumSources-1:0] mask = '0;
    int unsigned enabled_count;
    int unsigned max_enabled_clamped;

    max_enabled_clamped = max_enabled > NumSources ? NumSources : max_enabled;
    do begin
      enabled_count = 0;
      for (int source = 0; source < NumSources; source++) begin
        mask[source] = next_tb_random() [0];
        enabled_count += mask[source];
      end
    end while (enabled_count < min_enabled || enabled_count > max_enabled_clamped);
    return mask;
  endfunction

  function automatic atb_funnel_source_mode_t random_source_mode();
    if (next_tb_random() [0]) begin
      return AtbFunnelSourceStaggered;
    end
    return AtbFunnelSourceAligned;
  endfunction

  function automatic int unsigned min_unsigned(input int unsigned lhs, input int unsigned rhs);
    return lhs < rhs ? lhs : rhs;
  endfunction

  initial begin
    int enable_waves;
    if ($value$plusargs("atb_funnel_waves=%d", enable_waves) && enable_waves != 0) begin
      $dumpfile("br_amba_atb_funnel_tb.fst");
      $dumpvars(0, br_amba_atb_funnel_tb);
    end
  end

  // Initializes scenario control signals and watchdog state before helpers run.
  task automatic init_controls();
    scenario_active = 1'b0;
    scenario_timeout_seen = 1'b0;
    scenario_id = 0;
    driver_source_enable = '0;
    driver_beats_per_source = 0;
    driver_valid_gap_cycles = 0;
    driver_idle_cycles_after_valid = 0;
    driver_source_mode = AtbFunnelSourceAligned;
    driver_dst_ready_pattern = AtbFunnelDstReadyAlways;
    driver_data_seed = 0;
    input_monitor_expected_accepts = 0;
    scoreboard_expected_transfers = 0;
  endtask

  // Marks a scenario active and advances the helper start token.
  task automatic start_scenario();
    scenario_timeout_seen = 1'b0;
    scenario_active = 1'b1;
    scenario_id++;
    @(posedge clk);
  endtask

  // Marks the current scenario inactive so helper loops can quiesce.
  task automatic stop_scenario();
    scenario_active = 1'b0;
  endtask

  // Waits for component completion or a timeout thread, whichever finishes first.
  task automatic wait_for_scenario_done(input string scenario_name);
    fork : scenario_wait
      begin
        wait (driver_run_done && input_monitor_run_done && scoreboard_run_done &&
              input_monitor_accepted_count >= input_monitor_expected_accepts &&
              scoreboard_observed_count >= scoreboard_expected_transfers);
      end
      begin
        repeat (TimeoutCycles) @(posedge clk);
        scenario_timeout_seen = 1'b1;
        td.check(1'b0, $sformatf(
                 "%s timed out: drv=%0b in_mon=%0b sb=%0b accepted=%0d observed=%0d",
                 scenario_name,
                 driver_run_done,
                 input_monitor_run_done,
                 scoreboard_run_done,
                 input_monitor_accepted_count,
                 scoreboard_observed_count
                 ));
      end
    join_any
    disable scenario_wait;
    stop_scenario();
    if (!scenario_timeout_seen) begin
      td.check(input_monitor_error_count == 0, $sformatf(
               "%s had input monitor errors", scenario_name));
      td.check(scoreboard_error_count == 0, $sformatf("%s had scoreboard errors", scenario_name));
    end
  endtask

  // Checks final monitor and scoreboard counts after a completed scenario.
  task automatic check_scenario_counts(input string scenario_name,
                                       input int unsigned expected_transfers);
    if (!scenario_timeout_seen) begin
      td.check_integer(input_monitor_accepted_count, expected_transfers, $sformatf(
                       "%s source accepted count mismatch", scenario_name));
      td.check_integer(scoreboard_observed_count, expected_transfers, $sformatf(
                       "%s destination observed count mismatch", scenario_name));
    end
  endtask

  // Checks that the destination interface is idle immediately after reset.
  task automatic check_reset_idle(input string scenario_name);
    @(posedge clk);
    td.check(!dst_atvalid, $sformatf("%s: destination valid after reset", scenario_name));
  endtask

  // Runs the idle scenario without launching transaction helpers.
  task automatic run_idle_scenario();
    $display("Running idle");
    td.reset_dut();
    driver_source_enable = '0;
    driver_beats_per_source = 0;
    input_monitor_expected_accepts = 0;
    scoreboard_expected_transfers = 0;
    repeat (4) begin
      @(posedge clk);
      td.check(!dst_atvalid, "idle: destination valid while no sources are enabled");
    end
  endtask

  // Configures, runs, and checks one non-reset-interrupt scenario.
  task automatic run_scenario(
      input string scenario_name, input logic [NumSources-1:0] enable,
      input int unsigned beats_per_source, input atb_funnel_source_mode_t source_mode,
      input int unsigned valid_gap_cycles, input int unsigned idle_cycles_after_valid,
      input atb_funnel_dst_ready_pattern_t dst_ready_pattern, input int unsigned data_seed);
    int unsigned expected_transfers = count_enabled(enable) * beats_per_source;

    $display("Running %s: data_seed=0x%08h enable=0x%0h beats=%0d", scenario_name, data_seed,
             enable, beats_per_source);
    $display("  source_mode=%0d valid_gap=%0d initial_gap=%0d dst_ready_pattern=%0d", source_mode,
             valid_gap_cycles, idle_cycles_after_valid, dst_ready_pattern);
    td.reset_dut();
    check_reset_idle(scenario_name);

    driver_source_enable = enable;
    driver_beats_per_source = beats_per_source;
    driver_source_mode = source_mode;
    driver_valid_gap_cycles = valid_gap_cycles;
    driver_idle_cycles_after_valid = idle_cycles_after_valid;
    driver_dst_ready_pattern = dst_ready_pattern;
    driver_data_seed = data_seed;
    input_monitor_expected_accepts = expected_transfers;
    scoreboard_expected_transfers = expected_transfers;

    start_scenario();
    wait_for_scenario_done(scenario_name);
    check_scenario_counts(scenario_name, expected_transfers);
  endtask

  // Asserts reset after enough traffic has been accepted and the DUT is active.
  task automatic pulse_reset_while_busy(input int unsigned min_accepted_count);
    wait (((input_monitor_accepted_count >= min_accepted_count) &&
           (input_monitor_accepted_count > scoreboard_observed_count || |src_atvalid ||
            dst_atvalid)) || scenario_timeout_seen);
    if (!scenario_timeout_seen) begin
      rst = 1'b1;
      td.wait_cycles(ResetCycles);
      rst = 1'b0;
    end
  endtask

  // Runs randomized traffic, interrupts it with reset, then checks completion.
  task automatic run_reset_while_busy();
    int unsigned expected_transfers;
    int unsigned data_seed;
    int unsigned min_accepted_before_reset;
    int unsigned min_reset_sources;

    td.reset_dut();
    min_reset_sources = NumSources > 1 ? 2 : 1;
    driver_source_enable = random_source_mask(min_reset_sources, NumSources);
    driver_beats_per_source = random_range(12, 20);
    driver_source_mode = random_source_mode();
    driver_valid_gap_cycles = random_range(0, 1);
    driver_idle_cycles_after_valid = random_range(0, 2);
    driver_dst_ready_pattern = AtbFunnelDstReadyAlternating;
    data_seed = next_tb_random();
    driver_data_seed = data_seed;
    expected_transfers = count_enabled(driver_source_enable) * driver_beats_per_source;
    min_accepted_before_reset = min_unsigned(ResetWhileBusyMinAccepts, expected_transfers);
    input_monitor_expected_accepts = expected_transfers;
    scoreboard_expected_transfers = expected_transfers;
    $display("Running reset_while_busy: data_seed=0x%08h enable=0x%0h beats=%0d", data_seed,
             driver_source_enable, driver_beats_per_source);
    $display("  source_mode=%0d valid_gap=%0d initial_gap=%0d dst_ready_pattern=%0d min_reset=%0d",
             driver_source_mode, driver_valid_gap_cycles, driver_idle_cycles_after_valid,
             driver_dst_ready_pattern, min_accepted_before_reset);

    start_scenario();
    pulse_reset_while_busy(min_accepted_before_reset);
    wait_for_scenario_done("reset_while_busy");
    check_scenario_counts("reset_while_busy", expected_transfers);
  endtask

  // Start long-lived helpers, then run the directed and randomized scenarios.
  initial begin
    init_controls();
    fork
      driver.run();
      input_monitor.run();
      scoreboard.run();
    join_none

    bench_seed = $urandom;
    $display("br_amba_atb_funnel_tb bench_seed=0x%08h", bench_seed);
    td.reset_dut();

    run_idle_scenario();
    run_scenario("single_source_basic", random_source_mask(1, 1), random_range(2, 6),
                 AtbFunnelSourceAligned, 0, 0, AtbFunnelDstReadyAlways, next_tb_random());
    run_scenario("multi_source_round_robin", random_source_mask(2, NumSources), random_range(4, 8),
                 AtbFunnelSourceAligned, 0, 0, AtbFunnelDstReadyAlways, next_tb_random());
    run_scenario("destination_backpressure", random_source_mask(1, NumSources), random_range(4, 8),
                 random_source_mode(), random_range(0, 1), random_range(0, 2),
                 AtbFunnelDstReadyPeriodicStall, next_tb_random());
    run_scenario("starvation_smoke", random_source_mask(2, NumSources), random_range(8, 14),
                 AtbFunnelSourceStaggered, random_range(1, 3), random_range(1, 3),
                 AtbFunnelDstReadyAlternating, next_tb_random());
    run_scenario("stress_continuous", random_source_mask(1, NumSources), random_range(64, 96),
                 AtbFunnelSourceAligned, 0, 0, AtbFunnelDstReadyAlways, next_tb_random());
    run_reset_while_busy();

    td.finish(10);
  end

endmodule : br_amba_atb_funnel_tb
