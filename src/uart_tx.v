/*
    Simple UART transmitter.
    Sends one start bit, eight data bits (LSB first), and one stop bit.
*/

module uart_tx #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE = 115_200
) (
    input clk,
    input rst,
    input start,
    input [7:0] data,
    output reg tx,
    output reg busy,
    output reg done
);

    localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    localparam integer COUNTER_WIDTH = $clog2(CLKS_PER_BIT);

    reg [COUNTER_WIDTH-1:0] baud_counter;
    reg [3:0] bit_index;
    reg [9:0] frame_reg;

    always @(posedge clk) begin
        if (rst) begin
            tx <= 1'b1;
            busy <= 1'b0;
            done <= 1'b0;
            baud_counter <= {COUNTER_WIDTH{1'b0}};
            bit_index <= 4'd0;
            frame_reg <= 10'h3FF;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                tx <= 1'b1;
                baud_counter <= {COUNTER_WIDTH{1'b0}};
                bit_index <= 4'd0;

                if (start) begin
                    busy <= 1'b1;
                    frame_reg <= {1'b1, data, 1'b0};
                    tx <= 1'b0;
                    baud_counter <= CLKS_PER_BIT - 1;
                end
            end else if (baud_counter != 0) begin
                baud_counter <= baud_counter - 1'b1;
            end else begin
                baud_counter <= CLKS_PER_BIT - 1;

                if (bit_index == 4'd9) begin
                    busy <= 1'b0;
                    tx <= 1'b1;
                    done <= 1'b1;
                end else begin
                    bit_index <= bit_index + 1'b1;
                    tx <= frame_reg[bit_index + 1'b1];
                end
            end
        end
    end

endmodule
