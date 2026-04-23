/*
  CNN hardware accelerator with five parallel final-stage dividers.

  Architecture:
    [Multiplier] -> [Divide-by-9] -> [FIFO] -> [5 parallel dividers]

  The front end (multiply plus divide-by-9) still accepts work sequentially.
  Each completed divide-by-9 result is queued in the FIFO, and the scheduler
  dispatches queued work to the first free divider. This hides most of the
  latency of the wide iterative divider by keeping several divider instances
  busy at the same time.

  Expected throughput:
    - Single divider path: about 48.7k cycles for 676 patches
    - Five-divider path: about 11.1k cycles for 676 patches
*/

module cnn_accelerator_multi_div #(
    parameter WIDTH = 32,
    parameter ACC_WIDTH = 72,
    parameter NUM_INPUTS = 9,
    parameter NUM_DIVIDERS = 5,
    parameter FIFO_DEPTH = 128
) (
    input clk,
    input rst,
    input start,
    
    input signed [WIDTH-1:0] input_data [0:NUM_INPUTS-1],
    input signed [WIDTH-1:0] kernel [0:NUM_INPUTS-1],
    input signed [WIDTH-1:0] scale_factor,
    
    output signed [WIDTH-1:0] result,
    output done
);

    // Outputs from the shared front end.
    wire fe_div9_done;
    wire signed [ACC_WIDTH-1:0] fe_div9_result;
    wire signed [WIDTH-1:0] fe_div9_scale_factor;
    
    // FIFO write and read control/data signals.
    wire fifo_wr_valid = fe_div9_done;
    wire fifo_wr_en;
    wire signed [ACC_WIDTH-1:0] fifo_wr_dividend;
    wire signed [WIDTH-1:0] fifo_wr_scale_factor;
    
    wire fifo_rd_valid;
    wire fifo_rd_en;
    wire signed [ACC_WIDTH-1:0] fifo_rd_dividend;
    wire signed [WIDTH-1:0] fifo_rd_scale_factor;
    
    // Signals for the bank of parallel final dividers.
    wire [NUM_DIVIDERS-1:0] div_start;
    wire [NUM_DIVIDERS-1:0] div_done_bus;
    wire signed [ACC_WIDTH-1:0] div_quotient [0:NUM_DIVIDERS-1];
    
    reg [NUM_DIVIDERS-1:0] div_busy;
    reg signed [ACC_WIDTH-1:0] div_dividend [0:NUM_DIVIDERS-1];
    reg signed [WIDTH-1:0] div_scale_factor [0:NUM_DIVIDERS-1];
    
    // Result selection logic after any divider lane finishes.
    integer div_idx;
    wire any_div_done = |div_done_bus;
    reg signed [WIDTH-1:0] result_reg;
    reg output_valid_reg;
    
    // Front end produces the post-divide-by-9 value and matching scale factor.
    cnn_accelerator_frontend #(
        .WIDTH(WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .NUM_INPUTS(NUM_INPUTS)
    ) fe_accel (
        .clk(clk),
        .rst(rst),
        .start(start),
        .input_data(input_data),
        .kernel(kernel),
        .scale_factor(scale_factor),
        .div9_result(fe_div9_result),
        .div9_done(fe_div9_done),
        .div9_scale_factor(fe_div9_scale_factor)
    );
    
    // FIFO that holds divide-by-9 outputs until a divider becomes available.
    reg signed [ACC_WIDTH-1:0] fifo_dividend [0:FIFO_DEPTH-1];
    reg signed [WIDTH-1:0] fifo_scale_factor [0:FIFO_DEPTH-1];
    reg [7:0] fifo_wr_ptr, fifo_rd_ptr;
    reg [8:0] fifo_count;
    
    assign fifo_wr_en = fifo_wr_valid && (fifo_count < FIFO_DEPTH);
    assign fifo_rd_en = fifo_rd_valid && (fifo_count > 0);
    assign fifo_rd_valid = fifo_count > 0;
    
    assign fifo_wr_dividend = fe_div9_result;
    assign fifo_wr_scale_factor = fe_div9_scale_factor;
    
    assign fifo_rd_dividend = fifo_dividend[fifo_rd_ptr];
    assign fifo_rd_scale_factor = fifo_scale_factor[fifo_rd_ptr];
    
    always @(posedge clk) begin
        if (rst) begin
            fifo_wr_ptr <= 8'b0;
            fifo_rd_ptr <= 8'b0;
            fifo_count <= 9'b0;
        end else begin
            if (fifo_wr_en) begin
                fifo_dividend[fifo_wr_ptr] <= fifo_wr_dividend;
                fifo_scale_factor[fifo_wr_ptr] <= fifo_wr_scale_factor;
                fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
                fifo_count <= fifo_count + 1'b1;
            end
            
            if (fifo_rd_en) begin
                fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
                fifo_count <= fifo_count - 1'b1;
            end
        end
    end
    
    // Divider array and scheduler.
    genvar d_idx;
    generate
        for (d_idx = 0; d_idx < NUM_DIVIDERS; d_idx = d_idx + 1) begin : gen_dividers
            // Sign-extend the scale factor to match the divider width.
            wire signed [ACC_WIDTH-1:0] scale_extended = {{
                (ACC_WIDTH - WIDTH){div_scale_factor[d_idx][WIDTH-1]}
            }, div_scale_factor[d_idx]};
            
            divider #(.WIDTH(ACC_WIDTH)) div_inst (
                .clk(clk),
                .rst(rst),
                .start(div_start[d_idx]),
                .dividend(div_dividend[d_idx]),
                .divisor(scale_extended),
                .quotient(div_quotient[d_idx]),
                .remainder(),
                .done(div_done_bus[d_idx])
            );
        end
    endgenerate
    
    // Track which divider lanes are busy and load new work into free lanes.
    integer search_idx;
    reg [NUM_DIVIDERS-1:0] assign_mask_this_cycle;
    reg start_this_cycle;
    
    always @(posedge clk) begin
        if (rst) begin
            for (div_idx = 0; div_idx < NUM_DIVIDERS; div_idx = div_idx + 1) begin
                div_busy[div_idx] <= 1'b0;
                div_dividend[div_idx] <= {ACC_WIDTH{1'b0}};
                div_scale_factor[div_idx] <= {WIDTH{1'b0}};
            end
        end else begin
            // Release any lane that finished this cycle.
            for (div_idx = 0; div_idx < NUM_DIVIDERS; div_idx = div_idx + 1) begin
                if (div_done_bus[div_idx]) begin
                    div_busy[div_idx] <= 1'b0;
                end
            end
            
            // Load the selected FIFO entry into the divider chosen this cycle.
            for (div_idx = 0; div_idx < NUM_DIVIDERS; div_idx = div_idx + 1) begin
                if (assign_mask_this_cycle[div_idx] && fifo_rd_en) begin
                    div_busy[div_idx] <= 1'b1;
                    div_dividend[div_idx] <= fifo_rd_dividend;
                    div_scale_factor[div_idx] <= fifo_rd_scale_factor;
                end
            end
        end
    end
    
    // Find the first free divider and generate a one-cycle start pulse for it.
    always @(*) begin
        assign_mask_this_cycle = {NUM_DIVIDERS{1'b0}};
        start_this_cycle = 1'b0;
        
        // Lowest-index free divider wins the allocation for this cycle.
        for (search_idx = 0; search_idx < NUM_DIVIDERS; search_idx = search_idx + 1) begin
            if (!div_busy[search_idx] && !start_this_cycle) begin
                assign_mask_this_cycle[search_idx] = 1'b1;
                start_this_cycle = 1'b1;
            end
        end
    end
    
    // Pop the FIFO only when work is being assigned to a divider lane.
    assign fifo_rd_en = fifo_rd_valid && start_this_cycle;
    assign div_start = fifo_rd_en ? assign_mask_this_cycle : {NUM_DIVIDERS{1'b0}};
    
    // Capture the quotient from any divider that completes this cycle.
    always @(posedge clk) begin
        if (rst) begin
            result_reg <= {WIDTH{1'b0}};
            output_valid_reg <= 1'b0;
        end else begin
            output_valid_reg <= 1'b0;
            
            for (div_idx = 0; div_idx < NUM_DIVIDERS; div_idx = div_idx + 1) begin
                if (div_done_bus[div_idx]) begin
                    result_reg <= div_quotient[div_idx][WIDTH-1:0];
                    output_valid_reg <= 1'b1;
                end
            end
        end
    end
    
    assign result = result_reg;
    assign done = output_valid_reg;

endmodule

