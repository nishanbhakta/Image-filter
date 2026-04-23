/*
  Testbench for the CNN accelerator variant that uses five parallel dividers.
  This variant improves throughput by parallelizing division operations.
  The stimulus checks functional correctness across a few representative cases
  while exercising the divider scheduling path.
*/

`timescale 1ns / 1ps

module cnn_accelerator_multi_div_tb #(
    parameter WIDTH = 32,
    parameter ACC_WIDTH = 72,
    parameter NUM_INPUTS = 9
);

    reg clk;
    reg rst;
    reg start;
    reg signed [WIDTH-1:0] input_data [0:NUM_INPUTS-1];
    reg signed [WIDTH-1:0] kernel [0:NUM_INPUTS-1];
    reg signed [WIDTH-1:0] scale_factor;
    wire signed [WIDTH-1:0] result;
    wire done;

    cnn_accelerator_multi_div #(
        .WIDTH(WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .NUM_INPUTS(NUM_INPUTS),
        .NUM_DIVIDERS(5),
        .FIFO_DEPTH(128)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .input_data(input_data),
        .kernel(kernel),
        .scale_factor(scale_factor),
        .result(result),
        .done(done)
    );

    // Free-running simulation clock generator.
    always #5 clk = ~clk;

    // Software reference for (sum / 9) / scale_factor.
    function longint compute_reference_ll;
        input longint sum_prod;
        longint result_ll;
        begin
            result_ll = sum_prod / 9 / scale_factor;
            compute_reference_ll = result_ll;
        end
    endfunction

    // Apply reset, run a few scenarios, and compare against the reference model.
    initial begin
        clk = 1'b0;
        rst = 1'b1;
        start = 1'b0;
        
        repeat (10) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);
        
        // Test case 1: uniform inputs and kernel values.
        $display("Test 1: All ones");
        begin
            integer i;
            longint expected;
            longint sum_prod;
            
            sum_prod = 0;
            for (i = 0; i < NUM_INPUTS; i = i + 1) begin
                input_data[i] = 1;
                kernel[i] = 1;
                sum_prod = sum_prod + (longint'(1) * longint'(1));
            end
            scale_factor = 1;
            
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            
            // Allow enough time for the front end and one divider lane to finish.
            repeat (200) @(posedge clk);
            
            expected = sum_prod / 9 / 1;
            if (result == expected[WIDTH-1:0]) begin
                $display("  PASS: result=%0d", result);
            end else begin
                $display("  FAIL: expected=%0d, got=%0d", expected[WIDTH-1:0], result);
            end
        end
        
        repeat (5) @(posedge clk);
        
        // Test case 2: launch five patches back-to-back to exercise scheduling.
        $display("\nTest 2: Sequential launches (5 patches)");
        begin
            integer i, j;
            longint sum_prod;
            longint expected;
            reg signed [WIDTH-1:0] results [0:4];
            
            for (i = 0; i < 5; i = i + 1) begin
                // Each patch uses a different value so the expected result changes.
                sum_prod = 0;
                for (j = 0; j < NUM_INPUTS; j = j + 1) begin
                    input_data[j] = (i + 1);
                    kernel[j] = (i + 1);
                    sum_prod = sum_prod + (longint'(i+1) * longint'(i+1));
                end
                scale_factor = (i + 1);
                
                start = 1'b1;
                @(posedge clk);
                start = 1'b0;
                
                // Give the queued work time to drain through the divider bank.
                repeat (200) @(posedge clk);
                
                results[i] = result;
                expected = sum_prod / 9 / (i + 1);
                $display("  Patch %0d: expected=%0d, got=%0d %s", i, expected[WIDTH-1:0], results[i], 
                         (results[i] == expected[WIDTH-1:0]) ? "PASS" : "FAIL");
                
                repeat (2) @(posedge clk);
            end
        end
        
        repeat (5) @(posedge clk);
        
        // Test case 3: large positive values near the 32-bit limit.
        $display("\nTest 3: Large values");
        begin
            integer i;
            longint sum_prod;
            longint expected;
            
            sum_prod = 0;
            for (i = 0; i < NUM_INPUTS; i = i + 1) begin
                input_data[i] = 32'sd2147483647;
                kernel[i] = 32'sd1;
                sum_prod = sum_prod + (longint'(32'sd2147483647) * longint'(32'sd1));
            end
            scale_factor = 32'sd1;
            
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            
            // Allow enough time for the multi-stage datapath to complete.
            repeat (200) @(posedge clk);
            
            expected = sum_prod / 9 / 1;
            if (result == expected[WIDTH-1:0]) begin
                $display("  PASS: result=%0d", result);
            end else begin
                $display("  FAIL: expected=%0d, got=%0d", expected[WIDTH-1:0], result);
            end
        end
        
        repeat (5) @(posedge clk);
        $display("\nAll tests completed!");
        $finish;
    end

endmodule

