// Sequential candidate selection in the existing pixel domain. Geometry,
// distance and minimum comparison each receive a full clock period.
// Selection and committed result frame are passed to the independent axis controller.
module voice_target_select(
    input wire clk,rst_n,input wire [31:0] command,input wire command_toggle,
    output reg command_ack,
    input wire [1:0] status,input wire [2:0] count,
    input wire [319:0] objects,input wire [15:0] frame_id,
    output reg [31:0] xy,info,output reg [15:0] result_frame_id
);
    localparam IDLE=0,LOAD=1,GEOMETRY=2,DISTANCE=3,EVALUATE=4,COMMIT=5;
    localparam ASSOC_DISTANCE=128;
    (* async_reg="true" *) reg [1:0] req_sync;
    reg [2:0] state;
    reg [1:0] slot;
    reg [2:0] candidate_count;
    reg [7:0] operation,color,shape;
    reg [15:0] last_frame,epoch;
    reg [1:0] discard;
    reg lock_valid,had_selection,found,is_color,is_strict,size_ok;
    reg color_seen,chosen_continuation;
    reg [1:0] misses;
    reg [10:0] prev_x,chosen_x,cx;
    reg [9:0] prev_y,chosen_y,cy;
    reg [12:0] best_distance,distance;
    reg [79:0] object;
    reg [11:0] width;
    reg [10:0] height;
    reg [11:0] prev_width,chosen_width;
    reg [10:0] prev_height,chosen_height;
    wire square_ok=({4'd0,width}<<3)>=(({5'd0,height}<<3)-{5'd0,height}) &&
                   ({4'd0,width}<<3)<=(({5'd0,height}<<3)+{5'd0,height});
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            req_sync<=0;command_ack<=0;operation<=0;color<=0;shape<=0;
            last_frame<=0;epoch<=0;discard<=0;lock_valid<=0;misses<=0;
            prev_x<=0;prev_y<=0;xy<=0;info<=0;state<=IDLE;slot<=0;
            candidate_count<=0;had_selection<=0;found<=0;is_color<=0;is_strict<=0;size_ok<=0;
            color_seen<=0;chosen_continuation<=0;prev_width<=0;prev_height<=0;
            chosen_width<=0;chosen_height<=0;
            chosen_x<=0;chosen_y<=0;cx<=0;cy<=0;best_distance<=0;
            distance<=0;object<=0;width<=0;height<=0;result_frame_id<=0;
        end else begin
            req_sync<={req_sync[0],command_toggle};
            // A new command cancels any in-flight selection, even at COMMIT.
            if(req_sync[1]!=command_ack) begin
                command_ack<=req_sync[1];lock_valid<=0;misses<=0;xy<=0;
                epoch<=epoch+1'b1;discard<=2;last_frame<=frame_id;
                operation<=command[7:0];color<=command[15:8];shape<=command[23:16];
                info<={epoch+16'd1,2'd0,count,status,1'b0,command[7:0]};
                result_frame_id<=0;
                prev_x<=0;prev_y<=0;state<=IDLE;
            end else if(operation==1 && status!=1) begin
                // Never retain a coordinate when detection becomes invalid.
                lock_valid<=0;misses<=0;xy<=0;
                info<={epoch,2'd0,count,status,1'b0,operation};
                state<=IDLE;last_frame<=frame_id;
            end else if(operation==1 && frame_id!=last_frame) begin
                // Keep the last committed packet while scanning candidates.
                // Publish XY, validity and frame together at COMMIT, avoiding
                // a spurious target-loss pulse at the start of every frame.
                last_frame<=frame_id;state<=IDLE;
                if(discard!=0) discard<=discard-1'b1;
                else begin
                    candidate_count<=count;slot<=0;found<=0;color_seen<=0;
                    chosen_continuation<=0;
                    had_selection<=lock_valid;best_distance<=13'h1fff;
                    state<=LOAD;
                end
            end else case(state)
                LOAD: begin object<=objects[slot*80 +:80];state<=GEOMETRY;end
                GEOMETRY: begin
                    cx<=({1'b0,object[10:0]}+{1'b0,object[21:11]})>>1;
                    cy<=({1'b0,object[31:22]}+{1'b0,object[41:32]})>>1;
                    width<={1'b0,object[21:11]}-{1'b0,object[10:0]}+12'd1;
                    height<={1'b0,object[41:32]}-{1'b0,object[31:22]}+11'd1;
                    state<=DISTANCE;
                end
                DISTANCE: begin
                    distance<=(cx>=prev_x?cx-prev_x:prev_x-cx)+
                              (cy>=prev_y?cy-prev_y:prev_y-cy);
                    is_color<=slot<candidate_count && object[43:42]==color[1:0];
                    is_strict<=shape==4?(object[45:44]==3 && square_ok):({6'd0,object[45:44]}==shape);
                    size_ok<=({1'b0,width}<<1)>={1'b0,prev_width} &&
                        {1'b0,width}<=({1'b0,prev_width}<<1) &&
                        ({1'b0,height}<<1)>={1'b0,prev_height} &&
                        {1'b0,height}<=({1'b0,prev_height}<<1);
                    state<=EVALUATE;
                end
                EVALUATE: begin
                    if(is_color)color_seen<=1;
                    // Classify strictly to acquire. Once locked, associate the
                    // same-color component using bounded position/size changes;
                    // quantized distant shapes need not keep the same label.
                    if(is_color && (had_selection?(size_ok && distance<=ASSOC_DISTANCE):is_strict) &&
                        (!found || (had_selection && distance<best_distance))) begin
                        found<=1;chosen_x<=cx;chosen_y<=cy;best_distance<=distance;
                        chosen_width<=width;chosen_height<=height;
                        chosen_continuation<=!is_strict;
                    end
                    if(slot==3)state<=COMMIT;
                    else begin slot<=slot+1'b1;state<=LOAD;end
                end
                COMMIT: begin
                    result_frame_id<=last_frame;
                    if(found)begin
                        lock_valid<=1;misses<=0;
                        prev_x<=chosen_x;prev_y<=chosen_y;
                        prev_width<=chosen_width;prev_height<=chosen_height;
                        xy<={6'd0,chosen_y,5'd0,chosen_x};
                    end else begin
                        xy<=0;
                        // Misses never publish an old coordinate as valid.
                        // Retain association memory for at most two misses;
                        // the third requires a new strict-shape acquisition.
                        if(lock_valid && misses<2)misses<=misses+1'b1;
                        else begin lock_valid<=0;misses<=0;end
                    end
                    info<={epoch,(found && chosen_continuation),color_seen,candidate_count,status,found,operation};
                    state<=IDLE;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
