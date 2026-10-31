`timescale 1ns/1ps
module tb_voice_target_lock;
    reg clk=0,rst_n=0,toggle=0;
    always #5 clk=~clk;
    reg [31:0] command=0;
    reg [1:0] status=1;
    reg [2:0] count=1;
    reg [319:0] objects=0;
    reg [15:0] frame=0;
    wire ack;
    wire [31:0] xy,info;
    wire [15:0] result_frame;
    reg [79:0] far_box;
    voice_target_select dut(.clk(clk),.rst_n(rst_n),.command(command),.command_toggle(toggle),
        .command_ack(ack),.status(status),.count(count),.objects(objects),.frame_id(frame),
        .xy(xy),.info(info),.result_frame_id(result_frame));
    task box(input integer x0,x1,y0,y1,input [1:0] color,shape);
        begin objects=0;objects[10:0]=x0;objects[21:11]=x1;
            objects[31:22]=y0;objects[41:32]=y1;objects[43:42]=color;objects[45:44]=shape;end
    endtask
    task tick_frame;
        begin @(negedge clk);frame=frame+1'b1;repeat(25)@(negedge clk);end
    endtask
    task select(input [31:0] c);
        begin @(negedge clk);command=c;toggle=~toggle;repeat(6)@(negedge clk);
            tick_frame();tick_frame();end
    endtask
    task valid_at(input integer x,y,input bit continued);
        begin
            if(!info[8] || xy!={16'(y),16'(x)} || info[15]!=continued || result_frame!=frame)
                $fatal(1,"lock result XY=%h info=%h expected x=%0d y=%0d continued=%0d",xy,info,x,y,continued);
            if(info[10:9]!=1 || info[13:11]!=count || !info[14])$fatal(1,"detector diagnostic bits");
        end
    endtask
    initial begin
        #30;rst_n=1;
        box(100,179,100,179,1,0);select(32'h00010101);tick_frame();
        if(info[8] || !info[14])$fatal(1,"UNKNOWN must not acquire a red circle");
        objects[45:44]=1;tick_frame();valid_at(139,139,0);
        box(300,379,300,379,1,1);far_box=objects[79:0];
        box(110,189,110,189,1,0);objects[159:80]=objects[79:0];objects[79:0]=far_box;
        count=2;tick_frame();valid_at(149,149,1);count=1;
        box(114,193,114,193,1,3);tick_frame();valid_at(153,153,1);
        objects[43:42]=3;tick_frame();
        if(info[8] || xy!=0 || info[14])$fatal(1,"wrong color must stop tracking");
        objects[43:42]=1;objects[45:44]=0;tick_frame();valid_at(153,153,1);
        box(1,397,1,397,1,0);tick_frame();
        if(info[8])$fatal(1,"large size jump must not associate");
        box(114,193,114,193,1,0);tick_frame();valid_at(153,153,1);
        count=0;tick_frame();tick_frame();tick_frame();
        if(info[8] || xy!=0)$fatal(1,"empty results retained old target");
        count=1;tick_frame();if(info[8])$fatal(1,"lost lock reacquired UNKNOWN");
        objects[45:44]=1;tick_frame();valid_at(153,153,0);
        box(900,979,500,579,1,1);tick_frame();
        if(info[8])$fatal(1,"large position jump must stop tracking");
        tick_frame();tick_frame();tick_frame();valid_at(939,539,0);
        box(200,279,200,299,3,3);select(32'h00040301);tick_frame();
        if(info[8])$fatal(1,"non-square rectangle must not acquire square");
        box(200,279,200,279,3,3);tick_frame();valid_at(239,239,0);
        box(204,283,204,283,3,0);tick_frame();valid_at(243,243,1);
        status=2;repeat(3)@(negedge clk);
        if(info[8] || xy!=0 || info[10:9]!=2)$fatal(1,"detector failure must clear lock");
        status=1;tick_frame();if(info[8])$fatal(1,"failure retained UNKNOWN lock");
        objects[45:44]=3;tick_frame();valid_at(243,243,0);
        select(2);if(info[8] || xy!=0 || info[7:0]!=2)$fatal(1,"STOP must clear lock");
        $display("VOICE TARGET LOCK PASS: strict acquisition, same-color class drift, bounded size/position, brief misses, loss/reacquisition, detector failure, STOP and diagnostics");
        $finish;
    end
    initial begin #100000;$fatal(1,"target lock test timeout");end
endmodule
