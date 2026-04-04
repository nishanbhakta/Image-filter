`timescale 1ns/1ps

module mac_tb ();

    reg clk;
    reg rst;
    reg start;
    reg enable;
    reg reset_acc;
    reg signed [31:0] x;
    reg signed [31:0] h;
    wire signed [71:0] result;
    wire done;

    mac #(.WIDTH(32), .ACC_WIDTH(72)) uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .enable(enable),
        .reset_acc(reset_acc),
        .x(x),
        .h(h),
        .result(result),
        .done(done)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("mac_tb.vcd");
        $dumpvars(0, mac_tb);
    end

    task run_mac;
        input signed [31:0] x_value;
        input signed [31:0] h_value;
        input signed [71:0] expected_result;
        begin
            @(negedge clk);
            x = x_value;
            h = h_value;
            start = 1;

            @(negedge clk);
            start = 0;

            @(posedge done);
            #1;
            $display(
                "MAC: x = %0d, h = %0d, result = %0d (Expected: %0d)",
                x_value, h_value, result, expected_result
            );
        end
    endtask

    initial begin
        rst = 1;
        start = 0;
        enable = 1;
        reset_acc = 0;
        x = 0;
        h = 0;

        @(negedge clk);
        rst = 0;

        @(negedge clk);
        reset_acc = 1;
        @(negedge clk);
        reset_acc = 0;

        run_mac(32'sd10, 32'sd5, 72'sd50);
        run_mac(32'sd20, 32'sd3, 72'sd110);
        run_mac(32'sd15, 32'sd4, 72'sd170);

        $finish;
    end

endmodule
