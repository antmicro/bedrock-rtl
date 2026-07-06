// SPDX-License-Identifier: Apache-2.0

class br_ram_data_rd_pipe_item #(
    parameter int Width = 1
) extends br_item;
  // Interface valid value represented by this item.
  bit valid;
  // Selected depth row for input traffic; zero for output traffic.
  int unsigned depth_tile;
  // Full-width word driven into or observed from the pipe.
  logic [Width-1:0] word_data;
  // Monotonic transaction index assigned by monitors.
  longint unsigned id;
  // Clock cycle when the monitor observed this item.
  longint unsigned observed_cycle;
  // Simulation time when the monitor observed this item.
  time observed_time;

  function new(input bit valid = 1'b0, input int unsigned depth_tile = 0,
               input logic [Width-1:0] word_data = '0, input longint unsigned id = 0,
               input longint unsigned observed_cycle = 0, input time observed_time = 0);
    super.new("br_ram_data_rd_pipe_item");
    this.valid = valid;
    this.depth_tile = depth_tile;
    this.word_data = word_data;
    this.id = id;
    this.observed_cycle = observed_cycle;
    this.observed_time = observed_time;
  endfunction

endclass : br_ram_data_rd_pipe_item
