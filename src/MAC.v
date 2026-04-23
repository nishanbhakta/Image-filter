/*
  MAC Building Blocks for the CNN Hardware Accelerator
  - mac: standalone 32x32 -> 72-bit multiply-accumulate block
  - mac_accumulator: lightweight accumulator used by the top-level pipeline
 */

module mac #(
    parameter WIDTH = 32,
    parameter ACC_WIDTH = 72
) (
    input clk,
    input rst,
    input start,
    input enable,
    input reset_acc,
    input signed [WIDTH-1:0] x,
    input signed [WIDTH-1:0] h,
    output reg signed [ACC_WIDTH-1:0] result,
    output reg done
);

    reg signed [2*WIDTH-1:0] product_pipe;
    reg valid_pipe;
    reg enable_pipe;

    always @(posedge clk) begin
        if (rst || reset_acc) begin
            result <= {ACC_WIDTH{1'b0}};
            done <= 1'b0;
            product_pipe <= {2*WIDTH{1'b0}};
            valid_pipe <= 1'b0;
            enable_pipe <= 1'b0;
        end else begin
            done <= valid_pipe;

            if (valid_pipe && enable_pipe) begin
                result <= result + {{(ACC_WIDTH-2*WIDTH){product_pipe[2*WIDTH-1]}}, product_pipe};
            end

            if (start) begin
                product_pipe <= x * h;
            end

            valid_pipe <= start;
            enable_pipe <= enable;
        end
    end

endmodule

module mac_accumulator #(
    parameter WIDTH = 32,
    parameter ACC_WIDTH = 72
) (
    input clk,
    input rst,
    input enable,
    input reset_acc,
    input signed [2*WIDTH-1:0] product_in,
    output reg signed [ACC_WIDTH-1:0] result
);

    always @(posedge clk) begin
        if (rst || reset_acc) begin
            result <= {ACC_WIDTH{1'b0}};
        end else if (enable) begin
            result <= result + {{(ACC_WIDTH-2*WIDTH){product_in[2*WIDTH-1]}}, product_in};
        end
    end

endmodule
