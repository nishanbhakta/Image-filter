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

    localparam IDLE = 1'b0;
    localparam WAIT_PRODUCT = 1'b1;

    reg state;
    reg mult_start;
    reg enable_latched;
    reg signed [WIDTH-1:0] x_reg;
    reg signed [WIDTH-1:0] h_reg;
    wire signed [2*WIDTH-1:0] product;
    wire mult_done;

    multiplier #(.WIDTH(WIDTH)) mult_inst (
        .clk(clk),
        .rst(rst),
        .start(mult_start),
        .a(x_reg),
        .b(h_reg),
        .product(product),
        .done(mult_done)
    );

    always @(posedge clk) begin
        if (rst || reset_acc) begin
            state <= IDLE;
            mult_start <= 1'b0;
            enable_latched <= 1'b0;
            x_reg <= {WIDTH{1'b0}};
            h_reg <= {WIDTH{1'b0}};
            result <= {ACC_WIDTH{1'b0}};
            done <= 1'b0;
        end else begin
            mult_start <= 1'b0;
            done <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        x_reg <= x;
                        h_reg <= h;
                        enable_latched <= enable;
                        mult_start <= 1'b1;
                        state <= WAIT_PRODUCT;
                    end
                end

                WAIT_PRODUCT: begin
                    if (mult_done) begin
                        if (enable_latched) begin
                            result <= result + {{(ACC_WIDTH-2*WIDTH){product[2*WIDTH-1]}}, product};
                        end
                        done <= 1'b1;
                        state <= IDLE;
                    end
                end
            endcase
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
