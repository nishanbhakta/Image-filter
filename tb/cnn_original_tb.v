/*
  Test original accelerator to verify it still works
*/

`timescale 1ns / 1ps

module cnn_accel_original_tb;

    parameter WIDTH = 32;
    parameter ACC_WIDTH = 72;
    parameter NUM_INPUTS = 9;

    reg clk;
    reg rst;
    reg start;
    reg signed [WIDTH-1:0] input_data [0:NUM_INPUTS-1];
    reg signed [WIDTH-1:0] kernel [0:NUM_INPUTS-1];
    reg signed [WIDTH-1:0] scale_factor;
    
    wire signed [WIDTH-1:0] result;
    wire done;

    cnn_accelerator #(
        .WIDTH(WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .NUM_INPUTS(NUM_INPUTS),
        .INCLUDE_FINAL_DIVIDER(1)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .input_data(input_data),
        .kernel(kernel),
        .scale_factor(scale_factor),
        .result(result),
        .done(done),
        .div9_result_out(),
        .div9_done_out(),
        .div9_scale_out_valid(),
        .div9_scale_factor_out()
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst = 1;
        start = 0;
        
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);
        
        // Test case: All ones
        $display("Test: All ones with INCLUDE_FINAL_DIVIDER=1 (original behavior)");
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
            
            // Wait for output
            repeat (120) @(posedge clk);
            
            if (done) begin
                $display("  result = %0d (expected: 1)", result);
                if (result == 1) begin
                    $display("  PASS");
                end else begin
                    $display("  FAIL");
                end
            end else begin
                $display("  done never pulsed!");
            end
        end
        
        repeat (5) @(posedge clk);
        $finish;
    end

endmodule
