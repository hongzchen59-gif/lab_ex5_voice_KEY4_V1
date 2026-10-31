`timescale 1ns/1ps
module tb_toon_blend;
    video_style_core #(.H_TOTAL(24)) dut(.I_clk(1'b0),.I_rst_n(1'b0),.I_pixel(31'd0),.O_pixel(),.O_effect_ready());
    integer paint,original,expected,actual,count=0;
    initial begin
        for(paint=0;paint<256;paint=paint+1)for(original=0;original<256;original=original+1)begin
            expected=(3*paint+original)/4;
            if(paint==0 && original<8)expected=0;
            else if(paint==255 && original>=248)expected=255;
            actual=dut.blend75(paint[7:0],original[7:0]);
            if(actual!=expected)$fatal(1,"Blend width/rounding paint=%0d source=%0d got=%0d expected=%0d",paint,original,actual,expected);
            count=count+1;
        end
        $display("TOON BLEND PASS: %0d RTL byte pairs, ten-bit sum, endpoints and exact 75/25 rounding",count);$finish;
    end
endmodule
