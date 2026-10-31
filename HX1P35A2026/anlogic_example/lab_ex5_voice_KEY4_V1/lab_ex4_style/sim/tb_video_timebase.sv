`timescale 1ns/1ps
module tb_video_timebase;
    reg sys=0,cam=0,pix=0,rst=0;always #10 sys=~sys;always #8.334 cam=~cam;always #6.667 pix=~pix;
    wire [31:0] camera_us,pixel_us;
    video_timebase #(.INITIAL_US(32'hfffffff0)) dut(.sys_clk(sys),.sys_rst_n(rst),.camera_clk(cam),.camera_rst_n(rst),.pixel_clk(pix),.pixel_rst_n(rst),.camera_us(camera_us),.pixel_us(pixel_us));
    wire [31:0] delayed;genvar n;
    generate for(n=0;n<32;n=n+1)begin: skew
        assign #(n%7) delayed[n]=dut.time_gray[n];
    end endgenerate
    reg [31:0] old_cam=32'hfffffff0,old_pix=32'hfffffff0;
    integer wraps=0,checks=0;
    always @(posedge cam)begin #1;if(rst)begin
        if(camera_us-old_cam>1 || dut.time_us-camera_us>1)$fatal(1,"Camera Gray time discontinuity");
        if(camera_us<old_cam)wraps=wraps+1;old_cam=camera_us;checks=checks+1;
    end end
    always @(posedge pix)begin #1;if(rst)begin
        if(pixel_us-old_pix>1 || dut.time_us-pixel_us>1)$fatal(1,"Pixel Gray time discontinuity");old_pix=pixel_us;
    end end
    initial begin
        force dut.gray_bus=delayed;
        repeat(8) @(negedge sys);rst=1;
        #40000;
        if(wraps!=1 || checks<2000)$fatal(1,"Timebase wrap/coverage");
        $display("TIMEBASE PASS: shared 1us counter, unrelated 50/60/75MHz domains, 0..6ns bit skew, monotonic Gray decoding and 32-bit wrap");$finish;
    end
endmodule
