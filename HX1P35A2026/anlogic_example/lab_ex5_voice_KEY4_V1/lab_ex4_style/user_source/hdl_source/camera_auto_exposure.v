// SC500CS 720p30: VTS=2000, exposure unit=half a line, max=2*VTS-10.
// Gain index 0..127 represents 1x..15.75x using documented 03/07/0f/1f ranges.
module camera_auto_exposure #(
    parameter EXP_MIN=16,EXP_MAX=3990,INITIAL_EXP=1995,INITIAL_GAIN=0,
    parameter GAIN_MAX=64,SETTLE_FRAMES=3
)(
    input wire I_clk,I_rst_n,I_cfg_done,I_ae_done,I_meter_valid,
    input wire [23:0] I_means, // RAW, RGB before AWB, RGB after AWB
    input wire [7:0] I_highlights,
    output reg O_req,output reg [15:0] O_exp,
    output reg [6:0] O_gain,
    output reg [23:0] O_means,output reg O_debug_valid
);
    reg [3:0] cooldown;
    reg [1:0] transaction; // request sent -> wait busy -> wait done
    reg [15:0] next_exp,step;
    reg [7:0] next_gain;
    // Meter the AWB output used by detection, not just the uncorrected RGB.
    wire [7:0] brightness=I_means[7:0];
    always @(*) begin
        next_exp=O_exp;next_gain={1'b0,O_gain};step=O_exp>>2;
        if(step<16) step=16;
        if(brightness>64 || I_highlights>8) begin
            if(O_gain!=0) next_gain=(O_gain<8)?0:O_gain-8;
            else if(O_exp>EXP_MIN) next_exp=(O_exp<=EXP_MIN+step)?EXP_MIN:O_exp-step;
        end else if(brightness<40 && I_highlights<4) begin
            if(O_exp<EXP_MAX) next_exp=(O_exp+step>EXP_MAX)?EXP_MAX:O_exp+step;
            else if(O_gain<GAIN_MAX) next_gain=(O_gain+8>GAIN_MAX)?GAIN_MAX:O_gain+8;
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_req<=0;O_exp<=INITIAL_EXP;O_gain<=INITIAL_GAIN;O_means<=0;
            O_debug_valid<=0;cooldown<=3;transaction<=0;
        end else begin
            O_req<=0;O_debug_valid<=I_meter_valid;
            if(transaction==1 && !I_ae_done) transaction<=2;
            else if(transaction==2 && I_ae_done) transaction<=0;
            if(I_meter_valid) begin
                O_means<=I_means;
                if(cooldown!=0) cooldown<=cooldown-1'b1;
                else if(I_cfg_done && I_ae_done && transaction==0 &&
                    (next_exp!=O_exp || next_gain[6:0]!=O_gain)) begin
                    O_exp<=next_exp;O_gain<=next_gain[6:0];O_req<=1;
                    transaction<=1;cooldown<=SETTLE_FRAMES;
                end
            end
        end
    end
endmodule
