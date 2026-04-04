/*
  Divide-by-9 Module - Sequential Constant Divider
  - Exact signed division without using the / operator
  - Takes WIDTH cycles to complete
  - Implemented as a restoring divider specialized for divisor 9
 */

module divide_by_9 #(
    parameter WIDTH = 72
) (
    input clk,
    input rst,
    input start,
    input signed [WIDTH-1:0] dividend,
    output reg signed [WIDTH-1:0] quotient,
    output reg done
);

    localparam IDLE = 1'b0;
    localparam DIVIDE = 1'b1;
    localparam COUNTER_WIDTH = $clog2(WIDTH + 1);
    localparam [COUNTER_WIDTH-1:0] ITERATIONS = WIDTH;
    localparam [WIDTH:0] DIVISOR = {{WIDTH-4{1'b0}}, 5'd9};

    reg state;
    reg result_sign;
    reg [WIDTH-1:0] quotient_reg;
    reg [WIDTH:0] remainder_reg;
    reg [COUNTER_WIDTH-1:0] counter;

    wire [WIDTH-1:0] dividend_abs = dividend[WIDTH-1] ? (~dividend + 1'b1) : dividend;
    wire [WIDTH:0] shifted_remainder = {remainder_reg[WIDTH-1:0], quotient_reg[WIDTH-1]};
    wire subtract_ok = shifted_remainder >= DIVISOR;
    wire [WIDTH:0] remainder_next = subtract_ok ? (shifted_remainder - DIVISOR) : shifted_remainder;
    wire [WIDTH-1:0] quotient_next = {quotient_reg[WIDTH-2:0], subtract_ok};

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            done <= 1'b0;
            quotient <= {WIDTH{1'b0}};
            result_sign <= 1'b0;
            quotient_reg <= {WIDTH{1'b0}};
            remainder_reg <= {(WIDTH+1){1'b0}};
            counter <= {COUNTER_WIDTH{1'b0}};
        end else begin
            done <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        result_sign <= dividend[WIDTH-1];
                        quotient_reg <= dividend_abs;
                        remainder_reg <= {(WIDTH+1){1'b0}};
                        counter <= ITERATIONS;
                        state <= DIVIDE;
                    end
                end

                DIVIDE: begin
                    quotient_reg <= quotient_next;
                    remainder_reg <= remainder_next;
                    counter <= counter - 1'b1;

                    if (counter == {{(COUNTER_WIDTH-1){1'b0}}, 1'b1}) begin
                        quotient <= result_sign
                            ? -$signed(quotient_next)
                            : $signed(quotient_next);
                        done <= 1'b1;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
