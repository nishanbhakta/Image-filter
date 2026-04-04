/*
  Divide-by-9 Module using Fixed-Point Reciprocal Multiplication
  - Avoids full division for efficiency
  - Uses: result = (input * RECIPROCAL_1_9) >> 28
  - RECIPROCAL_1_9 = 2^28 / 9 = 29,826,228 (Q28 format)
  - Single-cycle latency
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

    localparam signed [39:0] RECIPROCAL_1_9 = 40'sd29826228;
    
    reg signed [WIDTH+39:0] temp_product;
    
    always @(posedge clk) begin
        if (rst) begin
            done <= 1'b0;
            quotient <= {WIDTH{1'b0}};
        end
        else if (start) begin
            temp_product <= dividend * RECIPROCAL_1_9;
            quotient <= temp_product >>> 28;
            done <= 1'b1;
        end
        else begin
            done <= 1'b0;
        end
    end

endmodule