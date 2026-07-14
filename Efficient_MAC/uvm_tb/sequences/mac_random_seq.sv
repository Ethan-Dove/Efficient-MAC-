// Constrained-random sequence. VCS generates num_transactions random
// transactions satisfying mac_seq_item constraints automatically —
// no manual test vectors required.
class mac_random_seq extends mac_base_seq;
    `uvm_object_utils(mac_random_seq)

    int unsigned num_transactions = 1000;

    function new(string name = "mac_random_seq");
        super.new(name);
    endfunction

    task body();
        mac_seq_item tx;
        repeat (num_transactions) begin
            tx = mac_seq_item::type_id::create("tx");
            start_item(tx);
            if (!tx.randomize())
                `uvm_fatal("RAND_FAIL", "mac_seq_item randomization failed")
            finish_item(tx);
        end
    endtask
endclass
