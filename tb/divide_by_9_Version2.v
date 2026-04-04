`timescale 1ns/1ps

module divide_by_9_tb ();

    reg clk;
    reg rst;
    reg start;
    reg signed [71:0] dividend;
    wire signed [71:0] quotient;
    wire done;

    divide_by_9 #(.WIDTH(72)) uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .dividend(dividend),
        .quotient(quotient),
        .done(done)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("divide_by_9_tb.vcd");
        $dumpvars(0, divide_by_9_tb);
    end

    task run_divide_by_9;
        input signed [71:0] dividend_value;
        input signed [71:0] expected_quotient;
        begin
            @(negedge clk);
            dividend = dividend_value;
            start = 1;

            @(negedge clk);
            start = 0;

            @(posedge done);
            #1;
            $display(
                "Divide-by-9: %0d / 9 = %0d (Expected: %0d)",
                dividend_value, quotient, expected_quotient
            );
        end
    endtask

    initial begin
        rst = 1;
        start = 0;
        dividend = 0;

        @(negedge clk);
        rst = 0;

        run_divide_by_9(72'sd81, 72'sd9);
        run_divide_by_9(-72'sd10, -72'sd1);
        run_divide_by_9(72'sd0, 72'sd0);

        $finish;
    end

endmodule
