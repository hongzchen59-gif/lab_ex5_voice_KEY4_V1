// Four passive, active-low switches. Each input has a 2-FF synchronizer.
// A key held during reset does not generate an action until released/repressed.
// Its debounced level still asserts STOP/DISABLE while physically held.
module voice_button_inputs #(parameter CLK_HZ=50000000,DEBOUNCE_MS=20)(
    input wire clk,rst_n,input wire [3:0] keys_n,
    output reg [3:0] level_n,output reg [3:0] press
);
    (* async_reg="true" *) reg [3:0] meta,sync;
    reg [3:0] sampled,armed;
    reg [15:0] divider;
    reg [4:0] count[0:3];
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            meta<=4'hf;sync<=4'hf;sampled<=4'hf;level_n<=4'hf;
            armed<=0;divider<=0;press<=0;
            for(i=0;i<4;i=i+1)count[i]<=0;
        end else begin
            meta<=keys_n;sync<=meta;press<=0;
            if(divider==CLK_HZ/1000-1)begin
                divider<=0;sampled<=sync;
                for(i=0;i<4;i=i+1)begin
                    if(sync[i]!=sampled[i])count[i]<=0;
                    else if((!armed[i] && sync[i] && level_n[i]) || sync[i]!=level_n[i])begin
                        if(count[i]==DEBOUNCE_MS-1)begin
                            count[i]<=0;level_n[i]<=sync[i];
                            if(sync[i])armed[i]<=1;
                            else if(armed[i])press[i]<=1;
                        end else count[i]<=count[i]+1'b1;
                    end else count[i]<=0;
                end
            end else divider<=divider+1'b1;
        end
    end
endmodule
