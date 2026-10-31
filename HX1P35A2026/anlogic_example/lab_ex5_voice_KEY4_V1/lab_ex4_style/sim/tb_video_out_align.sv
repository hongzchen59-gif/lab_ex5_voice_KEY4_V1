`timescale 1ns/1ps
// Real supplied FIFO + video_out, independent DDR and pixel clocks.
module tb_video_out_align;
    reg clk=0,ddr_clk=0,rst_n=0,vs=0,de=0,sof=0,eol=0;
    reg [1:0] mode=0;
    reg wr=0;reg [127:0] data=0;
    wire [23:0] rgb;wire [30:0] pixel;
    reg [30:0] ref1=0,ref2=0;
    reg [23:0] wanted=0;
    reg [383:0] packed_pixels;
    integer group_num,k,beat,x,y,checked=0;
    always #6.667 clk=~clk;
    always #7.5 ddr_clk=~ddr_clk;
    function [23:0] sample_rgb;
        input integer n;
        begin sample_rgb={8'(n),8'(n^8'hb5),8'((n*13+7)%256)};end
    endfunction
    video_out reader(.I_rst_n(rst_n),.I_ddr_clk(ddr_clk),
        .O_video_out_rd_busy(),.I_video_in_wr_busy(1'b0),.I_video_out_rp(2'b0),
        .O_ddr_user_rd_en(),.O_ddr_user_addr(),.I_ddr_user_ready(1'b0),
        .I_ddr_user_rd_valid(wr),.I_ddr_user_rd_data(data),.I_dsi_clk(clk),
        .I_video_vsync(vs),.I_video_rd_en(de),.O_vdieo_data(rgb));
    video_pixel_align aligner(.I_clk(clk),.I_rst_n(rst_n),.I_vs(vs),.I_hs(1'b0),
        .I_de(de),.I_sof(sof),.I_eol(eol),.I_mode(mode),.I_rgb(rgb),.O_pixel(pixel));
    always @(posedge clk) begin
        ref1 <= {mode,eol,sof,de,1'b0,vs,wanted};
        ref2 <= ref1;
        #1;
        if(rst_n && ref2[26]) begin
            if(pixel !== ref2) $fatal(1,"ALIGN FAIL pixel=%08h reference=%08h count=%0d",pixel,ref2,checked);
            checked=checked+1;
        end
    end
    initial begin
        repeat(8) @(negedge clk);rst_n=1;vs=1;
        repeat(24) @(negedge clk);vs=0;
        repeat(20) @(negedge ddr_clk);
        for(group_num=0;group_num<16;group_num=group_num+1) begin
            for(k=0;k<16;k=k+1) packed_pixels[383-k*24 -:24]=sample_rgb(group_num*16+k);
            for(beat=0;beat<3;beat=beat+1) begin
                @(negedge ddr_clk);wr=1;data=packed_pixels[383-beat*128 -:128];
            end
        end
        @(negedge ddr_clk);wr=0;
        repeat(20) @(negedge clk);
        for(y=0;y<4;y=y+1) begin
            for(x=0;x<80;x=x+1) begin
                @(negedge clk);de=x<64;sof=(x==0 && y==0);eol=x==63;
                mode=y;wanted=de?sample_rgb(y*64+x):24'd0;
            end
        end
        @(negedge clk);de=0;sof=0;eol=0;wanted=0;
        repeat(5) @(negedge clk);
        if(checked!=256) $fatal(1,"ALIGN wrong pixel count %0d",checked);
        $display("ALIGN PASS: 256 pixels, all 16 packing positions, four lines, real async FIFO and 2-clock metadata");
        $finish;
    end
    initial begin #200000;$fatal(1,"ALIGN timeout");end
endmodule
