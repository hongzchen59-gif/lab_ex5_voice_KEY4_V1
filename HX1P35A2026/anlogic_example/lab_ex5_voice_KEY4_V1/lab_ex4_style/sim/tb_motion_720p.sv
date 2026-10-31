`timescale 1ns/1ps
module tb_motion_720p;
    localparam W=1280,H=720,HT=1650,VT=750;
    reg clk=0,rst=0;always #6.667 clk=~clk;
    reg [30:0] pixel=0;reg [31:0] sid=0;
    reg [6:0] tick=0;reg [31:0] now_us=100000,capture_time=0;
    always @(posedge clk)if(rst)begin if(tick==74)begin tick<=0;now_us<=now_us+1;end else tick<=tick+1;end
    wire vs,hs,de;wire output_sof;wire [1:0] lat_status;wire lat_valid;
    wire [15:0] lat_bcd,lat_min,lat_max;wire [31:0] lat_source;wire lat_update;
    video_latency latency(.clk(clk),.rst_n(rst),.now_us(now_us),.input_sof(pixel[27]),.output_sof(output_sof),.output_de(de),
        .source_id(sid),.capture_us(capture_time),.source_valid(1'b1),.capture_valid(1'b1),.status(lat_status),.history_valid(lat_valid),
        .latency_bcd(lat_bcd),.min_bcd(lat_min),.max_bcd(lat_max),.measured_source(lat_source),.measured_us(),.update(lat_update));
    wire [2:0] status;wire [13:0] cells;wire [15:0] events;wire [41:0] bbox;
    wire done;wire [31:0] result_sid;
    video_motion dut(.I_clk(clk),.I_rst_n(rst),.I_pixel(pixel),.I_source_id(sid),.I_source_valid(1'b1),.I_axis_state(50'd0),
        .O_status(status),.O_cells(cells),.O_events(events),.O_bbox(bbox),.O_done(done),.O_result_source(result_sid));
    wire [23:0] rgb;
    hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.MOTION_ENABLE(1),.LATENCY_ENABLE(1)) mixer(.I_clk(clk),.I_rst_n(rst),
        .I_video_vsync(pixel[24]),.I_video_hsync(pixel[25]),.I_video_de(pixel[26]),.I_video_user(pixel[27]),.I_video_last(pixel[28]),
        .I_debug_status(4'd0),.I_mode(pixel[30:29]),.I_camera_debug(47'd0),.I_detect_status(2'd0),.I_detect_count(3'd0),.I_detect_objects(320'd0),
        .I_motion_status(status),.I_motion_cells(cells),.I_motion_events(events),.I_motion_bbox(bbox),
        .I_latency_status(lat_status),.I_latency_valid(lat_valid),.I_latency_bcd(lat_bcd),.I_latency_min(lat_min),.I_latency_max(lat_max),.I_latency_source(lat_source),
        .O_frame_sof(output_sof),.O_video_rd_en(),.I_video_rd_data(pixel[23:0]),.O_hdmi_vsync(vs),.O_hdmi_hsync(hs),.O_hdmi_de(de),.O_hdmi_data(rgb));
    reg [30:0] q1=0,q2=0,q3=0;reg [10:0] x1=0,x2=0,x3=0;reg [9:0] y1=0,y2=0,y3=0;
    integer f,x,y,frame_done_count=0,yellow=0,checked=0,left,cyan=0,lat_updates=0;
    reg [23:0] color;
    always @(posedge clk) begin
        q1<=pixel;q2<=q1;q3<=q2;x1<=x;x2<=x1;x3<=x2;y1<=y;y2<=y1;y3<=y2;
        if(done) frame_done_count=frame_done_count+1;
        if(lat_update)lat_updates=lat_updates+1;
        #1;
        if(rst && de) begin
            checked=checked+1;
            if({de,hs,vs}!==q3[26:24]) $fatal(1,"Motion mixer metadata");
            if(rgb==24'h80ffff && x3>=704)begin
                if(x3<912 || x3>=1248 || y3<600 || y3>=688)$fatal(1,"Latency HUD outside lower-right region");
                cyan=cyan+1;
            end
            if(rgb==24'hffff00) begin
                if(q3[30:29]!=3 || !((x3>=704 && x3<1216 && y3>=152 && y3<192) ||
                    (x3>=328 && x3<=575 && y3>=208 && y3<=351))) $fatal(1,"Yellow outside motion HUD/bbox x=%0d y=%0d",x3,y3);
                yellow=yellow+1;
            end
        end
    end
    initial begin
        x=0;y=0;repeat(8) @(negedge clk);rst=1;
        for(f=0;f<5;f=f+1) begin
            sid=(f<3)?f+1:3;if(f<3)capture_time=now_us-(4000+f*1000);left=(f<3)?40+f:42;
            for(y=0;y<VT;y=y+1) for(x=0;x<HT;x=x+1) begin
                color=((x>>3)>=left && (x>>3)<left+30 && (y>>3)>=25 && (y>>3)<45)?24'h909090:24'h202020;
                pixel={2'(f==4?0:3),1'(x==W-1 && y<H),1'(x==0 && y==0),1'(x<W && y<H),1'(x>=1390 && x<1430),1'(y>=725 && y<730),(x<W && y<H?color:24'd0)};
                @(negedge clk);
            end
            if(f==0 && status!=2) $fatal(1,"720p warmup");
            if(f==1 && (status!=2 || cells!=36 || events!=0)) $fatal(1,"720p first motion count=%0d cells=%0d",events,cells);
            if(f==2 || f==3) begin
                if(status!=3 || cells!=36 || events!=1 || bbox!=={10'd351,10'd208,11'd575,11'd328})
                    $fatal(1,"720p motion stats status=%0d cells=%0d events=%0d bbox=%h",status,cells,events,bbox);
            end
        end
        pixel=0;repeat(8) @(negedge clk);
        if(frame_done_count!=3 || yellow<100 || checked!=5*W*H) $fatal(1,"720p motion count/OSD frames=%0d yellow=%0d pixels=%0d",frame_done_count,yellow,checked);
        if(lat_updates!=2 || !lat_valid || lat_bcd!==16'h0060 || lat_min!==16'h0050 || lat_max!==16'h0060 || cyan<100)$fatal(1,"720p latency integration updates=%0d cyan=%0d",lat_updates,cyan);
        $display("MOTION 720P PASS: five real raster frames, three unique sources, 36-cell analytical mask/bbox, duplicate hold, frame-latched yellow HUD and ORIGINAL suppression, %0d HDMI pixels",checked);$finish;
    end
endmodule
