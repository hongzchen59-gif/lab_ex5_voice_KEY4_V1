module motion_overlay(
    input wire I_clk,I_rst_n,I_update,input wire [11:0] I_x,I_y,
    input wire I_de,I_enable,input wire [2:0] I_status,
    input wire [13:0] I_cells,input wire [15:0] I_events,input wire [41:0] I_bbox,
    output reg O_text_hit,O_box_hit,output reg [23:0] O_text_color,O_box_color
);
    reg update_d;reg [4:0] left;reg [15:0] bin_c,bin_e;
    reg [19:0] work_c,work_e,bcd_c,bcd_e;
    reg [19:0] adjust_c,adjust_e;integer k;
    always @(*) begin
        adjust_c=work_c;adjust_e=work_e;
        for(k=0;k<5;k=k+1) begin
            if(work_c[k*4+:4]>=5) adjust_c[k*4+:4]=work_c[k*4+:4]+4'd3;
            if(work_e[k*4+:4]>=5) adjust_e[k*4+:4]=work_e[k*4+:4]+4'd3;
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin update_d<=0;left<=0;bin_c<=0;bin_e<=0;work_c<=0;work_e<=0;bcd_c<=0;bcd_e<=0;end
        else begin
            update_d<=I_update;
            if(update_d) begin bin_c<={2'b0,I_cells};bin_e<=I_events;work_c<=0;work_e<=0;left<=16;end
            else if(left!=0) begin
                work_c<={adjust_c[18:0],bin_c[15]};work_e<={adjust_e[18:0],bin_e[15]};
                bin_c<=bin_c<<1;bin_e<=bin_e<<1;left<=left-1'b1;
                if(left==1) begin bcd_c<={adjust_c[18:0],bin_c[15]};bcd_e<={adjust_e[18:0],bin_e[15]};end
            end
        end
    end
    wire [11:0] lx=I_x-12'd704,ly=I_y-12'd152;
    wire [4:0] column=lx[8:4];
    reg [7:0] ch;reg [95:0] name;reg text_area;reg [3:0] font_row;
    reg box_hit;
    always @(*) begin
        case(I_status)
            1:name="WARMUP      ";2:name="IDLE        ";3:name="ACTIVE      ";4:name="PAUSE       ";
            5:name="SCENE CHANGE";6:name="FRAME ERR   ";default:name="WAIT        ";
        endcase
        ch=" ";font_row=0;text_area=0;
        if(ly<16) begin
            text_area=1;font_row=ly[3:0];
            case(column)0:ch="M";1:ch="O";2:ch="T";3:ch="I";4:ch="O";5:ch="N";
                default:if(column>=7 && column<19) ch=name[95-(column-7)*8-:8];endcase
        end else if(ly>=24 && ly<40) begin
            text_area=1;font_row=ly-24;
            case(column)
                0:ch="C";1:ch="E";2:ch="L";3:ch="L";4:ch="S";5:ch=":";
                12:ch="E";13:ch="V";14:ch="E";15:ch="N";16:ch="T";17:ch="S";18:ch=":";
                default:begin
                    if(column>=6 && column<=10)ch=8'h30+bcd_c[19-(column-6)*4-:4];
                    if(column>=19 && column<=23)ch=8'h30+bcd_e[19-(column-19)*4-:4];
                end
            endcase
        end
        box_hit=I_enable && I_de && I_status==3 && I_x>=I_bbox[10:0] && I_x<=I_bbox[21:11] &&
            I_y>=I_bbox[31:22] && I_y<=I_bbox[41:32] &&
            (I_x<I_bbox[10:0]+2 || I_x+2>I_bbox[21:11] || I_y<I_bbox[31:22]+2 || I_y+2>I_bbox[41:32]) && !(I_x[3]^I_y[3]);
    end
    reg [7:0] char_d;reg [3:0] row_d,col_d;reg allowed_d;
    wire [15:0] bits;
    osd_char_lib font(.I_char(char_d),.I_row(row_d),.O_row_bits(bits));
    // Same single lookup pipeline as detect_overlay PIPELINED=1.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin char_d<=0;row_d<=0;col_d<=0;allowed_d<=0;O_box_hit<=0;end
        else begin
            char_d<=ch;row_d<=font_row;col_d<=lx[3:0];
            allowed_d<=I_enable && I_de && I_x>=704 && I_x<1216 && I_y>=152 && text_area;
            O_box_hit<=box_hit;
        end
    end
    always @(*) begin
        O_text_hit=allowed_d && bits[15-col_d];O_text_color=24'hffff00;O_box_color=24'hffff00;
    end
endmodule
