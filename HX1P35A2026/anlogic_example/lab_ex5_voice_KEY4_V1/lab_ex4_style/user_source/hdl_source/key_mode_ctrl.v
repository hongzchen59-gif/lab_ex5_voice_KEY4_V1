// Four active-low board keys, sampled entirely in the pixel clock domain.
module key_mode_ctrl #(
    parameter integer DEBOUNCE_CYCLES = 1500000
)(
    input wire I_clk, input wire I_rst_n,
    input wire [3:0] I_key_n,
    input wire I_vblank,
    output reg [1:0] O_mode
);
    function integer clog2;
        input integer n;
        integer v;
        begin v=n-1; clog2=0; while(v>0) begin clog2=clog2+1; v=v>>1; end
            if(clog2<1) clog2=1;
        end
    endfunction
    localparam integer CW=clog2(DEBOUNCE_CYCLES);
    (* async_reg = "true" *) reg [3:0] key_meta, key_sync;
    reg [3:0] stable_n;
    reg [CW-1:0] stable_count;
    reg [1:0] pending;
    reg armed;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin key_meta<=4'hf; key_sync<=4'hf; end
        else begin key_meta<=I_key_n; key_sync<=key_meta; end
    end
    // Debounce the complete key vector. A chord must be released completely
    // before a new selection can occur, even if its members settle separately.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            stable_n<=4'hf; stable_count<=0; pending<=0; O_mode<=0; armed<=1;
        end else begin
            if(I_vblank) O_mode<=pending;
            if(key_sync==stable_n) stable_count<=0;
            else if(stable_count==DEBOUNCE_CYCLES-1) begin
                stable_count<=0; stable_n<=key_sync;
                if(key_sync==4'hf) armed<=1;
                else if(armed) begin
                    armed<=0;
                    case(key_sync)
                        4'b1110: pending<=2'd0;
                        4'b1101: pending<=2'd1;
                        4'b1011: pending<=2'd2;
                        4'b0111: pending<=2'd3;
                        default: pending<=pending;
                    endcase
                end
            end else stable_count<=stable_count+1'b1;
        end
    end
endmodule
