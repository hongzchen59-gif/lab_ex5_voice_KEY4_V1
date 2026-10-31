`timescale 1ns/1ps
// Exercise the previously untested real ISP-to-DDR boundary, including reset CDC.
module tb_isp_ddr_frame #(
    parameter W=1280,H=4,FRAMES=5,
    parameter real CAM_HALF=5.0, DDR_HALF=7.5
);
    localparam WORDS=W*H*3/16;
    reg cam=0,ddr=0,rst=0,sof=0,valid=0,last=0;
    reg [95:0] pixels=0;
    always #(CAM_HALF) cam=~cam;
    always #(DDR_HALF) ddr=~ddr;
    wire [95:0] wb;wire wv,ws,wl;
    awb #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.GAIN_MIN(256),.GAIN_MAX(256)) color(
        .I_clk(cam),.I_rst_n(rst),.I_tlast(last),.I_tuser(sof),.I_tdata(pixels),
        .I_tvalid(valid),.I_tready(),.O_tlast(wl),.O_tuser(ws),.O_tdata(wb),.O_tvalid(wv),.O_tready(1'b1));
    wire [127:0] packed_data;wire packed_valid,packed_sof;
    data_96bit_to_128bit packer(.I_clk(cam),.I_rst_n(rst),
        .I_96b_frame_start(ws),.I_96b_valid(wv),.I_96b_data(wb),
        .O_128b_frame_start(packed_sof),.O_128b_valid(packed_valid),.O_128b_data(packed_data));
    wire wr;wire [24:0] addr;wire [127:0] data;
    wire [127:0] bank_ids,bank_times;wire [3:0] complete,time_valid;
    reg capture_start=0;reg [31:0] camera_us=0;
    video_in #(.FRAME_WORDS(WORDS),.LATENCY_ENABLE(1)) writer(.I_rst_n(rst),.I_camera_clk(cam),.I_camera_frame_start(packed_sof),
        .I_capture_start(capture_start),.I_camera_time_us(camera_us),.O_bank_capture_us(bank_times),.O_bank_capture_valid(time_valid),
        .I_camera_valid(packed_valid),.I_camera_data(packed_data),.I_mipi_rx_error(1'b0),
        .I_ddr_clk(ddr),.I_display_pause(1'b0),.I_video_out_rd_busy(1'b0),
        .O_video_in_wr_busy(),.O_video_out_rp(),.O_bank_source_ids(bank_ids),.O_bank_complete(complete),.O_ddr_user_wr_en(wr),
        .O_ddr_user_addr(addr),.O_ddr_user_wr_data(data),.I_ddr_user_ready(1'b1));
    function [23:0] pixel(input integer n,input integer frame);
        begin pixel={8'((n+frame*17)%256),8'((n*3+81)%256),8'((n*7+39)%256)};end
    endfunction
    function [127:0] word(input integer n,input integer frame);
        integer k,index;reg [23:0] p;
        begin
            for(k=0;k<16;k=k+1) begin
                index=n*16+k;p=pixel(index/3,frame);
                case(index%3)
                    0:word[127-k*8-:8]=p[23:16];
                    1:word[127-k*8-:8]=p[15:8];
                    2:word[127-k*8-:8]=p[7:0];
                endcase
            end
        end
    endfunction
    integer received=0,frame_number=0,errors=0,checked=0;
    reg [24:0] base;
    always @(posedge ddr) begin
        if(rst && wr) begin
            case(frame_number%4) 0:base=0;1:base=7000000;2:base=14000000;3:base=21000000;endcase
            if(data!==word(received,frame_number) || addr!==base+received*8) begin
                if(errors<3) $display("FRAME mismatch frame=%0d word=%0d addr=%0d data=%032h expected=%032h",frame_number,received,addr,data,word(received,frame_number));
                errors=errors+1;
            end
            received=received+1;checked=checked+1;
        end
    end
    integer f,y,x,n,waited;
    initial begin
        repeat(12) @(negedge cam);rst=1;repeat(30) @(negedge cam);
        for(f=0;f<FRAMES;f=f+1) begin
            frame_number=f;received=0;
            camera_us=f*1000+123;capture_start=1;@(negedge cam);capture_start=0;
            camera_us=f*1000+321;repeat(8) @(negedge cam);
            // Exercise both SOF with data and SOF ahead of data.
            if(f%2==1) begin
                sof=1;@(negedge cam);sof=0;repeat(60) @(negedge cam);
            end
            for(y=0;y<H;y=y+1) begin
                for(x=0;x<W;x=x+4) begin
                    sof=(f%2==0 && y==0 && x==0);valid=1;last=(x==W-4);n=y*W+x;
                    pixels={pixel(n,f),pixel(n+1,f),pixel(n+2,f),pixel(n+3,f)};
                    @(negedge cam);
                end
                valid=0;sof=0;last=0;repeat(800) @(negedge cam);
            end
            repeat(1500) @(negedge cam);
            if(received!=WORDS) $fatal(1,"Frame %0d lost data: received %0d expected %0d (errors=%0d)",f,received,WORDS,errors);
            if(!complete[f%4] || bank_ids[(f%4)*32+:32]!==f+1) $fatal(1,"Frame metadata mismatch frame=%0d ids=%h complete=%b",f,bank_ids,complete);
            if(!time_valid[f%4] || bank_times[(f%4)*32+:32]!==f*1000+123) $fatal(1,"Capture timestamp mismatch frame=%0d time=%h valid=%b",f,bank_times,time_valid);
            if(errors!=0) $fatal(1,"Frame %0d byte ordering/pixel errors=%0d",f,errors);
        end
        frame_number=FRAMES;received=0;
        sof=1;valid=1;pixels={4{24'h123456}};@(negedge cam);sof=0;
        repeat(15) @(negedge cam);
        valid=0;repeat(300) @(negedge cam);
        if(complete[FRAMES%4] || time_valid[FRAMES%4]) $fatal(1,"Partial/missing capture frame published valid");
        capture_start=1;@(negedge cam);capture_start=0;repeat(3) @(negedge cam);
        capture_start=1;@(negedge cam);capture_start=0;repeat(3) @(negedge cam);
        sof=1;valid=1;@(negedge cam);sof=0;repeat(15) @(negedge cam);valid=0;repeat(300) @(negedge cam);
        if(time_valid[(FRAMES+1)%4]) $fatal(1,"Ambiguous double capture accepted");
        $display("ISP DDR FRAME PASS: %0d words / %0d pixels, %0d frames %0dx%0d, SOF with/ahead of data, real FIFO/reset CDC, RGB bytes and addresses",checked,FRAMES*W*H,FRAMES,W,H);
        $finish;
    end
    initial begin #100000000;$fatal(1,"ISP DDR timeout");end
endmodule
