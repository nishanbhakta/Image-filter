/*
    Signed non-restoring divider.
    - Latches operands on start and iterates for WIDTH cycles.
    - Avoids / and % operators in the datapath.
    - done pulses high for one cycle when quotient and remainder are ready.
 */

module divider #(
    parameter WIDTH = 32
) (
    input clk,
    input rst,
    input start,
    input signed [WIDTH-1:0] dividend,
    input signed [WIDTH-1:0] divisor,
    output reg signed [WIDTH-1:0] quotient,
    output reg signed [WIDTH-1:0] remainder,
    output reg done
);

    localparam integer COUNT_WIDTH = (WIDTH > 1) ? $clog2(WIDTH + 1) : 1;

    reg busy;
    reg quotient_negative;
    reg remainder_negative;
    reg [COUNT_WIDTH-1:0] count_reg;
    reg [WIDTH-1:0] dividend_shift_reg;
    reg [WIDTH-1:0] divisor_abs_reg;
    reg [WIDTH-1:0] quotient_abs_reg;
    reg signed [WIDTH:0] remainder_reg;

    reg [WIDTH-1:0] quotient_abs_next;
    reg signed [WIDTH:0] remainder_next;
    reg [WIDTH-1:0] dividend_shift_next;
    reg [WIDTH:0] shifted_remainder;
    reg [WIDTH:0] divisor_ext;

    wire [WIDTH-1:0] quotient_abs_final = quotient_abs_next;
    wire signed [WIDTH:0] remainder_final_raw = remainder_next;
    wire [WIDTH:0] remainder_unsigned_final = remainder_final_raw[WIDTH:0] + (remainder_final_raw[WIDTH] ? {1'b0, divisor_abs_reg} : {(WIDTH+1){1'b0}});
    wire [WIDTH-1:0] quotient_signed_bits = quotient_negative ? (~quotient_abs_final + 1'b1) : quotient_abs_final;
    wire [WIDTH-1:0] remainder_signed_bits = remainder_negative ? (~remainder_unsigned_final[WIDTH-1:0] + 1'b1) : remainder_unsigned_final[WIDTH-1:0];

    function [WIDTH-1:0] abs_unsigned;
        input signed [WIDTH-1:0] value;
        begin
            if (value[WIDTH-1]) begin
                abs_unsigned = ~value + 1'b1;
            end else begin
                abs_unsigned = value;
            end
        end
    endfunction

    always @(*) begin
        divisor_ext = {1'b0, divisor_abs_reg};
        shifted_remainder = {remainder_reg[WIDTH-1:0], dividend_shift_reg[WIDTH-1]};
        dividend_shift_next = dividend_shift_reg << 1;

        if (!remainder_reg[WIDTH]) begin
            remainder_next = $signed(shifted_remainder) - $signed(divisor_ext);
        end else begin
            remainder_next = $signed(shifted_remainder) + $signed(divisor_ext);
        end

        quotient_abs_next = {quotient_abs_reg[WIDTH-2:0], ~remainder_next[WIDTH]};
    end

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
            quotient <= {WIDTH{1'b0}};
            remainder <= {WIDTH{1'b0}};
            quotient_negative <= 1'b0;
            remainder_negative <= 1'b0;
            count_reg <= {COUNT_WIDTH{1'b0}};
            dividend_shift_reg <= {WIDTH{1'b0}};
            divisor_abs_reg <= {WIDTH{1'b0}};
            quotient_abs_reg <= {WIDTH{1'b0}};
            remainder_reg <= $signed({(WIDTH + 1){1'b0}});
        end else begin
            done <= 1'b0;

            if (!busy) begin
                if (start) begin
                    if (divisor == {WIDTH{1'b0}}) begin
                        quotient <= {WIDTH{1'b0}};
                        remainder <= dividend;
                        done <= 1'b1;
                    end else begin
                        busy <= 1'b1;
                        quotient_negative <= dividend[WIDTH-1] ^ divisor[WIDTH-1];
                        remainder_negative <= dividend[WIDTH-1];
                        count_reg <= WIDTH[COUNT_WIDTH-1:0];
                        dividend_shift_reg <= abs_unsigned(dividend);
                        divisor_abs_reg <= abs_unsigned(divisor);
                        quotient_abs_reg <= {WIDTH{1'b0}};
                        remainder_reg <= $signed({(WIDTH + 1){1'b0}});
                    end
                end
            end else begin
                dividend_shift_reg <= dividend_shift_next;
                quotient_abs_reg <= quotient_abs_next;
                remainder_reg <= remainder_next;
                count_reg <= count_reg - 1'b1;

                if (count_reg == {{(COUNT_WIDTH-1){1'b0}}, 1'b1}) begin
                    quotient <= quotient_signed_bits;
                    remainder <= remainder_signed_bits;
                    done <= 1'b1;
                    busy <= 1'b0;
                end
            end
        end
    end

endmodule
