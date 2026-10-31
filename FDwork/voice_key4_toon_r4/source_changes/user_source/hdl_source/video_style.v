// Two centered windows. KEY3 edges are measured after edge-preserving smoothing.
module video_style #(parameter integer H_TOTAL=1650,EDGE_THRESHOLD=80)(
    input wire I_clk,I_rst_n,input wire [30:0] I_pixel,output wire [30:0] O_pixel,output wire O_effect_ready
);
    wire [30:0] filtered;
    wire filter_ready,color_ready;
    assign O_effect_ready=filter_ready && color_ready;
    edge_preserve #(.H_TOTAL(H_TOTAL)) u_preserve(.I_clk(I_clk),.I_rst_n(I_rst_n),
        .I_pixel(I_pixel),.O_pixel(filtered),.O_effect_ready(filter_ready));
    video_style_core #(.H_TOTAL(H_TOTAL),.EDGE_THRESHOLD(EDGE_THRESHOLD)) u_style(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_pixel(filtered),.O_pixel(O_pixel),.O_effect_ready(color_ready));
endmodule
