// video_out has one registered FIFO read plus one RGB unpack register.
// Delay VTC metadata two clocks; do not delay the original FIFO read request.
module video_pixel_align (
    input wire I_clk, input wire I_rst_n,
    input wire I_vs, input wire I_hs, input wire I_de,
    input wire I_sof, input wire I_eol,
    input wire [1:0] I_mode,
    input wire [23:0] I_rgb,
    output wire [30:0] O_pixel
);
    reg [6:0] meta_1, meta_2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin meta_1<=0; meta_2<=0; end
        else begin meta_1<={I_mode,I_eol,I_sof,I_de,I_hs,I_vs}; meta_2<=meta_1; end
    end
    // [30:29] mode, [28] EOL, [27] SOF, [26] DE, [25] HS, [24] VS.
    assign O_pixel={meta_2,I_rgb};
endmodule
