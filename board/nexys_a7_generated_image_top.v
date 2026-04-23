/*
  Nexys A7 board wrapper for the generated-image runner.
  This wrapper facilitates testing with pre-computed results.
  - SW[0] selects the button action:
      0 = BTN U starts one full generated-image pass
      1 = BTN U advances to the next stored output sample
  - BTN C resets the design
  - LED[15:0] show the currently selected 16-bit signed output value
  - The seven-segment display shows the current value in signed decimal
*/

module nexys_a7_generated_image_top (
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

    localparam COUNT_WIDTH = 16;

    reg btnu_meta;
    reg btnu_sync;
    reg btnu_prev;
    reg [COUNT_WIDTH-1:0] browse_index_reg;
    reg [15:0] refresh_counter;

    reg [7:0] an_reg;
    reg [6:0] seg_reg;
    reg [3:0] active_decimal_digit;
    reg [3:0] decimal_digits [0:7];
    reg show_active_digit;
    reg show_minus;
    reg display_negative;
    reg [31:0] display_magnitude;
    integer remaining_value;
    integer highest_nonzero_digit;
    integer digit_index;

    wire rst = BTNC;
    wire btnu_pulse = btnu_sync & ~btnu_prev;
    wire browse_mode = SW[0];
    wire start_pulse = btnu_pulse & ~browse_mode & ~busy;
    wire busy;
    wire done;
    wire all_match;
    wire mismatch_seen;
    wire [COUNT_WIDTH-1:0] completed_windows;
    wire [COUNT_WIDTH-1:0] mismatch_count;
    wire [COUNT_WIDTH-1:0] total_windows;
    wire signed [15:0] display_value;
    wire display_value_valid;
    wire browse_next_pulse = btnu_pulse & browse_mode & done;
    wire [15:0] led_value = display_value_valid ? display_value : completed_windows;
    wire [2:0] active_digit = refresh_counter[15:13];
    wire unused_uart_txd_in = UART_TXD_IN;

    cnn_generated_image_runner #(
        .COUNT_WIDTH(COUNT_WIDTH)
    ) generated_runner_inst (
        .clk(CLK100MHZ),
        .rst(rst),
        .start(start_pulse),
        .display_index(browse_index_reg),
        .busy(busy),
        .done(done),
        .all_match(all_match),
        .mismatch_seen(mismatch_seen),
        .completed_windows(completed_windows),
        .mismatch_count(mismatch_count),
        .total_windows(total_windows),
        .display_value(display_value),
        .display_value_valid(display_value_valid)
    );

    assign UART_RXD_OUT = 1'b1;

    always @(posedge CLK100MHZ) begin
        if (rst) begin
            btnu_meta <= 1'b0;
            btnu_sync <= 1'b0;
            btnu_prev <= 1'b0;
            browse_index_reg <= {COUNT_WIDTH{1'b0}};
            refresh_counter <= 16'd0;
        end else begin
            btnu_meta <= BTNU;
            btnu_sync <= btnu_meta;
            btnu_prev <= btnu_sync;
            refresh_counter <= refresh_counter + 1'b1;

            if (start_pulse) begin
                browse_index_reg <= {COUNT_WIDTH{1'b0}};
            end else if (browse_next_pulse && (total_windows != {COUNT_WIDTH{1'b0}})) begin
                if ((browse_index_reg + 1'b1) >= total_windows) begin
                    browse_index_reg <= {COUNT_WIDTH{1'b0}};
                end else begin
                    browse_index_reg <= browse_index_reg + 1'b1;
                end
            end
        end
    end

    always @(*) begin
        if (display_value_valid) begin
            display_negative = display_value[15];
            if (display_value[15]) begin
                display_magnitude = $unsigned((~display_value) + 1'b1);
            end else begin
                display_magnitude = $unsigned(display_value);
            end
        end else begin
            display_negative = 1'b0;
            display_magnitude = completed_windows;
        end

        remaining_value = display_magnitude;
        for (digit_index = 0; digit_index < 8; digit_index = digit_index + 1) begin
            decimal_digits[digit_index] = remaining_value % 10;
            remaining_value = remaining_value / 10;
        end

        highest_nonzero_digit = 0;
        for (digit_index = 1; digit_index < 8; digit_index = digit_index + 1) begin
            if (decimal_digits[digit_index] != 0) begin
                highest_nonzero_digit = digit_index;
            end
        end

        case (active_digit)
            3'd0: begin an_reg = 8'b11111110; active_decimal_digit = decimal_digits[0]; end
            3'd1: begin an_reg = 8'b11111101; active_decimal_digit = decimal_digits[1]; end
            3'd2: begin an_reg = 8'b11111011; active_decimal_digit = decimal_digits[2]; end
            3'd3: begin an_reg = 8'b11110111; active_decimal_digit = decimal_digits[3]; end
            3'd4: begin an_reg = 8'b11101111; active_decimal_digit = decimal_digits[4]; end
            3'd5: begin an_reg = 8'b11011111; active_decimal_digit = decimal_digits[5]; end
            3'd6: begin an_reg = 8'b10111111; active_decimal_digit = decimal_digits[6]; end
            default: begin an_reg = 8'b01111111; active_decimal_digit = decimal_digits[7]; end
        endcase

        show_active_digit = (active_digit <= highest_nonzero_digit) || (active_digit == 0);
        show_minus = display_negative
            && (highest_nonzero_digit < 7)
            && (active_digit == (highest_nonzero_digit + 1));
    end

    always @(*) begin
        if (show_minus) begin
            seg_reg = 7'b1111110;
        end else if (!show_active_digit) begin
            seg_reg = 7'b1111111;
        end else begin
            case (active_decimal_digit)
                4'd0: seg_reg = 7'b1000000;
                4'd1: seg_reg = 7'b1111001;
                4'd2: seg_reg = 7'b0100100;
                4'd3: seg_reg = 7'b0110000;
                4'd4: seg_reg = 7'b0011001;
                4'd5: seg_reg = 7'b0010010;
                4'd6: seg_reg = 7'b0000010;
                4'd7: seg_reg = 7'b1111000;
                4'd8: seg_reg = 7'b0000000;
                default: seg_reg = 7'b0010000;
            endcase
        end
    end

    assign LED = led_value;

    assign AN = an_reg;
    assign {CA, CB, CC, CD, CE, CF, CG} = seg_reg;
    assign DP = browse_mode ? 1'b0 : 1'b1;

endmodule
