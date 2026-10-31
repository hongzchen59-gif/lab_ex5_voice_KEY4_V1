`timescale 1ns/1ps
module tb_motion_overlay;
    reg clk=0,rst=0,update=0,de=0,en=0;always #5 clk=~clk;
    reg [11:0] x=0,y=0;reg [2:0] status=3;
    wire th,bh;wire [23:0] tc,bc;
    motion_overlay dut(.I_clk(clk),.I_rst_n(rst),.I_update(update),.I_x(x),.I_y(y),.I_de(de),.I_enable(en),
        .I_status(status),.I_cells(14'd1234),.I_events(16'd65535),.I_bbox({10'd300,10'd240,11'd500,11'd400}),
        .O_text_hit(th),.O_box_hit(bh),.O_text_color(tc),.O_box_color(bc));
    wire [15:0] glyph;reg [3:0] row=0;
    osd_char_lib reference_font(.I_char(8'h4d),.I_row(row),.O_row_bits(glyph));
    integer xx,yy;reg expected_box;
    initial begin
        repeat(6) @(negedge clk);rst=1;update=1;@(negedge clk);update=0;repeat(20) @(negedge clk);
        if(dut.bcd_c!==20'h01234 || dut.bcd_e!==20'h65535) $fatal(1,"Motion BCD counts");
        en=1;de=1;
        for(yy=0;yy<16;yy=yy+1) for(xx=0;xx<16;xx=xx+1) begin
            x=704+xx;y=152+yy;row=yy;
            @(posedge clk);#1;if(th!==glyph[15-xx] || tc!=24'hffff00) $fatal(1,"Motion text alignment");@(negedge clk);
        end
        for(yy=238;yy<303;yy=yy+1) for(xx=398;xx<503;xx=xx+1) begin
            x=xx;y=yy;expected_box=xx>=400 && xx<=500 && yy>=240 && yy<=300 &&
                (xx<402 || xx>498 || yy<242 || yy>298) && !((xx>>3&1)^(yy>>3&1));
            @(posedge clk);#1;if(bh!==expected_box || bc!=24'hffff00) $fatal(1,"Motion box coordinate");@(negedge clk);
        end
        en=0;@(posedge clk);#1;if(th || bh) $fatal(1,"Motion overlay leaked outside DETECT");
        $display("MOTION OVERLAY PASS: decimal counters, text lookup alignment, dashed bbox edges/clipping and enable gating");$finish;
    end
endmodule
