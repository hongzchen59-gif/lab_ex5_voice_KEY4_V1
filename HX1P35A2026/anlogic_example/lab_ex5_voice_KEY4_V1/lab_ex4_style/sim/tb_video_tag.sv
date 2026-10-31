`timescale 1ns/1ps
module tb_video_tag #(parameter START_HIGH=0);
    reg pclk=0,dclk=0,rst=0,vs=START_HIGH;always #6.667 pclk=~pclk;always #7.5 dclk=~dclk;
    reg [1:0] bank=0;reg [127:0] ids={32'd44,32'd33,32'd22,32'd11};reg [3:0] complete=4'b1101;
    wire [31:0] sid,capture_time;wire tag_valid,capture_valid;
    reg [127:0] times={32'd4000,32'd3000,32'd2000,32'd1000};reg [3:0] times_valid=4'b1001;
    video_out #(.TAG_ENABLE(1),.LATENCY_ENABLE(1)) dut(.I_rst_n(rst),.I_ddr_clk(dclk),.I_video_in_wr_busy(1'b0),
        .I_video_out_rp(bank),.I_bank_source_ids(ids),.I_bank_complete(complete),.O_source_id(sid),.O_source_valid(tag_valid),
        .I_bank_capture_us(times),.I_bank_capture_valid(times_valid),.O_capture_us(capture_time),.O_capture_valid(capture_valid),
        .O_video_out_rd_busy(),.O_ddr_user_rd_en(),.O_ddr_user_addr(),.I_ddr_user_ready(1'b0),
        .I_ddr_user_rd_valid(1'b0),.I_ddr_user_rd_data(128'd0),.I_dsi_clk(pclk),.I_video_vsync(vs),.I_video_rd_en(1'b0),.O_vdieo_data());
    integer f;reg [31:0] expected;reg good;reg [31:0] expected_time;reg good_time;
    initial begin
        repeat(12) @(negedge pclk);rst=1;
        for(f=0;f<6;f=f+1) begin
            bank=f%4;expected=ids[bank*32+:32];good=complete[bank];expected_time=times[bank*32+:32];good_time=times_valid[bank];
            @(negedge pclk);vs=1;repeat(20) @(negedge pclk);vs=0;
            repeat(20) @(negedge pclk);
            if(sid!==expected || tag_valid!==good) $fatal(1,"Tag bank=%0d got=%0d/%b expected=%0d/%b",bank,sid,tag_valid,expected,good);
            if(capture_time!==expected_time || capture_valid!==good_time)$fatal(1,"Timestamp snapshot mismatch");
            times[bank*32+:32]=times[bank*32+:32]+1000;
            ids[bank*32+:32]=ids[bank*32+:32]+100;
            repeat(12) @(negedge pclk);
            if(sid!==expected || capture_time!==expected_time) $fatal(1,"Tag changed inside displayed frame");
        end
        $display("VIDEO TAG PASS: actual selected bank, coherent snapshot/epoch CDC, incomplete bank, stable tag despite bank-generation changes");$finish;
    end
    initial begin #100000;$fatal(1,"Tag timeout");end
endmodule
