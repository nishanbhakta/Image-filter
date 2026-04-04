/*
  Starter Nexys A7 board wrapper for the CNN accelerator.
  - BTN U starts one inference on a built-in 3x3 patch/kernel
  - BTN C resets the design
  - SW[15:0] set the positive scale factor, with 0 treated as 1
  - LED[15] shows done, LED[14] shows sign, LED[13:0] show result bits
  - The 8-digit seven-segment display shows the 32-bit result in hex
 */

module nexys_a7_top (
    input CLK100MHZ,
    input BTNC,
    input BTNU,
    input [15:0] SW,
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

    reg btnu_meta;
    reg btnu_sync;
    reg btnu_prev;
    reg [15:0] refresh_counter;

    wire rst = BTNC;
    wire start_pulse = btnu_sync & ~btnu_prev;
    wire signed [WIDTH-1:0] input_data [0:NUM_INPUTS-1];
    wire signed [WIDTH-1:0] kernel [0:NUM_INPUTS-1];
    wire signed [WIDTH-1:0] scale_factor;
    wire signed [WIDTH-1:0] result;
    wire done;

    reg [7:0] an_reg;
    reg [6:0] seg_reg;
    reg dp_reg;
    reg [3:0] hex_nibble;

    wire [2:0] active_digit = refresh_counter[15:13];
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
        .start(start_pulse),
        .input_data(input_data),
        .kernel(kernel),
        .scale_factor(scale_factor),
        .result(result),
        .done(done)
    );

    always @(posedge CLK100MHZ) begin
        btnu_meta <= BTNU;
        btnu_sync <= btnu_meta;
        btnu_prev <= btnu_sync;
        refresh_counter <= refresh_counter + 1'b1;
    end

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

    assign LED[15] = done;
    assign LED[14] = result[31];
    assign LED[13:0] = result[13:0];

    assign AN = an_reg;
    assign {CA, CB, CC, CD, CE, CF, CG} = seg_reg;
    assign DP = 1'b1;

endmodule
