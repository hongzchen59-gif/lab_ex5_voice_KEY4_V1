`timescale 1ns/1ps
module tb_vivid_status;
    reg clk=0,rst=0;always #6.667 clk=~clk;
    reg [30:0] pixel=0;wire [30:0] styled;wire ready;
    video_style #(.H_TOTAL(24)) dut(.I_clk(clk),.I_rst_n(rst),.I_pixel(pixel),.O_pixel(styled),.O_effect_ready(ready));
    hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.EFFECT_STATUS_ENABLE(1)) mixer(
        .I_clk(clk),.I_rst_n(rst),.I_mode(styled[30:29]),.I_effect_ready(ready),
        .I_video_vsync(styled[24]),.I_video_hsync(styled[25]),.I_video_de(styled[26]),
        .I_video_user(styled[27]),.I_video_last(styled[28]),.I_video_rd_data(styled[23:0]),
        .I_debug_status(4'd0),.I_camera_debug(47'd0),.I_detect_status(2'd0),.I_detect_count(3'd0),.I_detect_objects(320'd0),
        .O_frame_sof(),.O_video_rd_en(),.O_hdmi_vsync(),.O_hdmi_hsync(),.O_hdmi_de(),.O_hdmi_data());
    task frame;
        integer x,y;
        begin
            for(y=0;y<13;y=y+1)for(x=0;x<24;x=x+1)begin
                @(negedge clk);pixel={2'd2,1'(x==15&&y<8),1'(x==0&&y==0),1'(x<16&&y<8),2'b00,24'hb43c3c};
            end
        end
    endtask
    initial begin
        repeat(6)@(negedge clk);rst=1;
        repeat(5)frame;
        if(!ready || mixer.mode_text!=="TOON R4 ")$fatal(1,"Effect evidence did not arm");
        // Fault injection: either window's bypass must remove the ready label.
        force dut.u_preserve.valid=6'b0;repeat(3)frame;
        if(ready || mixer.mode_text!=="FX WAIT ")$fatal(1,"Smoothing bypass falsely ready");
        release dut.u_preserve.valid;repeat(4)frame;
        if(!ready)$fatal(1,"Smoothing recovery");
        force dut.u_style.valid_pipe=6'b0;repeat(3)frame;
        if(ready || mixer.mode_text!=="FX WAIT ")$fatal(1,"Color bypass falsely ready");
        release dut.u_style.valid_pipe;repeat(4)frame;
        if(!ready || mixer.mode_text!=="TOON R4 ")$fatal(1,"Color recovery");
        $display("VIVID STATUS PASS: both real windows active, version OSD, independent bypass fault injection and recovery");$finish;
    end
    initial begin #200000;$fatal(1,"Effect status timeout");end
endmodule
