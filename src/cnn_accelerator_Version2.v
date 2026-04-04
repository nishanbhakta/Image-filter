/*
  CNN Hardware Accelerator - Top Level Module
  Integrates all blocks into complete datapath
  Output = (Σ (xi × hi)) / 9 / K
*/

module cnn_accelerator #(
    parameter WIDTH = 32,
    parameter ACC_WIDTH = 72,
    parameter NUM_INPUTS = 9
) (
    input clk,
    input rst,
    input start,
    
    input signed [WIDTH-1:0] input_data [0:NUM_INPUTS-1],
    input signed [WIDTH-1:0] kernel [0:NUM_INPUTS-1],
    input signed [WIDTH-1:0] scale_factor,
    
    output signed [WIDTH-1:0] result,
    output done
);

    wire mult_start, mult_done;
    wire div9_start, div9_done;
    wire div_start, div_done;
    wire mac_reset, mac_enable;
    wire output_valid;
    
    wire signed [2*WIDTH-1:0] mult_product;
    wire signed [ACC_WIDTH-1:0] mac_result;
    wire signed [ACC_WIDTH-1:0] div9_result;
    wire signed [WIDTH-1:0] final_result;
    
    reg [3:0] input_idx;
    wire signed [WIDTH-1:0] curr_input = input_data[input_idx];
    wire signed [WIDTH-1:0] curr_kernel = kernel[input_idx];
    
    controller ctrl_inst (
        .clk(clk), .rst(rst), .start(start),
        .mult_done(mult_done), .div9_done(div9_done), .div_done(div_done),
        .mult_start(mult_start), .div9_start(div9_start), .div_start(div_start),
        .mac_reset(mac_reset), .mac_enable(mac_enable),
        .output_valid(output_valid), .state()
    );
    
    multiplier #(.WIDTH(WIDTH)) mult_inst (
        .clk(clk), .rst(rst), .start(mult_start),
        .a(curr_input), .b(curr_kernel),
        .product(mult_product), .done(mult_done)
    );
    
    mac #(.WIDTH(WIDTH), .ACC_WIDTH(ACC_WIDTH)) mac_inst (
        .clk(clk), .rst(rst), .enable(mac_enable),
        .reset_acc(mac_reset), .product_in(mult_product),
        .result(mac_result)
    );
    
    divide_by_9 #(.WIDTH(ACC_WIDTH)) div9_inst (
        .clk(clk), .rst(rst), .start(div9_start),
        .dividend(mac_result), .quotient(div9_result),
        .done(div9_done)
    );
    
    divider #(.WIDTH(WIDTH)) div_inst (
        .clk(clk), .rst(rst), .start(div_start),
        .dividend(div9_result[WIDTH-1:0]), .divisor(scale_factor),
        .quotient(final_result), .remainder(), .done(div_done)
    );
    
    assign result = final_result;
    assign done = output_valid;
    
    always @(posedge clk) begin
        if (rst) begin
            input_idx <= 4'b0;
        end
        else if (mult_done && input_idx < (NUM_INPUTS - 1)) begin
            input_idx <= input_idx + 1'b1;
        end
    end

endmodule