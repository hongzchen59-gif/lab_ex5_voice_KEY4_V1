// Acknowledged mailbox: source payload is held until the destination captures it.
module meter_cdc #(parameter WIDTH=24, BUNDLED_DIRECT=0)(
    input wire I_src_clk,I_src_rst_n,I_valid,
    input wire [WIDTH-1:0] I_data,
    input wire I_dst_clk,I_dst_rst_n,
    output reg O_valid, output reg [WIDTH-1:0] O_data
);
    reg [WIDTH-1:0] held;
    wire [WIDTH-1:0] payload_at_dst=held;
    reg req,ack;
    (* async_reg="true" *) reg ack_1,ack_2,req_1,req_2;
    reg [WIDTH-1:0] data_1,data_2;
    always @(posedge I_src_clk or negedge I_src_rst_n) begin
        if(!I_src_rst_n) begin held<=0;req<=0;ack_1<=0;ack_2<=0;end
        else begin
            ack_1<=ack;ack_2<=ack_1;
            if(I_valid && req==ack_2) begin held<=I_data;req<=~req;end
        end
    end
    always @(posedge I_dst_clk or negedge I_dst_rst_n) begin
        if(!I_dst_rst_n) begin req_1<=0;req_2<=0;data_1<=0;data_2<=0;ack<=0;O_valid<=0;O_data<=0;end
        else begin
            req_1<=req;req_2<=req_1;data_1<=payload_at_dst;data_2<=data_1;O_valid<=0;
            // Motion links sample the held bundle after the synchronized REQ.
            // Their payload has >=2 destination clocks to settle (20ns bound).
            // Parallel DATA/REQ pipelines can return a stale bundle on skew.
            if(req_2!=ack) begin O_data<=BUNDLED_DIRECT?payload_at_dst:data_2;O_valid<=1;ack<=req_2;end
        end
    end
endmodule
