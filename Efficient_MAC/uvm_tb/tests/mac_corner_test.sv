// Corner-case test: FP special values, sign combinations, near-overflow.
// Run with: ./simv +UVM_TESTNAME=mac_corner_test
class mac_corner_test extends mac_base_test;
    `uvm_component_utils(mac_corner_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        mac_corner_seq seq;
        phase.raise_objection(this);
        seq = mac_corner_seq::type_id::create("seq");
        seq.start(env.agent.seqr);
        #200;
        phase.drop_objection(this);
    endtask
endclass
