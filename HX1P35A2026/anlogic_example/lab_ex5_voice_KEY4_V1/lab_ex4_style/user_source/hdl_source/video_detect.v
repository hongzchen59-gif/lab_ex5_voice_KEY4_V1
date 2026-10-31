module video_detect #(
    parameter integer WIDTH=1280,HEIGHT=720,MIN_SIDE=16,MIN_AREA=96,BUDGET=1000000
)(
    input wire I_clk,I_rst_n,input wire [30:0] I_pixel,
    output wire [1:0] O_status,output wire [2:0] O_count,
    output wire [319:0] O_objects,output wire [15:0] O_frame_id
);
    wire start,complete,bank,busy;
    wire [15:0] addr,frame_id;
    wire [1:0] data;
    wire [19:0] cycles;
    detect_color_mask #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_mask(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_pixel(I_pixel),
        .O_start(start),.O_complete(complete),.O_read_bank(bank),.O_frame_id(frame_id),
        .I_read_addr(addr),.O_read_data(data));
    detect_components #(.WIDTH(WIDTH/4),.HEIGHT(HEIGHT/4),.MIN_SIDE(MIN_SIDE),.MIN_AREA(MIN_AREA),.BUDGET(BUDGET)) u_components(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(start),.I_complete(complete),.I_frame_id(frame_id),
        .O_read_addr(addr),.I_read_data(data),.O_status(O_status),.O_count(O_count),
        .O_objects(O_objects),.O_frame_id(O_frame_id),.O_busy(busy),.O_cycles(cycles));
endmodule
