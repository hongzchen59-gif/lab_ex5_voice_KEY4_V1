`timescale 1ns/1ps
module tb_color_fill;
    video_style_core #(.H_TOTAL(48)) dut(.I_clk(1'b0),.I_rst_n(1'b0),.I_pixel(31'd0),.O_pixel(),.O_effect_ready());
    integer r,g,b,y,q,got,expected,count=0;reg [23:0] p,out;
    reg [32:0] candidate;reg [31:0] plan;
    task check(input [23:0] raw);
        integer rr,gg,bb,oy,ny;
        begin
            candidate=dut.candidate_chroma(raw);
            oy=(raw[23:16]+2*int'(raw[15:8])+raw[7:0])/4;
            plan=dut.prepare_fill(candidate,raw,dut.quant_up(oy[7:0]));
            rr=int'(plan[23:16])+plan[31:24];gg=int'(plan[15:8])+plan[31:24];bb=int'(plan[7:0])+plan[31:24];
            if(rr>255 || gg>255 || bb>255)$fatal(1,"Fill overflow %h",raw);
            ny=(rr+2*gg+bb)/4;
            if(ny<oy)$fatal(1,"Fill darkened %h Y=%0d -> %0d",raw,oy,ny);
            if((raw[23:16]>=raw[15:8] && rr<gg) || (raw[15:8]>=raw[7:0] && gg<bb) ||
               (raw[7:0]>=raw[23:16] && bb<rr))$fatal(1,"Channel order changed");
            out={8'(rr),8'(gg),8'(bb)};count=count+1;
        end
    endtask
    initial begin
        for(y=0;y<256;y=y+1)begin
            expected=y<16?y:((y/16+1)*16);if(expected>255)expected=255;
            got=dut.quant_up(y[7:0]);if(got!=expected)$fatal(1,"Luma LUT");
            check({8'(y),8'(y),8'(y)});
            if(out!=={8'(expected),8'(expected),8'(expected)})$fatal(1,"Neutral tint/darkening");
        end
        for(r=0;r<256;r=r+17)for(g=0;g<256;g=g+17)for(b=0;b<256;b=b+17)check({8'(r),8'(g),8'(b)});
        for(q=0;q<4096;q=q+1)begin p=$random;check(p);end
        check(24'h7f817f);if(int'(out[15:8])-int'(out[23:16])!=2 || out[23:16]!==out[7:0])$fatal(1,"Near-neutral exaggerated");
        check(24'hffffff);if(out!==24'hffffff)$fatal(1,"White became gray");
        $display("COLOR FILL PASS: %0d colors, all gray levels, non-darkening luminance, gamut and near-neutral hue protection",count);$finish;
    end
endmodule
