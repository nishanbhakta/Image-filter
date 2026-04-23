/*
  CNN accelerator testbench
  Formula: result = trunc_toward_zero(trunc_toward_zero(sum(xi * hi) / 9) / K)
*/

`timescale 1ns/1ps

`ifndef CNN_VCD_FILE
`define CNN_VCD_FILE "cnn_accelerator_tb.vcd"
`endif

module cnn_accelerator_tb;

    parameter WIDTH = 32;
    parameter ACC_WIDTH = 72;
    parameter NUM_INPUTS = 9;
    parameter CLK_PERIOD = 10;

`ifdef USE_GENERATED_IMAGE_DATA
`ifndef CNN_ACTUAL_OUTPUT_CSV
`define CNN_ACTUAL_OUTPUT_CSV "output.csv"
`endif
`ifndef CNN_ACTUAL_TRACE_CSV
`define CNN_ACTUAL_TRACE_CSV "output_trace.csv"
`endif
`include "generated_windows.vh"
`endif

    reg clk;
    reg rst;
    reg start;
    reg signed [WIDTH-1:0] input_data [0:NUM_INPUTS-1];
    reg signed [WIDTH-1:0] kernel [0:NUM_INPUTS-1];
    reg signed [WIDTH-1:0] scale_factor;
    wire signed [WIDTH-1:0] result;
    wire done;

    integer test_num;
    reg signed [WIDTH-1:0] expected_result;
    integer total_tests;
    integer pass_count;
    integer fail_count;
    integer accuracy_hundredths;
    integer i;
    integer current_output_row;
    integer current_output_col;
    integer simulation_timeout_cycles;

`ifdef USE_GENERATED_IMAGE_DATA
    reg capture_generated_output;
    reg signed [WIDTH-1:0] generated_output_vram [0:GENERATED_OUTPUT_HEIGHT-1][0:GENERATED_OUTPUT_WIDTH-1];
    reg generated_output_valid [0:GENERATED_OUTPUT_HEIGHT-1][0:GENERATED_OUTPUT_WIDTH-1];
    integer generated_output_fd;
    integer generated_trace_fd;
    integer generated_row_index;
    integer generated_col_index;
`endif

`ifdef USE_CSV_TEST_DATA
`ifndef CNN_CSV_FILE
`define CNN_CSV_FILE "tb/data/cnn_complex_vectors.csv"
`endif
    integer csv_fd;
    integer csv_status;
    integer csv_fields;
    integer csv_line_number;
    integer csv_test_id;
    integer csv_row;
    integer csv_col;
    integer signed csv_patch_values [0:NUM_INPUTS-1];
    integer signed csv_kernel_values [0:NUM_INPUTS-1];
    reg signed [ACC_WIDTH-1:0] csv_accumulator;
    reg signed [ACC_WIDTH-1:0] csv_after_div9;
    integer signed csv_scale_factor_value;
    integer signed csv_expected_result_value;
    reg [4095:0] csv_line;
`endif

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

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        $dumpfile(`CNN_VCD_FILE);
        $dumpvars(0, cnn_accelerator_tb);
    end

    // Compute a percentage with two fractional digits without using real numbers.
    function integer compute_accuracy_hundredths;
        input integer passed;
        input integer total;
        begin
            if (total == 0) begin
                compute_accuracy_hundredths = 0;
            end else begin
                compute_accuracy_hundredths = ((passed * 10000) + (total / 2)) / total;
            end
        end
    endfunction

    // Build the software reference trace used in console diagnostics.
    task compute_reference_trace;
        output signed [ACC_WIDTH-1:0] accumulator_out;
        output signed [ACC_WIDTH-1:0] after_div9_out;
        integer idx;
        begin
            accumulator_out = 0;
            for (idx = 0; idx < NUM_INPUTS; idx = idx + 1) begin
                accumulator_out = accumulator_out + (input_data[idx] * kernel[idx]);
            end
            after_div9_out = accumulator_out / 9;
        end
    endtask

    // Print the active patch, kernel, and expected arithmetic pipeline values.
    task print_current_vector;
        reg signed [ACC_WIDTH-1:0] computed_accumulator;
        reg signed [ACC_WIDTH-1:0] computed_after_div9;
        begin
            compute_reference_trace(computed_accumulator, computed_after_div9);
            $display(
                "Input   : [%0d %0d %0d] [%0d %0d %0d] [%0d %0d %0d]",
                input_data[0],
                input_data[1],
                input_data[2],
                input_data[3],
                input_data[4],
                input_data[5],
                input_data[6],
                input_data[7],
                input_data[8]
            );
            $display(
                "Kernel  : [%0d %0d %0d] [%0d %0d %0d] [%0d %0d %0d]",
                kernel[0],
                kernel[1],
                kernel[2],
                kernel[3],
                kernel[4],
                kernel[5],
                kernel[6],
                kernel[7],
                kernel[8]
            );
            $display(
                "Reference: sum=%0d -> div9=%0d -> divK(%0d)=%0d",
                computed_accumulator,
                computed_after_div9,
                scale_factor,
                expected_result
            );
        end
    endtask

    // Emit the aggregate pass/fail summary at the end of simulation.
    task print_summary;
        begin
            accuracy_hundredths = compute_accuracy_hundredths(pass_count, total_tests);
            $display("\n========================================");
            $display("Simulation Summary");
            $display("========================================");
            $display("Total tests : %0d", total_tests);
            $display("Passed      : %0d", pass_count);
            $display("Failed      : %0d", fail_count);
            $display(
                "Accuracy    : %0d.%02d%%",
                accuracy_hundredths / 100,
                accuracy_hundredths % 100
            );
            $display("========================================");
        end
    endtask

`ifdef USE_GENERATED_IMAGE_DATA
    task initialize_generated_output_vram;
        begin
            for (generated_row_index = 0; generated_row_index < GENERATED_OUTPUT_HEIGHT; generated_row_index = generated_row_index + 1) begin
                for (generated_col_index = 0; generated_col_index < GENERATED_OUTPUT_WIDTH; generated_col_index = generated_col_index + 1) begin
                    generated_output_vram[generated_row_index][generated_col_index] = 0;
                    generated_output_valid[generated_row_index][generated_col_index] = 1'b0;
                end
            end
        end
    endtask

    task open_generated_trace_csv;
        begin
            generated_trace_fd = $fopen(`CNN_ACTUAL_TRACE_CSV, "w");
            if (generated_trace_fd == 0) begin
                $display("\n*** ERROR: Could not open output trace CSV: %s ***", `CNN_ACTUAL_TRACE_CSV);
                $finish;
            end
            $fwrite(
                generated_trace_fd,
                "test_id,row,col,hardware_result,expected_result,status\n"
            );
        end
    endtask

    task record_generated_output;
        begin
            generated_output_vram[current_output_row][current_output_col] = $signed(result);
            generated_output_valid[current_output_row][current_output_col] = 1'b1;

            if (generated_trace_fd != 0) begin
                if ($signed(result) == expected_result) begin
                    $fwrite(
                        generated_trace_fd,
                        "%0d,%0d,%0d,%0d,%0d,PASS\n",
                        test_num,
                        current_output_row,
                        current_output_col,
                        $signed(result),
                        expected_result
                    );
                end else begin
                    $fwrite(
                        generated_trace_fd,
                        "%0d,%0d,%0d,%0d,%0d,FAIL\n",
                        test_num,
                        current_output_row,
                        current_output_col,
                        $signed(result),
                        expected_result
                    );
                end
            end
        end
    endtask

    task write_generated_output_csv;
        begin
            generated_output_fd = $fopen(`CNN_ACTUAL_OUTPUT_CSV, "w");
            if (generated_output_fd == 0) begin
                $display("\n*** ERROR: Could not open output CSV: %s ***", `CNN_ACTUAL_OUTPUT_CSV);
                $finish;
            end

            for (generated_row_index = 0; generated_row_index < GENERATED_OUTPUT_HEIGHT; generated_row_index = generated_row_index + 1) begin
                for (generated_col_index = 0; generated_col_index < GENERATED_OUTPUT_WIDTH; generated_col_index = generated_col_index + 1) begin
                    if (generated_col_index > 0) begin
                        $fwrite(generated_output_fd, ",");
                    end

                    if (generated_output_valid[generated_row_index][generated_col_index]) begin
                        $fwrite(
                            generated_output_fd,
                            "%0d",
                            generated_output_vram[generated_row_index][generated_col_index]
                        );
                    end
                end
                $fwrite(generated_output_fd, "\n");
            end

            $fclose(generated_output_fd);
        end
    endtask
`endif

    // Launch one hardware transaction, wait for completion, and compare results.
    task run_test;
        reg signed [ACC_WIDTH-1:0] computed_accumulator;
        reg signed [ACC_WIDTH-1:0] computed_after_div9;
        integer signed error_value;
        integer absolute_error;
        begin
            total_tests = total_tests + 1;
            print_current_vector();

            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;

            wait(done == 1'b1);
            @(posedge clk);

            compute_reference_trace(computed_accumulator, computed_after_div9);
            error_value = $signed(result) - expected_result;
            if (error_value < 0) begin
                absolute_error = -error_value;
            end else begin
                absolute_error = error_value;
            end

            $display(
                "Result   : expected=%0d, hardware=%0d, abs_error=%0d",
                expected_result,
                result,
                absolute_error
            );

            if ($signed(result) == expected_result) begin
                pass_count = pass_count + 1;
                $display("Status   : PASS");
            end else begin
                fail_count = fail_count + 1;
                $display("Status   : FAIL");
            end

`ifdef USE_GENERATED_IMAGE_DATA
            if (capture_generated_output) begin
                record_generated_output();
            end
`endif

            accuracy_hundredths = compute_accuracy_hundredths(pass_count, total_tests);
            $display(
                "Accuracy : %0d.%02d%% (%0d/%0d)",
                accuracy_hundredths / 100,
                accuracy_hundredths % 100,
                pass_count,
                total_tests
            );

            #(CLK_PERIOD * 5);
        end
    endtask

`ifdef USE_GENERATED_IMAGE_DATA
    // Copy one generated image window into the DUT inputs.
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
            current_output_row = generated_window_rows[window_index];
            current_output_col = generated_window_cols[window_index];
        end
    endtask

    // Iterate through every generated image window and capture hardware outputs.
    task run_generated_tests;
        integer window_index;
        begin
            capture_generated_output = 1'b1;
            initialize_generated_output_vram();
            open_generated_trace_csv();

            $display("\n========================================");
            $display("Generated Image Data Mode");
            $display("Image size    : %0dx%0d", GENERATED_IMAGE_WIDTH, GENERATED_IMAGE_HEIGHT);
            $display("Output size   : %0dx%0d", GENERATED_OUTPUT_WIDTH, GENERATED_OUTPUT_HEIGHT);
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

            write_generated_output_csv();
            $fclose(generated_trace_fd);
            generated_trace_fd = 0;
            capture_generated_output = 1'b0;

            $display("Output CSV       : %s", `CNN_ACTUAL_OUTPUT_CSV);
            $display("Output trace CSV : %s", `CNN_ACTUAL_TRACE_CSV);
        end
    endtask
`endif

`ifdef USE_CSV_TEST_DATA
    // Move one CSV dataset row into the DUT input arrays.
    task load_csv_vector_into_dut;
        integer patch_index;
        begin
            for (patch_index = 0; patch_index < NUM_INPUTS; patch_index = patch_index + 1) begin
                input_data[patch_index] = csv_patch_values[patch_index];
                kernel[patch_index] = csv_kernel_values[patch_index];
            end
            scale_factor = csv_scale_factor_value;
            expected_result = csv_expected_result_value;
        end
    endtask

    // Walk the CSV dataset, validate the reference fields, and run each vector.
    task run_csv_tests;
        reg signed [ACC_WIDTH-1:0] computed_accumulator;
        reg signed [ACC_WIDTH-1:0] computed_after_div9;
        begin
            $display("\n========================================");
            $display("CSV Dataset Mode");
            $display("Dataset : %s", `CNN_CSV_FILE);
            $display("Columns : test_id,row,col,p0..p8,k0..k8,accumulator,after_div9,scale_factor,expected_result");
            $display("========================================");

            csv_fd = $fopen(`CNN_CSV_FILE, "r");
            if (csv_fd == 0) begin
                $display("\n*** ERROR: Could not open CSV dataset: %s ***", `CNN_CSV_FILE);
                $finish;
            end

            csv_line_number = 1;
            csv_status = $fgets(csv_line, csv_fd);
            if (csv_status == 0) begin
                $display("\n*** ERROR: CSV dataset is empty: %s ***", `CNN_CSV_FILE);
                $finish;
            end

            while (!$feof(csv_fd)) begin
                csv_line = 0;
                csv_status = $fgets(csv_line, csv_fd);
                if (csv_status > 1) begin
                    csv_line_number = csv_line_number + 1;
                    csv_fields = $sscanf(
                        csv_line,
                        "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d",
                        csv_test_id,
                        csv_row,
                        csv_col,
                        csv_patch_values[0],
                        csv_patch_values[1],
                        csv_patch_values[2],
                        csv_patch_values[3],
                        csv_patch_values[4],
                        csv_patch_values[5],
                        csv_patch_values[6],
                        csv_patch_values[7],
                        csv_patch_values[8],
                        csv_kernel_values[0],
                        csv_kernel_values[1],
                        csv_kernel_values[2],
                        csv_kernel_values[3],
                        csv_kernel_values[4],
                        csv_kernel_values[5],
                        csv_kernel_values[6],
                        csv_kernel_values[7],
                        csv_kernel_values[8],
                        csv_accumulator,
                        csv_after_div9,
                        csv_scale_factor_value,
                        csv_expected_result_value
                    );

                    if (csv_fields != 25) begin
                        $display(
                            "\n*** WARNING: Skipping CSV line %0d because %0d fields were parsed instead of 25 ***",
                            csv_line_number,
                            csv_fields
                        );
                    end else begin
                        load_csv_vector_into_dut();
                        compute_reference_trace(computed_accumulator, computed_after_div9);

                        if ((computed_accumulator != csv_accumulator) || (computed_after_div9 != csv_after_div9)) begin
                            $display(
                                "\n*** WARNING: CSV reference mismatch on line %0d (file sum=%0d, computed sum=%0d, file div9=%0d, computed div9=%0d) ***",
                                csv_line_number,
                                csv_accumulator,
                                computed_accumulator,
                                csv_after_div9,
                                computed_after_div9
                            );
                        end

                        test_num = csv_test_id;
                        $display(
                            "\n--- CSV test %0d at row=%0d col=%0d (line %0d) ---",
                            test_num,
                            csv_row,
                            csv_col,
                            csv_line_number
                        );
                        run_test();
                    end
                end
            end

            $fclose(csv_fd);
        end
    endtask
`endif

    // Main simulation flow: reset the DUT, choose the active data source, then run tests.
    initial begin
        $display("========================================");
        $display("CNN Accelerator Testbench Started");
        $display("========================================");

        test_num = 0;
        total_tests = 0;
        pass_count = 0;
        fail_count = 0;
        accuracy_hundredths = 0;
        rst = 1;
        start = 0;
        current_output_row = 0;
        current_output_col = 0;

`ifdef USE_GENERATED_IMAGE_DATA
        capture_generated_output = 1'b0;
        generated_output_fd = 0;
        generated_trace_fd = 0;
`endif

        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = 0;
            kernel[i] = 0;
        end
        scale_factor = 1;
        expected_result = 0;

        #(CLK_PERIOD * 2);
        rst = 0;
        #(CLK_PERIOD);

`ifdef USE_CSV_TEST_DATA
        run_csv_tests();
`elsif USE_GENERATED_IMAGE_DATA
        run_generated_tests();
`else
        test_num = 1;
        $display("\n--- Test %0d: Uniform inputs (all 1s) ---", test_num);
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = 32'd1;
            kernel[i] = 32'd1;
        end
        scale_factor = 32'd1;
        expected_result = 32'd1;
        run_test();

        test_num = 2;
        $display("\n--- Test %0d: Uniform inputs with scale factor 3 ---", test_num);
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = 32'd3;
            kernel[i] = 32'd3;
        end
        scale_factor = 32'd3;
        expected_result = 32'd3;
        run_test();

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
        expected_result = 32'd13;
        run_test();

        test_num = 4;
        $display("\n--- Test %0d: Negative inputs ---", test_num);
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = -32'd2;
            kernel[i] = 32'd3;
        end
        scale_factor = 32'd1;
        expected_result = -32'd6;
        run_test();

        test_num = 5;
        $display("\n--- Test %0d: Mixed positive and negative ---", test_num);
        for (i = 0; i < NUM_INPUTS / 2; i = i + 1) begin
            input_data[i] = 32'd5;
            kernel[i] = 32'd2;
        end
        for (i = NUM_INPUTS / 2; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = -32'd5;
            kernel[i] = 32'd2;
        end
        scale_factor = 32'd1;
        expected_result = -32'd1;
        run_test();

        test_num = 6;
        $display("\n--- Test %0d: Large values ---", test_num);
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = 32'd1000;
            kernel[i] = 32'd500;
        end
        scale_factor = 32'd100;
        expected_result = 32'd5000;
        run_test();

        test_num = 7;
        $display("\n--- Test %0d: Zero inputs ---", test_num);
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = 32'd0;
            kernel[i] = 32'd5;
        end
        scale_factor = 32'd1;
        expected_result = 32'd0;
        run_test();

        test_num = 8;
        $display("\n--- Test %0d: Sparse kernel ---", test_num);
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = 32'd10;
            if ((i % 2) == 0) begin
                kernel[i] = 32'd0;
            end else begin
                kernel[i] = 32'd2;
            end
        end
        scale_factor = 32'd1;
        expected_result = 32'd8;
        run_test();

        test_num = 9;
        $display("\n--- Test %0d: Preserve full precision before final divide ---", test_num);
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
            input_data[i] = 32'sh7fffffff;
            kernel[i] = 32'sh7fffffff;
        end
        scale_factor = 32'sh7fffffff;
        expected_result = 32'sh7fffffff;
        run_test();
`endif

        #(CLK_PERIOD * 10);
        print_summary();
        $finish;
    end

    // Safety timeout so a stalled handshake does not hang the simulator forever.
    initial begin
`ifdef USE_GENERATED_IMAGE_DATA
        simulation_timeout_cycles = (GENERATED_NUM_WINDOWS * 250) + 1000;
`elsif USE_CSV_TEST_DATA
        simulation_timeout_cycles = 200000;
`else
        simulation_timeout_cycles = 10000;
`endif

        #(CLK_PERIOD * simulation_timeout_cycles);
        $display("\n*** ERROR: Simulation timeout! ***");
        $finish;
    end

endmodule
