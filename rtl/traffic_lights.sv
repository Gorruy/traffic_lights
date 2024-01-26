module traffic_lights #(
  // This module will collect serial data
  // of data bus size and put it in parallel
  // form with first came bit as MSB
  parameter BLINK_HALF_PERIOD_MS  = 10,
  parameter BLINK_GREEN_TIME_TICK = 2,
  parameter RED_YELLOW_MS         = 5
)(
  input  logic        clk_i,
  input  logic        srst_i,

  input  logic [2:0]  cmd_type_i,
  input  logic        cmd_valid_i,
  input  logic [15:0] cmd_data_i,

  output logic        red_o,
  output logic        yellow_o,
  output logic        green_o
);

  localparam G_Y_TOGGLE_HPERIOD_CLK_CYCLES = BLINK_HALF_PERIOD_MS * 2; 
  localparam G_BLINK_CLK_CYCLES            = BLINK_GREEN_TIME_TICK * G_Y_TOGGLE_HPERIOD_CLK_CYCLES * 2;
  localparam RED_YELLOW_CLK_CYCLES         = RED_YELLOW_MS * 2;

  localparam CMD_SIZE                      = 3;
  localparam CTR_SIZE                      = 16;
  localparam PERIOD_SIZE                   = 16;
  localparam DEFAULT_PERIOD                = 10;

  logic [PERIOD_SIZE - 1:0]  yellow_period;
  logic [PERIOD_SIZE - 1:0]  green_period;
  logic [PERIOD_SIZE - 1:0]  red_period;

  logic [CTR_SIZE - 1:0]     counter;
  logic [CTR_SIZE - 1:0]     counter_max;
  logic [CTR_SIZE - 1:0]     toggling_counter;

  logic                      yellow_toggle;
  logic                      green_toggle;      

  typedef enum logic [3:0] { 
    NOTRANSITION_S,
    R_S,
    RY_S,
    G_S,
    Y_S,
    GT_S,
    OFF_S 
  } state_t;
  
  state_t state, next_state;

  function state_t command_type_parse( input logic [CMD_SIZE - 1:0] cmd_type, 
                                        state_t                current_state 
                                     );
    state_t next_state;

    case ( cmd_type )
      (CMD_SIZE)'(0):
        begin
          if ( current_state == NOTRANSITION_S || current_state == OFF_S )
            next_state = R_S;
          else 
            next_state = current_state;
        end

      (CMD_SIZE)'(1):
        begin
          next_state = OFF_S;
        end

      (CMD_SIZE)'(2):
        begin
          next_state = NOTRANSITION_S;
        end

      (CMD_SIZE)'(3), (CMD_SIZE)'(4), (CMD_SIZE)'(5):
        begin
          if ( current_state == NOTRANSITION_S )
            next_state = NOTRANSITION_S;
          else
            next_state = current_state;
        end

      default:
        next_state = state_t'('x);
    endcase

    return next_state;

  endfunction

  always_ff @( posedge clk_i )
    begin
      if ( srst_i ) 
        state <= R_S;
      else 
        state <= next_state;
    end

  always_comb
    begin
      next_state = state;
      
      case ( state )
        R_S: begin
          if ( cmd_valid_i )
            next_state = command_type_parse( cmd_type_i, state );
          else if ( counter == counter_max )
            next_state = RY_S;
        end

        RY_S: begin
          if ( cmd_valid_i )
            next_state = command_type_parse( cmd_type_i, state );
          else if ( counter == counter_max )
            next_state = G_S;
        end

        G_S: begin
          if ( cmd_valid_i )
            next_state = command_type_parse( cmd_type_i, state );
          else if ( counter == counter_max )
            next_state = GT_S;
        end

        GT_S: begin
          if ( cmd_valid_i )
            next_state = command_type_parse( cmd_type_i, state );
          else if ( counter == counter_max )
            next_state = Y_S;
        end

        Y_S: begin
          if ( cmd_valid_i )
            next_state = command_type_parse( cmd_type_i, state );
          else if ( counter == counter_max )
            next_state = R_S;
        end

        NOTRANSITION_S: begin
          if ( cmd_valid_i )
            next_state = command_type_parse( cmd_type_i, state );
        end

        OFF_S: begin
          if ( cmd_valid_i && cmd_type_i == (CMD_SIZE)'(0) )
            next_state = R_S;
        end

        default: begin
          next_state = state_t'('x);
        end
      endcase
    end

  always_ff @( posedge clk_i )
    begin
      if ( srst_i )
        green_period <= (PERIOD_SIZE)'(DEFAULT_PERIOD);
      else if ( state == NOTRANSITION_S && cmd_valid_i && cmd_type_i == (CMD_SIZE)'(3) )
        green_period <= cmd_data_i;
      
    end

  always_ff @( posedge clk_i )
    begin
      if ( srst_i )
        red_period <= (PERIOD_SIZE)'(DEFAULT_PERIOD);
      else if ( state == NOTRANSITION_S && cmd_valid_i && cmd_type_i == (CMD_SIZE)'(4) )
        red_period <= cmd_data_i;
    end

  always_ff @( posedge clk_i )
    begin
      if ( srst_i )
        yellow_period <= (PERIOD_SIZE)'(DEFAULT_PERIOD);
      else if ( state == NOTRANSITION_S && cmd_valid_i && cmd_type_i == (CMD_SIZE)'(5) )
        yellow_period <= cmd_data_i;
    end

  always_ff @( posedge clk_i )
    begin
      if ( srst_i )
        counter <= '0;
      else 
        begin
          if ( counter == counter_max || 
               state == OFF_S || state == NOTRANSITION_S )
            counter <= '0;
          else
            counter <= counter + (PERIOD_SIZE)'(1);
        end
      
    end

  always_ff @( posedge clk_i )
    begin
      if ( srst_i )
        toggling_counter <= '0;
      else
        begin
          if ( toggling_counter == G_Y_TOGGLE_HPERIOD_CLK_CYCLES )
            toggling_counter <= '0;
          else if ( state == GT_S || state == NOTRANSITION_S )
            toggling_counter <= toggling_counter + (CTR_SIZE)'(1);
        end
    end

  always_ff @( posedge clk_i )
    begin
      if ( state != GT_S )
        green_toggle <= 1'b0;
      else if ( state == GT_S )
        if ( toggling_counter == G_Y_TOGGLE_HPERIOD_CLK_CYCLES )
          green_toggle <= ~green_toggle;
    end

  always_ff @( posedge clk_i )
    begin
      if ( state != NOTRANSITION_S )
        yellow_toggle <= 1'b0;
      else if ( state == NOTRANSITION_S )
        if ( toggling_counter == G_Y_TOGGLE_HPERIOD_CLK_CYCLES )
          yellow_toggle <= ~yellow_toggle;
    end

  always_comb
    begin
      red_o       = 1'b0;
      yellow_o    = 1'b0;
      green_o     = 1'b0;
      counter_max = '0;

      case ( state )
        R_S: begin
          counter_max = red_period;
          red_o       = 1'b1;
        end

        RY_S: begin
          counter_max         = (CTR_SIZE)'(RED_YELLOW_CLK_CYCLES);
          { red_o, yellow_o } = { 1'b1, 1'b1 };
        end

        G_S: begin
          counter_max = green_period;
          green_o     = 1'b1;
        end

        GT_S: begin
          counter_max = (CTR_SIZE)'(G_BLINK_CLK_CYCLES);
          green_o     = green_toggle;
        end

        Y_S: begin
          counter_max = yellow_period;
          yellow_o    = 1'b1;
        end

        NOTRANSITION_S: begin
          yellow_o = yellow_toggle;
        end

        OFF_S: begin
          { red_o, yellow_o, green_o } = { 1'b0, 1'b0, 1'b0 };
        end

        default: begin
          { red_o, yellow_o, green_o } = { 'x, 'x, 'x };
        end
      endcase
    end

endmodule