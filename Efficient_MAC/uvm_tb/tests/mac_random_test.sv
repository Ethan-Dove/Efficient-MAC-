// Random test: 1000 constrained-random transactions.
// Run with: ./simv +UVM_TESTNAME=mac_random_test +ntb_random_seed_automatic
// Each run uses a different seed — failing seeds are printed for reproduction.
class mac_random_test extends mac_base_test;
    `uvm_component_utils(mac_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        mac_random_seq seq;
        phase.raise_objection(this);
        seq = mac_random_seq::type_id::create("seq");
        seq.num_transactions = 1000;
        seq.start(env.agent.seqr);
        #200;
        phase.drop_objection(this);
    endtask
endclass
