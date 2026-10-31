// INMP441: 32-bit slots, one-bit I2S delay, selected channel only.
// 50 MHz / (2 * 25 * 64) = 15625 samples/s. Clock never stops.
module voice_i2s_rx #(
    parameter HALF_DIV=25, parameter CHANNEL=0, parameter WARMUP=15000000
)(
    input wire clk, rst_n, sd,
    output reg sck, ws, output reg ready, valid,
    output reg signed [15:0] pcm
);
    reg [7:0] div_count;
    reg [5:0] bit_count;
    reg [23:0] shift;
    reg [24:0] warm_count;
    (* async_reg="true" *) reg [1:0] sd_sync;
    // Sample after the preceding falling-edge data launch. The synchronizer
    // delay is only 40 ns versus the 500 ns SCK half-period.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) sd_sync<=0; else sd_sync<={sd_sync[0],sd};
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            div_count<=0;bit_count<=0;sck<=0;ws<=0;shift<=0;
            warm_count<=0;ready<=0;valid<=0;pcm<=0;
        end else begin
            valid<=0;
            if(!ready) begin
                if(warm_count==WARMUP-1) ready<=1;
                else warm_count<=warm_count+1'b1;
            end
            if(div_count==HALF_DIV-1) begin
                div_count<=0;sck<=~sck;
                if(sck) begin
                    // WS changes on the falling edge BEFORE the slot's delay bit.
                    bit_count<=bit_count+1'b1;
                    ws<=(bit_count==31)?1'b1:((bit_count==63)?1'b0:ws);
                end else if(ws==CHANNEL && bit_count[4:0]>=1 && bit_count[4:0]<=24) begin
                    shift<={shift[22:0],sd_sync[1]};
                    if(bit_count[4:0]==24) begin
                        // Signed Q23 -> Q15, arithmetic truncation; no unsigned cast.
                        pcm<=shift[22:7];
                        if(ready) valid<=1;
                    end
                end
            end else div_count<=div_count+1'b1;
        end
    end
endmodule
