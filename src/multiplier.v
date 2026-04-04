/*
  32-bit Signed Multiplier - Sequential Shift-Add Implementation
  - Takes WIDTH cycles to complete
  - Uses only shifts, adds, and sign handling
  - done pulses high for one cycle when the product is ready
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

    localparam COUNTER_WIDTH = $clog2(WIDTH + 1);

    reg busy;
    reg product_sign;
    reg [COUNTER_WIDTH-1:0] counter;
    reg [2*WIDTH-1:0] multiplicand_reg;
    reg [WIDTH-1:0] multiplier_reg;
    reg [2*WIDTH-1:0] accumulator_reg;

    wire [WIDTH-1:0] a_abs = a[WIDTH-1] ? (~a + 1'b1) : a;
    wire [WIDTH-1:0] b_abs = b[WIDTH-1] ? (~b + 1'b1) : b;
    wire [2*WIDTH-1:0] accumulator_next = multiplier_reg[0]
        ? (accumulator_reg + multiplicand_reg)
        : accumulator_reg;

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
            product <= {2*WIDTH{1'b0}};
            counter <= {COUNTER_WIDTH{1'b0}};
            multiplicand_reg <= {2*WIDTH{1'b0}};
            multiplier_reg <= {WIDTH{1'b0}};
            accumulator_reg <= {2*WIDTH{1'b0}};
            product_sign <= 1'b0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                if (start) begin
                    busy <= 1'b1;
                    counter <= WIDTH;
                    multiplicand_reg <= {{WIDTH{1'b0}}, a_abs};
                    multiplier_reg <= b_abs;
                    accumulator_reg <= {2*WIDTH{1'b0}};
                    product_sign <= a[WIDTH-1] ^ b[WIDTH-1];
                end
            end else begin
                accumulator_reg <= accumulator_next;
                multiplicand_reg <= multiplicand_reg << 1;
                multiplier_reg <= multiplier_reg >> 1;
                counter <= counter - 1'b1;

                if (counter == {{(COUNTER_WIDTH-1){1'b0}}, 1'b1}) begin
                    product <= product_sign
                        ? -$signed(accumulator_next)
                        : $signed(accumulator_next);
                    done <= 1'b1;
                    busy <= 1'b0;
                end
            end
        end
    end

endmodule
