// SPDX-License-Identifier: Apache-2.0

// Bedrock-RTL ATB Funnel Input Monitor
//
// DUT-specific source-side monitor for br_amba_atb_funnel simulation.
// Contract: observes accepted source transfers and source stability while
// backpressured. It does not drive DUT signals or predict destination order.

module br_amba_atb_funnel_input_monitor #(
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
    input logic driver_done,
    input int unsigned expected_accepts,

    input logic [NumSources-1:0] src_atvalid,
    input logic [NumSources-1:0] src_atready,
    input logic [NumSources-1:0][br_amba::AtbIdWidth-1:0] src_atid,
    input logic [NumSources-1:0][DataWidth-1:0] src_atdata,
    input logic [NumSources-1:0][ByteCountWidth-1:0] src_atbytes,
    input logic [NumSources-1:0][UserWidth-1:0] src_atuser,

    output int unsigned accepted_count,
    output int unsigned error_count
);

  logic [NumSources-1:0] prev_src_atvalid;
  logic [NumSources-1:0] prev_src_atready;
  logic [NumSources-1:0][br_amba::AtbIdWidth-1:0] prev_src_atid;
  logic [NumSources-1:0][DataWidth-1:0] prev_src_atdata;
  logic [NumSources-1:0][ByteCountWidth-1:0] prev_src_atbytes;
  logic [NumSources-1:0][UserWidth-1:0] prev_src_atuser;

  // Records a monitor failure and emits the diagnostic message.
  task automatic record_error(input string message);
    error_count++;
    $error("%s", message);
  endtask

  // Counts source accepts and checks stable payload while backpressured.
  task automatic run();
    int unsigned observed_scenario_id = 0;

    run_done = 1'b0;
    accepted_count = 0;
    error_count = 0;
    prev_src_atvalid = '0;
    prev_src_atready = '0;
    prev_src_atid = '0;
    prev_src_atdata = '0;
    prev_src_atbytes = '0;
    prev_src_atuser = '0;

    forever begin
      while (scenario_id == observed_scenario_id) begin
        @(posedge clk);
      end
      observed_scenario_id = scenario_id;
      run_done = 1'b0;
      accepted_count = 0;
      error_count = 0;
      prev_src_atvalid = src_atvalid;
      prev_src_atready = src_atready;
      prev_src_atid = src_atid;
      prev_src_atdata = src_atdata;
      prev_src_atbytes = src_atbytes;
      prev_src_atuser = src_atuser;

      while (scenario_active && (!driver_done || accepted_count < expected_accepts)) begin
        @(posedge clk);
        if (rst) begin
          accepted_count = 0;
        end else begin
          for (int source = 0; source < NumSources; source++) begin
            if (prev_src_atvalid[source] && !prev_src_atready[source]) begin
              if (!src_atvalid[source]) begin
                record_error($sformatf("source %0d dropped valid while backpressured", source));
              end
              if (src_atid[source] !== prev_src_atid[source] ||
                  src_atdata[source] !== prev_src_atdata[source] ||
                  src_atbytes[source] !== prev_src_atbytes[source] ||
                  src_atuser[source] !== prev_src_atuser[source]) begin
                record_error($sformatf("source %0d changed payload while backpressured", source));
              end
            end
            if (src_atvalid[source] && src_atready[source]) begin
              accepted_count++;
              if (accepted_count > expected_accepts) begin
                record_error($sformatf(
                             "source accepts exceeded expected count: observed %0d expected %0d",
                             accepted_count,
                             expected_accepts
                             ));
              end
            end
          end
        end
        prev_src_atvalid = src_atvalid;
        prev_src_atready = src_atready;
        prev_src_atid = src_atid;
        prev_src_atdata = src_atdata;
        prev_src_atbytes = src_atbytes;
        prev_src_atuser = src_atuser;
      end

      if (scenario_active) begin
        @(posedge clk);
        if (!rst && |src_atvalid) begin
          record_error("source valid remained asserted after driver completion");
        end
      end
      if (accepted_count < expected_accepts) begin
        record_error($sformatf(
                     "observed %0d source accepts, expected %0d", accepted_count, expected_accepts
                     ));
      end
      run_done = 1'b1;
    end
  endtask

endmodule : br_amba_atb_funnel_input_monitor
