`timescale 1ns/1ps
module tb_motion;
    localparam W=96,H=64,F=20;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg [30:0] pixel=0;reg [31:0] sid=0;reg tag_valid=1;reg [49:0] axis=0;
    wire [2:0] status;wire [13:0] cells;wire [15:0] events;wire [41:0] bbox;wire done;wire [31:0] result_sid;
    video_motion #(.WIDTH(W),.HEIGHT(H),.MIN_CELLS(2),.SETTLE_CYCLES(80)) dut(
        .I_clk(clk),.I_rst_n(rst),.I_pixel(pixel),.I_source_id(sid),.I_source_valid(tag_valid),.I_axis_state(axis),
        .O_status(status),.O_cells(cells),.O_events(events),.O_bbox(bbox),.O_done(done),.O_result_source(result_sid));
    reg [23:0] images[0:F*W*H-1];reg [79:0] expected[0:F-1];reg [39:0] config_data[0:F-1];
    integer f,x,y,finishes=0;reg [79:0] actual;
    always @(posedge clk) if(done) finishes=finishes+1;
    task constant_frame(input integer id,input integer rows);
        integer xx,yy;
        begin
            sid=id;
            for(yy=0;yy<rows;yy=yy+1) begin
                for(xx=0;xx<W+24;xx=xx+1) begin
                    pixel={2'd3,1'(xx==W-1),1'(xx==0 && yy==0),1'(xx<W),2'b00,24'h202020};
                    @(negedge clk);
                end
            end
            pixel=0;repeat(500) @(negedge clk);
        end
    endtask
    initial begin
        $readmemh("motion_pixels.hex",images);$readmemh("motion_expected.hex",expected);$readmemh("motion_config.hex",config_data);
        repeat(8) @(negedge clk);rst=1;
        for(f=0;f<F;f=f+1) begin
            sid=config_data[f][39:8];axis=config_data[f][2]?{2'b11,16'd3,16'd1500,16'd1500}:50'd0;
            repeat(200) @(negedge clk);
            for(y=0;y<H;y=y+1) begin
                for(x=0;x<W+24;x=x+1) begin
                    pixel={config_data[f][1:0],1'(x==W-1),1'(x==0 && y==0),1'(x<W),2'b00,(x<W?images[f*W*H+y*W+x]:24'd0)};
                    @(negedge clk);
                end
            end
            pixel=0;repeat(500) @(negedge clk);
            actual={5'd0,status,events,cells,bbox};
            if(actual!==expected[f]) $fatal(1,"MOTION frame=%0d sid=%0d status=%0d cells=%0d events=%0d bbox=%h got=%020h expected=%020h",f,sid,status,cells,events,bbox,actual,expected[f]);
        end
        if(finishes!=16) $fatal(1,"Repeated frame processed or unique frame lost: %0d",finishes);
        constant_frame(20,H-1);
        constant_frame(21,H);
        if(status!=6 || dut.prev_valid) $fatal(1,"Incomplete frame not rejected");
        constant_frame(22,H);
        if(status!=2 || cells!=0) $fatal(1,"Reference rebuild after incomplete frame");
        tag_valid=0;constant_frame(23,H);
        if(status!=0 || dut.prev_valid) $fatal(1,"Invalid source tag accepted");
        tag_valid=1;constant_frame(24,H);
        if(status!=2 || cells!=0) $fatal(1,"Invalid-tag recovery");
        $display("MOTION PASS: 20 independent pixel/reference frames, block average, difference/filter/bbox, repeats, hysteresis/events, illumination, gaps, gimbal pause, mode reset");$finish;
    end
    initial begin #4000000;$fatal(1,"Motion timeout");end
endmodule
