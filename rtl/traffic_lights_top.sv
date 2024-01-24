module traffic_lights_top (
  input  logic        clk_i,
  input  logic        srst_i,

  input  logic [2:0]  cmd_type_i,
  input  logic        cmd_valid_i,
  input  logic [15:0] cmd_data_i,
  
  output logic        red_o,
  output logic        yellow_o,
  output logic        green_o
);

  logic        srst;

  logic [2:0]  cmd_type;
  logic        cmd_valid;
  logic [15:0] cmd_data;

  logic        red_o;
  logic        yellow_o;
  logic        green_o;

  always_ff @( posedge clk_i )
    begin
      srst      <= srst_i;
      cmd_type  <= cmd_type_i;
      cmd_valid <= cmd_valid_i;
      cmd_data  <= cmd_data_i;
      
    end 

  deserializer #(
    .BLINK_HALF_PREIOD_MS  (10         ),
    .BLINK_GREEN_TIME_TICK (2          ),
    .RED_YELLOW_MS         (5          )
  ) deserializer (
    .clk_i                 ( clk_i     ),
    .srst_i                ( srst      ),
    .cmd_type_i            ( cmd_type  ),
    .cmd_valid_i           ( cmd_valid ),
    .cmd_data_i            ( cmd_data  ),
    .red_o                 ( red       ),
    .yellow_o              ( yellow    ),
    .green_o               ( green     )
);

  always_ff @( posedge clk_i )
    begin
      red_o    <= red;
      yellow_o <= yellow;
      green_o  <= green;
    end


endmodule