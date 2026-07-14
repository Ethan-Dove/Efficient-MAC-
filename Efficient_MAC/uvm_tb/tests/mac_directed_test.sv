// Directed test: runs all original tb_mac_top.v vectors through the UVM
// scoreboard. Must pass before random tests are meaningful.
// Run with: ./simv +UVM_TESTNAME=mac_directed_test
class mac_directed_test extends mac_base_test;
    `uvm_component_utils(mac_directed_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        mac_directed_seq seq;
        phase.raise_objection(this);
        seq = mac_directed_seq::type_id::create("seq");
        seq.start(env.agent.seqr);
        // Flush pipeline before dropping objection
        #200;
        phase.drop_objection(this);
    endtask
endclass
