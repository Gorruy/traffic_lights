module top_tb;

  parameter NUMBER_OF_TEST_RUNS            = 10000;

  parameter BLINK_HALF_PERIOD_MS           = 10;
  parameter BLINK_GREEN_TIME_TICK          = 2;
  parameter RED_YELLOW_MS                  = 5;

  localparam G_Y_TOGGLE_HPERIOD_CLK_CYCLES = BLINK_HALF_PERIOD_MS * 2; 
  localparam G_BLINK_CLK_CYCLES            = BLINK_GREEN_TIME_TICK * G_Y_TOGGLE_HPERIOD_CLK_CYCLES * 2;
  localparam RED_YELLOW_CLK_CYCLES         = RED_YELLOW_MS * 2;

  localparam CMD_SIZE                      = 3;
  localparam CTR_SIZE                      = 16;
  localparam PERIOD_SIZE                   = 16;
  localparam DEFAULT_PERIOD                = 10;

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
    int                       off_time;
    int                       notransition_time;
    int                       normal_time_after_to;
    int                       normal_time_after_set; 
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

  task settle_sessions ( mailbox #( session_t ) generated_sessions );
    session_t session_to_settle;

    while ( generated_sessions.num() )
      begin
        generated_sessions.get( session_to_settle );

        if ( session_to_settle.off_time )
          begin
            put_settings( '0, '0, '0, (CMD_SIZE)'(1) );
            ##(session_to_settle.off_time);
          end

        if ( session_to_settle.normal_time_after_to )
          begin
            put_settings( '0, '0, '0, (CMD_SIZE)'(0) );
            ##(session_to_settle.normal_time_after_to);
          end

        if ( session_to_settle.notransition_time )
          begin
            put_settings( '0, '0, '0, (CMD_SIZE)'(2) );
            put_settings( session_to_settle.green_period, '0, '0, (CMD_SIZE)'(3) );
            put_settings( '0, session_to_settle.red_period, '0, (CMD_SIZE)'(4) );
            put_settings( '0, '0, session_to_settle.yellow_period, (CMD_SIZE)'(5) );
            ##(session_to_settle.notransition_time);
          end

        if ( session_to_settle.normal_time_after_set )
          begin
            put_settings( '0, '0, '0, (CMD_SIZE)'(1) );
            ##(session_to_settle.normal_time_after_set);
          end
        
      end
  endtask

  task generate_sessions ( mailbox #( session_t ) generated_sessions );

    session_t generated_session;

    repeat ( NUMBER_OF_TEST_RUNS )
      begin
        generated_session.yellow_period         = $urandom_range( 10, 1 );
        generated_session.red_period            = $urandom_range( 10, 1 );
        generated_session.green_period          = $urandom_range( 10, 1 );

        // some state transitions can be skiped to randomize configuration of session
        generated_session.off_time              = $urandom_range( 100, 0 ) * $urandom_range( 1, 0 );
        generated_session.notransition_time     = $urandom_range( 100, 0 ) * $urandom_range( 1, 0 );
        generated_session.normal_time_after_set = $urandom_range( 100, 0 ) * $urandom_range( 1, 0 );
        generated_session.normal_time_after_to  = $urandom_range( 100, 0 ) * $urandom_range( 1, 0 );

        generated_sessions.put( generated_session );
      end

  endtask

  function state_t command_parse( input logic [CMD_SIZE - 1:0] cmd_type_i,
                                        state_t                current_state );

    // This function normal set of states
    state_t next_state;

    if ( cmd_type_i === (CMD_SIZE)'(1) )
      next_state = OFF_S;
    else if ( cmd_type_i === (CMD_SIZE)'(2) )
      next_state = NOTRANSITION_S;
    else 
      next_state = current_state;

    return next_state;
    
  endfunction

  task observe_sessions;
    state_t                   current_state;
    logic                     expected_green;
    logic                     expected_yellow;
    logic [PERIOD_SIZE - 1:0] yellow_period;
    logic [PERIOD_SIZE - 1:0] red_period;
    logic [PERIOD_SIZE - 1:0] green_period;
    int                       counter;
    int                       timeout_counter;
    int                       toggling_counter;

    current_state    = R_S;
    counter          = 0;
    expected_green   = 1'b0;
    expected_yellow  = 1'b0;
    yellow_period    = (PERIOD_SIZE)'(DEFAULT_PERIOD);
    red_period       = (PERIOD_SIZE)'(DEFAULT_PERIOD);
    green_period     = (PERIOD_SIZE)'(DEFAULT_PERIOD);
    toggling_counter = 0;

    forever 
      begin
        @( posedge clk );

        if ( toggling_counter == G_Y_TOGGLE_HPERIOD_CLK_CYCLES )
          toggling_counter <= '0;
        else if ( current_state == NOTRANSITION_S || current_state == GT_S)            
          toggling_counter <= toggling_counter + 1;

        if ( toggling_counter == G_Y_TOGGLE_HPERIOD_CLK_CYCLES &&
             current_state === GT_S )
          expected_green <= ~expected_green;
        else if ( current_state !== GT_S )
          expected_green <= 1'b0;

        if ( toggling_counter == G_Y_TOGGLE_HPERIOD_CLK_CYCLES &&
             current_state === NOTRANSITION_S )
          expected_yellow <= ~expected_yellow;
        else if ( current_state !== NOTRANSITION_S )
          expected_yellow <= 1'b0;

        if ( cmd_valid_i === 1'b1 )
          begin
            timeout_counter <= 0;

            if ( current_state == NOTRANSITION_S )
              begin
                if ( cmd_type_i == (CMD_SIZE)'(3) )
                  green_period <= cmd_data_i;
                else if ( cmd_type_i == (CMD_SIZE)'(4) )
                  red_period <= cmd_data_i;
                else if ( cmd_type_i == (CMD_SIZE)'(5) )
                  yellow_period <= cmd_data_i;
              end
          end
          
        case ( current_state )
          NOTRANSITION_S: begin
            if ( { green_o, red_o, yellow_o } !== { 1'b0, 1'b0, expected_yellow } )
              begin
                test_succeed = 1'b0;
                $error( "NOTRANSITION STATE fault: not expected signal values!: g:%b, r:%b, y:%b", green_o, red_o, yellow_o);
                return;
              end

            if ( cmd_valid_i )
              begin
                case ( cmd_type_i )
                  (CMD_SIZE)'(0):
                    current_state <= R_S;
 
                  (CMD_SIZE)'(1):
                    current_state <= OFF_S;
 
                  (CMD_SIZE)'(2), (CMD_SIZE)'(3), (CMD_SIZE)'(4), (CMD_SIZE)'(5):
                    current_state <= NOTRANSITION_S;

                  default: 
                    current_state <= state_t'('x);
                endcase
              end
          end

          R_S: begin
            if ( { green_o, red_o, yellow_o } !== { 1'b0, 1'b1, 1'b0 } )
              begin
                test_succeed = 1'b0;
                $error( "Wrong colors during red state: g:%b, r:%b, y:%b", green_o, red_o, yellow_o );
                return;
              end
            if ( counter == red_period )
              begin
                current_state <= RY_S;
                counter       <= 0;
              end
          end

          RY_S: begin
            if ( { green_o, red_o, yellow_o } !== { 1'b0, 1'b1, 1'b1 } )
              begin
                test_succeed = 1'b0;
                $error( "Wrong colors during red yellow state: g:%b, r:%b, y:%b", green_o, red_o, yellow_o );
                return;
              end
            if ( counter == RED_YELLOW_CLK_CYCLES )
              begin
                current_state <= G_S;
                counter       <= 0;
              end
          end

          G_S: begin
            if ( { green_o, red_o, yellow_o } !== { 1'b1, 1'b0, 1'b0 } )
              begin
                test_succeed = 1'b0;
                $error( "Wrong colors during green state: g:%b, r:%b, y:%b", green_o, red_o, yellow_o );
                return;
              end
            if ( counter == green_period )
              begin
                current_state <= GT_S;
                counter       <= 0;
              end
          end

          GT_S: begin
            if ( { green_o, red_o, yellow_o } !== { expected_green, 1'b0, 1'b0 } )
              begin
                test_succeed = 1'b0;
                $error( "Wrong colors during green blink state: g:%b, r:%b, y:%b", green_o, red_o, yellow_o );
                return;
              end
            if ( counter == G_BLINK_CLK_CYCLES )
              begin
                current_state <= Y_S;
                counter       <= 0;
              end
          end

          Y_S: begin
            if ( { green_o, red_o, yellow_o } !== { 1'b0, 1'b0, 1'b1 } )
              begin
                test_succeed = 1'b0;
                $error( "Wrong colors during yellow state: g:%b, r:%b, y:%b", green_o, red_o, yellow_o );
                return;
              end
            if ( counter == yellow_period )
              begin
                current_state <= R_S;
                counter       <= 0;
              end
          end

          OFF_S: begin
            if ( { green_o, red_o, yellow_o } !== { 1'b0, 1'b0, 1'b0 } )
              begin
                test_succeed = 1'b0;
                $error( "Wrong colors during off state: g:%b, r:%b, y:%b", green_o, red_o, yellow_o );
                return;
              end
            if ( cmd_valid_i && cmd_type_i === (CMD_SIZE)'(0) )
              current_state <= R_S;
          end
        endcase

        if ( current_state == OFF_S || current_state == NOTRANSITION_S )
          counter <= '0;
        else
          begin 
            counter = counter + 1;
            if ( cmd_valid_i && current_state !== OFF_S && current_state !== NOTRANSITION_S )
              current_state <= command_parse( cmd_type_i, current_state );
          end

        if ( timeout_counter == 101 )
          return;
        else 
         timeout_counter += 1;

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

    fork
      observe_sessions();
      settle_sessions( generated_sessions );
    join

    $display("Simulation is over!");
    if ( test_succeed )
      $display("All tests passed!");
    $stop();
  end



endmodule