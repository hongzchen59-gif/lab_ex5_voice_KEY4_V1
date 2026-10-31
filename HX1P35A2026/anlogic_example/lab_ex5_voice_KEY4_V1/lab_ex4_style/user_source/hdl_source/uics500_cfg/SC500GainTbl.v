// SC500CS datasheet v1.8, tables 2-4: index 0..127 = 1x..15.75x.
module SC500GainTbl(input wire I_clk,I_rstn,input wire [6:0] I,output reg [15:0] O);
    reg [7:0] coarse;
    always @(*) case(I[6:5])
        0:coarse=8'h03;1:coarse=8'h07;2:coarse=8'h0f;default:coarse=8'h1f;
    endcase
    always @(posedge I_clk) begin
        if(!I_rstn) O<=16'h0f20;
        else O<={coarse,3'b001,I[4:0]};
    end
endmodule
