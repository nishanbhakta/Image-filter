/*
    CNN hardware accelerator front end (no final scale division stage).
    Exposes the divide-by-9 output so downstream divider lanes can run in parallel.

    Datapath output: (sum(xi * hi)) / 9
*/

module cnn_accelerator_frontend #(
    parameter WIDTH = 32,
    parameter ACC_WIDTH = 72,
    parameter NUM_INPUTS = 9
) (
    input clk,
    input rst,
    input start,

    input signed [WIDTH-1:0] input_data [0:NUM_INPUTS-1],
    input signed [WIDTH-1:0] kernel [0:NUM_INPUTS-1],
    input signed [WIDTH-1:0] scale_factor,

    output signed [ACC_WIDTH-1:0] div9_result,
    output div9_done,
    output signed [WIDTH-1:0] div9_scale_factor
);

    wire [NUM_INPUTS-1:0] mult_done_bus;
    wire signed [2*WIDTH-1:0] mult_product [0:NUM_INPUTS-1];
    wire signed [ACC_WIDTH-1:0] mult_product_ext [0:NUM_INPUTS-1];
    reg signed [ACC_WIDTH-1:0] sum_from_mult;
    wire signed [ACC_WIDTH-1:0] div9_result_wire;
    wire all_mult_done = &mult_done_bus;
    wire div9_done_wire;

    reg signed [WIDTH-1:0] result_scale_factor;
    reg mul_busy;
    reg div9_busy;

    reg signed [WIDTH-1:0] mul_scale_reg;
    reg signed [ACC_WIDTH-1:0] sum_reg;
    reg signed [WIDTH-1:0] sum_scale_reg;
    reg sum_valid;

    reg mult_start_reg;
    reg div9_start_reg;

    integer idx;

    genvar mult_idx;
    generate
        for (mult_idx = 0; mult_idx < NUM_INPUTS; mult_idx = mult_idx + 1) begin : gen_parallel_mult
            multiplier #(.WIDTH(WIDTH)) mult_inst (
                .clk(clk),
                .rst(rst),
                .start(mult_start_reg),
                .a(input_data[mult_idx]),
                .b(kernel[mult_idx]),
                .product(mult_product[mult_idx]),
                .done(mult_done_bus[mult_idx])
            );

            assign mult_product_ext[mult_idx] = {{
                (ACC_WIDTH - (2 * WIDTH)){mult_product[mult_idx][(2 * WIDTH) - 1]}
            }, mult_product[mult_idx]};
        end
    endgenerate

    always @(*) begin
        sum_from_mult = {ACC_WIDTH{1'b0}};
        for (idx = 0; idx < NUM_INPUTS; idx = idx + 1) begin
            sum_from_mult = sum_from_mult + mult_product_ext[idx];
        end
    end

    divide_by_9 #(.WIDTH(ACC_WIDTH)) div9_inst (
        .clk(clk),
        .rst(rst),
        .start(div9_start_reg),
        .dividend(sum_reg),
        .quotient(div9_result_wire),
        .done(div9_done_wire)
    );

    always @(posedge clk) begin
        if (rst) begin
            result_scale_factor <= {WIDTH{1'b0}};
            mul_busy <= 1'b0;
            sum_valid <= 1'b0;
            div9_busy <= 1'b0;
            mult_start_reg <= 1'b0;
            div9_start_reg <= 1'b0;
            sum_reg <= {ACC_WIDTH{1'b0}};
            sum_scale_reg <= {WIDTH{1'b0}};
            mul_scale_reg <= {WIDTH{1'b0}};
        end else begin
            mult_start_reg <= 1'b0;
            div9_start_reg <= 1'b0;

            // On div-by-9 completion, publish the aligned scale factor.
            if (div9_done_wire) begin
                result_scale_factor <= sum_scale_reg;
                div9_busy <= 1'b0;
            end

            // Start div-by-9 once a summed patch is available and the unit is idle.
            if (sum_valid && !div9_busy) begin
                div9_start_reg <= 1'b1;
                div9_busy <= 1'b1;
                sum_valid <= 1'b0;
            end

            // Capture the reduction sum after all multiplier lanes assert done.
            if (all_mult_done && mul_busy) begin
                sum_reg <= sum_from_mult;
                sum_scale_reg <= mul_scale_reg;
                sum_valid <= 1'b1;
                mul_busy <= 1'b0;
            end

            // Accept a new request and issue a one-cycle start pulse to all multipliers.
            if (start && !mul_busy) begin
                mul_scale_reg <= scale_factor;
                mult_start_reg <= 1'b1;
                mul_busy <= 1'b1;
            end
        end
    end

    assign div9_result = div9_result_wire;
    assign div9_done = div9_done_wire;
    assign div9_scale_factor = result_scale_factor;

endmodule
