module top_tb;

  parameter NUMBER_OF_TEST_RUNS            = 100;

  parameter BLINK_HALF_PERIOD_MS           = 10;
  parameter BLINK_GREEN_TIME_TICK          = 2;
  parameter RED_YELLOW_MS                  = 5;

  localparam G_Y_TOGGLE_HPERIOD_CLK_CYCLES = BLINK_HALF_PERIOD_MS * 2; 
  localparam G_BLINK_CLK_CYCLES            = BLINK_GREEN_TIME_TICK * G_Y_TOGGLE_HPERIOD_CLK_CYCLES * 2;
  localparam RED_YELLOW_CLK_CYCLES         = RED_YELLOW_MS * 2;

  localparam CMD_SIZE                      = 3;
  localparam CTR_SIZE                      = 16;
  localparam PERIOD_SIZE                   = 16;

  bit          clk;
  logic        srst;

  logic [2:0]  cmd_type_i;
  logic        cmd_valid_i;
  logic [15:0] cmd_data_i;

  logic        red_o;
  logic        yellow_o;
  logic        green_o;

  

  // flag to indicate if there is an error
  bit test_succeed;

  logic srst_done;

  initial forever #5 clk = !clk;

  default clocking cb @( posedge clk );
  endclocking

  initial 
    begin
      srst      <= 1'b0;
      ##1;
      srst      <= 1'b1;
      ##1;
      srst      <= 1'b0;
      srst_done <= 1'b1;
    end

  traffic_lights #(
    .BLINK_HALF_PERIOD_MS  ( 10          ),
    .BLINK_GREEN_TIME_TICK ( 2           ),
    .RED_YELLOW_MS         ( 5           )
  ) traffic_lights (
    .clk_i                 ( clk         ),
    .srst_i                ( srst        ),
    .cmd_type_i            ( cmd_type_i  ),
    .cmd_valid_i           ( cmd_valid_i ),
    .cmd_data_i            ( cmd_data_i  ),
    .red_o                 ( red_o       ),
    .yellow_o              ( yellow_o    ),
    .green_o               ( green_o     )
  );

  typedef struct { logic [PERIOD_SIZE - 1:0] yellow_period;
                   logic [PERIOD_SIZE - 1:0] red_period;
                   logic [PERIOD_SIZE - 1:0] green_period;
                   int                       off_time;
                   int                       notransition_time;
                   int                       normal_time_after_to;
                   int                       normal_time_after_set; } session_t;

  mailbox #( session_t ) generated_sessions = new();

  task put_settings ( input logic [PERIOD_SIZE - 1:0] green_period,
                            logic [PERIOD_SIZE - 1:0] red_period, 
                            logic [PERIOD_SIZE - 1:0] yellow_period, 
                            logic [CMD_SIZE - 1:0]    cmd_type 
                    );
    cmd_type_i  = cmd_type;
    cmd_valid_i = 1'b1;

    case ( cmd_type )
      (CMD_SIZE)'(3):
        cmd_data_i = green_period;

      (CMD_SIZE)'(4):
        cmd_data_i = red_period;

      (CMD_SIZE)'(5):
        cmd_data_i = yellow_period;

      default:
        cmd_data_i = '0;
    endcase

    ##1;

    cmd_type_i  = '0;
    cmd_valid_i = 1'b0;
    cmd_data_i  = '0;

  endtask

  function void display_error ( );

  endfunction

  task settle_sessions ( mailbox #( session_t ) generated_sessions );
    session_t session_to_settle;

    while ( generated_sessions.num() )
      begin
        generated_sessions.get( session_to_settle );

        put_settings( '0, '0, '0, (CMD_SIZE)'(1) );
        ##(session_to_settle.off_time);

        put_settings( '0, '0, '0, (CMD_SIZE)'(0) );
        ##(session_to_settle.normal_time_after_to);

        put_settings( '0, '0, '0, (CMD_SIZE)'(2) );
        put_settings( session_to_settle.green_period, '0, '0, (CMD_SIZE)'(3) );
        put_settings( '0, session_to_settle.red_period, '0, (CMD_SIZE)'(4) );
        put_settings( '0, '0, session_to_settle.yellow_period, (CMD_SIZE)'(5) );
        ##(session_to_settle.notransition_time);

        put_settings( '0, '0, '0, (CMD_SIZE)'(1) );
        ##(session_to_settle.normal_time_after_set);
        
      end
  endtask

  task generate_sessions ( mailbox #( session_t ) generated_sessions );

    session_t generated_session;

    repeat ( NUMBER_OF_TEST_RUNS )
      begin
        generated_session.yellow_period         = $urandom_range( 100, 0 );
        generated_session.red_period            = $urandom_range( 100, 0 );
        generated_session.green_period          = $urandom_range( 100, 0 );
        generated_session.off_time              = $urandom_range( 100, 0 );
        generated_session.notransition_time     = $urandom_range( 100, 0 );
        generated_session.normal_time_after_set = $urandom_range( 100, 0 );
        generated_session.normal_time_after_to  = $urandom_range( 100, 0 );

        generated_sessions.put( generated_session );
      end

  endtask

  task read_data ( mailbox #( session_t ) output_data );

  endtask

  initial begin
    test_succeed   <= 1'b1;

    $display("Simulation started!");
    generate_sessions( generated_sessions );
    wait( srst_done === 1'b1 );

    fork
      settle_sessions( generated_sessions );
    join

    $display("Simulation is over!");
    if ( test_succeed )
      $display("All tests passed!");
    $stop();
  end



endmodule