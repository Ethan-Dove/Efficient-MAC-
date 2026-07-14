// Observes mac_top inputs and outputs, handles pipeline latency, and sends
// completed transactions to the scoreboard via the analysis port.
//
// Pipeline timing (from empirical TB analysis):
//   Driver NBA at posedge N → DUT captures at posedge N+1.
//   FIX: OUT_fx valid at posedge N+3  → monitor sees at cycle N+3 (+#1).
//   FLP: OUT_fp valid at posedge N+4  → monitor sees at cycle N+4 (+#1).
//   Therefore from monitor sample cycle M: FIX_LAT=3, FLP_LAT=4.
class mac_monitor extends uvm_monitor;
    `uvm_component_utils(mac_monitor)

    virtual mac_if vif;
    uvm_analysis_port #(mac_seq_item) ap;

    // In-flight queues: separate per mode, each entry tagged with sample cycle.
    mac_seq_item fix_q[$], flp_q[$];
    int          fix_cyc[$], flp_cyc[$];
    int          cyc;

    localparam int FIX_LAT = 3;
    localparam int FLP_LAT = 4;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db #(virtual mac_if)::get(this, "", "mac_vif", vif))
            `uvm_fatal("NO_VIF", "mac_monitor: virtual interface not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        // Wait for reset deassertion
        @(posedge vif.clk iff (vif.rst_n === 1'b1));
        cyc = 0;

        forever begin
            @(posedge vif.clk);
            #1; // settle after posedge — see timing note in header
            cyc++;

            // Sample input and push to the mode-appropriate queue
            begin
                mac_seq_item tx = mac_seq_item::type_id::create("mon_tx");
                tx.float_mode  = vif.float;
                tx.A           = vif.A;
                tx.B           = vif.B;
                tx.accumulator = vif.accumulator;
                if (!tx.float_mode) begin
                    fix_q.push_back(tx); fix_cyc.push_back(cyc);
                end else begin
                    flp_q.push_back(tx); flp_cyc.push_back(cyc);
                end
            end

            // FIX: OUT_fx at cycle cyc = result of input sampled at cyc - FIX_LAT
            if (fix_cyc.size() > 0 && (cyc - fix_cyc[0]) >= FIX_LAT) begin
                mac_seq_item done = fix_q.pop_front();
                void'(fix_cyc.pop_front());
                done.out_fx = vif.OUT_fx;
                ap.write(done);
            end

            // FLP: OUT_fp at cycle cyc = result of input sampled at cyc - FLP_LAT
            if (flp_cyc.size() > 0 && (cyc - flp_cyc[0]) >= FLP_LAT) begin
                mac_seq_item done = flp_q.pop_front();
                void'(flp_cyc.pop_front());
                done.out_fp = vif.OUT_fp;
                ap.write(done);
            end
        end
    endtask
endclass
