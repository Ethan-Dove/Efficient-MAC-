// Base sequence — all MAC sequences extend this.
class mac_base_seq extends uvm_sequence #(mac_seq_item);
    `uvm_object_utils(mac_base_seq)
    function new(string name = "mac_base_seq");
        super.new(name);
    endfunction
    // Subclasses override body().
    virtual task body(); endtask
endclass
