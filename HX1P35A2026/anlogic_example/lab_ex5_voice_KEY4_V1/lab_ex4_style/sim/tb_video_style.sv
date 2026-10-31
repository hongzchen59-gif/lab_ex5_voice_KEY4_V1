`timescale 1ns/1ps
module tb_video_style;
    localparam HT=24, VT=13, N=56*HT*VT, LATENCY=2*HT+19;
    reg clk=0,rst_n=0;
    always #6.667 clk=~clk;
    reg [30:0] pixel=0;
    wire [30:0] result;
    reg [30:0] stimulus [0:N-1];
    reg [30:0] expected [0:N-1];
    integer i,j,errors=0,checked=0;
    video_style #(.H_TOTAL(HT)) dut(.I_clk(clk),.I_rst_n(rst_n),.I_pixel(pixel),.O_pixel(result));
    initial begin
        $readmemh("input.hex",stimulus);$readmemh("expected.hex",expected);
        repeat(5) @(negedge clk);rst_n=1;
        for(i=0;i<N+LATENCY;i=i+1) begin
            @(negedge clk);pixel=(i<N)?stimulus[i]:31'd0;
            @(posedge clk);#1;
            j=i-LATENCY;
            // The RAM is uninitialized at startup; output starts at the first
            // complete SOF after line memories have warmed up (frame 1 here).
            if(j>=HT*VT && j<N) begin
                checked=checked+1;
                if(result !== expected[j]) begin
                    if(errors<12) $display("Mismatch clock=%0d ref=%0d frame=%0d x=%0d y=%0d got=%08h expected=%08h",i,j,j/(HT*VT),j%HT,(j/HT)%VT,result,expected[j]);
                    errors=errors+1;
                end
            end
        end
        if(errors) $fatal(1,"STYLE FAIL errors=%0d checked=%0d",errors,checked);
        $display("STYLE PASS: %0d raster clocks, RGB + HS/VS/DE/SOF/EOL/mode exact",checked);
        $finish;
    end
    initial begin #2000000;$fatal(1,"STYLE timeout");end
endmodule
