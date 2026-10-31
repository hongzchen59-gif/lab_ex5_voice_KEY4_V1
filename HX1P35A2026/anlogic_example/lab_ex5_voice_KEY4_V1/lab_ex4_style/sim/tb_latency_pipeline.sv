`timescale 1ns/1ps
module tb_latency_pipeline;
    reg clk=0,rst=0;always #6.667 clk=~clk;
    reg [30:0] pixel=0;wire [30:0] gamma_pixel,styled;
    reg [6:0] divider=0;reg [31:0] now_us=100000;
    always @(posedge clk)if(rst)begin if(divider==74)begin divider<=0;now_us<=now_us+1;end else divider<=divider+1;end
    reg [31:0] sid=1,capture=95000;
    wire out_sof,out_de;wire [23:0] rgb;wire [1:0] status;wire history;
    wire [15:0] val,minimum,maximum;wire [31:0] measured;wire [19:0] us;wire update;
    base_gamma gamma(.I_clk(clk),.I_rst_n(rst),.I_pixel(pixel),.O_pixel(gamma_pixel));
    video_style style(.I_clk(clk),.I_rst_n(rst),.I_pixel(gamma_pixel),.O_pixel(styled));
    video_latency latency(.clk(clk),.rst_n(rst),.now_us(now_us),.input_sof(pixel[27]),.output_sof(out_sof),.output_de(out_de),
        .source_id(sid),.capture_us(capture),.source_valid(1'b1),.capture_valid(1'b1),.status(status),.history_valid(history),
        .latency_bcd(val),.min_bcd(minimum),.max_bcd(maximum),.measured_source(measured),.measured_us(us),.update(update));
    hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.LATENCY_ENABLE(1)) mixer(.I_clk(clk),.I_rst_n(rst),
        .I_video_vsync(styled[24]),.I_video_hsync(styled[25]),.I_video_de(styled[26]),.I_video_user(styled[27]),.I_video_last(styled[28]),
        .I_debug_status(4'd0),.I_mode(styled[30:29]),.I_camera_debug(47'd0),.I_detect_status(2'd0),.I_detect_count(3'd0),.I_detect_objects(320'd0),
        .I_motion_status(3'd0),.I_motion_cells(14'd0),.I_motion_events(16'd0),.I_motion_bbox(42'd0),
        .I_latency_status(status),.I_latency_valid(history),.I_latency_bcd(val),.I_latency_min(minimum),.I_latency_max(maximum),.I_latency_source(measured),
        .O_frame_sof(out_sof),.O_video_rd_en(),.I_video_rd_data(styled[23:0]),.O_hdmi_vsync(),.O_hdmi_hsync(),.O_hdmi_de(out_de),.O_hdmi_data(rgb));
    integer outputs=0,updates=0,clocks=0,start_clock=0,observed_delay=0;
    always @(posedge clk)begin
        clocks=clocks+1;if(pixel[27])start_clock=clocks;
        if(out_sof)begin
            if(!out_de)$fatal(1,"Output SOF not first valid pixel");
            observed_delay=clocks-start_clock;outputs=outputs+1;
            if(observed_delay<3323 || observed_delay>3326)$fatal(1,"Wrong whole video pipeline endpoint %0d",observed_delay);
        end
        if(update)updates=updates+1;
    end
    task pulse;
        begin @(negedge clk);capture=now_us-5000;pixel={2'd0,1'b1,1'b1,1'b1,2'b00,24'h202020};
            @(negedge clk);pixel=0;repeat(3500) @(negedge clk);end
    endtask
    initial begin
        repeat(8) @(negedge clk);rst=1;repeat(7000) @(negedge clk);pulse;sid=2;pulse;
        if(outputs!=2 || updates!=1 || !history || measured!=2 || us<5043 || us>5046 || val!==16'h0050)
            $fatal(1,"Pipeline timestamp omitted stages outputs=%0d updates=%0d us=%0d",outputs,updates,us);
        $display("LATENCY PIPELINE PASS: actual gamma/style/HDMI mixer, endpoint delayed %0d clocks, measured %0d us includes ~44us display pipeline",observed_delay,us);$finish;
    end
    initial begin #300000;$fatal(1,"Latency pipeline timeout");end
endmodule
