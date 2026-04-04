module Multiplier (input wire clk, input wire start, input wire signed [31:0] A, input wire signed [31:0] B, output reg signed [63:0] result, output reg done);
    reg [63:0] partial;
    reg [5:0] cycle;
    reg [31:0] A_reg, B_reg;
    reg [64:0] A_ext, B_ext;
    
    always @(posedge clk) begin
        if (start) begin
            A_reg <= A;
            B_reg <= B;
            partial <= 0;
            result <= 0;
            done <= 0;
            cycle <= 0;
            A_ext <= {1'b0, A}; // Sign extend A
            B_ext <= {1'b0, B}; // Sign extend B
        end else if (cycle < 32) begin
            if (B_ext[cycle]) begin
                partial <= partial + (A_ext << cycle);
            end
            cycle <= cycle + 1;
        end else begin
            result <= partial;
            done <= 1;
        end
    end
endmodule
