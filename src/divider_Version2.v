/*
  32-bit Restoring Divider - Sequential Implementation
  - Takes 32 cycles to complete
  - Supports signed integers
  - Outputs quotient and remainder
  - No / operator - pure shift-subtract implementation
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

    reg signed [2*WIDTH-1:0] working_reg;
    reg signed [WIDTH-1:0] divisor_reg;
    reg [5:0] counter;
    
    localparam IDLE = 1'b0, DIVIDE = 1'b1;
    reg state;
    
    wire dividend_sign = dividend[WIDTH-1];
    wire divisor_sign = divisor[WIDTH-1];
    reg result_sign, remainder_sign;
    
    wire signed [WIDTH-1:0] dividend_abs = dividend_sign ? -dividend : dividend;
    wire signed [WIDTH-1:0] divisor_abs = divisor_sign ? -divisor : divisor;
    
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            done <= 1'b0;
            counter <= 6'b0;
        end
        else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        working_reg <= {{WIDTH{1'b0}}, dividend_abs};
                        divisor_reg <= divisor_abs;
                        result_sign <= dividend_sign ^ divisor_sign;
                        remainder_sign <= dividend_sign;
                        counter <= 6'b0;
                        state <= DIVIDE;
                    end
                end
                
                DIVIDE: begin
                    working_reg <= working_reg << 1;
                    
                    if (working_reg[2*WIDTH-1:WIDTH] >= divisor_reg) begin
                        working_reg[2*WIDTH-1:WIDTH] <= 
                            working_reg[2*WIDTH-1:WIDTH] - divisor_reg;
                        working_reg[0] <= 1'b1;
                    end
                    
                    counter <= counter + 1'b1;
                    
                    if (counter == 6'd31) begin
                        quotient <= result_sign ? 
                            -working_reg[WIDTH-1:0] : working_reg[WIDTH-1:0];
                        remainder <= remainder_sign ? 
                            -working_reg[2*WIDTH-1:WIDTH] : working_reg[2*WIDTH-1:WIDTH];
                        done <= 1'b1;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule