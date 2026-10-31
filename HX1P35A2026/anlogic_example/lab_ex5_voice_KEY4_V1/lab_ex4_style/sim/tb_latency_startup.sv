`timescale 1ns/1ps
// Actual top-level VTC polarity/reset, not a VS pulse starting low after reset.
// On the board ~O_vtc_vs is already high while HDMI reset is asserted.
module tb_latency_startup;
    reg pclk=0,dclk=0,rst=0;
    always #6.667 pclk=~pclk;
    always #7.5 dclk=~dclk;
    wire vs,hs,de,sof,eol;
    uivtc #(.H_ActiveSize(32),.H_FrameSize(48),.H_SyncStart(36),.H_SyncEnd(40),
        .V_ActiveSize(8),.V_FrameSize(14),.V_SyncStart(9),.V_SyncEnd(11)) timing(
        .I_vtc_rstn(rst),.I_vtc_clk(pclk),.O_vtc_vs(vs),.O_vtc_hs(hs),
        .O_vtc_de_valid(de),.O_vtc_user(sof),.O_vtc_last(eol));
    reg [31:0] next_source=1;
    always @(posedge pclk) if(rst && sof) next_source<=next_source+1;
    wire [31:0] source_id,capture_time;
    wire source_valid,capture_valid;
    video_out #(.TAG_ENABLE(1),.LATENCY_ENABLE(1)) reader(
        .I_rst_n(rst),.I_ddr_clk(dclk),.I_video_in_wr_busy(1'b0),.I_video_out_rp(2'd0),
        .I_bank_source_ids({96'd0,next_source}),.I_bank_complete(4'b0001),
        .I_bank_capture_us(128'd0),.I_bank_capture_valid(4'b0001),
        .O_source_id(source_id),.O_source_valid(source_valid),.O_capture_us(capture_time),.O_capture_valid(capture_valid),
        .O_video_out_rd_busy(),.O_ddr_user_rd_en(),.O_ddr_user_addr(),.I_ddr_user_ready(1'b0),
        .I_ddr_user_rd_valid(1'b0),.I_ddr_user_rd_data(128'd0),.I_dsi_clk(pclk),
        .I_video_vsync(~vs),.I_video_rd_en(1'b0),.O_vdieo_data());
    reg [31:0] now_us=1000;
    reg [3:0] sof_delay=0,de_delay=0;
    always @(posedge pclk) begin
        now_us<=now_us+1;
        sof_delay<={sof_delay[2:0],sof};de_delay<={de_delay[2:0],de};
    end
    wire [1:0] status;wire history_valid,update;
    video_latency latency(.clk(pclk),.rst_n(rst),.now_us(now_us),.input_sof(sof),
        .output_sof(sof_delay[3]),.output_de(de_delay[3]),.source_id(source_id),
        .capture_us(capture_time),.source_valid(source_valid),.capture_valid(capture_valid),
        .status(status),.history_valid(history_valid),.latency_bcd(),.min_bcd(),.max_bcd(),
        .measured_source(),.measured_us(),.update(update));
    integer frames=0,updates=0;
    always @(posedge pclk) begin
        if(rst && sof) frames=frames+1;
        if(rst && update) updates=updates+1;
    end
    initial begin
        repeat(24) @(negedge pclk);
        if((~vs)!==1'b1)$fatal(1,"VTC must reproduce the board's reset-high read VS");
        rst=1;
        wait(frames==5);repeat(40) @(negedge pclk);
        if(status!==1 || !history_valid || updates!=4)
            $fatal(1,"Startup remains WAIT: frames=%0d updates=%0d status=%0d epochs=%0d/%0d tags=%b/%b",
                frames,updates,status,reader.g_tag.read_epoch,reader.g_tag.pixel_epoch,source_valid,capture_valid);
        $display("LATENCY STARTUP PASS: actual VTC/reset-high polarity, 5 frames, 4 LIVE updates across DDR/pixel clocks");
        $finish;
    end
    initial begin #100000;$fatal(1,"Startup timeout");end
endmodule
