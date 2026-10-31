`timescale 1ns/1ps
module tb_thin_contour #(parameter PATTERN=0);
    localparam W=32,H=16,HT=48,VT=20;
    reg clk=0,rst=0;always #6.667 clk=~clk;
    reg [30:0] pixel=0;wire [30:0] result;wire ready;
    video_style_core #(.H_TOTAL(HT)) dut(.I_clk(clk),.I_rst_n(rst),.I_pixel(pixel),.O_pixel(result),.O_effect_ready(ready));
    function integer value(input integer x);
        begin
            if(PATTERN==0)value=x<16?64:192;
            else if(x<8)value=0;
            else if(x>14)value=240;
            else value=(x-8)*40;
        end
    endfunction
    integer f,x,y,ox=0,oy=0,frames=0,ink=0,checked=0,v,expected;
    always @(posedge clk)begin
        #1;
        if(rst && result[26])begin
            if(result[27])begin ox=0;oy=0;if(ready)frames=frames+1;end
            if(ready)begin
                v=value(ox);
                if(PATTERN==0)begin
                    expected=(ox==0 || ox==W-1 || oy==0 || oy==H-1)?v:(ox==16?0:(v+16));
                    if(result[23:0]!=={8'(expected),8'(expected),8'(expected)})$fatal(1,"Step x=%0d y=%0d got=%h exp=%0d",ox,oy,result[23:0],expected);
                    if(result[23:0]==0)ink=ink+1;
                    checked=checked+1;
                end else if(ox>=10 && ox<=13 && oy>0 && oy<H-1)begin
                    expected=(v/16+1)*16;
                    if(result[23:0]!=={8'(expected),8'(expected),8'(expected)})$fatal(1,"Linear shading painted black x=%0d got=%h",ox,result[23:0]);
                    checked=checked+1;
                end
            end
            if(ox==W-1)begin ox=0;oy=oy+1;end else ox=ox+1;
        end
    end
    initial begin
        repeat(6)@(negedge clk);rst=1;
        for(f=0;f<4;f=f+1)for(y=0;y<VT;y=y+1)for(x=0;x<HT;x=x+1)begin
            @(negedge clk);v=value(x);
            pixel={2'd2,1'(x==W-1&&y<H),1'(x==0&&y==0),1'(x<W&&y<H),2'b00,8'(v),8'(v),8'(v)};
        end
        @(negedge clk);pixel=0;repeat(200)@(negedge clk);
        if(frames<2 || checked<100 || (PATTERN==0 && ink!=frames*(H-2)))$fatal(1,"Contour counts frames=%0d ink=%0d checked=%0d",frames,ink,checked);
        $display("THIN CONTOUR PASS: pattern=%0d frames=%0d checked=%0d ink=%0d, one bright-side step column / linear-gradient rejection",PATTERN,frames,checked,ink);$finish;
    end
    initial begin #100000;$fatal(1,"Contour timeout");end
endmodule
