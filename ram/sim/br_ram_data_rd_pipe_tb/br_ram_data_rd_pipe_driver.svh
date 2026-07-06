// SPDX-License-Identifier: Apache-2.0

class br_ram_data_rd_pipe_driver #(
    parameter int Width = 1,
    parameter int DepthTiles = 1,
    parameter int WidthTiles = 1,
    type BrRamDataRdPipeItem = br_ram_data_rd_pipe_item#(.Width(Width))
) extends br_dv_driver #(
    .ItemType(BrRamDataRdPipeItem)
);
  local virtual br_dv_clk_rst_if clk_rst_vif;
  local virtual
  br_ram_data_rd_pipe_input_if #(
      .Width(Width),
      .DepthTiles(DepthTiles),
      .WidthTiles(WidthTiles)
  )
  in_vif;

  function new(input br_dv_context ctx, input virtual br_dv_clk_rst_if clk_rst_vif,
               input virtual br_ram_data_rd_pipe_input_if #(
                   .Width(Width),
                   .DepthTiles(DepthTiles),
                   .WidthTiles(WidthTiles)
               ) in_vif);
    super.new(ctx);
    this.clk_rst_vif = clk_rst_vif;
    this.in_vif = in_vif;
    drive_idle();
  endfunction

  function void drive_idle();
    in_vif.tile_valid <= '0;
    in_vif.tile_data  <= '0;
  endfunction

  virtual task drive_item(input BrRamDataRdPipeItem item);
    if (item == null) begin
      @(posedge clk_rst_vif.clk);
      drive_idle();
      return;
    end

    @(posedge clk_rst_vif.clk);
    in_vif.tile_valid <= '0;
    in_vif.tile_data  <= '0;
    if (item.valid) begin
      in_vif.tile_valid[item.depth_tile] <= '1;
    end
    for (int w = 0; w < WidthTiles; w++) begin
      in_vif.tile_data[item.depth_tile][w] <= item.word_data[
          w*br_math::ceil_div(Width, WidthTiles)+:br_math::ceil_div(Width, WidthTiles)];
    end
  endtask
endclass : br_ram_data_rd_pipe_driver
