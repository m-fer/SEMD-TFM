# frozen_string_literal: true

# File: netlist_utils.rb
module NetlistUtils
    CACHE_FILE = 'database.cache'
    DB_TEXT_FILE = 'cellDescriptorsTable_ordenado.txt'
    
    def self.auto_label_vdd_gnd(cell, m1_lyr, lbl_lyr, min_width_micron = 0.39, first_rail_is_vdd = true)
      min_rail_width_dbu = (min_width_micron / cell.layout.dbu).to_i
      rails = []
      m1_lyr.data.each do |polygon|
        bbox = polygon.bbox
        if bbox.height >= min_rail_width_dbu && bbox.width >= bbox.height
          rails << bbox
        end
      end
  
      # Sort the rails vertically from bottom to top
      rails.sort_by! { |box| box.center.y }
      
      puts "INFO [NetlistUtils]: Found #{rails.length} qualifying power rails."
  scratch_layer_idx = cell.layout.insert_layer(RBA::LayerInfo.new)
    scratch_shapes = cell.shapes(scratch_layer_idx)

    # Inject alternating labels into our temporary database container
    rails.each_with_index do |box, index|
      is_even_row = (index % 2 == 0)
      signal_name = is_even_row ? (first_rail_is_vdd ? "VDD" : "GND") : (first_rail_is_vdd ? "GND" : "VDD")
      
      text_obj = RBA::Text.new(signal_name, box.center.x, box.center.y)
      puts text_obj.to_s
      # Text objects fit perfectly inside an RBA::Shapes database collection
      scratch_shapes.insert(text_obj)
    end
    
    # FIX: Move the text labels into your live LVS label layer object using its native installer
    puts m1_lyr.data.insert(scratch_shapes)
    cell.layout.update
    # Clear out the scratch layer from the layout database to keep it clean
    # cell.layout.delete_layer(scratch_layer_idx)
    
    puts "INFO [NetlistUtils]: Successfully injected #{rails.length} labels into the label layer wrapper."
    return rails.length
    end

    def self.extract_signature(text_line)
        # 1. (6 integers) -> net_descriptor
        net_signature = text_line.scan(/\(\s*(\d+(?:\s+\d+){5})\s*\)/).map do |match|
            match[0].split.map(&:to_i)
        end.sort

        # 2. Extract all named block segments (term and connexion descriptor mixed together)
        raw_sections = text_line.scan(/"(\$?\w+)"\s*(.*?)(?=(?:"\$?\w+")|\z)/m)

        connex_signatures = []
        term_signatures = []
        topology_name = nil

        raw_sections.each do |name, block_text|
            # Harvest Pin Vectors (Exactly 3 integers)
            connex_vectors = block_text.scan(/\(\s*(\d+(?:\s+\d+){2})\s*\)/).map do |match|
                match[0].split.map(&:to_i)
            end

            # Harvest Terminal Vectors (Exactly 5 integers)
            term_vectors = block_text.scan(/\(\s*(\d+(?:\s+\d+){4})\s*\)/).map do |match|
                match[0].split.map(&:to_i)
            end

            if connex_vectors.any?
                connex_signatures << connex_vectors.sort
            elsif term_vectors.any?
                term_signatures << term_vectors.sort
            else
                # If it has no tracking vectors, it's the root macro name (e.g., "LF_NOR3I_X1")
                topology_name = name
            end
        end

        # Sort the outer lists to guarantee total order-independence
        connex_signatures.sort!
        term_signatures = term_signatures.empty? ? nil : term_signatures.sort

        [topology_name, net_signature, connex_signatures, term_signatures]
    end

    def self.load_database(force_load = false)
        # 1. Check if a pre-compiled binary cache already exists and is up to date
        if !force_load && File.exist?(CACHE_FILE) && File.mtime(CACHE_FILE) >= File.mtime(DB_TEXT_FILE)
            return File.open(CACHE_FILE, 'rb') { |f| Marshal.load(f) }
        end

        # 2. Cache is missing or outdated -> Parse the text file (Slow step, runs ONCE)
        puts 'Cache missing or outdated. Parsing raw database text file...'
        database = parse_text_database(DB_TEXT_FILE)

        # 3. Save the live Ruby Hash to disk as a binary dump for next time
        File.open(CACHE_FILE, 'wb') { |f| Marshal.dump(database, f) }

        database
    end

    # Your original text-parsing loop moved to a helper
    def self.parse_text_database(file_path)
        database = {}
        current_category = nil

        File.foreach(file_path) do |line|
            line = line.strip
            next if line.empty?

            if line =~ /"(\d+\s+\d+)"\s*:/
                current_category = ::Regexp.last_match(1)
                database[current_category] ||= {}
                next
            end

            if line.start_with?('((') && current_category
                topology_name, net_signature, connex_signatures, term_signatures = extract_signature(line)
                if topology_name && !net_signature.empty?
                    signature_key = [net_signature, connex_signatures, term_signatures]
                    database[current_category][signature_key] = topology_name
                    if topology_name == 'NAND2'
                        puts current_category
                        p signature_key
                    end
                end
            end
        end
        database
    end

    def self.identify_descriptor(runtime_str, database)
        # Extract the category context (e.g., "4 4")
        unless runtime_str =~ /"(\d+\s+\d+)"\s*:/
            puts 'Error: Invalid descriptor format (missing grid category identifier).'
            return nil
        end
        category = ::Regexp.last_match(1)

        # Generate the signature for the unknown runtime object
        _, net_signature, connex_signatures, term_signatures = extract_signature(runtime_str)
        runtime_key = [net_signature, connex_signatures, term_signatures]

        # Instant lookup inside our Hash of Hashes
        return database[category][runtime_key] if database[category]&.key?(runtime_key)

        'Unknown/Unmapped Topology'
    end

    def self.print_info(nl)
        return puts 'Netlist is null!' if nl.nil?

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
          to_s = #{net},
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
                # device_class.parameter_definitions.each do |param_def|
                #  val = device.parameter(param_def.id)
                #  puts "  Param: #{param_def.name} = #{val}"
                # end

                # 2. Get Terminals and Net Connections
                device_class.terminal_definitions.each do |term_def|
                    net = device.net_for_terminal(term_def.id)
                    net_name = net ? net.name : 'unconnected'
                    puts "  Terminal: #{term_def.name} : #  -> Net: #{net_name} : #{net}"
                end
            end
        end
    end

    if __FILE__ == $PROGRAM_NAME

        db = NetlistUtils.load_database(true)

        # test for nand2
        runtime_descriptor = '"4 4": (UnknownName (1 0 2 2 0 0)(2 1 1 0 2 1)(1 2 1 3 0 1))(("$3" ((2 1 11)(1 1 11)) ("$1" ((1 2 21)) ("$4" ((2 1 12)(1 1 10)))'
        matched_gate = NetlistUtils.identify_descriptor(runtime_descriptor, db)
        puts "Descriptor classified as: #{matched_gate}"

        # test for and2
        runtime_descriptor = '"6 5": (UnknownName (1 1 1 2 0 1)(1 3 2 3 2 0)(1 0 2 2 0 0)(2 1 1 0 2 1))(("$5" ((2 2 21)(1 0 0)) ("$1" ((2 2 23)(1 0 0)) ("$2" ((2 2 22)(1 0 0)))'
        matched_gate = NetlistUtils.identify_descriptor(runtime_descriptor, db)
        puts "Descriptor classified as: #{matched_gate}"

    end
end
