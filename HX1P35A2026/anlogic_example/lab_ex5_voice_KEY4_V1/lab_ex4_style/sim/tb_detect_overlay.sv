`timescale 1ns/1ps
module tb_detect_overlay;
    reg clk=0,rst_n=0;
    always #0.5 clk=~clk;
    reg [11:0] x=0,y=0;reg de=1,en=1;reg [1:0] status=1;reg [2:0] count=1;reg [319:0] objects=0;
    wire text_hit,box_hit;wire [23:0] text_color,box_color;
    reg [255:0] line;integer i,j,hits=0;reg expected_box;
    detect_overlay dut(.I_clk(1'b0),.I_rst_n(1'b1),.I_x(x),.I_y(y),.I_de(de),.I_enable(en),.I_status(status),.I_count(count),.I_objects(objects),
        .O_text_hit(text_hit),.O_text_color(text_color),.O_box_hit(box_hit),.O_box_color(box_color));
    wire text_p,box_p;wire [23:0] tc_p,bc_p;
    detect_overlay #(.PIPELINED(1)) pipe(.I_clk(clk),.I_rst_n(rst_n),.I_x(x),.I_y(y),.I_de(de),.I_enable(en),.I_status(status),.I_count(count),.I_objects(objects),
        .O_text_hit(text_p),.O_text_color(tc_p),.O_box_hit(box_p),.O_box_color(bc_p));
    reg text_ref,box_ref;reg [23:0] tc_ref,bc_ref;
    always @(posedge clk)begin
        text_ref=text_hit;box_ref=box_hit;tc_ref=text_color;bc_ref=box_color;
        #0.1;
        if(rst_n && {text_p,box_p,tc_p,bc_p}!=={text_ref,box_ref,tc_ref,bc_ref})$fatal(1,"overlay pipeline equivalence");
    end
    task check_line;
        input [11:0] yy;input [255:0] chars;
        begin
            y=yy;
            for(i=0;i<32;i=i+1)begin
                x=704+16*i;#1;
                if(dut.ch!==chars[255-i*8 -:8])$fatal(1,"OSD col %0d got=%c expected=%c",i,dut.ch,chars[255-i*8 -:8]);
            end
        end
    endtask
    initial begin
        #2;rst_n=1;
        objects[79:0]={2'd0,16'h0361,16'h0381,2'd1,2'd1,10'd399,10'd320,11'd479,11'd320};
        check_line(16,"DETECT  COUNT:1   RUN           ");
        check_line(40,"1 RED   CIRCLE   X:0381 Y:0361  ");
        status=2;check_line(16,"DETECT  COUNT:--  OVERFLOW      ");
        status=0;check_line(16,"DETECT  COUNT:--  WAIT          ");
        status=1;count=5;check_line(16,"DETECT  COUNT:4+  RUN           ");
        for(j=315;j<405;j=j+1)for(i=315;i<485;i=i+1)begin
            x=i;y=j;#1;
            expected_box=(i>=320 && i<=479 && j>=320 && j<=399 && (i<322 || i>477 || j<322 || j>397));
            if(box_hit!==expected_box || (box_hit && box_color!=24'hff4040))$fatal(1,"box geometry");
            if(box_hit)hits=hits+1;
        end
        en=0;x=320;y=320;#1;if(box_hit || text_hit)$fatal(1,"mode disable");
        en=1;status=2;#1;if(box_hit)$fatal(1,"overflow must suppress boxes");
        $display(" PASS: tb_detect_overlay text/color/shape/BCD/status/4+/exact two-pixel boxes=%0d",hits);$finish;
    end
endmodule
