`timescale 1ns/1ps

module interpatch_pipeline_tb;

    parameter WIDTH = 32;
    parameter ACC_WIDTH = 72;
    parameter NUM_INPUTS = 9;
    parameter CLK_PERIOD = 10;

    reg clk;
    reg rst;
    reg start;
    reg signed [WIDTH-1:0] input_data [0:NUM_INPUTS-1];
    reg signed [WIDTH-1:0] kernel [0:NUM_INPUTS-1];
    reg signed [WIDTH-1:0] scale_factor;
    wire signed [WIDTH-1:0] result;
    wire done;

    integer patch_idx;

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

    task launch_patch;
        input signed [WIDTH-1:0] base_value;
        integer i;
        begin
            for (i = 0; i < NUM_INPUTS; i = i + 1) begin
                input_data[i] = base_value;
                kernel[i] = 32'sd1;
            end
            scale_factor = 32'sd1;
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    initial begin
        $display("Inter-patch pipeline smoke test");
        $dumpfile("interpatch_pipeline_tb.vcd");
        $dumpvars(0, interpatch_pipeline_tb);

        rst = 1'b1;
        start = 1'b0;
        scale_factor = 0;
        for (patch_idx = 0; patch_idx < NUM_INPUTS; patch_idx = patch_idx + 1) begin
            input_data[patch_idx] = 0;
            kernel[patch_idx] = 0;
        end

        repeat (2) @(negedge clk);
        rst = 1'b0;

        launch_patch(32'sd1);
        launch_patch(32'sd2);
        launch_patch(32'sd3);

        repeat (400) @(negedge clk);
        $finish;
    end

    always @(posedge clk) begin
        if (done) begin
            $display("Done pulse: result=%0d at t=%0t", result, $time);
        end
    end

endmodule
