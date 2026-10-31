`timescale 1ns/1ps
module tb_motion_cdc;
    reg src=0,dst=0,rst=0,valid=0;reg [31:0] value=0;
    always #5 src=~src;always #6.667 dst=~dst;
    wire new_valid,old_valid;wire [31:0] data_new,data_old;
    meter_cdc #(.WIDTH(32),.BUNDLED_DIRECT(1)) direct(.I_src_clk(src),.I_src_rst_n(rst),.I_valid(valid),.I_data(value),.I_dst_clk(dst),.I_dst_rst_n(rst),.O_valid(new_valid),.O_data(data_new));
    meter_cdc #(.WIDTH(32)) legacy(.I_src_clk(src),.I_src_rst_n(rst),.I_valid(valid),.I_data(value),.I_dst_clk(dst),.I_dst_rst_n(rst),.O_valid(old_valid),.O_data(data_old));
    wire [31:0] slow_new,slow_old;
    assign #18 slow_new=direct.held;
    assign #18 slow_old=legacy.held;
    integer i,old_errors=0;reg [31:0] expected;
    initial begin
        force direct.payload_at_dst=slow_new;
        force legacy.payload_at_dst=slow_old;
        repeat(10) @(negedge src);rst=1;repeat(10) @(negedge src);
        for(i=0;i<100;i=i+1) begin
            @(negedge src);expected=32'h19283746^(i*32'h1020311);value=expected;valid=1;
            @(negedge src);valid=0;value=~expected;
            @(posedge new_valid);#1;
            if(data_new!==expected) $fatal(1,"Held bundle corrupted with 18ns skew i=%0d got=%h expected=%h",i,data_new,expected);
            if(data_old!==expected) old_errors=old_errors+1;
            repeat(12+(i%3)) @(negedge src);
        end
        if(old_errors==0) $fatal(1,"Skew fixture did not exercise stale parallel pipeline");
        $display("MOTION CDC PASS: 100 coherent held payloads with 18ns data/REQ skew; legacy parallel pipeline reproduced %0d stale captures",old_errors);$finish;
    end
    initial begin #100000;$fatal(1,"Motion CDC timeout");end
endmodule
