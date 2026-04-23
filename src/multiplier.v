/*
    DSP-friendly signed multiplier.
    - Captures a*b on start.
    - Produces done exactly one cycle later.
    - Maintains a simple start/done handshake for controller compatibility.
 */

module multiplier #(
    parameter WIDTH = 32
) (
    input clk,
    input rst,
    input start,
    input signed [WIDTH-1:0] a,
    input signed [WIDTH-1:0] b,
    output reg signed [2*WIDTH-1:0] product,
    output reg done
);

    reg signed [2*WIDTH-1:0] product_pipe;
    reg valid_pipe;

    always @(posedge clk) begin
        if (rst) begin
            done <= 1'b0;
            product <= {2*WIDTH{1'b0}};
            product_pipe <= {2*WIDTH{1'b0}};
            valid_pipe <= 1'b0;
        end else begin
            done <= valid_pipe;

            if (valid_pipe) begin
                product <= product_pipe;
            end

            if (start) begin
                product_pipe <= a * b;
            end

            valid_pipe <= start;
        end
    end

endmodule
