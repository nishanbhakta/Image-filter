/*
    Compact testbench to verify front-end accelerator outputs (divide-by-9 stage only).
    Validates the MAC pipeline and initial division stage.
*/

`timescale 1ns / 1ps

module cnn_accel_frontend_tb;

    parameter WIDTH = 32;
    parameter ACC_WIDTH = 72;
    parameter NUM_INPUTS = 9;

    reg clk;
    reg rst;
    reg start;
    reg signed [WIDTH-1:0] input_data [0:NUM_INPUTS-1];
    reg signed [WIDTH-1:0] kernel [0:NUM_INPUTS-1];
    reg signed [WIDTH-1:0] scale_factor;
    
    wire signed [ACC_WIDTH-1:0] div9_result_out;
    wire div9_done_out;
    wire div9_scale_out_valid;
    wire signed [WIDTH-1:0] div9_scale_factor_out;

    cnn_accelerator_frontend #(
        .WIDTH(WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .NUM_INPUTS(NUM_INPUTS)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .input_data(input_data),
        .kernel(kernel),
        .scale_factor(scale_factor),
        .div9_result(div9_result_out),
        .div9_done(div9_done_out),
        .div9_scale_factor(div9_scale_factor_out)
    );

    // Free-running simulation clock.
    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst = 1;
        start = 0;
        
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);
        
        // Simple smoke test with unit-valued inputs and kernel coefficients.
        $display("Test: All ones");
        begin
            integer i;
            for (i = 0; i < NUM_INPUTS; i = i + 1) begin
                input_data[i] = 1;
                kernel[i] = 1;
            end
            scale_factor = 1;
            
            start = 1;
            @(posedge clk);
            start = 0;
            
            // Wait long enough for the multiplier fanout and div9 pipeline to complete.
            repeat (20) @(posedge clk);
            
            if (div9_done_out) begin
                $display("  div9_result = %0d (expected: 1)", div9_result_out);
                $display("  div9_scale_factor = %0d (expected: 1)", div9_scale_factor_out);
                if (div9_result_out == 1 && div9_scale_factor_out == 1) begin
                    $display("  PASS");
                end else begin
                    $display("  FAIL");
                end
            end else begin
                $display("  div9_done_out never pulsed!");
            end
        end
        
        repeat (5) @(posedge clk);
        $finish;
    end

endmodule
