// SPDX-License-Identifier: Apache-2.0

typedef enum {
  BrRamDataRdPipeIn,
  BrRamDataRdPipeOut
} br_ram_data_rd_pipe_scoreboard_port_e;

class br_ram_data_rd_pipe_scoreboard #(
    parameter int Width = 1,
    parameter int DepthTiles = 1,
    parameter int WidthTiles = 1,
    type BrRamDataRdPipeItem = br_ram_data_rd_pipe_item#(.Width(Width))
) extends br_dv_port_sink_target #(
    .ItemType(BrRamDataRdPipeItem),
    .PortType(br_ram_data_rd_pipe_scoreboard_port_e)
);
  typedef br_dv_port_sink#(
      .ItemType(BrRamDataRdPipeItem),
      .PortType(br_ram_data_rd_pipe_scoreboard_port_e)
  ) BrRamDataRdPipeSink;

  localparam string ScoreboardName = "br_ram_data_rd_pipe";

  local int expected_latency_cycles;
  local BrRamDataRdPipeItem exp_q[$];
  local BrRamDataRdPipeItem act_q[$];
  local BrRamDataRdPipeSink in_sink;
  local BrRamDataRdPipeSink out_sink;

  function new(input br_dv_context ctx = null, input int expected_latency_cycles = 0);
    super.new(ctx);
    this.expected_latency_cycles = expected_latency_cycles;
    if (ctx != null) begin
      ctx.register(this);
    end
    in_sink  = new(this, BrRamDataRdPipeIn);
    out_sink = new(this, BrRamDataRdPipeOut);
  endfunction

  virtual function br_dv_component_kind_e get_kind();
    return BrDvScoreboard;
  endfunction

  function BrRamDataRdPipeSink get_sink(input br_ram_data_rd_pipe_scoreboard_port_e port);
    case (port)
      BrRamDataRdPipeIn: return in_sink;
      BrRamDataRdPipeOut: return out_sink;
      default: return null;
    endcase
  endfunction

  task write_port(input br_ram_data_rd_pipe_scoreboard_port_e port, input BrRamDataRdPipeItem item);
    case (port)
      BrRamDataRdPipeIn: write_in(item);
      BrRamDataRdPipeOut: write_out(item);
      default: ctx.check(1'b0, $sformatf("%s unknown write port %0d", ScoreboardName, port));
    endcase
  endtask

  task write_in(input BrRamDataRdPipeItem item);
    exp_q.push_back(predict(item));
  endtask

  task write_out(input BrRamDataRdPipeItem item);
    act_q.push_back(item);
  endtask

  function longint unsigned expected_cycle(input BrRamDataRdPipeItem item);
    return item.observed_cycle + longint'(expected_latency_cycles);
  endfunction

  task flush_inflight_expected_for_reset(input longint unsigned reset_cycle);
    BrRamDataRdPipeItem kept_q[$];

    if (exp_q.size() == 0) return;

    foreach (exp_q[i]) begin
      if (expected_cycle(exp_q[i]) < reset_cycle) begin
        kept_q.push_back(exp_q[i]);
      end
    end
    exp_q = kept_q;
  endtask

  function BrRamDataRdPipeItem predict(input BrRamDataRdPipeItem in_item);
    BrRamDataRdPipeItem predicted_item;

    predicted_item = new(
        in_item.valid,
        in_item.depth_tile,
        in_item.word_data,
        in_item.id,
        in_item.observed_cycle,
        in_item.observed_time
    );
    return predicted_item;
  endfunction

  task compare_item(input BrRamDataRdPipeItem exp_item, input BrRamDataRdPipeItem act_item);
    longint unsigned exp_observed_cycle;

    exp_observed_cycle = expected_cycle(exp_item);
    ctx.check(exp_item.id == act_item.id, $sformatf(
              "%s id mismatch: exp=%0d act=%0d", ScoreboardName, exp_item.id, act_item.id));
    ctx.check(exp_item.word_data === act_item.word_data, $sformatf(
              "%s data mismatch: exp=0x%0h act=0x%0h",
              ScoreboardName,
              exp_item.word_data,
              act_item.word_data
              ));
    ctx.check(act_item.observed_cycle == exp_observed_cycle, $sformatf(
              "%s latency mismatch: exp_cycle=%0d act_cycle=%0d latency=%0d",
              ScoreboardName,
              exp_observed_cycle,
              act_item.observed_cycle,
              expected_latency_cycles
              ));
  endtask

  task compare_all();
    BrRamDataRdPipeItem exp_item;
    BrRamDataRdPipeItem act_item;

    while ((exp_q.size() != 0) && (act_q.size() != 0)) begin
      exp_item = exp_q.pop_front();
      act_item = act_q.pop_front();
      compare_item(exp_item, act_item);
    end
  endtask

  task check_empty();
    ctx.check(exp_q.size() == 0, $sformatf(
              "%s has %0d unmatched expected items", ScoreboardName, exp_q.size()));
    ctx.check(act_q.size() == 0, $sformatf(
              "%s has %0d unmatched actual items", ScoreboardName, act_q.size()));
  endtask

  task check_all();
    compare_all();
    check_empty();
  endtask
endclass : br_ram_data_rd_pipe_scoreboard
