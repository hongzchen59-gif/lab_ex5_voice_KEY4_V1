`timescale 1ns/1ps
module tb_video_720p;
    localparam W=1280,H=720,HT=1650,VT=750,FRAME=HT*VT,LAT=2*HT+20;
    reg clk=0,rst_n=0;
    reg [30:0] pixel=0;
    wire [30:0] result;wire effect_ready;
    wire [30:0] gamma_pixel;
    base_gamma base(.I_clk(clk),.I_rst_n(rst_n),.I_pixel(pixel),.O_pixel(gamma_pixel));
    wire ov,oh,od;wire [23:0] orgb;
    reg [30:0] mixed_ref1=0,mixed_ref2=0,mixed_ref3=0;
    integer i,j,x,y,f,m,errors=0,checked=0,mixed_count=0;
    integer mx=0,my=0,labels=0,logo_ink=0,counter_ink=0,diagnostic_ink=0;
    reg [24:0] logo_reference[0:25599];
    reg [23:0] expected_rgb;
    reg [30:0] expected_pixel;
    always #6.667 clk=~clk;
    video_style dut(.I_clk(clk),.I_rst_n(rst_n),.I_pixel(gamma_pixel),.O_pixel(result),.O_effect_ready(effect_ready));
    hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.EFFECT_STATUS_ENABLE(1)) mixer(.I_clk(clk),.I_rst_n(rst_n),
        .I_video_vsync(result[24]),.I_video_hsync(result[25]),.I_video_de(result[26]),
        .I_video_user(result[27]),.I_video_last(result[28]),.I_debug_status(4'hf),
        .I_detect_status(2'd0),.I_detect_count(3'd0),.I_detect_objects(320'd0),.I_mode(result[30:29]),.I_effect_ready(effect_ready),.I_camera_debug({24'h204020,16'd3990,7'd64}),.O_video_rd_en(),.I_video_rd_data(result[23:0]),
        .O_hdmi_vsync(ov),.O_hdmi_hsync(oh),.O_hdmi_de(od),.O_hdmi_data(orgb));
    function [7:0] gamma80;
        input integer v;
        begin gamma80=$rtoi(255.0*((v/255.0)**0.80)+0.5);end
    endfunction
    function [23:0] natural;
        input [23:0] p;
        integer r,g,b,y,target,hi,lo,cr,cg,cb,cy,lift;
        begin
            r=p[23:16];g=p[15:8];b=p[7:0];y=(r+2*g+b)/4;
            target=y<16?y:((y/16+1)*16);if(target>255)target=255;
            hi=r>g?r:g;if(b>hi)hi=b;lo=r<g?r:g;if(b<lo)lo=b;
            cr=r;cg=g;cb=b;
            if(y>=32 && y<=208 && hi-lo>=32)begin cr=r+((r-y)>>>3);cg=g+((g-y)>>>3);cb=b+((b-y)>>>3);end
            cy=(cr+2*cg+cb)/4;
            if(!(lo<=8 && hi>=224) && cr>=0 && cr<=255 && cg>=0 && cg<=255 && cb>=0 && cb<=255 && cy<=target &&
                cr+target-cy<=255 && cg+target-cy<=255 && cb+target-cy<=255)begin
                lift=target-cy;r=cr;g=cg;b=cb;
            end else begin
                lift=target-y;if(lift>255-hi)lift=255-hi;
                if(lo<=8 && hi>=224)lift=0;
            end
            natural={8'(r+lift),8'(g+lift),8'(b+lift)};
        end
    endfunction
    function [7:0] gamma85;
        input integer v;
        begin gamma85=$rtoi(255.0*((v/255.0)**0.85)+0.5);end
    endfunction
    // Check output geometry, transparency outside overlays, and visible overlays.
    always @(posedge clk) begin
        mixed_ref1<=result;mixed_ref2<=mixed_ref1;mixed_ref3<=mixed_ref2;
        #1;
        if(rst_n && mixed_ref3[26]) begin
            if(!od || {oh,ov} !== mixed_ref3[25:24]) $fatal(1,"OSD metadata misaligned");
            if(mixed_ref3[27]) begin mx=0;my=0;end
            if(mx<160 && my<160) begin
                if(orgb !== (logo_reference[my*160+mx][24]?logo_reference[my*160+mx][23:0]:mixed_ref3[23:0]))
                    $fatal(1,"Logo lookup misaligned x=%0d y=%0d",mx,my);
                if(orgb!=mixed_ref3[23:0]) logo_ink=logo_ink+1;
            end else if(mx>=375 && mx<575 && my>=120 && my<144) begin
                if(orgb!=mixed_ref3[23:0]) counter_ink=counter_ink+1;
            end else if(mx>=16 && mx<144 && my>=H-32 && my<H-16) begin
                if(orgb==24'h00e6ff) labels=labels+1;
            end else if(mx>=16 && mx<656 && my>=H-56 && my<H-40) begin
                if(orgb==24'h80ff80) diagnostic_ink=diagnostic_ink+1;
            end else if(orgb !== mixed_ref3[23:0])
                $fatal(1,"OSD changed background x=%0d y=%0d got=%06h ref=%06h",mx,my,orgb,mixed_ref3[23:0]);
            mixed_count=mixed_count+1;
            if(mx==W-1) begin mx=0;my=my+1;end else mx=mx+1;
        end else if(rst_n && mixed_count>0 && od) $fatal(1,"OSD extra DE");
    end
    initial begin
        $readmemh("logo_reference.hex",logo_reference);
        repeat(5) @(negedge clk);rst_n=1;
        // One startup frame + EDGE/CARTOON/ENHANCE/ORIGINAL complete frames.
        for(i=0;i<5*FRAME+LAT;i=i+1) begin
            @(negedge clk);
            x=i%HT;y=(i/HT)%VT;f=i/FRAME;m=f%4;
            pixel={2'(m),1'(x==W-1 && y<H),1'(x==0 && y==0),
                1'(x<W && y<H),1'(x>=1390 && x<1430),1'(y>=725 && y<730),24'h4080c0};
            if(i>=5*FRAME) pixel=0;
            @(posedge clk);#1;
            j=i-LAT;
            if(j>=FRAME && j<5*FRAME) begin
                x=j%HT;y=(j/HT)%VT;m=(j/FRAME)%4;
                expected_rgb={gamma80(64),gamma80(128),gamma80(192)};
                if(x<W && y<H) begin
                    if(m==1) expected_rgb=0;
                    else if(x>0 && x<W-1 && y>0 && y<H-1) begin
                        if(m==2) expected_rgb=natural({gamma80(64),gamma80(128),gamma80(192)});
                    end
                end else expected_rgb=0;
                expected_pixel={2'(m),1'(x==W-1 && y<H),1'(x==0 && y==0),
                    1'(x<W && y<H),1'(x>=1390 && x<1430),1'(y>=725 && y<730),expected_rgb};
                checked=checked+1;
                if(result !== expected_pixel) begin
                    if(errors<8) $display("720P mismatch x=%0d y=%0d mode=%0d got=%08h exp=%08h",x,y,m,result,expected_pixel);
                    errors=errors+1;
                end
            end
        end
        @(negedge clk);pixel=0;
        repeat(6) @(negedge clk);
        if(errors || mixed_count!=4*W*H || labels==0 || logo_ink==0 || counter_ink==0 || diagnostic_ink==0)
            $fatal(1,"720P FAIL errors=%0d HDMI pixels=%0d labels=%0d logo=%0d counter=%0d",errors,mixed_count,labels,logo_ink,counter_ink);
        $display("720P PASS: %0d raster clocks, %0d HDMI pixels, four full modes; label=%0d logo=%0d counter=%0d pixels; diagnostic=%0d",checked,mixed_count,labels,logo_ink,counter_ink,diagnostic_ink);
        $finish;
    end
    initial begin #100000000;$fatal(1,"720P timeout");end
endmodule
