# frozen_string_literal: true

# File: netlist_utils.rb
require 'fileutils'

module NetlistUtils
    CACHE_FILE ||= 'database.cache'
    DB_TEXT_FILE = 'cellDescriptorsTable_updated.txt'
    @unknown_gates = Set.new
    @matched_gates = Hash.new(0)
    
    def self.save_gates_descriptor(file_path = 'processed_gates.txt')
      existing_lines = !File.exist?(file_path) ? Set.new :
                        File.readlines(file_path, chomp: true).map(&:strip).to_set
      
      lines_to_write = "********************************************************** \n\n"
      lines_to_write += "Found #{@matched_gates.size} diferent gates and #{@unknown_gates.size} unknown:\n\n"
      
      @matched_gates.each do |descriptor, count|
        lines_to_write += "#{descriptor} -> seen #{count} times \n"
      end
      lines_to_write += "Unknwown gates: \n"
      lines_to_write += @unknown_gates.to_a.join("\n")
      lines_to_write += "********************************************************** \n"
      
      FileUtils.mkdir_p(File.dirname(file_path))
      File.open(file_path, 'a') do |file|
        file.puts lines_to_write
      end
    end
    
    def self.auto_label_vdd_gnd(cell, m1_lyr, lbl_lyr, lbl_datatype, rail_height = 0.24, rail_spacing = 2000, first_rail_is_vdd = true)
      layout_obj = cell.layout
      dbu = layout_obj.dbu
      
      # 1. Clear previous labels
      lbl_layer_idx = layout_obj.layer(lbl_lyr, lbl_datatype)
      db_shapes = cell.shapes(lbl_layer_idx)
      db_shapes.clear
      
      tolerance = (rail_height / dbu).to_i
      total_labels = 0
      m1_lyr.data.each do |poly|
        bbox = poly.bbox
        rail_distance = (bbox.center.y + tolerance) % rail_spacing
        if rail_distance <= tolerance*2
          rail_row = (bbox.center.y + tolerance) / rail_spacing
          signal_name = (rail_row.even? == first_rail_is_vdd) ? "VDD" : "GND"
          text_obj = RBA::Text.new(signal_name, bbox.center.x, rail_row*rail_spacing)
          db_shapes.insert(text_obj)
          total_labels += 1
        end
      end
      
      layout_obj.update
      puts "INFO [NetlistUtils]: Successfully injected #{total_labels} labels."
      return total_labels
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
            # Search (Groups of 3 integers)
            connex_vectors = block_text.scan(/\(\s*(\d+(?:\s+\d+){2})\s*\)/).map do |match|
                match[0].split.map(&:to_i)
            end

            # Search (Groups of 5 integers)
            term_vectors = block_text.scan(/\(\s*(\d+(?:\s+\d+){4})\s*\)/).map do |match|
                match[0].split.map(&:to_i)
            end

            if connex_vectors.any?
                connex_signatures << connex_vectors.sort
            elsif term_vectors.any?
                term_signatures << term_vectors.sort
            else
                topology_name = name
            end
        end

        connex_signatures.sort!
        term_signatures = term_signatures.empty? ? nil : term_signatures.sort

        [topology_name, net_signature, connex_signatures, term_signatures]
    end

    def self.load_database(force_load = true)
        if !force_load && File.exist?(CACHE_FILE) && File.mtime(CACHE_FILE) >= File.mtime(DB_TEXT_FILE)
            return File.open(CACHE_FILE, 'rb') { |f| Marshal.load(f) }
        end
        puts 'Cache missing or outdated. Parsing raw database text file...'
        database = parse_text_database(DB_TEXT_FILE)
        File.open(CACHE_FILE, 'wb') { |f| Marshal.dump(database, f) }
        database
    end

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
        # Extract the index ("4 4")
        unless runtime_str =~ /"(\d+\s+\d+)"\s*:/
            puts 'Error: Invalid descriptor format (missing grid category identifier).'
            return nil
        end
        category = ::Regexp.last_match(1)

        # Generate the signature for the unknown runtime object
        _, net_signature, connex_signatures, term_signatures = extract_signature(runtime_str)
        runtime_key = [net_signature, connex_signatures, term_sign                # 2. Get Terminals and Net Connections
atures]

        if database[category]&.key?(runtime_key)
          @matched_gates[database[category][runtime_key]] += 1
          return database[category][runtime_key]
        end
                
        @unknown_gates.add(runtime_str)
        return 'Unknown/Unmapped Topology'
    end
  
    # Used to test klayout lvs objects
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
                device_class.terminal_definitions.each do |term_def|
                    net = device.net_for_terminal(term_def.id)
                    net_name = net ? net.name : 'unconnected'
                    puts "  Terminal: #{term_def.name} : #  -> Net: #{net_name} : #{net}"
                end
            end
        end
    end
    
end
