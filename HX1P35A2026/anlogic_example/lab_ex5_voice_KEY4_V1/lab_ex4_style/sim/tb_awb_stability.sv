`timescale 1ns/1ps
module tb_awb_stability;
    reg clk=0,rst=0,sof=0,valid=0,last=0;
    reg [95:0] pixels=0;wire [95:0] out;
    wire ov,os,ol;
    always #5 clk=~clk;
    awb #(.IMG_WIDTH(32),.IMG_HEIGHT(8)) dut(.I_clk(clk),.I_rst_n(rst),
        .I_tlast(last),.I_tuser(sof),.I_tdata(pixels),.I_tvalid(valid),.I_tready(),
        .O_tlast(ol),.O_tuser(os),.O_tdata(out),.O_tvalid(ov),.O_tready(1'b1));
    reg [95:0] expected=0,next_expected;
    reg ev=0,es=0,el=0;
    integer i,rr,bb,gr,gb,checked=0;
    // Compare all four output lanes and independently delayed metadata.
    always @(posedge clk) begin
        next_expected=0;
        gr=sof?dut.pending_r:dut.gain_r;gb=sof?dut.pending_b:dut.gain_b;
        for(i=0;i<4;i=i+1) begin
            rr=(pixels[i*24+16+:8]*gr)>>8;bb=(pixels[i*24+:8]*gb)>>8;
            next_expected[i*24+:24]={8'(rr>255?255:rr),pixels[i*24+8+:8],8'(bb>255?255:bb)};
        end
        #1;
        if(rst) begin
            if({ov,os,ol}!=={ev,es,el}) $fatal(1,"AWB sideband alignment");
            if(out!==(ev?expected:96'd0)) $fatal(1,"AWB pixel alignment/saturation");
            if(ov) checked=checked+4;
        end
        expected=next_expected;ev=valid;es=sof;el=last;
    end
    task tick;@(negedge clk);endtask
    integer f,j;
    task frame(input [23:0] neutral,input integer red_groups,input integer groups);
        reg [9:0] held_r,held_b;
        begin
            tick;sof=1;valid=1;pixels={4{neutral}};last=0;
            tick;sof=0;held_r=dut.gain_r;held_b=dut.gain_b;
            for(j=1;j<groups;j=j+1) begin
                valid=1;pixels={4{j<red_groups?24'hb42018:neutral}};last=(j%8==7);
                tick;
                if(dut.gain_r!=held_r || dut.gain_b!=held_b) $fatal(1,"AWB changed within frame");
                if(j%7==0) begin valid=0;last=0;tick;end
            end
            valid=0;last=0;repeat(50) tick;
        end
    endtask
    initial begin
        repeat(4) tick;rst=1;
        for(f=0;f<40;f=f+1) frame(24'h506040,32,64);
        if(dut.gain_r!=307 || dut.gain_b!=384) $fatal(1,"Neutral convergence R=%0d B=%0d",dut.gain_r,dut.gain_b);
        for(f=0;f<8;f=f+1) frame(24'hb42018,64,64);
        if(dut.gain_r!=307 || dut.gain_b!=384) $fatal(1,"Red scene contaminated WB");
        for(f=0;f<8;f=f+1) frame(24'h808040,0,12);
        if(dut.gain_r!=307 || dut.gain_b!=384) $fatal(1,"Partial frame changed WB");
        for(f=0;f<40;f=f+1) frame(24'hb46060,0,64);
        if(dut.gain_r!=192 || dut.gain_b!=256) $fatal(1,"WB lower clamp");
        for(f=0;f<40;f=f+1) frame(24'h508028,0,64);
        if(dut.gain_r!=192 || dut.gain_b!=256) $fatal(1,"WB accepted colored sample");
        for(f=0;f<40;f=f+1) frame(24'h505028,0,64);
        if(dut.gain_r!=256 || dut.gain_b!=512) $fatal(1,"WB upper clamp");
        frame(24'hffffff,64,64);
        $display("AWB PASS: %0d pixels, SOF/DE/EOL alignment, frame-held gains, neutral convergence, colored targets, incomplete frames, clamps",checked);
        $finish;
    end
    initial begin #2000000;$fatal(1,"AWB timeout");end
endmodule
