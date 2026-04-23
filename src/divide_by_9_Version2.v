/*
    Signed divide-by-9 using reciprocal multiply with bounded correction.
    - Captures dividend on start.
    - Computes quotient from reciprocal estimate and exacts it with small corrections.
    - done pulses high one cycle after start.
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

    localparam integer RECIP_SHIFT = WIDTH + 4;
    localparam [RECIP_SHIFT:0] RECIP_ONE = {1'b1, {RECIP_SHIFT{1'b0}}};
    localparam [RECIP_SHIFT:0] RECIP_CONST = (RECIP_ONE + 8) / 9;

    reg valid_s1;
    reg valid_s2;
    reg valid_s3;
    reg valid_s4;

    reg sign_s1;
    reg sign_s2;
    reg sign_s3;
    reg [WIDTH-1:0] abs_dividend_s1;
    reg [WIDTH-1:0] abs_dividend_s2;
    reg [WIDTH+RECIP_SHIFT:0] recip_product_s2;
    reg [WIDTH-1:0] quotient_abs_s3;
    reg [WIDTH+2:0] remainder_s3;
    reg signed [WIDTH-1:0] quotient_s4;

    reg [WIDTH-1:0] quotient_abs_est;
    reg [WIDTH-1:0] quotient_abs_corr;
    reg [WIDTH+2:0] remainder_calc;
    reg [WIDTH+2:0] prod_q9;
    reg [WIDTH+2:0] abs_ext;

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

    always @(posedge clk) begin
        if (rst) begin
            done <= 1'b0;
            quotient <= {WIDTH{1'b0}};
            valid_s1 <= 1'b0;
            valid_s2 <= 1'b0;
            valid_s3 <= 1'b0;
            valid_s4 <= 1'b0;
            sign_s1 <= 1'b0;
            sign_s2 <= 1'b0;
            sign_s3 <= 1'b0;
            abs_dividend_s1 <= {WIDTH{1'b0}};
            abs_dividend_s2 <= {WIDTH{1'b0}};
            recip_product_s2 <= {(WIDTH + RECIP_SHIFT + 1){1'b0}};
            quotient_abs_s3 <= {WIDTH{1'b0}};
            remainder_s3 <= {(WIDTH + 3){1'b0}};
            quotient_s4 <= {WIDTH{1'b0}};
        end else begin
            done <= valid_s4;

            if (valid_s4) begin
                quotient <= quotient_s4;
            end

            if (start) begin
                sign_s1 <= dividend[WIDTH-1];
                abs_dividend_s1 <= abs_unsigned(dividend);
            end

            if (valid_s1) begin
                sign_s2 <= sign_s1;
                abs_dividend_s2 <= abs_dividend_s1;
                recip_product_s2 <= abs_dividend_s1 * RECIP_CONST;
            end

            if (valid_s2) begin
                quotient_abs_est = (recip_product_s2 >> RECIP_SHIFT);
                quotient_abs_corr = quotient_abs_est;
                abs_ext = {{3{1'b0}}, abs_dividend_s2};

                prod_q9 = ({{3{1'b0}}, quotient_abs_corr} << 3) + {{3{1'b0}}, quotient_abs_corr};
                if (prod_q9 > abs_ext) begin
                    quotient_abs_corr = quotient_abs_corr - 1'b1;
                    prod_q9 = ({{3{1'b0}}, quotient_abs_corr} << 3) + {{3{1'b0}}, quotient_abs_corr};
                end

                remainder_calc = abs_ext - prod_q9;

                quotient_abs_s3 <= quotient_abs_corr;
                remainder_s3 <= remainder_calc;
                sign_s3 <= sign_s2;
            end

            if (valid_s3) begin
                quotient_abs_corr = quotient_abs_s3;
                remainder_calc = remainder_s3;

                if (remainder_calc >= 9) begin
                    quotient_abs_corr = quotient_abs_corr + 1'b1;
                    remainder_calc = remainder_calc - 9;
                end
                if (remainder_calc >= 9) begin
                    quotient_abs_corr = quotient_abs_corr + 1'b1;
                end

                if (sign_s3) begin
                    quotient_s4 <= -$signed(quotient_abs_corr);
                end else begin
                    quotient_s4 <= $signed(quotient_abs_corr);
                end
            end

            valid_s1 <= start;
            valid_s2 <= valid_s1;
            valid_s3 <= valid_s2;
            valid_s4 <= valid_s3;

        end
    end

endmodule
