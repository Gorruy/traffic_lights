module top_tb;

  parameter NUMBER_OF_TEST_RUNS            = 10;

  parameter BLINK_HALF_PERIOD_MS           = 11;
  parameter BLINK_GREEN_TIME_TICK          = 2;
  parameter RED_YELLOW_MS                  = 5;

  localparam G_Y_TOGGLE_HPERIOD_CLK_CYCLES = BLINK_HALF_PERIOD_MS * 2; 
  localparam G_BLINK_CLK_CYCLES            = BLINK_GREEN_TIME_TICK * G_Y_TOGGLE_HPERIOD_CLK_CYCLES * 2;
  localparam RED_YELLOW_CLK_CYCLES         = RED_YELLOW_MS * 2;

  localparam CMD_SIZE                      = 3;
  localparam CTR_SIZE                      = 16;
  localparam PERIOD_SIZE                   = 16;
  localparam DEFAULT_PERIOD                = 10;

  localparam MAX_PERIOD                    = 15;
  localparam MIN_PERIOD                    = 5;
  localparam NOTRANSITION_TIME             = 20;
  localparam OFF_TIME                      = 30;

  bit                       clk;
  logic                     srst;

  logic [CMD_SIZE - 1:0]    cmd_type_i;
  logic                     cmd_valid_i;
  logic [PERIOD_SIZE - 1:0] cmd_data_i;

  logic                     red_o;
  logic                     yellow_o;
  logic                     green_o;

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
    .BLINK_HALF_PERIOD_MS  ( BLINK_HALF_PERIOD_MS  ),
    .BLINK_GREEN_TIME_TICK ( BLINK_GREEN_TIME_TICK ),
    .RED_YELLOW_MS         ( RED_YELLOW_MS         )
  ) DUT (
    .clk_i                 ( clk                   ),
    .srst_i                ( srst                  ),
    .cmd_type_i            ( cmd_type_i            ),
    .cmd_valid_i           ( cmd_valid_i           ),
    .cmd_data_i            ( cmd_data_i            ),
    .red_o                 ( red_o                 ),
    .yellow_o              ( yellow_o              ),
    .green_o               ( green_o               )
  );

  typedef struct { 
    logic [PERIOD_SIZE - 1:0] yellow_period;
    logic [PERIOD_SIZE - 1:0] red_period;
    logic [PERIOD_SIZE - 1:0] green_period;
  } session_t;

  typedef enum logic [3:0] { 
    R_S,
    RY_S,
    G_S,
    GT_S,
    Y_S,
    OFF_S,
    NOTRANSITION_S 
  } state_t;

  typedef enum logic [2:0] {
    ON,
    OFF,
    TO_NOTRANSITION,
    GREEN_SET,
    RED_SET,
    YELLOW_SET
  } command_t;

  command_t commands;

  mailbox #( session_t ) generated_sessions = new();
  mailbox #( session_t ) input_sessions     = new();

  event off, on, notransition;

  task put_settings ( input logic [PERIOD_SIZE - 1:0] period, 
                            logic [CMD_SIZE - 1:0]    cmd_type 
                    );
    cmd_type_i  = cmd_type;
    cmd_valid_i = 1'b1;

    case ( cmd_type )
      GREEN_SET:
        cmd_data_i = period;

      RED_SET:
        cmd_data_i = period;

      YELLOW_SET:
        cmd_data_i = period;

      default:
        cmd_data_i = '0;
    endcase

    ##1;

    cmd_type_i  = '0;
    cmd_valid_i = 1'b0;
    cmd_data_i  = '0;

  endtask

  task settle_sessions ( mailbox #( session_t ) generated_sessions,
                         mailbox #( session_t ) input_sessions
                       );
    session_t session_to_settle;

    while ( generated_sessions.num() )
      begin
        generated_sessions.get( session_to_settle );
        input_sessions.put( session_to_settle );

        put_settings( session_to_settle.green_period, GREEN_SET );
        put_settings( session_to_settle.red_period, RED_SET );
        put_settings( session_to_settle.yellow_period, YELLOW_SET );

        put_settings( '0, OFF );
        ->off;
        ##( OFF_TIME );

        put_settings( '0, ON );
        ->on;
        ##( session_to_settle.green_period + session_to_settle.red_period + 
        session_to_settle.yellow_period + G_BLINK_CLK_CYCLES + RED_YELLOW_CLK_CYCLES );

        put_settings( '0, TO_NOTRANSITION );
        ->notransition;
        ##( NOTRANSITION_TIME );
        
      end
  endtask

  task generate_sessions ( mailbox #( session_t ) generated_sessions );

    session_t generated_session;

    repeat ( NUMBER_OF_TEST_RUNS )
      begin
        generated_session.yellow_period = $urandom_range( MAX_PERIOD, MIN_PERIOD );
        generated_session.red_period    = $urandom_range( MAX_PERIOD, MIN_PERIOD );
        generated_session.green_period  = $urandom_range( MAX_PERIOD, MIN_PERIOD );

        generated_sessions.put( generated_session );
      end

  endtask

  task observe_sessions ( mailbox #( session_t ) input_sessions );

    logic     prev_yellow;
    logic     prev_green;
    int       counter;
    session_t current_session;
    
    repeat ( NUMBER_OF_TEST_RUNS )
      begin
        input_sessions.get( current_session );

        wait ( off.triggered );

        repeat ( OFF_TIME )
          begin
            @( posedge clk );
            if ( { green_o, red_o, yellow_o } !== { 1'b0, 1'b0, 1'b0 } )
              begin
                test_succeed = 1'b0;
                $error( "Wrong colors during off state: g:%b, r:%b, y:%b", green_o, red_o, yellow_o );
                return;
              end
          end

        wait ( on.triggered );

        repeat ( current_session.red_period )
          begin
            @( posedge clk );
            if ( { green_o, red_o, yellow_o } !== { 1'b0, 1'b1, 1'b0 } )
              begin
                test_succeed = 1'b0;
                $error( "Wrong colors during red state: g:%b, r:%b, y:%b", green_o, red_o, yellow_o );
                return;
              end
          end

        repeat ( RED_YELLOW_CLK_CYCLES )
          begin
            @( posedge clk );
            if ( { green_o, red_o, yellow_o } !== { 1'b0, 1'b1, 1'b1 } )
              begin
                test_succeed = 1'b0;
                $error( "Wrong colors during red yellow state: g:%b, r:%b, y:%b", green_o, red_o, yellow_o );
                return;
              end
          end

        repeat ( current_session.green_period )
          begin
            @( posedge clk );
            if ( { green_o, red_o, yellow_o } !== { 1'b1, 1'b0, 1'b0 } )
              begin
                test_succeed = 1'b0;
                $error( "Wrong colors during green state: g:%b, r:%b, y:%b", green_o, red_o, yellow_o );
                return;
              end
          end

        #1;
        counter    = 0;
        prev_green = green_o;
        repeat ( G_BLINK_CLK_CYCLES )
          begin
            @( posedge clk );
            if ( { red_o, yellow_o } !== { 1'b0, 1'b0 } )
              begin
                test_succeed = 1'b0;
                $error( "Wrong colors during green blink state: g:%b, r:%b, y:%b", green_o, red_o, yellow_o );
                return;
              end
            if ( counter >= G_Y_TOGGLE_HPERIOD_CLK_CYCLES - 1 )
              begin
                #1;
                counter = 0;
                if ( prev_green !== !green_o )
                  begin
                    test_succeed = 1'b0;
                    $error( "Wrong colors during green blink state: g:%b, r:%b, y:%b", green_o, red_o, yellow_o );
                    return;
                  end
                else 
                  begin
                    prev_green = green_o;
                    continue;
                  end
              end
            else
              begin
                counter += 1;
              end
          end

        repeat ( current_session.yellow_period )
          begin
            @( posedge clk );
            if ( { green_o, red_o, yellow_o } !== { 1'b0, 1'b0, 1'b1 } )
              begin
                test_succeed = 1'b0;
                $error( "Wrong colors during yellow state: g:%b, r:%b, y:%b", green_o, red_o, yellow_o );
                return;
              end
          end

        wait ( notransition.triggered );

        #1;
        counter     = 0;
        prev_yellow = yellow_o;
        repeat ( NOTRANSITION_TIME - 1 )
          begin
            @( posedge clk );
            if ( counter >= G_Y_TOGGLE_HPERIOD_CLK_CYCLES - 1 )
              begin
                counter = 0;
                if ( { green_o, red_o, prev_yellow } !== { !yellow_o, 1'b0, 1'b0 })
                  begin
                    test_succeed = 1'b0;
                    $error( "NOTRANSITION fault: not expected signal values!: g:%b, r:%b, y:%b", green_o, red_o, yellow_o);
                    return;
                  end
                else 
                  begin
                    prev_yellow = yellow_o;
                    continue;
                  end
              end
            else
              begin
                counter += 1;
              end
          end
      end
  endtask

  initial begin
    test_succeed <= 1'b1;
    cmd_data_i   <= '0;
    cmd_type_i   <= '0;
    cmd_valid_i  <= 1'b0;

    $display("Simulation started!");
    generate_sessions( generated_sessions );
    wait( srst_done === 1'b1 );
    put_settings( '0, TO_NOTRANSITION );

    fork
      observe_sessions( input_sessions );
      settle_sessions( generated_sessions, input_sessions );
    join

    $display("Simulation is over!");
    if ( test_succeed )
      $display("All tests passed!");
    $stop();
  end



endmodule