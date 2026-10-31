`timescale 1ns/1ps
module tb_key_mode;
    reg clk=0,rst_n=0,vblank=0;
    reg [3:0] keys=4'hf;
    wire [1:0] mode;
    integer a,b;
    always #5 clk=~clk;
    key_mode_ctrl #(.DEBOUNCE_CYCLES(4)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_key_n(keys),.I_vblank(vblank),.O_mode(mode));
    task cycles(input integer n);repeat(n) @(negedge clk);endtask
    task select_mode(input integer requested);
        reg [1:0] old;
        begin
            vblank=0;old=mode;keys=~(4'b0001<<requested);cycles(10);
            if(mode!==old) $fatal(1,"mode changed in active frame");
            vblank=1;cycles(3);
            if(mode!==requested[1:0]) $fatal(1,"wrong selected mode");
            vblank=0;cycles(10);
            if(mode!==requested[1:0]) $fatal(1,"hold changed mode");
            keys=4'hf;cycles(10);
        end
    endtask
    initial begin
        cycles(4);rst_n=1;cycles(4);
        if(mode!==0) $fatal(1,"default mode not ORIGINAL");
        // Verify every source/destination pair, including selecting same mode.
        for(a=0;a<4;a=a+1) for(b=0;b<4;b=b+1) begin select_mode(a);select_mode(b);end
        select_mode(0);
        // Short contact bounce must not select EDGE.
        keys=4'b1101;cycles(1);keys=4'hf;cycles(2);
        keys=4'b1101;cycles(1);keys=4'hf;cycles(10);vblank=1;cycles(3);
        if(mode!==0) $fatal(1,"bounce accepted");
        // Chord, including releasing just one member, stays rejected.
        keys=4'b1001;cycles(10);keys=4'b1101;cycles(10);
        if(mode!==0) $fatal(1,"chord accepted");
        keys=4'hf;cycles(10);select_mode(3);
        rst_n=0;cycles(2);rst_n=1;cycles(3);
        if(mode!==0) $fatal(1,"reset mode not ORIGINAL");
        $display("KEY PASS: all 16 transitions, hold, bounce, chord, frame commit, reset");$finish;
    end
    initial begin #100000;$fatal(1,"KEY timeout");end
endmodule
