// Single-outstanding AHB word transactions -> 50 MHz local request port.
// AHB address and write data belong to DIFFERENT phases. Payload stays stable
// until the synchronized response; each transfer receives exactly one response.
module voice_ahb_bridge(
    input wire hclk, hreset_n, input wire [1:0] htrans,
    input wire hwrite, input wire [30:0] haddr, input wire [2:0] hsize,
    input wire [31:0] hwdata, output wire hready,
    output wire [1:0] hresp, output reg [31:0] hrdata,
    input wire clk, reset_n,
    output reg req, output reg wr, output reg [19:0] addr,
    output reg [31:0] wdata, input wire [31:0] rdata,
    input wire error
);
    localparam IDLE=0,DATA=1,WAIT_ACK=2,RESP=3,ERR_FIRST=4,ERR_LAST=5;
    reg [2:0] state;
    reg [19:0] addr_hold;
    reg wr_hold,bad_hold,req_toggle,ack_toggle;
    reg [31:0] data_hold,response_hold;
    reg response_error;
    (* async_reg="true" *) reg [1:0] ack_sync,req_sync;
    reg seen;
    reg local_pending;
    assign hready=(state==IDLE || state==RESP || state==ERR_LAST);
    assign hresp=(state==ERR_FIRST || state==ERR_LAST)?2'b01:2'b00;
    always @(posedge hclk or negedge hreset_n) begin
        if(!hreset_n) begin
            state<=IDLE;addr_hold<=0;wr_hold<=0;bad_hold<=0;
            req_toggle<=0;data_hold<=0;ack_sync<=0;hrdata<=0;
        end else begin
            ack_sync<={ack_sync[0],ack_toggle};
            case(state)
                IDLE,RESP,ERR_LAST: begin
                    if(htrans[1]) begin
                        addr_hold<=haddr[19:0];wr_hold<=hwrite;
                        bad_hold<=haddr[30:20]!=0 || haddr[1:0]!=0 || hsize!=3'd2;
                        state<=DATA;
                    end else state<=IDLE;
                end
                DATA: begin
                    if(bad_hold) state<=ERR_FIRST;
                    else begin data_hold<=hwdata;req_toggle<=~req_toggle;state<=WAIT_ACK;end
                end
                WAIT_ACK: if(ack_sync[1]==req_toggle) begin
                    hrdata<=response_hold;state<=response_error?ERR_FIRST:RESP;
                end
                ERR_FIRST: state<=ERR_LAST;
                default: state<=IDLE;
            endcase
        end
    end
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            req_sync<=0;seen<=0;ack_toggle<=0;req<=0;wr<=0;addr<=0;wdata<=0;
            local_pending<=0;response_hold<=0;response_error<=0;
        end else begin
            req_sync<={req_sync[0],req_toggle};req<=0;
            if(req_sync[1]!=seen && !local_pending && !req) begin
                addr<=addr_hold;wr<=wr_hold;wdata<=data_hold;
                req<=1;local_pending<=1;seen<=req_sync[1];
            end else if(local_pending && !req) begin
                response_hold<=rdata;response_error<=error;
                ack_toggle<=seen;local_pending<=0;
            end
        end
    end
endmodule
