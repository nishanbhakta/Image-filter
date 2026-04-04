/*
  CNN Accelerator Testbench
  Tests the complete CNN accelerator with various input patterns
  Formula: Output = (Σ(xi × hi)) / 9 / K
*/

`timescale 1ns/1ps

module cnn_accelerator_tb;

    // Parameters
    parameter WIDTH = 32;
    parameter ACC_WIDTH = 72;
    parameter NUM_INPUTS = 9;
    parameter CLK_PERIOD = 10;
    
    // Testbench signals
    reg clk;
    reg rst;
    reg start;
    reg signed [WIDTH-1:0] input_data [0:NUM_INPUTS-1];
    reg signed [WIDTH-1:0] kernel [0:NUM_INPUTS-1];
    reg signed [WIDTH-1:0] scale_factor;
    wire signed [WIDTH-1:0] result;
    wire done;
    
    // Test tracking
    integer test_num;
    reg signed [WIDTH-1:0] expected_result;
    integer i;

`ifdef USE_GENERATED_IMAGE_DATA
`include "generated_windows.vh"
`endif
    
    // DUT instantiation
    cnn_accelerator #(
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
        .result(result),
        .done(done)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Waveform dump
    initial begin
        $dumpfile("cnn_accelerator_tb.vcd");
        $dumpvars(0, cnn_accelerator_tb);
    end
    
    // Test stimulus
    initial begin
        $display("========================================");
        $display("CNN Accelerator Testbench Started");
        $display("========================================");
        
        // Initialize
        test_num = 0;
        rst = 1;
        start = 0;
        
        // Initialize arrays
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = 0;
            kernel[i] = 0;
        end
        scale_factor = 1;
        
        // Reset
        #(CLK_PERIOD * 2);
        rst = 0;
        #(CLK_PERIOD);
        
`ifdef USE_GENERATED_IMAGE_DATA
        run_generated_tests();
`else
        // Test 1: Simple uniform inputs
        test_num = 1;
        $display("\n--- Test %0d: Uniform inputs (all 1s) ---", test_num);
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = 32'd1;
            kernel[i] = 32'd1;
        end
        scale_factor = 32'd1;
        // Expected: (1*1 + 1*1 + ... 9 times) / 9 / 1 = 9/9/1 = 1
        expected_result = 32'd1;
        run_test();
        
        // Test 2: Different scale factor
        test_num = 2;
        $display("\n--- Test %0d: Uniform inputs with scale factor 3 ---", test_num);
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = 32'd3;
            kernel[i] = 32'd3;
        end
        scale_factor = 32'd3;
        // Expected: (3*3 * 9) / 9 / 3 = 81 / 9 / 3 = 9 / 3 = 3
        expected_result = 32'd3;
        run_test();
        
        // Test 3: Mixed positive values
        test_num = 3;
        $display("\n--- Test %0d: Mixed positive values ---", test_num);
        input_data[0] = 32'd10; kernel[0] = 32'd2;
        input_data[1] = 32'd20; kernel[1] = 32'd3;
        input_data[2] = 32'd30; kernel[2] = 32'd1;
        input_data[3] = 32'd5;  kernel[3] = 32'd4;
        input_data[4] = 32'd15; kernel[4] = 32'd2;
        input_data[5] = 32'd25; kernel[5] = 32'd1;
        input_data[6] = 32'd8;  kernel[6] = 32'd3;
        input_data[7] = 32'd12; kernel[7] = 32'd2;
        input_data[8] = 32'd18; kernel[8] = 32'd1;
        scale_factor = 32'd2;
        // Sum = 10*2 + 20*3 + 30*1 + 5*4 + 15*2 + 25*1 + 8*3 + 12*2 + 18*1
        //     = 20 + 60 + 30 + 20 + 30 + 25 + 24 + 24 + 18 = 251
        // Expected: 251 / 9 / 2 = 27 / 2 = 13 (integer division)
        expected_result = 32'd13;
        run_test();
        
        // Test 4: Negative inputs
        test_num = 4;
        $display("\n--- Test %0d: Negative inputs ---", test_num);
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = -32'd2;
            kernel[i] = 32'd3;
        end
        scale_factor = 32'd1;
        // Expected: (-2*3 * 9) / 9 / 1 = -54 / 9 / 1 = -6
        expected_result = -32'd6;
        run_test();
        
        // Test 5: Mixed positive and negative
        test_num = 5;
        $display("\n--- Test %0d: Mixed positive and negative ---", test_num);
        for (i = 0; i < NUM_INPUTS/2; i = i + 1) begin
            input_data[i] = 32'd5;
            kernel[i] = 32'd2;
        end
        for (i = NUM_INPUTS/2; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = -32'd5;
            kernel[i] = 32'd2;
        end
        scale_factor = 32'd1;
        // Sum = 5*2*4 + (-5)*2*5 = 40 - 50 = -10
        // Expected: -10 / 9 / 1 = -1 (integer division rounds toward zero)
        expected_result = -32'd1;
        run_test();
        
        // Test 6: Large values
        test_num = 6;
        $display("\n--- Test %0d: Large values ---", test_num);
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = 32'd1000;
            kernel[i] = 32'd500;
        end
        scale_factor = 32'd100;
        // Expected: (1000*500*9) / 9 / 100 = 4500000 / 9 / 100 = 500000 / 100 = 5000
        expected_result = 32'd5000;
        run_test();
        
        // Test 7: Zero inputs
        test_num = 7;
        $display("\n--- Test %0d: Zero inputs ---", test_num);
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = 32'd0;
            kernel[i] = 32'd5;
        end
        scale_factor = 32'd1;
        // Expected: 0
        expected_result = 32'd0;
        run_test();
        
        // Test 8: Sparse kernel (some zeros)
        test_num = 8;
        $display("\n--- Test %0d: Sparse kernel ---", test_num);
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = 32'd10;
            if (i % 2 == 0)
                kernel[i] = 32'd0;
            else
                kernel[i] = 32'd2;
        end
        scale_factor = 32'd1;
        // Sum = 0+20+0+20+0+20+0+20+0 = 80
        // Expected: 80 / 9 / 1 = 8 (integer division)
        expected_result = 32'd8;
        run_test();
`endif
        
        // Wait for final operations
        #(CLK_PERIOD * 10);
        
        $display("\n========================================");
        $display("All tests completed!");
        $display("========================================");
        $finish;
    end
    
    // Task to run a single test
    task run_test;
        begin
            // Apply start pulse
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;
            
            // Wait for done signal
            wait(done);
            @(posedge clk);
            
            // Check result
            $display("Expected: %0d, Got: %0d", expected_result, result);
            if (result == expected_result) begin
                $display("✓ PASS");
            end else begin
                $display("✗ FAIL - Mismatch!");
            end
            
            // Wait between tests
            #(CLK_PERIOD * 5);
        end
    endtask

`ifdef USE_GENERATED_IMAGE_DATA
    task load_generated_window;
        input integer window_index;
        integer patch_index;
        begin
            for (patch_index = 0; patch_index < NUM_INPUTS; patch_index = patch_index + 1) begin
                input_data[patch_index] = generated_image_windows[window_index][patch_index];
                kernel[patch_index] = generated_kernel[patch_index];
            end
            scale_factor = GENERATED_SCALE_FACTOR;
            expected_result = generated_expected_results[window_index];
        end
    endtask

    task run_generated_tests;
        integer window_index;
        begin
            $display("\n========================================");
            $display("Generated Image Data Mode");
            $display("Total windows: %0d", GENERATED_NUM_WINDOWS);
            $display("Scale factor: %0d", GENERATED_SCALE_FACTOR);
            $display("========================================");

            for (window_index = 0; window_index < GENERATED_NUM_WINDOWS; window_index = window_index + 1) begin
                test_num = window_index + 1;
                load_generated_window(window_index);
                $display(
                    "\n--- Generated window %0d/%0d at row=%0d col=%0d ---",
                    test_num,
                    GENERATED_NUM_WINDOWS,
                    generated_window_rows[window_index],
                    generated_window_cols[window_index]
                );
                run_test();
            end
        end
    endtask
`endif
    
    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 10000);
        $display("\n*** ERROR: Simulation timeout! ***");
        $finish;
    end

endmodule
