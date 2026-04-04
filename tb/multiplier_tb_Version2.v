`timescale 1ns/1ps

module multiplier_tb ();

    reg clk;
    reg rst;
    reg start;
    reg signed [31:0] a;
    reg signed [31:0] b;
    wire signed [63:0] product;
    wire done;

    multiplier #(.WIDTH(32)) uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .a(a),
        .b(b),
        .product(product),
        .done(done)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("multiplier_tb.vcd");
        $dumpvars(0, multiplier_tb);
    end

    task run_multiply;
        input signed [31:0] a_value;
        input signed [31:0] b_value;
        input signed [63:0] expected_product;
        begin
            @(negedge clk);
            a = a_value;
            b = b_value;
            start = 1;

            @(negedge clk);
            start = 0;

            @(posedge done);
            #1;
            $display(
                "Multiply: %0d * %0d = %0d (Expected: %0d)",
                a_value, b_value, product, expected_product
            );
        end
    endtask

    initial begin
        rst = 1;
        start = 0;
        a = 0;
        b = 0;

        @(negedge clk);
        rst = 0;

        run_multiply(32'sd5, 32'sd3, 64'sd15);
        run_multiply(32'sd100, 32'sd200, 64'sd20000);
        run_multiply(-32'sd50, 32'sd4, -64'sd200);

        $finish;
    end

endmodule
