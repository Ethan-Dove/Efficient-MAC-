// Drives stimulus onto mac_top via the interface.
// Uses NBA assignments after @(posedge clk) so DUT registers values
// at the subsequent posedge — matching the original tb_mac_top timing model.
class mac_driver extends uvm_driver #(mac_seq_item);
    `uvm_component_utils(mac_driver)

    virtual mac_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual mac_if)::get(this, "", "mac_vif", vif))
            `uvm_fatal("NO_VIF", "mac_driver: virtual interface not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        mac_seq_item tx;
        apply_reset();
        forever begin
            seq_item_port.get_next_item(tx);
            drive_item(tx);
            seq_item_port.item_done();
        end
    endtask

    task apply_reset();
        vif.rst_n       <= 1'b0;
        vif.float       <= 1'b0;
        vif.A           <= 16'd0;
        vif.B           <= 16'd0;
        vif.accumulator <= 32'd0;
        repeat (4) @(posedge vif.clk);
        vif.rst_n <= 1'b1;
        @(posedge vif.clk);
    endtask

    task drive_item(mac_seq_item tx);
        @(posedge vif.clk);
        vif.float       <= tx.float_mode;
        vif.A           <= tx.A;
        vif.B           <= tx.B;
        vif.accumulator <= tx.accumulator;
    endtask
endclass
