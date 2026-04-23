/*
  Nexys A7 board wrapper for the CNN accelerator demo.
  This module integrates the CNN accelerator with the Nexys A7 FPGA board.

`ifdef USE_GENERATED_RESULT_ROM
  Generated-result playback mode:
  - BTN U advances through the generated 16-bit results one by one
  - BTN C resets playback to the first result
  - LED[15] indicates the final generated result is selected
  - LED[14] indicates UART transmission is active
  - LED[13] shows the result sign, LED[12:0] show result bits
  - The 8-digit seven-segment display shows the result index in the upper
    four digits and the 16-bit result value in the lower four digits
  - The displayed 16-bit value is streamed over USB-UART as 4 hex digits + CR/LF
`else
  Accelerator demo mode:
  - BTN U starts one inference on a built-in 3x3 patch/kernel
  - BTN C resets the design
  - SW[15:0] set the positive scale factor, with 0 treated as 1
  - LED[15] pulses when the accelerator completes
  - LED[14] indicates UART transmission is active
  - LED[13] shows the result sign, LED[12:0] show result bits
  - The 8-digit seven-segment display shows the 32-bit result in hex
  - The result is also streamed over USB-UART as ASCII hex + CR/LF
`endif
*/

module nexys_a7_top (
    input CLK100MHZ,
    input BTNC,
    input BTNU,
    input [15:0] SW,
    input UART_TXD_IN,
    output UART_RXD_OUT,
    output [15:0] LED,
    output CA,
    output CB,
    output CC,
    output CD,
    output CE,
    output CF,
    output CG,
    output DP,
    output [7:0] AN
);

    localparam WIDTH = 32;
    localparam ACC_WIDTH = 72;
    localparam NUM_INPUTS = 9;

`ifdef USE_GENERATED_RESULT_ROM
`include "generated_board_results.vh"
    localparam integer GENERATED_RESULT_INDEX_WIDTH =
        (GENERATED_BOARD_RESULT_COUNT <= 1) ? 1 : $clog2(GENERATED_BOARD_RESULT_COUNT);
`endif

    reg btnu_meta;
    reg btnu_sync;
    reg btnu_prev;
    reg [15:0] refresh_counter;

    wire rst = BTNC;
    wire btnu_pulse = btnu_sync & ~btnu_prev;
    wire uart_busy;
    wire uart_done;

    reg [7:0] an_reg;
    reg [6:0] seg_reg;
    reg [3:0] hex_nibble;

    wire [2:0] active_digit = refresh_counter[15:13];

`ifdef USE_GENERATED_RESULT_ROM
    reg [GENERATED_RESULT_INDEX_WIDTH-1:0] playback_index;
    reg [15:0] uart_result_value;
    reg uart_start_reg;

    wire playback_at_last =
        (playback_index == (GENERATED_BOARD_RESULT_COUNT - 1));
    wire [GENERATED_RESULT_INDEX_WIDTH-1:0] playback_index_next =
        playback_at_last ? {GENERATED_RESULT_INDEX_WIDTH{1'b0}} : (playback_index + 1'b1);
    wire [15:0] playback_index_display = playback_index;
    wire signed [15:0] current_generated_result =
        generated_board_results[playback_index];
    wire [31:0] result_display = {
        playback_index_display,
        current_generated_result[15:0]
    };

    uart_result_streamer #(
        .CLK_FREQ_HZ(100_000_000),
        .BAUD_RATE(115_200),
        .RESULT_WIDTH(16)
    ) uart_streamer_inst (
        .clk(CLK100MHZ),
        .rst(rst),
        .start(uart_start_reg),
        .result(uart_result_value),
        .tx(UART_RXD_OUT),
        .busy(uart_busy),
        .done(uart_done)
    );
`else
    wire signed [WIDTH-1:0] input_data [0:NUM_INPUTS-1];
    wire signed [WIDTH-1:0] kernel [0:NUM_INPUTS-1];
    wire signed [WIDTH-1:0] scale_factor;
    wire signed [WIDTH-1:0] result;
    wire done;
    wire [WIDTH-1:0] fifo_dout;
    wire fifo_full;
    wire fifo_empty;
    wire fifo_wr_en;
    reg fifo_rd_en;
    reg uart_start_reg;
    reg [WIDTH-1:0] uart_result_value;
    wire [31:0] result_display = result;

    assign scale_factor = (SW == 16'd0) ? 32'sd1 : $signed({16'd0, SW});

    assign input_data[0] = 32'sd10;
    assign input_data[1] = 32'sd20;
    assign input_data[2] = 32'sd30;
    assign input_data[3] = 32'sd40;
    assign input_data[4] = 32'sd50;
    assign input_data[5] = 32'sd60;
    assign input_data[6] = 32'sd70;
    assign input_data[7] = 32'sd80;
    assign input_data[8] = 32'sd90;

    assign kernel[0] = 32'sd1;
    assign kernel[1] = 32'sd0;
    assign kernel[2] = -32'sd1;
    assign kernel[3] = 32'sd1;
    assign kernel[4] = 32'sd0;
    assign kernel[5] = -32'sd1;
    assign kernel[6] = 32'sd1;
    assign kernel[7] = 32'sd0;
    assign kernel[8] = -32'sd1;

    cnn_accelerator #(
        .WIDTH(WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .NUM_INPUTS(NUM_INPUTS)
    ) dut (
        .clk(CLK100MHZ),
        .rst(rst),
        .start(btnu_pulse),
        .input_data(input_data),
        .kernel(kernel),
        .scale_factor(scale_factor),
        .result(result),
        .done(done)
    );

    assign fifo_wr_en = done;

    sync_fifo #(
        .WIDTH(WIDTH),
        .DEPTH(16)
    ) result_fifo_inst (
        .clk(CLK100MHZ),
        .rst(rst),
        .wr_en(fifo_wr_en),
        .rd_en(fifo_rd_en),
        .din(result),
        .dout(fifo_dout),
        .full(fifo_full),
        .empty(fifo_empty)
    );

    uart_result_streamer #(
        .CLK_FREQ_HZ(100_000_000),
        .BAUD_RATE(115_200)
    ) uart_streamer_inst (
        .clk(CLK100MHZ),
        .rst(rst),
        .start(uart_start_reg),
        .result(uart_result_value),
        .tx(UART_RXD_OUT),
        .busy(uart_busy),
        .done(uart_done)
    );

    always @(posedge CLK100MHZ) begin
        if (rst) begin
            fifo_rd_en <= 1'b0;
            uart_start_reg <= 1'b0;
            uart_result_value <= {WIDTH{1'b0}};
        end else begin
            fifo_rd_en <= 1'b0;
            uart_start_reg <= 1'b0;

            if (!uart_busy && !fifo_empty) begin
                fifo_rd_en <= 1'b1;
                uart_result_value <= fifo_dout;
                uart_start_reg <= 1'b1;
            end
        end
    end
`endif

    always @(posedge CLK100MHZ) begin
        btnu_meta <= BTNU;
        btnu_sync <= btnu_meta;
        btnu_prev <= btnu_sync;
        refresh_counter <= refresh_counter + 1'b1;
    end

`ifdef USE_GENERATED_RESULT_ROM
    always @(posedge CLK100MHZ) begin
        if (rst) begin
            playback_index <= {GENERATED_RESULT_INDEX_WIDTH{1'b0}};
            uart_result_value <= generated_board_results[0];
            uart_start_reg <= 1'b0;
        end else begin
            uart_start_reg <= 1'b0;

            if (btnu_pulse && !uart_busy) begin
                playback_index <= playback_index_next;
                uart_result_value <= generated_board_results[playback_index_next];
                uart_start_reg <= 1'b1;
            end
        end
    end
`endif

    always @(*) begin
        case (active_digit)
            3'd0: begin an_reg = 8'b11111110; hex_nibble = result_display[3:0]; end
            3'd1: begin an_reg = 8'b11111101; hex_nibble = result_display[7:4]; end
            3'd2: begin an_reg = 8'b11111011; hex_nibble = result_display[11:8]; end
            3'd3: begin an_reg = 8'b11110111; hex_nibble = result_display[15:12]; end
            3'd4: begin an_reg = 8'b11101111; hex_nibble = result_display[19:16]; end
            3'd5: begin an_reg = 8'b11011111; hex_nibble = result_display[23:20]; end
            3'd6: begin an_reg = 8'b10111111; hex_nibble = result_display[27:24]; end
            default: begin an_reg = 8'b01111111; hex_nibble = result_display[31:28]; end
        endcase
    end

    always @(*) begin
        case (hex_nibble)
            4'h0: seg_reg = 7'b1000000;
            4'h1: seg_reg = 7'b1111001;
            4'h2: seg_reg = 7'b0100100;
            4'h3: seg_reg = 7'b0110000;
            4'h4: seg_reg = 7'b0011001;
            4'h5: seg_reg = 7'b0010010;
            4'h6: seg_reg = 7'b0000010;
            4'h7: seg_reg = 7'b1111000;
            4'h8: seg_reg = 7'b0000000;
            4'h9: seg_reg = 7'b0010000;
            4'hA: seg_reg = 7'b0001000;
            4'hB: seg_reg = 7'b0000011;
            4'hC: seg_reg = 7'b1000110;
            4'hD: seg_reg = 7'b0100001;
            4'hE: seg_reg = 7'b0000110;
            default: seg_reg = 7'b0001110;
        endcase
    end

`ifdef USE_GENERATED_RESULT_ROM
    assign LED[15] = playback_at_last;
    assign LED[14] = uart_busy;
    assign LED[13] = current_generated_result[15];
    assign LED[12:0] = current_generated_result[12:0];
`else
    assign LED[15] = done;
    assign LED[14] = uart_busy;
    assign LED[13] = result[31];
    assign LED[12:0] = result[12:0];
`endif

    assign AN = an_reg;
    assign {CA, CB, CC, CD, CE, CF, CG} = seg_reg;
    assign DP = 1'b1;

endmodule
