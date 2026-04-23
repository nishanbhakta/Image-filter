/*
    Controller for the CNN hardware accelerator datapath.
    It launches one patch at a time through parallel multiplies, reduction,
    exact divide-by-9, and the final signed divider.
 */

module controller (
    input clk,
    input rst,
    input start,
    input mult_done,
    input div9_done,
    input div_done,

    output reg mult_start,
    output reg stage2_en,
    output reg stage3_en,
    output reg div9_start,
    output reg div_start,
    output reg output_valid,
    output reg [3:0] state
);

    // One-cycle delayed handshake signals that advance the datapath.
    reg mult_done_d1;
    reg stage2_en_d1;
    reg stage3_en_d1;
    reg div9_done_d1;
    reg div_done_d1;

    always @(posedge clk) begin
        if (rst) begin
            state <= 4'd0;
            mult_start <= 1'b0;
            stage2_en <= 1'b0;
            stage3_en <= 1'b0;
            div9_start <= 1'b0;
            div_start <= 1'b0;
            output_valid <= 1'b0;
            mult_done_d1 <= 1'b0;
            stage2_en_d1 <= 1'b0;
            stage3_en_d1 <= 1'b0;
            div9_done_d1 <= 1'b0;
            div_done_d1 <= 1'b0;
        end else begin
            // Emit one-cycle enables that move data from one stage to the next.
            mult_start <= start;
            stage2_en <= mult_done_d1;
            stage3_en <= stage2_en_d1;
            div9_start <= stage3_en_d1;
            div_start <= div9_done_d1;
            output_valid <= div_done_d1;

            // Delay completion pulses so the controller can generate clean starts.
            mult_done_d1 <= mult_done;
            stage2_en_d1 <= stage2_en;
            stage3_en_d1 <= stage3_en;
            div9_done_d1 <= div9_done;
            div_done_d1 <= div_done;

            // Expose a compact view of pipeline activity for debug/bring-up.
            state <= {div_done_d1, div9_done_d1, stage3_en_d1, stage2_en_d1};
        end
    end

endmodule
