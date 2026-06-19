// SPDX-License-Identifier: Apache-2.0

// Bedrock-RTL ATB Funnel Driver
//
// DUT-specific source-side driver for br_amba_atb_funnel simulation.
// Contract: owns ATB source inputs and destination readiness, emits
// randomized packet fields from the scenario seed, and completes once all
// enabled source lanes send their configured beat count.

import br_amba_atb_funnel_sim_pkg::*;

module br_amba_atb_funnel_driver #(
    parameter int NumSources = 2,
    parameter int DataWidth = 32,
    parameter int UserWidth = 1,
    localparam int ByteCountWidth = $clog2(DataWidth / 8)
) (
    input logic clk,
    input logic rst,

    input int unsigned scenario_id,
    output logic run_done,
    input logic scenario_active,
    input logic [NumSources-1:0] source_enable,
    input int unsigned beats_per_source,
    input int unsigned valid_gap_cycles,
    input int unsigned idle_cycles_after_valid,
    input atb_funnel_source_mode_t source_mode,
    input atb_funnel_dst_ready_pattern_t dst_ready_pattern,
    input int unsigned data_seed,

    output logic [NumSources-1:0] src_atvalid,
    input logic [NumSources-1:0] src_atready,
    output logic [NumSources-1:0][br_amba::AtbIdWidth-1:0] src_atid,
    output logic [NumSources-1:0][DataWidth-1:0] src_atdata,
    output logic [NumSources-1:0][ByteCountWidth-1:0] src_atbytes,
    output logic [NumSources-1:0][UserWidth-1:0] src_atuser,

    output logic dst_atready
);

  int unsigned beat_count[NumSources];
  int unsigned gap_count[NumSources];
  int unsigned source_seed[NumSources];
  logic [NumSources-1:0] source_done;

  // Deasserts valid and clears payload fields for one source lane.
  task automatic clear_source(input int source);
    src_atvalid[source] = 1'b0;
    src_atid[source] = '0;
    src_atdata[source] = '0;
    src_atbytes[source] = '0;
    src_atuser[source] = '0;
  endtask

  function automatic int unsigned next_random(input int source);
    int unsigned value;
    value = $urandom(source_seed[source]);
    source_seed[source] = value;
    return value;
  endfunction

  // Populates one source lane with the next randomized ATB packet fields.
  task automatic load_source_packet(input int source);
    src_atid[source] = br_amba::AtbIdWidth'(next_random(source));
    src_atdata[source] = DataWidth'({next_random(source), next_random(source)});
    src_atbytes[source] = ByteCountWidth'(next_random(source));
    src_atuser[source] = UserWidth'(next_random(source));
  endtask

  // Starts a new valid beat on one source lane.
  task automatic start_source_beat(input int source);
    src_atvalid[source] = 1'b1;
    load_source_packet(source);
  endtask

  // Keeps valid asserted for a source lane while preserving its payload.
  task automatic hold_source_beat(input int source);
    src_atvalid[source] = 1'b1;
  endtask

  // Initializes per-source counters, seeds, done flags, and output signals.
  task automatic reset_counts();
    for (int source = 0; source < NumSources; source++) begin
      beat_count[source] = 0;
      gap_count[source]  = (source_mode == AtbFunnelSourceStaggered) ?
                           source * idle_cycles_after_valid : 0;
      source_seed[source] = data_seed + (source * AtbFunnelSourceSeedStride);
      source_done[source] = !source_enable[source] || beats_per_source == 0;
      clear_source(source);
    end
  endtask

  // Drives one source lane until its configured beat count is accepted.
  task automatic drive_one_source(input int source);
    bit accepted_last_cycle = 1'b0;

    if (!source_enable[source] || beats_per_source == 0) begin
      source_done[source] = 1'b1;
      clear_source(source);
    end else begin
      while (scenario_active && beat_count[source] < beats_per_source) begin
        @(negedge clk);
        if (rst) begin
          beat_count[source] = 0;
          gap_count[source] = (source_mode == AtbFunnelSourceStaggered) ?
                              source * idle_cycles_after_valid : 0;
          source_done[source] = 1'b0;
          accepted_last_cycle = 1'b0;
          clear_source(source);
        end else if (accepted_last_cycle) begin
          accepted_last_cycle = 1'b0;
          gap_count[source]   = valid_gap_cycles;
          clear_source(source);
        end else if (src_atvalid[source]) begin
          hold_source_beat(source);
        end else if (gap_count[source] != 0) begin
          gap_count[source]--;
          clear_source(source);
        end else begin
          start_source_beat(source);
        end

        @(posedge clk);
        if (rst) begin
          beat_count[source] = 0;
          gap_count[source] = (source_mode == AtbFunnelSourceStaggered) ?
                              source * idle_cycles_after_valid : 0;
          source_done[source] = 1'b0;
          accepted_last_cycle = 1'b0;
          clear_source(source);
        end else if (src_atvalid[source] && src_atready[source]) begin
          beat_count[source]++;
          accepted_last_cycle = 1'b1;
        end
      end
      @(negedge clk);
      source_done[source] = 1'b1;
      clear_source(source);
    end
  endtask

  function automatic logic dst_ready_value(input int unsigned cycle);
    case (dst_ready_pattern)
      AtbFunnelDstReadyAlways: return 1'b1;
      AtbFunnelDstReadyAlternating: return cycle[0];
      AtbFunnelDstReadyPeriodicStall: return (cycle % 7) >= 3;
      default: return 1'b0;
    endcase
  endfunction

  // Drives destination readiness according to the selected ready pattern.
  task automatic drive_dst_ready();
    int unsigned cycle = 0;

    while (scenario_active && !(&source_done)) begin
      @(negedge clk);
      if (rst) begin
        dst_atready = 1'b0;
      end else begin
        dst_atready = dst_ready_value(cycle);
        cycle++;
      end

      @(posedge clk);
      if (rst) begin
        cycle = 0;
      end
    end

    @(negedge clk);
    dst_atready = 1'b1;
  endtask

  // Starts one independent source-driving process per source lane.
  task automatic run_sources();
    for (int source = 0; source < NumSources; source++) begin
      automatic int source_index = source;
      fork
        drive_one_source(source_index);
      join_none
    end
    wait ((&source_done) || !scenario_active);
  endtask

  // Clears every source lane after a scenario completes.
  task automatic clear_all_sources();
    for (int source = 0; source < NumSources; source++) begin
      clear_source(source);
    end
  endtask

  // Waits for each scenario start, then runs source and ready drivers.
  task automatic run();
    int unsigned observed_scenario_id = 0;

    run_done = 1'b0;
    src_atvalid = '0;
    src_atid = '0;
    src_atdata = '0;
    src_atbytes = '0;
    src_atuser = '0;
    dst_atready = 1'b1;

    forever begin
      while (scenario_id == observed_scenario_id) begin
        @(posedge clk);
      end
      observed_scenario_id = scenario_id;
      run_done = 1'b0;
      reset_counts();

      fork
        run_sources();
        drive_dst_ready();
      join

      clear_all_sources();
      run_done = 1'b1;
    end
  endtask

endmodule : br_amba_atb_funnel_driver
