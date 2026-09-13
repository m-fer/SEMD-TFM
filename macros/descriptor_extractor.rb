# frozen_string_literal: true

# File: descriptor_extractor.rb
module DescriptorExtractor
    IS_VALID_NET ||= ->(net) { !(net.nil? || %w[VDD GND].include?(net.expanded_name)) }

    def self.get_global_io_nets(circ)
        io_net_list = Set.new
        circ.each_net do |net|
            gate_found = false
            sd_pmos_found = false
            sd_nmos_found = false
            net.each_terminal do |term|
                dev_class = term.device_class
                if term.terminal_def.name == 'G'
                    gate_found = true
                elsif %w[S D].include?(term.terminal_def.name)
                    sd_nmos_found |= dev_class.name == 'NMOS'
                    sd_pmos_found |= dev_class.name == 'PMOS'
                else
                    next # We don't process bulk
                end
                break if gate_found && (sd_pmos_found || sd_nmos_found)
            end
            # input if its only connected to gates
            input = gate_found && !(sd_pmos_found || sd_nmos_found)

            # output if its only connected to sd
            output = !gate_found && sd_pmos_found && sd_nmos_found
            io_net_list << net.expanded_name if input || output
        end
        io_net_list
    end

    # returns for each net: (Name (eqnets, pmos, nmos, sd, g, io))
    def self.get_net_descriptor(circuit, io_netlist)
        net_analysis = Hash.new { |h, k| h[k] = { pmos: 0, nmos: 0, sd: 0, g: 0, io: 0 } }

        circuit.each_net do |net|
            next unless IS_VALID_NET.call(net)
            
            net_analysis[net][:io] += 1 if io_netlist.include?(net.expanded_name)
            net.each_terminal do |term|
                if term.terminal_def.name == 'G'
                    net_analysis[net][:g] += 1
                elsif %w[S D].include?(term.terminal_def.name)
                    net_analysis[net][:sd] += 1
                else
                    next # We don't process bulk
                end

                net_analysis[net][:nmos] += 1 if term.device_class.name == 'NMOS'
                net_analysis[net][:pmos] += 1 if term.device_class.name == 'PMOS'
            end
        end

        unique_nets = Hash.new(0)

        net_analysis.each_value do |signature|
            unique_nets[signature] += 1
        end

        net_descriptor = ''

        unique_nets.each do |sig, count|
            net_descriptor += "(#{count} " \
                              "#{sig[:pmos]} " \
                              "#{sig[:nmos]} " \
                              "#{sig[:sd]} " \
                              "#{sig[:g]} " \
                              "#{sig[:io]}) "
        end
        net_descriptor = net_descriptor.chop
        "(\"UnknownName\" #{net_descriptor}) "
    end

    def self.get_connection_descriptor(circuit, io_netlist, net_count)
        net_connection_descriptor = '('
        descriptor_tracker = Hash.new { |h, k| h[k] = [] }

        io_netlist.each do |current_io_net_name|
            # current_io_net = circuit.net_by_name(current_io_net_name)
            current_io_net = circuit.each_net.find { |n| n.expanded_name == current_io_net_name }
            next unless IS_VALID_NET.call(current_io_net)

            net_connection_descriptor += "(\"#{current_io_net.expanded_name}\" ("
            round_descriptor = ''
            current_nets_list = { current_io_net.expanded_name => current_io_net }
            visited = { current_io_net.expanded_name => current_io_net }
            current_reached_io_net = {}
            discovered_net_list = {}
            round, score = 0
            while visited.size < net_count && round < 10
                score = 0
                current_reached_io_net.clear
                discovered_net_list.clear
                current_nets_list.each_value do |current_net|
                    current_net.each_terminal do |term|
                        # Ignore the Bulk connection (Terminal ID 3)
                        next if term.terminal_id == 3

                        (0...term.device.device_class.terminal_definitions.size).each do |term_id|
                            next_net = term.device.net_for_terminal(term_id)
                            next if !IS_VALID_NET.call(next_net) || visited.key?(next_net.expanded_name)

                            discovered_net_list[next_net.expanded_name] = next_net
                            next unless io_netlist.include?(next_net.expanded_name)

                            current_reached_io_net[next_net.expanded_name] = next_net
                            score += 1 if term.device_class.name == 'NMOS'
                            score += 10 if term.device_class.name == 'PMOS'
                        end
                    end
                end
                visited.update(discovered_net_list)
                current_nets_list = discovered_net_list.dup
                round += 1
                round_descriptor = " (#{round} " \
                                    "#{current_reached_io_net.size} " \
                                    "#{score})" \
                                    + round_descriptor
            end
            round_descriptor.slice!(0)
            descriptor_tracker[round_descriptor] << current_io_net_name
            net_connection_descriptor += "#{round_descriptor})) "
        end
        duplicates = descriptor_tracker.select { |_descriptor, nets| nets.size > 1 }
        net_connection_descriptor = net_connection_descriptor.chop
        ["#{net_connection_descriptor}) ", !duplicates.empty?]
    end

    DescTermStats ||= Struct.new(:round, :num_pmos, :num_nmos, :num_sd, :num_g) do
        def initialize(round = 0, num_pmos = 0, num_nmos = 0, num_sd = 0, num_g = 0)
            super
        end
    end

    def self.get_terminal_descriptor(circuit, io_netlist)
        terminal_analysis = io_netlist.to_h do |net_name|
            # net = circuit.net_by_name(net_name)
            net = circuit.each_net.find { |n| n.expanded_name == net_name }
            if net
                [net, { visited_pmos_nets: Set.new, visited_nmos_nets: Set.new,
                        visited_pmos_dev: Set.new, visited_nmos_dev: Set.new,
                        current_pmos_nets: [net], current_nmos_nets: [net],
                        discovered_pmos_nets: [], discovered_nmos_nets: [] }]
            end
        end

        terminal_descriptor_values = Hash.new do |hash, key|
            hash[key] = {
                pmos_list: DescTermStats.new,
                nmos_list: DescTermStats.new
            }
        end

        round = 0
        while !terminal_analysis.empty? && round < 10
            terminal_analysis.each do |starting_net, lists|
                lists[:discovered_pmos_nets].clear
                lists[:discovered_nmos_nets].clear
                # search pmos
                lists[:current_pmos_nets].each do |current_net|
                    next if lists[:visited_pmos_nets].include?(current_net.expanded_name)

                    lists[:visited_pmos_nets].add(current_net.expanded_name)
                    current_net.each_terminal do |term|
                        dev_class = term.device_class
                        
                        terminal_descriptor_values[starting_net.expanded_name][:pmos_list].round = round+1
                        # process stats of the net
                        if term.terminal_def.name == 'G'
                            terminal_descriptor_values[starting_net.expanded_name][:pmos_list].num_g += 1
                        elsif %w[S D].include?(term.terminal_def.name)
                            terminal_descriptor_values[starting_net.expanded_name][:pmos_list].num_sd += 1
                        else
                            next # We don't process bulk
                        end
                        
                        next unless !lists[:visited_pmos_dev].include?(term.device.expanded_name)
                        lists[:visited_pmos_dev].add(term.device.expanded_name)
                        
                        if dev_class.name == 'NMOS'
                            terminal_descriptor_values[starting_net.expanded_name][:pmos_list].num_nmos += 1
                            next
                        end
                        if dev_class.name == 'PMOS'
                            terminal_descriptor_values[starting_net.expanded_name][:pmos_list].num_pmos += 1
                        end

                        # look for connected nets that are not visited yet
                        (0...term.device.device_class.terminal_definitions.size).each do |term_id|
                            next_net = term.device.net_for_terminal(term_id)
                            next unless IS_VALID_NET.call(next_net) && !lists[:visited_pmos_nets].include?(next_net.expanded_name)

                            lists[:discovered_pmos_nets] << next_net
                        end
                    end
                end

                # search nmos
                lists[:current_nmos_nets].each do |current_net|
                    next if lists[:visited_nmos_nets].include?(current_net.expanded_name)

                    lists[:visited_nmos_nets].add(current_net.expanded_name)
                    current_net.each_terminal do |term|
                        dev_class = term.device_class
                        
                        terminal_descriptor_values[starting_net.expanded_name][:nmos_list].round = round+1
                        # process stats of the net
                        if term.terminal_def.name == 'G'
                            terminal_descriptor_values[starting_net.expanded_name][:nmos_list].num_g += 1
                        elsif %w[S D].include?(term.terminal_def.name)
                            terminal_descriptor_values[starting_net.expanded_name][:nmos_list].num_sd += 1
                        else
                            next # We don't process bulk
                        end
                        
                        next unless !lists[:visited_nmos_dev].include?(term.device.expanded_name)
                        lists[:visited_nmos_dev].add(term.device.expanded_name)
                        
                        if dev_class.name == 'NMOS'
                            terminal_descriptor_values[starting_net.expanded_name][:nmos_list].num_nmos += 1
                        end
                        if dev_class.name == 'PMOS'
                            terminal_descriptor_values[starting_net.expanded_name][:nmos_list].num_pmos += 1
                            next
                        end

                        # look for connected nets that are not visited yet
                        (0...term.device.device_class.terminal_definitions.size).each do |term_id|
                            next_net = term.device.net_for_terminal(term_id)
                            next unless IS_VALID_NET.call(next_net) && !lists[:visited_nmos_nets].include?(next_net.expanded_name)

                            lists[:discovered_nmos_nets] << next_net
                        end
                    end
                end
                lists[:current_pmos_nets] = lists[:discovered_pmos_nets].dup
                lists[:current_nmos_nets] = lists[:discovered_nmos_nets].dup
            end
            

            # unique? = delete from analyze
            grouped = terminal_descriptor_values.group_by { |_net, stats| stats }

            # 2. Identify the names of nets that have a UNIQUE signature
            unique_net = grouped.select { |_stats, occurrences| occurrences.size == 1 }
                                .flat_map { |_stats, occurrences| occurrences.map(&:first) }
                                
                                
          terminal_descriptor_values.each do |net_name, stats|
              puts "(\"#{net_name}\" " \
                   "(#{stats[:pmos_list].round} " \
                    "#{stats[:pmos_list].num_pmos} " \
                    "#{stats[:pmos_list].num_nmos} " \
                    "#{stats[:pmos_list].num_sd} " \
                    "#{stats[:pmos_list].num_g})" \
                   " (#{stats[:nmos_list].round} " \
                    "#{stats[:nmos_list].num_pmos} " \
                    "#{stats[:nmos_list].num_nmos} " \
                    "#{stats[:nmos_list].num_sd} " \
                    "#{stats[:nmos_list].num_g})) " 
          end
             
            unique_net.each do |net_name|
                target_key = terminal_analysis.keys.find { |net_obj| net_obj.expanded_name == net_name }
                next unless target_key

                terminal_analysis.delete(target_key)
                terminal_descriptor_values[target_key.expanded_name][:pmos_list].round = round + 1
                terminal_descriptor_values[target_key.expanded_name][:nmos_list].round = round + 1
            end
            round += 1
        end
        descriptor = ''
        terminal_descriptor_values.each do |net_name, stats|
            descriptor += "(\"#{net_name}\" " \
                           "(#{stats[:pmos_list].round} " \
                            "#{stats[:pmos_list].num_pmos} " \
                            "#{stats[:pmos_list].num_nmos} " \
                            "#{stats[:pmos_list].num_sd} " \
                            "#{stats[:pmos_list].num_g})" \
                           " (#{stats[:nmos_list].round} " \
                            "#{stats[:nmos_list].num_pmos} " \
                            "#{stats[:nmos_list].num_nmos} " \
                            "#{stats[:nmos_list].num_sd} " \
                            "#{stats[:nmos_list].num_g})) " 
        end
        descriptor.chop!
    end

    # Extracts unique topographic descriptor from a circuit
    def self.get_utdescriptor(circuit)
        return 'Circuit is null!' if circuit.nil?

        io_netlist = get_global_io_nets(circuit)
        net_count = circuit.each_net.count { |net| IS_VALID_NET.call(net) }
        net_descriptor = get_net_descriptor(circuit, io_netlist)
        connection_descriptor, duplicates = get_connection_descriptor(circuit, io_netlist, net_count)
        "\"#{circuit.each_device.count} #{net_count}\": (" +
            net_descriptor +
            connection_descriptor +
            (duplicates ? get_terminal_descriptor(circuit, io_netlist) : ' nil') + ')'
    end

    # --- UNIT TEST CASE BLOCK ---
    if __FILE__ == $PROGRAM_NAME
        puts 'Initializing SPICE Mock Test...'

        test_nl = RBA::Netlist.new

        begin
            test_nl.read(File.join(File.dirname(__FILE__), '../output/results_iteration_1/clean_pulpino_gate_6629_netlist.sp'), RBA::NetlistSpiceReader.new)

            lib_path = File.join(File.dirname(__FILE__), 'netlist_utils.rb')
            load lib_path
            db = NetlistUtils.load_database

            test_nl.each_circuit do |circuit|
                runtime_descriptor = get_utdescriptor(circuit)
                puts runtime_descriptor
                matched_gate = NetlistUtils.identify_descriptor(runtime_descriptor, db)
                puts "Descriptor classified as: #{matched_gate}"
            end
        rescue StandardError => e
            puts "[SPICE Error] #{e.message}"
            puts e.backtrace # This is like a GDB backtrace
        end
    end
end
