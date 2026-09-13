# Technology-Independent Identification of CMOS Logic Gates Through Topological Connectivity Analisis

[![License: GPL v2](https://img.shields.io/badge/License-GPL_v2-blue.svg)](LICENSE)

Automated tools for netlist extraction and logic gate identification within the **KLayout** EDA environment. This project uses topological connectivity analysis to perform technology-independent recognition of standard CMOS logic gates.

---

## Directory Structure

```text
SEMD-TFM/
├── macros/                           # Ruby and LVS scripts for CMOS gate identification
├── tech/                             # KLayout technology files (.lyt, .lyp)
│   └── OriginRe/                     # Generic technology definition
├── output/                           # Macro default output directory, with example results
├── .vscode/                          # Workspace configuration for editor setups
├── cellDescriptorTable_updated.txt   # Database mapping standard cells and identified signatures
├── clean_pulpino.gds.gz              # Target test layout (PULPino IC layout, RISC-V)
└── clean_session.lys                 # Saved KLayout layout session state
└── launcher.sh                       # Script to launch the saved session.
```

## Prerequisites & Requirements

* KLayout: Version 0.28+ (with Ruby script execution enabled)
* OS: Linux, macOS, or Windows

## Usage Guide

   * Open your layout file (e.g., `clean_pulpino.gds.gz`) inside KLayout. Recomended:
     ```bash
     ./launcher.sh
     ```
      
1. **Setup Technology Files:**
   Create a technology for KLayout: `Tools` -> `Manage Technologies` -> `+`. Change `base path` to `$pwd/tech/OriginRe/` and `layers propierties` to `OriginRE.lyp`

2. **Execute Identification Macros:**
   * Open the **Macro Development** editor (`F5`).
   * Run the recognition script `macros/device_extraction_originRE.lylvs` to trigger topological analysis and multi-pass execution (also `F5`).

3. **Output & Netlists:**
   * The SPICE file for each gate detected has been saved in the `output/` directory.
   * Unnown gates marked in the layout in layer configured by output_unknown_gate (`237`)
   * Known gates marked in the layout in layer configured by output_known_gate (`238`)
     
4. **Script configurations:**
   The following variables can be found at the start of the main script `device_extraction_originRE.lylvs`:
   ```Ruby #
   * output_unknown_gate      # Used to mark the unknown gates
   * output_known_gate        # Used to mark the known gates
   * input_mask_layer         # Used to exclude some regions from the computation
   * extract_labels           # Bool to extract the m1_lbl texts, use false to skip this step
   * max_internal_distance    # Distance between different cells observed in the layout
   * rail_height              # Size of the power rails of the layout
   * rail_spacing             # Distance between the power rails
   * first_vdd                # is the first rail VDD? 
   ```
   
