`timescale 1ns/1ps
module tb_preserve_norm;
    reg clk=0;always #5 clk=~clk;
    edge_preserve #(.H_TOTAL(24)) dut(.I_clk(clk),.I_rst_n(1'b0),.I_pixel(31'b0),.O_pixel());
    integer d,n,expected,actual,inv,checked=0;
    initial begin
        for(d=8;d<=32;d=d+1) for(n=0;n<=255*d;n=n+1) begin
            inv=dut.reciprocal(d);
            actual=(n*inv+524288)>>20;
            expected=(2*n+d)/(2*d);
            if(actual!=expected) $fatal(1,"Normalization mismatch d=%0d n=%0d got=%0d expected=%0d",d,n,actual,expected);
            checked=checked+1;
        end
        $display("NORM PASS: %0d legal numerator/denominator pairs, exact rounded division",checked);$finish;
    end
endmodule
