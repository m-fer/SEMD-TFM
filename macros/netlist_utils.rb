# File: netlist_utils.rb
module NetlistUtils

  def self.print_info(nl)
    return puts "Netlist is null!" if nl.nil?
    puts " #circuits: #{nl.each_circuit.count}"
    puts " #top_circuit: #{nl.top_circuit_count}"
    
    nl.each_circuit do |circuit|
      puts "Circuit: #{circuit.name}"
      
      puts "#pins: #{circuit.each_pin.count}"
      puts "#subcircuits: #{circuit.each_subcircuit.count}"
      puts "#nets: #{circuit.each_net.count}"
      puts "#devices: #{circuit.each_device.count}"
    
      circuit.each_pin do |pin|
        puts "--- Pin found {name: #{pin.name}; id: #{pin.id}}---"
      end
      circuit.each_subcircuit do |subcircuit|
        puts "--- Subcircuit found {name: #{subcircuit.name}; id: #{subcircuit.id} }---"
      end
      
      circuit.each_net do |net|
        puts "--- Net found: 
        { name = #{net.name},
          cluster_id = #{net.cluster_id},
          expanded_name = #{net.expanded_name},
          pin_count = #{net.pin_count},
          terminal_count = #{net.terminal_count},
          subcircuit_pin_count = #{net.subcircuit_pin_count},
          to_s = #{net.to_s},
          is_floating = #{net.is_floating?},
          is_internal = #{net.is_internal?},
          is_passive = #{net.is_passive?} }
         ---"
      end
      # Iterate through all Devices within this circuit
      circuit.each_device do |device|
        device_class = device.device_class
        puts "--- Device found: #{device.name} ---"
        
        # Get Device Parameters (e.g., W, L, Area)
        #device_class.parameter_definitions.each do |param_def|
        #  val = device.parameter(param_def.id)
        #  puts "  Param: #{param_def.name} = #{val}"
        #end
        
        # 2. Get Terminals and Net Connections
        device_class.terminal_definitions.each do |term_def|
          net = device.net_for_terminal(term_def.id)
          net_name = net ? net.name : "unconnected"
          puts "  Terminal: #{term_def.name} : #  -> Net: #{net_name} : #{net}"
        end
      end

    end
  end #print_info
  
  
  if __FILE__ == $0
    puts "Initializing SPICE Mock Test..."
  
    spice_data = <<-SPICE
      .subckt TOP
        device NMOS $1 (S=$1,G=$3,D=$9) (L=22.7368706394,W=113.489,AS=6635.333128,AD=2121.58674,PS=339.849,PD=150.079)
        device NMOS $2 (S=$9,G=$4,D=$2) (L=21.345343957,W=114.6495,AS=2121.58674,AD=6943.866188,PS=150.079,PD=342.434)
        device PMOS $3 (S=$5,G=$3,D=$1) (L=20.8698165221,W=177.798,AS=10103.737577,AD=5911.9923335,PS=466.062,PD=239.743)
        device PMOS $4 (S=$1,G=$4,D=$5) (L=25.6770118891,W=175.455,AS=5911.9923335,AD=11407.592793,PS=239.743,PD=480.952)
      .ends
    SPICE
  
    test_nl = RBA::Netlist.new
    
    
    begin
      test_nl.read("~/extracted_output.sp", RBA::NetlistSpiceReader.new)
      
      NetlistUtils.print_info(test_nl)
    rescue => e
      puts "[SPICE Error] #{e.message}"
      puts e.backtrace # This is like a GDB backtrace
    end
  end # Tests
  
end #NetlistUtils
