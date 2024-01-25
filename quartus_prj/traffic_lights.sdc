set_time_format -unit ms -decimal_places 2

create_clock -period 0.50 -name clk_2 -waveform {0.00 0.25} [get_ports clk_i]

derive_pll_clocks