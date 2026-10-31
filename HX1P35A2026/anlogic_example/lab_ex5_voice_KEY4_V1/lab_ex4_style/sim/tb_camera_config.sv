`timescale 1ns/1ps
module tb_camera_config;
    reg clk=0,rst=0,req=0;reg [15:0] exp=3990,ag=80;
    always #5 clk=~clk;
    tri1 sda;wire scl,cfg,done;
    // Emulate the camera ACK during the master's ninth bit only.
    assign sda=(dut.u_i2c.IIC_S==3)?1'b0:1'bz;
    uicfgcs500_720p #(.CLK_DIV(3)) dut(.I_clk(clk),.I_rst_n(rst),.I_ae_req(req),
        .I_ae(exp),.I_ag(ag),.O_cam_scl(scl),.IO_cam_sda(sda),.O_cfg_done(cfg),.O_ae_cfg_done(done));
    integer count=0,updates=0,i;
    reg [15:0] addr;reg [7:0] value;
    reg [15:0] vts=0,shutter=0,gainregs=0;
    reg [7:0] manual_mode=0;
    reg [15:0] expected_gain;
    // Observe transactions actually accepted by the supplied I2C controller.
    always @(posedge dut.iic_busy) begin
        #1;
        addr={dut.wr_data[15:8],dut.wr_data[23:16]};value=dut.wr_data[31:24];
        if(dut.wr_data[7:0]!==8'h6c) $fatal(1,"Wrong I2C address");
        if(!cfg) count=count+1;else updates=updates+1;
        case(addr)
            16'h320e:vts[15:8]=value;16'h320f:vts[7:0]=value;
            16'h3e00:shutter[15:12]=value[3:0];
            16'h3e01:shutter[11:4]=value;
            16'h3e02:shutter[3:0]=value[7:4];
            16'h3e08:gainregs[15:8]=value;16'h3e09:gainregs[7:0]=value;
            16'h3e03:manual_mode=value;
            16'h0100:if(value==1 && (vts!=2000 || shutter!=1995 || gainregs!=16'h0320 || manual_mode!=8'h0b))
                $fatal(1,"Bad startup VTS=%0d exp=%0d gain=%04h manual=%02h",vts,shutter,gainregs,manual_mode);
        endcase
    end
    reg [6:0] gain_index=0;wire [15:0] mapped_gain;
    SC500GainTbl gainmap(.I_clk(clk),.I_rstn(rst),.I(gain_index),.O(mapped_gain));
    initial begin
        repeat(8) @(negedge clk);rst=1;
        for(i=0;i<128;i=i+1) begin
            @(negedge clk);gain_index=i;@(posedge clk);#1;
            case(i/32) 0:expected_gain=16'h0320;1:expected_gain=16'h0720;
                2:expected_gain=16'h0f20;3:expected_gain=16'h1f20;endcase
            expected_gain=expected_gain+(i%32);
            if(mapped_gain!==expected_gain) $fatal(1,"Gain map %0d %04h",i,mapped_gain);
        end
        wait(cfg && done);@(negedge clk);
        if(count!=117) $fatal(1,"Init transaction count %0d",count);
        exp=16;ag=143;req=1;@(negedge clk);req=0;
        wait(!done);wait(done);@(negedge clk);
        if(updates!=5 || shutter!=16 || gainregs!=16'h1f3f) $fatal(1,"Runtime AE writes %0d exp=%0d gain=%04h",updates,shutter,gainregs);
        $display("CONFIG PASS: 117 init writes, VTS=2000 exp=1995 gain=1x manual mode, all 128 gains, five runtime AE writes");$finish;
    end
    initial begin #20000000;$fatal(1,"Camera config timeout");end
endmodule
