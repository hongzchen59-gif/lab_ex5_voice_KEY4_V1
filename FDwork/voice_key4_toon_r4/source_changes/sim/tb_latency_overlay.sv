`timescale 1ns/1ps
module tb_latency_overlay;
    reg clk=0,rst=0,de=1;always #5 clk=~clk;
    reg [11:0] x=0,y=0;reg [1:0] status=1;reg hist=1;wire hit;wire [23:0] color;
    latency_overlay dut(.clk(clk),.rst_n(rst),.x(x),.y(y),.de(de),.status(status),.history_valid(hist),
        .value_bcd(16'h0667),.min_bcd(16'h0650),.max_bcd(16'h0833),.measured_source(32'h1234567b),.text_hit(hit),.text_color(color));
    reg [7:0] ch=8'h4c;reg [3:0] row=0;wire [15:0] glyph;
    osd_char_lib font(.I_char(ch),.I_row(row),.O_row_bits(glyph));
    integer xx,yy,col;reg [7:0] expected[0:4];
    initial begin
        repeat(5) @(negedge clk);rst=1;
        for(yy=0;yy<16;yy=yy+1)for(xx=0;xx<16;xx=xx+1)begin
            x=912+xx;y=600+yy;row=yy;
            @(posedge clk);#1;if(hit!==glyph[15-xx] || color!=24'h80ffff)$fatal(1,"Latency glyph alignment");@(negedge clk);
        end
        expected[0]="0";expected[1]="6";expected[2]="6";expected[3]=".";expected[4]="7";
        for(col=0;col<5;col=col+1)begin
            x=912+(col+5)*16;y=600;@(posedge clk);#1;
            if(dut.char_d!==expected[col])$fatal(1,"Latency decimal position %0d",col);@(negedge clk);
        end
        x=912+13*16;y=672;@(posedge clk);#1;if(dut.char_d!==8'h42)$fatal(1,"Measurement source hex");@(negedge clk);
        x=992;y=600;status=2;@(posedge clk);#1;if(dut.char_d!==8'h2d)$fatal(1,"HOLD falsely shows live value");@(negedge clk);
        status=1;hist=0;@(posedge clk);#1;if(dut.char_d!==8'h2d)$fatal(1,"Uninitialized numeric HUD");@(negedge clk);
        de=0;@(posedge clk);#1;if(hit)$fatal(1,"HUD in blanking");@(negedge clk);
        ch=".";row=12;#1;if(glyph==0)$fatal(1,"Missing decimal glyph");
        ch="m";row=7;#1;if(glyph==0)$fatal(1,"Missing millisecond unit glyph");
        ch="s";row=9;#1;if(glyph==0)$fatal(1,"Missing unit s glyph");
        de=1;hist=1;
        for(yy=0;yy<720;yy=yy+1)for(xx=0;xx<1280;xx=xx+1)begin
            x=xx;y=yy;@(posedge clk);#1;
            if(hit && (xx<912 || xx>=1248 || yy<600 || yy>=688))$fatal(1,"HUD escaped lower-right region");
            @(negedge clk);
        end
        $display("LATENCY OVERLAY PASS: live decimal ms, WAIT/HOLD placeholders, source hex, pipeline/DE gating and ms punctuation glyphs");$finish;
    end
endmodule
