// Independent display storage: eight grayscale pixels per 72-bit UltraRAM word.
// One clock domain, synchronous read, elastic output, whole-frame publication.
module display_framebuffer_640x480 #(
    parameter integer INPUT_WIDTH = 640, INPUT_HEIGHT = 480,
    parameter integer X_OFFSET = 320, Y_OFFSET = 120,
    parameter MEMORY_STYLE = "ultra"
) (
    input logic aclk, aresetn,
    input logic [7:0] s_axis_tdata,
    input logic s_axis_tvalid, s_axis_tuser, s_axis_tlast,
    input logic [31:0] s_frame_id,
    output logic s_axis_tready,
    input logic [11:0] fetch_x, fetch_y,
    input logic fetch_valid, fetch_sof, fetch_eol,
    output logic fetch_ready,
    output logic [11:0] pixel_x, pixel_y,
    output logic [23:0] m_axis_tdata,
    output logic m_axis_tvalid, m_axis_tuser, m_axis_tlast,
    input logic m_axis_tready,
    output logic [31:0] display_frame_id,
    output logic display_frame_valid, frame_ready,
    output logic [31:0] protocol_error_count, display_drop_count
);
    localparam integer PIXELS = INPUT_WIDTH * INPUT_HEIGHT;
    localparam integer WORDS = (PIXELS + 7) / 8;
    (* ram_style = MEMORY_STYLE *) logic [71:0] bank0 [0:WORDS-1];
    (* ram_style = MEMORY_STYLE *) logic [71:0] bank1 [0:WORDS-1];
    logic [71:0] read0, read1;
    logic [71:0] write_word;
    wire [71:0] completed_word = {1'b0,s_axis_tdata,write_word[62:0]};
    logic write_bank, display_bank, pending, have_display, writing, discarding;
    integer write_x, write_y, write_index;
    logic [31:0] write_frame_id, pending_frame_id;
    logic bank_q, visible_q, have_q;
    logic [2:0] lane_q;
    integer current_x, current_y, current_index, read_index;
    logic good_beat, commit_display, read_bank;

    // A blocked HDMI sink must never apply backpressure to the algorithm path.
    // While a complete bank waits for publication, discard incoming whole frames.
    assign s_axis_tready = aresetn;
    assign fetch_ready = aresetn && (!m_axis_tvalid || m_axis_tready);
    assign frame_ready = pending;
    assign display_frame_valid = have_display;
    always_comb begin
        current_x = s_axis_tuser ? 0 : write_x;
        current_y = s_axis_tuser ? 0 : write_y;
        current_index = s_axis_tuser ? 0 : write_index;
        good_beat = !pending && (s_axis_tuser || writing) &&
                    (s_axis_tlast == (current_x == INPUT_WIDTH-1));
        commit_display = fetch_valid && fetch_ready && fetch_sof && pending;
        read_bank = commit_display ? write_bank : display_bank;
        read_index = 0;
        if ((fetch_x >= X_OFFSET) && (fetch_x < X_OFFSET+INPUT_WIDTH) &&
            (fetch_y >= Y_OFFSET) && (fetch_y < Y_OFFSET+INPUT_HEIGHT))
            read_index = (fetch_y-Y_OFFSET)*INPUT_WIDTH + (fetch_x-X_OFFSET);
        m_axis_tdata = 0;
        if (visible_q && have_q) begin
            if (bank_q) m_axis_tdata = {3{read1[lane_q*9 +: 8]}};
            else        m_axis_tdata = {3{read0[lane_q*9 +: 8]}};
        end
    end

    // Accumulate eight pixels, then write one complete native UltraRAM word.
    // The supported frame dimensions must contain a multiple of eight pixels.
    always_ff @(posedge aclk) begin
        if (aresetn && s_axis_tvalid && s_axis_tready && good_beat && current_index%8 == 7) begin
            if (write_bank) bank1[current_index/8] <= completed_word;
            else           bank0[current_index/8] <= completed_word;
        end
        if (fetch_valid && fetch_ready) begin
            read0 <= bank0[read_index/8];
            read1 <= bank1[read_index/8];
        end
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            write_bank <= 1; display_bank <= 0;
            pending <= 0; have_display <= 0; writing <= 0; discarding <= 0;
            write_x <= 0; write_y <= 0; write_index <= 0;
            write_frame_id <= 0; pending_frame_id <= 0;
            display_frame_id <= 0; protocol_error_count <= 0; display_drop_count <= 0;
            m_axis_tvalid <= 0; m_axis_tuser <= 0; m_axis_tlast <= 0;
            pixel_x <= 0; pixel_y <= 0;
            bank_q <= 0; visible_q <= 0; have_q <= 0; lane_q <= 0;
            write_word <= 0;
        end else begin
            if (fetch_ready) begin
                m_axis_tvalid <= fetch_valid;
                if (fetch_valid) begin
                    m_axis_tuser <= fetch_sof; m_axis_tlast <= fetch_eol;
                    pixel_x <= fetch_x; pixel_y <= fetch_y;
                    bank_q <= read_bank; have_q <= have_display || commit_display;
                    lane_q <= read_index % 8;
                    visible_q <= (fetch_x >= X_OFFSET) && (fetch_x < X_OFFSET+INPUT_WIDTH) &&
                                 (fetch_y >= Y_OFFSET) && (fetch_y < Y_OFFSET+INPUT_HEIGHT);
                end
            end
            if (commit_display) begin
                display_bank <= write_bank; write_bank <= ~write_bank;
                display_frame_id <= pending_frame_id;
                have_display <= 1; pending <= 0;
            end
            if (s_axis_tvalid && s_axis_tready && pending && s_axis_tuser) begin
                display_drop_count <= display_drop_count + 1;
                discarding <= 1;
            end
            if (s_axis_tvalid && s_axis_tready && !pending && (s_axis_tuser || !discarding)) begin
                if ((s_axis_tuser && writing) || !good_beat)
                    protocol_error_count <= protocol_error_count + 1;
                if (!good_beat) begin
                    writing <= 0; discarding <= 1;
                    write_x <= 0; write_y <= 0; write_index <= 0;
                end else begin
                    discarding <= 0;
                    write_word[(current_index%8)*9 +: 9] <= {1'b0,s_axis_tdata};
                    if (s_axis_tuser) write_frame_id <= s_frame_id;
                    writing <= 1; write_index <= current_index + 1;
                    if (current_x == INPUT_WIDTH-1) begin
                        write_x <= 0; write_y <= current_y + 1;
                    end else begin
                        write_x <= current_x + 1; write_y <= current_y;
                    end
                    if (current_index == PIXELS-1) begin
                        pending <= 1; writing <= 0;
                        pending_frame_id <= s_axis_tuser ? s_frame_id : write_frame_id;
                        write_x <= 0; write_y <= 0; write_index <= 0;
                    end
                end
            end
        end
    end
endmodule
