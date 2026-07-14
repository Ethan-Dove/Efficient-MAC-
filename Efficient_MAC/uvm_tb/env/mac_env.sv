// Top-level UVM environment: wires agent → scoreboard and agent → coverage.
class mac_env extends uvm_env;
    `uvm_component_utils(mac_env)

    mac_agent      agent;
    mac_scoreboard scoreboard;
    mac_coverage   coverage;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = mac_agent::type_id::create("agent", this);
        scoreboard = mac_scoreboard::type_id::create("scoreboard", this);
        coverage   = mac_coverage::type_id::create("coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        agent.mon.ap.connect(scoreboard.analysis_export);
        agent.mon.ap.connect(coverage.analysis_export);
    endfunction
endclass
