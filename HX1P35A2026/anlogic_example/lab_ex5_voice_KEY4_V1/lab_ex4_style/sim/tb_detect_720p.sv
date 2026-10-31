`timescale 1ns/1ps
module tb_detect_720p;
    localparam HT=1650,VT=750,FRAME=HT*VT,LAT=2*HT+23;
    reg clk=0,rst_n=0;reg [30:0] pixel=0;
    wire [30:0] gp,sp;
    wire [1:0] status;wire [2:0] count;wire [319:0] objects;wire [15:0] fid;
    wire ov,oh,od;wire [23:0] rgb;
    integer i,j,x,y,f,xx,yy,m,checked=0,frames_checked=0,box_pixels=0;
    reg [23:0] color,expected_color;
    reg [327:0] expected[0:24];
    reg [79:0] a,b;
    reg box_expected;
    always #5 clk=~clk;
    video_detect detector(.I_clk(clk),.I_rst_n(rst_n),.I_pixel(pixel),.O_status(status),.O_count(count),.O_objects(objects),.O_frame_id(fid));
    base_gamma gamma0(.I_clk(clk),.I_rst_n(rst_n),.I_pixel(pixel),.O_pixel(gp));
    video_style style(.I_clk(clk),.I_rst_n(rst_n),.I_pixel(gp),.O_pixel(sp));
    hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.DETECT_ENABLE(1)) mixer(.I_clk(clk),.I_rst_n(rst_n),
        .I_video_vsync(sp[24]),.I_video_hsync(sp[25]),.I_video_de(sp[26]),.I_video_user(sp[27]),.I_video_last(sp[28]),
        .I_debug_status(4'hf),.I_mode(sp[30:29]),.I_camera_debug(47'd0),
        .I_detect_status(status),.I_detect_count(count),.I_detect_objects(objects),.O_video_rd_en(),.I_video_rd_data(sp[23:0]),
        .O_hdmi_vsync(ov),.O_hdmi_hsync(oh),.O_hdmi_de(od),.O_hdmi_data(rgb));
    function [23:0] source;
        input integer x,y;
        integer dx,dy;
        begin
            source=24'h202020;
            // 40x40 low-resolution circle at (80,60).
            dx=2*(x/4-80)-39;dy=2*(y/4-60)-39;
            if(x/4>=80 && x/4<120 && y/4>=60 && y/4<100 && dx*dx+dy*dy<=1600)source=24'hff0000;
            // 40x40 triangle at (200,60), independent of its green color.
            dx=x/4-200;dy=y/4-60;
            if(dx>=0 && dx<40 && dy>=0 && dy<40 && dx>=(40-(dy+1))/2 && dx<(40-(dy+1))/2+dy+1)source=24'h00ff00;
        end
    endfunction
    function [7:0] gamma80;
        input integer v;
        begin gamma80=$rtoi(255.0*((v/255.0)**0.80)+0.5);end
    endfunction
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        for(i=0;i<5*FRAME+LAT+8;i=i+1)begin
            @(negedge clk);x=i%HT;y=(i/HT)%VT;f=i/FRAME;
            color=(f<3)?source(x,y):24'h202020;
            m=(f==4)?0:3;
            pixel={2'(m),1'(x==1279 && y<720),1'(x==0 && y==0),1'(x<1280 && y<720),1'(x>=1390 && x<1430),1'(y>=725 && y<730),color};
            if(i>=5*FRAME)pixel=0;
            @(posedge clk);#1;j=i-LAT;
            if(j>=FRAME && j<5*FRAME)begin
                x=j%HT;y=(j/HT)%VT;f=j/FRAME;
                if(od!==(x<1280 && y<720) || oh!==(x>=1390 && x<1430) || ov!==(y>=725 && y<730))$fatal(1,"detect HDMI timing x=%0d y=%0d",x,y);
                if(x==0 && y==0)begin
                    if(f==2 || f==3)begin
                        if(mixer.detect_status!=1 || mixer.detect_count!=2)$fatal(1,"result atomic commit frame %0d status=%0d count=%0d",f,mixer.detect_status,mixer.detect_count);
                        a=mixer.detect_objects[79:0];b=mixer.detect_objects[159:80];
                        if(a[43:42]!=1 || a[45:44]!=1 || b[43:42]!=2 || b[45:44]!=2)$fatal(1,"full 720p shape/color mismatch %h %h",a,b);
                    end
                    frames_checked=frames_checked+1;
                end
                // Exhaustively check video and box edges below fixed OSDs.
                if(x<1280 && y>=180 && y<640)begin
                    color=(f<3)?source(x,y):24'h202020;
                    expected_color={gamma80(color[23:16]),gamma80(color[15:8]),gamma80(color[7:0])};
                    box_expected=0;
                    if(f==2 || f==3)begin
                        if(((x>=320 && x<=479 && y>=240 && y<=399) && (x<322 || x>477 || y<242 || y>397)))begin expected_color=24'hff4040;box_expected=1;end
                        if(((x>=800 && x<=959 && y>=240 && y<=399) && (x<802 || x>957 || y<242 || y>397)))begin expected_color=24'h40ff60;box_expected=1;end
                    end
                    if(rgb!==expected_color)$fatal(1,"detect overlay x=%0d y=%0d f=%0d got=%h want=%h",x,y,f,rgb,expected_color);
                    if(box_expected)box_pixels=box_pixels+1;
                    checked=checked+1;
                end
            end
        end
        if(checked!=4*1280*460 || box_pixels==0 || frames_checked!=4)$fatal(1,"coverage missing");
        $display(" PASS: tb_detect_720p real geometry/frame-latched two targets/KEY1 suppression RGB=%0d box_pixels=%0d",checked,box_pixels);$finish;
    end
endmodule
