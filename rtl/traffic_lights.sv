module traffic_lights #(
  // This module will collect serial data
  // of data bus size and put it in parallel
  // form with first came bit as MSB
  parameter BLINK_HALF_PREIOD_MS  = 10,
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

  localparam G_Y_TOGGLE_PERIOD_CLK_CYCLES = BLINK_HALF_PERIOD_CLK_CYCLES * 2; 
  localparam G_BLINK_CLK_CYCLES           = BLINK_GREEN_TIME_TICK * G_Y_TOGGLE_CLK_CYCLES * 2;
  localparam RED_YELLOW_CLK_CYCLES        = RED_YELLOW_MS * 2;

  localparam CMD_SIZE                     = 3;
  localparam TTL_CTR_SIZE                 = 16;
  localparam PERIOD_SIZE                  = 16;

  logic [PERIOD_SIZE - 1:0]  yellow_period;
  logic [PERIOD_SIZE - 1:0]  green_period;
  logic [PERIOD_SIZE - 1:0]  red_period;

  logic [TTL_CTR_SIZE - 1:0] counter;
  logic [TTL_CTR_SIZE - 1:0] counter_max;

  logic                      yellow;
  logic                      green;
  logic                      red;       

  typedef enum logic [3:0] { NOTRANSITION_S,
                             R_S,
                             RY_S,
                             G_S,
                             Y_S,
                             GT_S,
                             OFF_S} state_t;
  
  state_t state, next_state;

  function state_t command_parse(input logic [CMD_SIZE - 1:0] cmd_type, 
                                       state_t current_state 
                                );
    state_t next_state;
    
    case ( cmd_type )
      (CMD_SIZE)'(0):
        next_state = R_S;

      (CMD_SIZE)'(1):
        next_state = OFF_S;

      (CMD_SIZE)'(2):
        next_state = NOTRANSITION_S;

      (CMD_SIZE)'(3), (CMD_SIZE)'(4), (CMD_SIZE)'(5):
        if ( current_state == NOTRANSITION_S )
          next_state = NOTRANSITION_S;
        else
          next_state = current_state;

      default:
        next_state = (state_t)'('x);
    endcase

    return next_state;
  endfunction

  always_ff @( posedge clk_i )
    begin
      if ( srst_i ) 
        state <= NOTRANSITION_S;
      else 
        state <= next_state;
    end

    always_comb
    begin
      next_state = state;
      case ( state )
        R_S: begin
          if ( cmd_valid_i )
            next_state = command_parse( cmd_type_i, state );
          else if ( counter == counter_max )
            next_state = RY_S;
        end

        RY_S: begin
          if ( cmd_valid_i )
            next_state = command_parse( cmd_type_i, state );
          else if ( counter == counter_max )
            next_state = G_S;
        end

        G_S: begin
          if ( cmd_valid_i )
            next_state = command_parse( cmd_type_i, state );
          else if ( counter == counter_max )
            next_state = GT_S;
        end

        GT_S: begin
          if ( cmd_valid_i )
            next_state = command_parse( cmd_type_i, state );
          else if ( counter == counter_max )
            next_state = Y_S;
        end

        Y_S: begin
          if ( cmd_valid_i )
            next_state = command_parse( cmd_type_i, state );
          else if ( counter == counter_max )
            next_state = R_S;
        end

        NOTRANSITION_S: begin
          if ( cmd_valid_i )
            next_state = command_parse( cmd_type_i, state );
        end

        OFF_S: begin
          if ( cmd_valid_i && cmd_type_i == (CMD_SIZE)'(0) )
            next_state = R_S;
        end

        default: begin
          next_state = (state_t)'('x);
        end
      endcase
    end

  always_ff @( posedge clk_i )
    begin
      if ( state == NOTRANSITION_S )
        if ( cmd_valid_i && cmd_type_i == (CMD_SIZE)'(3) )
          green_period <= cmd_data_i;
    end

  always_ff @( posedge clk_i )
    begin
      if ( state == NOTRANSITION_S )
        if ( cmd_valid_i && cmd_type_i == (CMD_SIZE)'(4) )
          red_period <= cmd_data_i;
    end

  always_ff @( posedge clk_i )
    begin
      if ( state == NOTRANSITION_S )
        if ( cmd_valid_i && cmd_type_i == (CMD_SIZE)'(5) )
          yellow_period <= cmd_data_i;
    end

  always_ff @( posedge clk_i )
    begin
      if ( srst_i )
        counter <= '0
      else 
        begin
          if ( counter == counter_max || 
               state == OFF_S || state == NOTRANSITION_S )
            counter <= '0;
          else
            counter <= counter + (PERIOD_SIZE)'(1);
        end
      
    end

  always_comb
    begin
      red_o    = 1'b0;
      yellow_o = 1'b0;
      green_o  = 1'b0;

      case ( state )
        R_S: begin
          counter_max = red_period;
          red_o = red;
        end

        RY_S: begin
          counter_max = RED_YELLOW_CLK_CYCLES;
          { red_o, yellow_o, } = { red, yellow };
        end

        G_S: begin
          counter_max = green_period;
          green_o = green;
        end

        GT_S: begin
          counter_max = G_BLINK_CLK_CYCLES;
          green_o = green;
        end

        Y_S: begin
          counter_max = yellow_period;
          yellow_o = yellow;
        end

        NOTRANSITION_S: begin
          yellow_o = yellow;
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