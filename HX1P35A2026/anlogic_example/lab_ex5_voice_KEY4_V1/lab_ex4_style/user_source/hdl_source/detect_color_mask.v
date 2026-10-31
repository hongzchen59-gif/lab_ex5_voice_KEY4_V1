// Gamma-before-OSD RGB input. 4x4 categorical vote; banks never stall video.
module detect_color_mask #(
    parameter integer WIDTH=1280, HEIGHT=720,
    parameter integer V_MIN=48, CHROMA_MIN=24, ADVANTAGE=16
)(
    input wire I_clk,I_rst_n, input wire [30:0] I_pixel,
    output reg O_start, output reg O_complete, output reg O_read_bank,
    output reg [15:0] O_frame_id,
    input wire [15:0] I_read_addr, output wire [1:0] O_read_data
);
    localparam DW=WIDTH/4, DH=HEIGHT/4;
    reg [1:0] bank0 [0:DW*DH-1];
    reg [1:0] bank1 [0:DW*DH-1];
    reg [14:0] partial [0:DW-1];
    reg [14:0] partial_q;
    reg [1:0] read0,read1;
    reg write_bank,started,complete,bad;
    reg [10:0] x;
    reg [9:0] y;
    reg [15:0] cell_addr;
    reg [2:0] hr,hg,hb;
    wire sof=I_pixel[27],de=I_pixel[26],eol=I_pixel[28];
    wire [10:0] px=sof?11'd0:x;
    wire [9:0] py=sof?10'd0:y;
    wire [7:0] r=I_pixel[23:16],g=I_pixel[15:8],b=I_pixel[7:0];
    wire [7:0] mx=(r>g)?((r>b)?r:b):((g>b)?g:b);
    wire [7:0] mn=(r<g)?((r<b)?r:b):((g<b)?g:b);
    wire chroma=(mx>=V_MIN) && ({1'b0,mx}-{1'b0,mn}>=CHROMA_MIN);
    wire red=chroma && {1'b0,r}>={1'b0,g}+ADVANTAGE && {1'b0,r}>={1'b0,b}+ADVANTAGE;
    wire green=chroma && {1'b0,g}>={1'b0,r}+ADVANTAGE && {1'b0,g}>={1'b0,b}+ADVANTAGE;
    wire blue=chroma && {1'b0,b}>={1'b0,r}+ADVANTAGE && {1'b0,b}>={1'b0,g}+ADVANTAGE;
    wire [4:0] sr=(py[1:0]==0?5'd0:partial_q[14:10])+{2'b0,hr}+red;
    wire [4:0] sg=(py[1:0]==0?5'd0:partial_q[9:5])+{2'b0,hg}+green;
    wire [4:0] sb=(py[1:0]==0?5'd0:partial_q[4:0])+{2'b0,hb}+blue;
    wire [1:0] voted=(sr>=8 && sr>sg && sr>sb)?2'd1:
                     (sg>=8 && sg>sr && sg>sb)?2'd2:
                     (sb>=8 && sb>sr && sb>sg)?2'd3:2'd0;
    // Synchronous reads and writes infer ERAM. No image-array reset.
    always @(posedge I_clk) begin
        read0<=bank0[I_read_addr];read1<=bank1[I_read_addr];
        if(de && px<WIDTH && py<HEIGHT) begin
            if(px[1:0]==0) partial_q<=partial[px[10:2]];
            if(px[1:0]==3) begin
                partial[px[10:2]]<={sr,sg,sb};
                if(py[1:0]==3 && started) begin
                    if(write_bank)bank1[cell_addr]<=voted;
                    else bank0[cell_addr]<=voted;
                end
            end
        end
    end
    assign O_read_data=O_read_bank?read1:read0;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_start<=0;O_complete<=0;O_read_bank<=0;O_frame_id<=0;
            write_bank<=1;started<=0;complete<=0;bad<=0;x<=0;y<=0;
            cell_addr<=0;hr<=0;hg<=0;hb<=0;
        end else begin
            O_start<=0;
            if(sof) begin
                O_start<=1;O_complete<=complete && !bad && started;
                O_read_bank<=write_bank;O_frame_id<=O_frame_id+1'b1;
                write_bank<=~write_bank;started<=1;complete<=0;
                bad<=!de;x<=de?1:0;y<=0;cell_addr<=0;
            end else if(de) begin
                if(eol) begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
            end
            if(de) begin
                if(px[1:0]==0)begin hr<=red;hg<=green;hb<=blue;end
                else begin hr<=hr+red;hg<=hg+green;hb<=hb+blue;end
                if(!sof && (!started || px>=WIDTH || py>=HEIGHT || eol!=(px==WIDTH-1))) bad<=1;
                if(px[1:0]==3 && py[1:0]==3) cell_addr<=cell_addr+1'b1;
                if(px==WIDTH-1 && py==HEIGHT-1 && eol && !bad &&
                   cell_addr==DW*DH-1)complete<=1;
            end
        end
    end
endmodule
