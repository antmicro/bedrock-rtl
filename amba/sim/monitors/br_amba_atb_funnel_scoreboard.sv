// SPDX-License-Identifier: Apache-2.0

// Bedrock-RTL ATB Funnel Scoreboard
//
// DUT-specific end-to-end monitor for br_amba_atb_funnel simulation.
// Contract: records packets accepted on source interfaces, then compares every
// destination transfer against the recorded stream in acceptance order.

module br_amba_atb_funnel_scoreboard #(
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
    input int unsigned expected_transfers,

    input logic [NumSources-1:0] src_atvalid,
    input logic [NumSources-1:0] src_atready,
    input logic [NumSources-1:0][br_amba::AtbIdWidth-1:0] src_atid,
    input logic [NumSources-1:0][DataWidth-1:0] src_atdata,
    input logic [NumSources-1:0][ByteCountWidth-1:0] src_atbytes,
    input logic [NumSources-1:0][UserWidth-1:0] src_atuser,

    input logic dst_atvalid,
    input logic dst_atready,
    input logic [br_amba::AtbIdWidth-1:0] dst_atid,
    input logic [DataWidth-1:0] dst_atdata,
    input logic [ByteCountWidth-1:0] dst_atbytes,
    input logic [UserWidth-1:0] dst_atuser,

    output int unsigned observed_count,
    output int unsigned error_count
);

  localparam int SourceIndexWidth = (NumSources > 1) ? $clog2(NumSources) : 1;

  typedef struct packed {
    logic [SourceIndexWidth-1:0] source;
    logic [br_amba::AtbIdWidth-1:0] atid;
    logic [DataWidth-1:0] atdata;
    logic [ByteCountWidth-1:0] atbytes;
    logic [UserWidth-1:0] atuser;
  } atb_packet_t;

  atb_packet_t expected_packets[$];
  logic prev_dst_atvalid;
  logic prev_dst_atready;
  logic [br_amba::AtbIdWidth-1:0] prev_dst_atid;
  logic [DataWidth-1:0] prev_dst_atdata;
  logic [ByteCountWidth-1:0] prev_dst_atbytes;
  logic [UserWidth-1:0] prev_dst_atuser;

  // Records a scoreboard failure and emits the diagnostic message.
  task automatic record_error(input string message);
    error_count++;
    $error("%s", message);
  endtask

  // Compares one destination transfer against the expected source packet.
  task automatic check_dst_packet(input atb_packet_t expected);
    if (dst_atid !== expected.atid) begin
      record_error($sformatf("dst_atid mismatch: got 0x%0h expected 0x%0h", dst_atid, expected.atid
                   ));
    end
    if (dst_atdata !== expected.atdata) begin
      record_error($sformatf(
                   "dst_atdata mismatch: got 0x%0h expected 0x%0h", dst_atdata, expected.atdata));
    end
    if (dst_atbytes !== expected.atbytes) begin
      record_error($sformatf(
                   "dst_atbytes mismatch: got 0x%0h expected 0x%0h", dst_atbytes, expected.atbytes
                   ));
    end
    if (dst_atuser !== expected.atuser) begin
      record_error($sformatf(
                   "dst_atuser mismatch: got 0x%0h expected 0x%0h", dst_atuser, expected.atuser));
    end
  endtask

  // Records source packets and checks destination ordering, data, and stalls.
  task automatic run();
    int unsigned observed_scenario_id = 0;
    atb_packet_t expected;

    run_done = 1'b0;
    observed_count = 0;
    error_count = 0;
    prev_dst_atvalid = 1'b0;
    prev_dst_atready = 1'b0;
    prev_dst_atid = '0;
    prev_dst_atdata = '0;
    prev_dst_atbytes = '0;
    prev_dst_atuser = '0;

    forever begin
      while (scenario_id == observed_scenario_id) begin
        @(posedge clk);
      end
      observed_scenario_id = scenario_id;
      run_done = 1'b0;
      observed_count = 0;
      error_count = 0;
      expected_packets.delete();
      prev_dst_atvalid = dst_atvalid;
      prev_dst_atready = dst_atready;
      prev_dst_atid = dst_atid;
      prev_dst_atdata = dst_atdata;
      prev_dst_atbytes = dst_atbytes;
      prev_dst_atuser = dst_atuser;

      while (scenario_active &&
             (!driver_done || observed_count < expected_transfers ||
              expected_packets.size() != 0)) begin
        @(posedge clk);
        if (rst) begin
          expected_packets.delete();
          observed_count = 0;
        end else begin
          if (prev_dst_atvalid && !prev_dst_atready) begin
            if (!dst_atvalid) begin
              record_error("destination dropped valid while backpressured");
            end
            if (dst_atid !== prev_dst_atid || dst_atdata !== prev_dst_atdata ||
                dst_atbytes !== prev_dst_atbytes || dst_atuser !== prev_dst_atuser) begin
              record_error("destination changed payload while backpressured");
            end
          end

          for (int source = 0; source < NumSources; source++) begin
            if (src_atvalid[source] && src_atready[source]) begin
              expected.source = SourceIndexWidth'(source);
              expected.atid = src_atid[source];
              expected.atdata = src_atdata[source];
              expected.atbytes = src_atbytes[source];
              expected.atuser = src_atuser[source];
              expected_packets.push_back(expected);
            end
          end

          if (dst_atvalid && dst_atready) begin
            if (expected_packets.size() == 0) begin
              record_error("destination transfer without a recorded source transfer");
            end else begin
              expected = expected_packets.pop_front();
              check_dst_packet(expected);
            end
            observed_count++;
            if (observed_count > expected_transfers) begin
              record_error($sformatf(
                           "destination over-issue: observed %0d expected %0d",
                           observed_count,
                           expected_transfers
                           ));
            end
          end
        end
        prev_dst_atvalid = dst_atvalid;
        prev_dst_atready = dst_atready;
        prev_dst_atid = dst_atid;
        prev_dst_atdata = dst_atdata;
        prev_dst_atbytes = dst_atbytes;
        prev_dst_atuser = dst_atuser;
      end

      if (scenario_active) begin
        @(posedge clk);
        if (!rst && dst_atvalid) begin
          record_error("destination valid remained asserted after expected transfers completed");
        end
      end
      if (observed_count < expected_transfers) begin
        record_error(
            $sformatf(
            "observed %0d destination transfers, expected %0d", observed_count, expected_transfers
            ));
      end
      if (expected_packets.size() != 0) begin
        record_error($sformatf(
                     "scoreboard still has %0d pending source packets", expected_packets.size()));
      end
      run_done = 1'b1;
    end
  endtask

endmodule : br_amba_atb_funnel_scoreboard
