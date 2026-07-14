// UVM agent: bundles sequencer, driver, and monitor for mac_top.
class mac_agent extends uvm_agent;
    `uvm_component_utils(mac_agent)

    uvm_sequencer #(mac_seq_item) seqr;
    mac_driver                    drv;
    mac_monitor                   mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        seqr = uvm_sequencer #(mac_seq_item)::type_id::create("seqr", this);
        drv  = mac_driver::type_id::create("drv", this);
        mon  = mac_monitor::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
endclass
